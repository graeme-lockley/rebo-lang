const std = @import("std");

const AST = @import("./ast.zig");
const Builtins = @import("./builtins.zig");
const Errors = @import("./errors.zig");
const Lexer = @import("./lexer.zig");
const MS = @import("./memory_state.zig");
const Parser = @import("./parser.zig");
const SP = @import("./string_pool.zig");
const V = @import("./value.zig");

fn evalExpr(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    switch (e.kind) {
        .assignment => try assignment(machine, e.kind.assignment.lhs, e.kind.assignment.value),
        .binaryOp => try binaryOp(machine, e),
        .call => try call(machine, e, e.kind.call.callee, e.kind.call.args),
        .catche => try catche(machine, e),
        .dot => try dot(machine, e),
        .exprs => try exprs(machine, e),
        .idDeclaration => try idDeclaration(machine, e),
        .identifier => try identifier(machine, e),
        .ifte => try ifte(machine, e),
        .indexRange => try indexRange(machine, e.kind.indexRange.expr, e.kind.indexRange.start, e.kind.indexRange.end),
        .indexValue => try indexValue(machine, e.kind.indexValue.expr, e.kind.indexValue.index),
        .literalBool => try machine.createBoolValue(e.kind.literalBool),
        .literalChar => try machine.memoryState.pushCharValue(e.kind.literalChar),
        .literalFloat => try machine.memoryState.pushFloatValue(e.kind.literalFloat),
        .literalFunction => try literalFunction(machine, e),
        .literalInt => try machine.createIntValue(e.kind.literalInt),
        .literalRecord => try literalRecord(machine, e),
        .literalSequence => try literalSequence(machine, e),
        .literalString => try machine.memoryState.pushStringPoolValue(e.kind.literalString),
        .literalVoid => try machine.createVoidValue(),
        .match => try match(machine, e),
        .notOp => try notOp(machine, e),
        .patternDeclaration => try patternDeclaration(machine, e),
        .raise => try raise(machine, e),
        .whilee => try whilee(machine, e),
    }
}

inline fn assignment(machine: *Machine, lhs: *AST.Expression, value: *AST.Expression) Errors.RuntimeErrors!void {
    switch (lhs.kind) {
        .identifier => {
            try evalExpr(machine, value);

            if (!(try machine.memoryState.updateInScope(lhs.kind.identifier, machine.memoryState.peek(0)))) {
                const rec = try pushNamedUserError(machine, "UnknownIdentifierError", lhs.position);
                try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "identifier", try machine.memoryState.newStringPoolValue(lhs.kind.identifier));
                return Errors.RuntimeErrors.InterpreterError;
            }
        },
        .dot => {
            try evalExpr(machine, lhs.kind.dot.record);
            const record = machine.memoryState.peek(0);

            if (record.v != V.ValueValue.RecordKind) {
                try raiseExpectedTypeError(machine, lhs.kind.dot.record.position, &[_]V.ValueKind{V.ValueValue.RecordKind}, record.v);
            }
            try evalExpr(machine, value);

            try record.v.RecordKind.set(lhs.kind.dot.field, machine.memoryState.peek(0));

            const v = machine.memoryState.pop();
            _ = machine.memoryState.pop();
            try machine.memoryState.push(v);
        },
        .indexRange => {
            try evalExpr(machine, lhs.kind.indexRange.expr);
            const sequence = machine.memoryState.peek(0);
            if (sequence.v != V.ValueValue.SequenceKind) {
                try raiseExpectedTypeError(machine, lhs.kind.indexRange.expr.position, &[_]V.ValueKind{V.ValueValue.SequenceKind}, sequence.v);
            }

            const seqLen = sequence.v.SequenceKind.len();

            const start: V.IntType = clamp(try indexPoint(machine, lhs.kind.indexRange.start, 0), 0, @intCast(seqLen));
            const end: V.IntType = clamp(try indexPoint(machine, lhs.kind.indexRange.end, @intCast(seqLen)), start, @intCast(seqLen));

            try evalExpr(machine, value);
            const v = machine.memoryState.peek(0);

            switch (v.v) {
                V.ValueValue.SequenceKind => try sequence.v.SequenceKind.replaceRange(@intCast(start), @intCast(end), v.v.SequenceKind.items()),
                V.ValueValue.UnitKind => try sequence.v.SequenceKind.removeRange(@intCast(start), @intCast(end)),
                else => try raiseExpectedTypeError(machine, lhs.kind.indexRange.expr.position, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.UnitKind }, v.v),
            }
            machine.memoryState.popn(2);
            try machine.memoryState.push(v);
        },
        .indexValue => {
            const exprA = lhs.kind.indexValue.expr;
            const indexA = lhs.kind.indexValue.index;

            try evalExpr(machine, exprA);
            const expr = machine.memoryState.peek(0);

            switch (expr.v) {
                V.ValueValue.ScopeKind => {
                    try evalExpr(machine, indexA);
                    const index = machine.memoryState.peek(0);

                    if (index.v != V.ValueValue.StringKind) {
                        try raiseExpectedTypeError(machine, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
                    }

                    try evalExpr(machine, value);

                    if (!(try expr.v.ScopeKind.update(index.v.StringKind.value, machine.memoryState.peek(0)))) {
                        const rec = try pushNamedUserError(machine, "UnknownIdentifierError", indexA.position);
                        try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "identifier", index);
                        return Errors.RuntimeErrors.InterpreterError;
                    }
                },
                V.ValueValue.SequenceKind => {
                    try evalExpr(machine, indexA);
                    const index = machine.memoryState.peek(0);

                    if (index.v != V.ValueValue.IntKind) {
                        try raiseExpectedTypeError(machine, indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
                    }

                    try evalExpr(machine, value);

                    const seq = expr.v.SequenceKind;
                    const idx = index.v.IntKind;

                    if (idx < 0 or idx >= seq.len()) {
                        try raiseIndexOutOfRangeError(machine, indexA.position, idx, @intCast(seq.len()));
                    } else {
                        seq.set(@intCast(idx), machine.memoryState.peek(0));
                    }
                },
                V.ValueValue.RecordKind => {
                    try evalExpr(machine, indexA);
                    const index = machine.memoryState.peek(0);

                    if (index.v != V.ValueValue.StringKind) {
                        try raiseExpectedTypeError(machine, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
                    }

                    try evalExpr(machine, value);

                    try expr.v.RecordKind.set(index.v.StringKind.value, machine.memoryState.peek(0));
                },
                else => {
                    machine.memoryState.popn(1);
                    try raiseExpectedTypeError(machine, exprA.position, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.ScopeKind, V.ValueValue.SequenceKind }, expr.v);
                },
            }

            const v = machine.memoryState.pop();
            machine.memoryState.popn(2);
            try machine.memoryState.push(v);
        },
        else => try raiseNamedUserError(machine, "InvalidLHSError", lhs.position),
    }
}

inline fn binaryOp(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    const leftAST = e.kind.binaryOp.left;
    const op = e.kind.binaryOp.op;
    const rightAST = e.kind.binaryOp.right;

    switch (op) {
        AST.Operator.Plus => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.memoryState.peek(0);
            const left = machine.memoryState.peek(1);

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.popn(2);
                            try machine.memoryState.pushIntValue(left.v.IntKind + right.v.IntKind);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.popn(2);
                            try machine.memoryState.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) + right.v.FloatKind);
                        },
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.popn(2);
                            try machine.memoryState.pushFloatValue(left.v.FloatKind + @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.popn(2);
                            try machine.memoryState.pushFloatValue(left.v.FloatKind + right.v.FloatKind);
                        },
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.SequenceKind => {
                    switch (right.v) {
                        V.ValueValue.SequenceKind => {
                            try machine.memoryState.pushEmptySequenceValue();
                            const seq = machine.memoryState.peek(0);
                            try seq.v.SequenceKind.appendSlice(left.v.SequenceKind.items());
                            try seq.v.SequenceKind.appendSlice(right.v.SequenceKind.items());
                            machine.memoryState.popn(3);
                            try machine.memoryState.push(seq);
                        },
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    switch (right.v) {
                        V.ValueValue.StringKind => {
                            machine.memoryState.popn(2);

                            const slices = [_][]const u8{ left.v.StringKind.slice(), right.v.StringKind.slice() };
                            try machine.memoryState.pushOwnedStringValue(try std.mem.concat(machine.memoryState.allocator, u8, &slices));
                        },
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
            }
        },
        AST.Operator.Minus => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushIntValue(left.v.IntKind - right.v.IntKind),
                        V.ValueValue.FloatKind => try machine.memoryState.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) - right.v.FloatKind),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushFloatValue(left.v.FloatKind - @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushFloatValue(left.v.FloatKind - right.v.FloatKind),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
            }
        },
        AST.Operator.Times => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushIntValue(left.v.IntKind * right.v.IntKind),
                        V.ValueValue.FloatKind => try machine.memoryState.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) * right.v.FloatKind),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushFloatValue(left.v.FloatKind * @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushFloatValue(left.v.FloatKind * right.v.FloatKind),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.IntKind) {
                        const mem = try machine.memoryState.allocator.alloc(u8, left.v.StringKind.len() * @as(usize, @intCast(right.v.IntKind)));

                        for (0..@intCast(right.v.IntKind)) |index| {
                            std.mem.copyForwards(u8, mem[index * left.v.StringKind.len() ..], left.v.StringKind.slice());
                        }

                        try machine.memoryState.pushOwnedStringValue(mem);
                    } else {
                        try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
            }
        },
        AST.Operator.Divide => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            if (right.v.IntKind == 0) {
                                try raiseNamedUserError(machine, "DivideByZeroError", e.position);
                            }
                            try machine.memoryState.pushIntValue(@divTrunc(left.v.IntKind, right.v.IntKind));
                        },
                        V.ValueValue.FloatKind => {
                            if (right.v.FloatKind == 0.0) {
                                try raiseNamedUserError(machine, "DivideByZeroError", e.position);
                            }
                            try machine.memoryState.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) / right.v.FloatKind);
                        },
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            if (right.v.IntKind == 0) {
                                try raiseNamedUserError(machine, "DivideByZeroError", e.position);
                            }
                            try machine.memoryState.pushFloatValue(left.v.FloatKind / @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        },
                        V.ValueValue.FloatKind => {
                            if (right.v.FloatKind == 0.0) {
                                try raiseNamedUserError(machine, "DivideByZeroError", e.position);
                            }
                            try machine.memoryState.pushFloatValue(left.v.FloatKind / right.v.FloatKind);
                        },
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
            }
        },
        AST.Operator.Power => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushIntValue(std.math.pow(V.IntType, left.v.IntKind, right.v.IntKind)),
                        V.ValueValue.FloatKind => try machine.memoryState.pushFloatValue(std.math.pow(V.FloatType, @as(V.FloatType, @floatFromInt(left.v.IntKind)), right.v.FloatKind)),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushFloatValue(std.math.pow(V.FloatType, left.v.FloatKind, @as(V.FloatType, @floatFromInt(right.v.IntKind)))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushFloatValue(std.math.pow(V.FloatType, left.v.FloatKind, right.v.FloatKind)),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
            }
        },
        AST.Operator.Modulo => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            if (left.v != V.ValueValue.IntKind or right.v != V.ValueValue.IntKind) {
                try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v);
            }
            if (right.v.IntKind == 0) {
                try raiseNamedUserError(machine, "DivideByZeroError", e.position);
            }
            try machine.memoryState.pushIntValue(@mod(left.v.IntKind, right.v.IntKind));
        },
        AST.Operator.LessThan => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushBoolValue(left.v.IntKind < right.v.IntKind),
                        V.ValueValue.FloatKind => try machine.memoryState.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) < right.v.FloatKind),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushBoolValue(left.v.FloatKind < @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushBoolValue(left.v.FloatKind < right.v.FloatKind),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.StringKind) {
                        try machine.memoryState.pushBoolValue(std.mem.lessThan(u8, left.v.StringKind.slice(), right.v.StringKind.slice()));
                    } else {
                        try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
            }
        },
        AST.Operator.LessEqual => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushBoolValue(left.v.IntKind <= right.v.IntKind),
                        V.ValueValue.FloatKind => try machine.memoryState.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) <= right.v.FloatKind),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushBoolValue(left.v.FloatKind <= @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushBoolValue(left.v.FloatKind <= right.v.FloatKind),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.StringKind) {
                        try machine.memoryState.pushBoolValue(std.mem.lessThan(u8, left.v.StringKind.slice(), right.v.StringKind.slice()) or std.mem.eql(u8, left.v.StringKind.slice(), right.v.StringKind.slice()));
                    } else {
                        try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
            }
        },
        AST.Operator.GreaterThan => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushBoolValue(left.v.IntKind > right.v.IntKind),
                        V.ValueValue.FloatKind => try machine.memoryState.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) > right.v.FloatKind),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushBoolValue(left.v.FloatKind > @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushBoolValue(left.v.FloatKind > right.v.FloatKind),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.StringKind) {
                        try machine.memoryState.pushBoolValue(std.mem.lessThan(u8, right.v.StringKind.slice(), left.v.StringKind.slice()));
                    } else {
                        try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
            }
        },
        AST.Operator.GreaterEqual => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushBoolValue(left.v.IntKind >= right.v.IntKind),
                        V.ValueValue.FloatKind => try machine.memoryState.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) >= right.v.FloatKind),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushBoolValue(left.v.FloatKind >= @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushBoolValue(left.v.FloatKind >= right.v.FloatKind),
                        else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.StringKind) {
                        try machine.memoryState.pushBoolValue(std.mem.lessThan(u8, right.v.StringKind.slice(), left.v.StringKind.slice()) or std.mem.eql(u8, right.v.StringKind.slice(), left.v.StringKind.slice()));
                    } else {
                        try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v),
            }
        },
        AST.Operator.Equal => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            try machine.memoryState.pushBoolValue(V.eq(left, right));
        },
        AST.Operator.NotEqual => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            try machine.memoryState.pushBoolValue(!V.eq(left, right));
        },
        AST.Operator.And => {
            try evalExpr(machine, leftAST);

            const left = machine.memoryState.peek(0);
            if (left.v != V.ValueValue.BoolKind) {
                try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, V.ValueKind.BoolKind);
            } else if (left.v.BoolKind) {
                _ = machine.pop();
                try evalExpr(machine, rightAST);
                const right = machine.memoryState.peek(0);

                if (right.v != V.ValueValue.BoolKind) {
                    try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v);
                }
            }
        },
        AST.Operator.Or => {
            try evalExpr(machine, leftAST);

            const left = machine.memoryState.peek(0);
            if (left.v != V.ValueValue.BoolKind) {
                try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, V.ValueKind.BoolKind);
            } else if (!left.v.BoolKind) {
                _ = machine.pop();
                try evalExpr(machine, rightAST);
                const right = machine.memoryState.peek(0);

                if (right.v != V.ValueValue.BoolKind) {
                    try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v);
                }
            }
        },
        AST.Operator.Append => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);
            const left = machine.memoryState.peek(1);
            const right = machine.memoryState.peek(0);

            if (left.v != V.ValueValue.SequenceKind) {
                try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v);
            }

            try machine.memoryState.pushEmptySequenceValue();
            const result = machine.memoryState.peek(0);

            try result.v.SequenceKind.appendSlice(left.v.SequenceKind.items());
            try result.v.SequenceKind.appendItem(right);

            machine.memoryState.popn(3);
            try machine.memoryState.push(result);
        },
        AST.Operator.AppendUpdate => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);
            const left = machine.memoryState.peek(1);
            const right = machine.memoryState.peek(0);

            if (left.v != V.ValueValue.SequenceKind) {
                try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v);
            }

            try left.v.SequenceKind.appendItem(right);

            machine.memoryState.popn(1);
        },
        AST.Operator.Prepend => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);
            const left = machine.memoryState.peek(1);
            const right = machine.memoryState.peek(0);

            if (right.v != V.ValueValue.SequenceKind) {
                try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v);
            }

            try machine.memoryState.pushEmptySequenceValue();
            const result = machine.memoryState.peek(0);

            try result.v.SequenceKind.appendItem(left);
            try result.v.SequenceKind.appendSlice(right.v.SequenceKind.items());

            machine.memoryState.popn(3);
            try machine.memoryState.push(result);
        },
        AST.Operator.PrependUpdate => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);
            const left = machine.memoryState.peek(1);
            const right = machine.memoryState.peek(0);

            if (right.v != V.ValueValue.SequenceKind) {
                try raiseIncompatibleOperandTypesError(machine, e.position, e.kind.binaryOp.op, left.v, right.v);
            }

            try right.v.SequenceKind.prependItem(left);

            machine.memoryState.popn(2);
            try machine.memoryState.push(right);
        },
        AST.Operator.Hook => {
            try evalExpr(machine, leftAST);

            const left = machine.memoryState.peek(0);

            if (left.v == V.ValueValue.UnitKind) {
                _ = machine.memoryState.pop();

                try evalExpr(machine, rightAST);
            }
        },

        // else => unreachable,
    }
}

inline fn call(machine: *Machine, e: *AST.Expression, calleeAST: *AST.Expression, argsAST: []*AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, calleeAST);
    for (argsAST) |arg| {
        try evalExpr(machine, arg);
    }

    callFn(machine, argsAST.len) catch |err| {
        try machine.appendErrorPosition(Errors.Position{ .start = calleeAST.position.start, .end = e.position.end });
        return err;
    };
}

pub inline fn callFn(machine: *Machine, numberOfArgs: usize) Errors.RuntimeErrors!void {
    const callee = machine.memoryState.peek(@intCast(numberOfArgs));

    switch (callee.v) {
        V.ValueValue.FunctionKind => try callUserFn(machine, numberOfArgs),
        V.ValueValue.BuiltinKind => try callBuiltinFn(machine, numberOfArgs),
        else => try raiseExpectedTypeError(machine, null, &[_]V.ValueKind{V.ValueValue.FunctionKind}, callee.v),
    }

    const result = machine.memoryState.pop();
    machine.memoryState.popn(@intCast(numberOfArgs + 1));
    try machine.memoryState.push(result);
}

inline fn callUserFn(machine: *Machine, numberOfArgs: usize) !void {
    const enclosingScope = machine.memoryState.scope().?;

    const callee = machine.memoryState.peek(@intCast(numberOfArgs));

    try machine.memoryState.openScopeFrom(callee.v.FunctionKind.scope);
    defer machine.memoryState.restoreScope();

    try machine.memoryState.addU8ToScope("__caller_scope__", enclosingScope);

    var lp: usize = 0;
    const maxArgs = @min(numberOfArgs, callee.v.FunctionKind.arguments.len);
    const sp = machine.memoryState.stack.items.len - numberOfArgs;
    while (lp < maxArgs) {
        try machine.memoryState.addToScope(callee.v.FunctionKind.arguments[lp].name, machine.memoryState.stack.items[sp + lp]);
        lp += 1;
    }
    while (lp < callee.v.FunctionKind.arguments.len) {
        const value = callee.v.FunctionKind.arguments[lp].default orelse machine.memoryState.unitValue.?;

        try machine.memoryState.addToScope(callee.v.FunctionKind.arguments[lp].name, value);
        lp += 1;
    }

    if (callee.v.FunctionKind.restOfArguments != null) {
        if (numberOfArgs > callee.v.FunctionKind.arguments.len) {
            const rest = machine.memoryState.stack.items[sp + callee.v.FunctionKind.arguments.len ..];
            try machine.memoryState.addArrayValueToScope(callee.v.FunctionKind.restOfArguments.?, rest);
        } else {
            try machine.memoryState.addToScope(callee.v.FunctionKind.restOfArguments.?, try machine.memoryState.newEmptySequenceValue());
        }
    }

    try evalExpr(machine, callee.v.FunctionKind.body);
}

inline fn callBuiltinFn(machine: *Machine, numberOfArgs: usize) !void {
    const callee = machine.memoryState.peek(@intCast(numberOfArgs));

    try callee.v.BuiltinKind.body(machine, numberOfArgs);
}

inline fn catche(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    const sp = machine.memoryState.stack.items.len;
    evalExpr(machine, e.kind.catche.value) catch |err| {
        const value = machine.memoryState.peek(0);

        for (e.kind.catche.cases) |case| {
            try machine.memoryState.openScope();

            const matched = try matchPattern(machine, case.pattern, value);
            if (matched) {
                const result = evalExpr(machine, case.body);

                machine.memoryState.restoreScope();
                const v = machine.memoryState.pop();
                machine.memoryState.stack.items.len = sp;
                try machine.memoryState.push(v);

                return result;
            }
            machine.memoryState.restoreScope();
        }
        return err;
    };
}

inline fn dot(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.dot.record);

    const record = machine.memoryState.pop();

    if (record.v != V.ValueValue.RecordKind) {
        try raiseExpectedTypeError(machine, e.kind.dot.record.position, &[_]V.ValueKind{V.ValueValue.RecordKind}, record.v);
    }

    if (record.v.RecordKind.get(e.kind.dot.field)) |value| {
        try machine.memoryState.push(value);
    } else {
        try machine.memoryState.pushUnitValue();
    }
}

inline fn exprs(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    if (e.kind.exprs.len == 0) {
        try machine.memoryState.pushUnitValue();
    } else {
        var isFirst = true;

        for (e.kind.exprs) |expr| {
            if (isFirst) {
                isFirst = false;
            } else {
                _ = machine.memoryState.pop();
            }

            try evalExpr(machine, expr);
        }
    }
}

inline fn idDeclaration(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.idDeclaration.value);
    try machine.memoryState.addToScope(e.kind.idDeclaration.name, machine.memoryState.peek(0));
}

inline fn identifier(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    if (machine.memoryState.getFromScope(e.kind.identifier)) |result| {
        try machine.memoryState.push(result);
    } else {
        const rec = try pushNamedUserError(machine, "UnknownIdentifierError", e.position);
        try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "identifier", try machine.memoryState.newStringPoolValue(e.kind.identifier));
        return Errors.RuntimeErrors.InterpreterError;
    }
}

inline fn ifte(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    for (e.kind.ifte) |case| {
        if (case.condition == null) {
            try evalExpr(machine, case.then);
            return;
        }

        try evalExpr(machine, case.condition.?);

        const condition = machine.memoryState.pop();

        if (condition.v == V.ValueValue.BoolKind and condition.v.BoolKind) {
            try evalExpr(machine, case.then);
            return;
        }
    }

    try machine.createVoidValue();
}

inline fn indexRange(machine: *Machine, exprA: *AST.Expression, startA: ?*AST.Expression, endA: ?*AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, exprA);
    const expr = machine.memoryState.peek(0);

    switch (expr.v) {
        V.ValueValue.SequenceKind => {
            const seq = expr.v.SequenceKind;

            const start: V.IntType = clamp(try indexPoint(machine, startA, 0), 0, @intCast(seq.len()));
            const end: V.IntType = clamp(try indexPoint(machine, endA, @intCast(seq.len())), start, @intCast(seq.len()));

            try machine.memoryState.pushEmptySequenceValue();
            try machine.memoryState.peek(0).v.SequenceKind.appendSlice(seq.items()[@intCast(start)..@intCast(end)]);
        },
        V.ValueValue.StringKind => {
            const str = expr.v.StringKind.slice();

            const start: V.IntType = clamp(try indexPoint(machine, startA, 0), 0, @intCast(str.len));
            const end: V.IntType = clamp(try indexPoint(machine, endA, @intCast(str.len)), start, @intCast(str.len));

            try machine.memoryState.pushStringValue(str[@intCast(start)..@intCast(end)]);
        },
        else => {
            machine.memoryState.popn(1);
            try raiseExpectedTypeError(machine, exprA.position, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v);
        },
    }

    const result = machine.memoryState.pop();
    _ = machine.memoryState.pop();
    try machine.memoryState.push(result);
}

inline fn indexPoint(machine: *Machine, point: ?*AST.Expression, def: V.IntType) Errors.RuntimeErrors!V.IntType {
    if (point == null) {
        return def;
    } else {
        try evalExpr(machine, point.?);
        const pointV = machine.memoryState.peek(0);
        if (pointV.v != V.ValueValue.IntKind) {
            try raiseExpectedTypeError(machine, point.?.position, &[_]V.ValueKind{V.ValueValue.IntKind}, pointV.v);
        }

        const v = pointV.v.IntKind;
        _ = machine.memoryState.pop();
        return v;
    }
}

inline fn indexValue(machine: *Machine, exprA: *AST.Expression, indexA: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, exprA);
    const expr = machine.memoryState.peek(0);

    switch (expr.v) {
        V.ValueValue.RecordKind => {
            try evalExpr(machine, indexA);
            const index = machine.memoryState.peek(0);

            if (index.v != V.ValueValue.StringKind) {
                try raiseExpectedTypeError(machine, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
            }

            machine.memoryState.popn(2);

            const value = expr.v.RecordKind.get(index.v.StringKind.value);

            if (value == null) {
                try machine.memoryState.pushUnitValue();
            } else {
                try machine.memoryState.push(value.?);
            }
        },
        V.ValueValue.ScopeKind => {
            try evalExpr(machine, indexA);
            const index = machine.memoryState.peek(0);

            if (index.v != V.ValueValue.StringKind) {
                try raiseExpectedTypeError(machine, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
            }

            machine.memoryState.popn(2);

            const value = expr.v.ScopeKind.get(index.v.StringKind.value);

            if (value == null) {
                try machine.memoryState.pushUnitValue();
            } else {
                try machine.memoryState.push(value.?);
            }
        },
        V.ValueValue.SequenceKind => {
            try evalExpr(machine, indexA);
            const index = machine.memoryState.peek(0);

            if (index.v != V.ValueValue.IntKind) {
                try raiseExpectedTypeError(machine, indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
            }

            machine.memoryState.popn(2);

            const seq = expr.v.SequenceKind;
            const idx = index.v.IntKind;

            if (idx < 0 or idx >= seq.len()) {
                try machine.memoryState.pushUnitValue();
            } else {
                try machine.memoryState.push(seq.at(@intCast(idx)));
            }
        },
        V.ValueValue.StringKind => {
            try evalExpr(machine, indexA);
            const index = machine.memoryState.peek(0);

            if (index.v != V.ValueValue.IntKind) {
                try raiseExpectedTypeError(machine, indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
            }

            machine.memoryState.popn(2);

            const str = expr.v.StringKind.slice();
            const idx = index.v.IntKind;

            if (idx < 0 or idx >= str.len) {
                try machine.memoryState.pushUnitValue();
            } else {
                try machine.memoryState.pushCharValue(str[@intCast(idx)]);
            }
        },
        else => {
            machine.memoryState.popn(1);
            try raiseExpectedTypeError(machine, exprA.position, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v);
        },
    }
}

inline fn literalFunction(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    var arguments = try machine.memoryState.allocator.alloc(V.FunctionArgument, e.kind.literalFunction.params.len);

    for (e.kind.literalFunction.params, 0..) |param, index| {
        arguments[index] = V.FunctionArgument{ .name = param.name.incRefR(), .default = null };
    }

    _ = try machine.memoryState.pushValue(V.ValueValue{ .FunctionKind = V.FunctionValue{
        .scope = machine.memoryState.scope(),
        .arguments = arguments,
        .restOfArguments = if (e.kind.literalFunction.restOfParams == null) null else e.kind.literalFunction.restOfParams.?.incRefR(),
        .body = e.kind.literalFunction.body.incRefR(),
    } });

    for (e.kind.literalFunction.params, 0..) |param, index| {
        if (param.default != null) {
            try evalExpr(machine, param.default.?);
            arguments[index].default = machine.pop();
        }
    }
}

inline fn literalRecord(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    try machine.memoryState.pushEmptyRecordValue();
    var map = machine.topOfStack().?;

    for (e.kind.literalRecord) |entry| {
        switch (entry) {
            .value => {
                try evalExpr(machine, entry.value.value);

                const value = machine.memoryState.pop();
                try map.v.RecordKind.set(entry.value.key, value);
            },
            .record => {
                try evalExpr(machine, entry.record);

                const value = machine.memoryState.pop();
                if (value.v != V.ValueValue.RecordKind) {
                    try raiseExpectedTypeError(machine, entry.record.position, &[_]V.ValueKind{V.ValueValue.RecordKind}, value.v);
                }

                var iterator = value.v.RecordKind.iterator();
                while (iterator.next()) |rv| {
                    try map.v.RecordKind.set(rv.key_ptr.*, rv.value_ptr.*);
                }
            },
        }
    }
}

inline fn literalSequence(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    try machine.memoryState.pushEmptySequenceValue();
    const seq = machine.memoryState.peek(0);

    for (e.kind.literalSequence) |v| {
        switch (v) {
            .value => {
                try evalExpr(machine, v.value);
                try seq.v.SequenceKind.appendItem(machine.memoryState.pop());
            },
            .sequence => {
                try evalExpr(machine, v.sequence);
                const vs = machine.memoryState.pop();

                if (vs.v != V.ValueValue.SequenceKind) {
                    try raiseExpectedTypeError(machine, v.sequence.position, &[_]V.ValueKind{V.ValueValue.SequenceKind}, vs.v);
                }

                try seq.v.SequenceKind.appendSlice(vs.v.SequenceKind.items());
            },
        }
    }
}

inline fn match(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.match.value);

    const value = machine.memoryState.peek(0);

    for (e.kind.match.cases) |case| {
        try machine.memoryState.openScope();

        const matched = try matchPattern(machine, case.pattern, value);
        if (matched) {
            const result = evalExpr(machine, case.body);

            machine.memoryState.restoreScope();
            const v = machine.memoryState.pop();
            _ = machine.memoryState.pop();
            try machine.memoryState.push(v);

            return result;
        }
        machine.memoryState.restoreScope();
    }

    try raiseMatchError(machine, e.position, value);
}

fn matchPattern(machine: *Machine, p: *AST.Pattern, v: *V.Value) !bool {
    return switch (p.kind) {
        .identifier => {
            if (!std.mem.eql(u8, p.kind.identifier.slice(), "_")) {
                try machine.memoryState.addToScope(p.kind.identifier, v);
            }
            return true;
        },
        .literalBool => return v.v == V.ValueValue.BoolKind and v.v.BoolKind == p.kind.literalBool,
        .literalChar => return v.v == V.ValueValue.CharKind and v.v.CharKind == p.kind.literalChar,
        .literalFloat => return v.v == V.ValueValue.FloatKind and v.v.FloatKind == p.kind.literalFloat or v.v == V.ValueValue.IntKind and v.v.IntKind == @as(V.IntType, @intFromFloat(p.kind.literalFloat)),
        .literalInt => return v.v == V.ValueValue.IntKind and v.v.IntKind == p.kind.literalInt or v.v == V.ValueValue.FloatKind and v.v.FloatKind == @as(V.FloatType, @floatFromInt(p.kind.literalInt)),
        .literalString => return v.v == V.ValueValue.StringKind and std.mem.eql(u8, v.v.StringKind.slice(), p.kind.literalString.slice()),
        .record => {
            if (v.v != V.ValueValue.RecordKind) return false;

            const record = v.v.RecordKind;

            for (p.kind.record.entries) |entry| {
                const value = record.get(entry.key);

                if (value == null) return false;

                if (entry.pattern == null) {
                    try machine.memoryState.addToScope(if (entry.id == null) entry.key else entry.id.?, value.?);
                } else if (entry.pattern != null and !try matchPattern(machine, entry.pattern.?, value.?)) {
                    return false;
                }
            }

            if (p.kind.record.id != null) {
                try machine.memoryState.addToScope(p.kind.record.id.?, v);
            }

            return true;
        },
        .sequence => {
            if (v.v != V.ValueValue.SequenceKind) return false;

            const seq = v.v.SequenceKind;

            if (p.kind.sequence.restOfPatterns == null and seq.len() != p.kind.sequence.patterns.len) return false;
            if (p.kind.sequence.restOfPatterns != null and seq.len() < p.kind.sequence.patterns.len) return false;

            var index: u8 = 0;
            while (index < p.kind.sequence.patterns.len) {
                if (!try matchPattern(machine, p.kind.sequence.patterns[index], seq.at(index))) return false;
                index += 1;
            }

            if (p.kind.sequence.restOfPatterns != null and !std.mem.eql(u8, p.kind.sequence.restOfPatterns.?.slice(), "_")) {
                var newSeq = try V.SequenceValue.init(machine.memoryState.allocator);
                if (seq.len() > p.kind.sequence.patterns.len) {
                    try newSeq.appendSlice(seq.items()[p.kind.sequence.patterns.len..]);
                }
                try machine.memoryState.addToScope(p.kind.sequence.restOfPatterns.?, try machine.memoryState.newValue(V.ValueValue{ .SequenceKind = newSeq }));
            }

            if (p.kind.sequence.id != null) {
                try machine.memoryState.addToScope(p.kind.sequence.id.?, v);
            }

            return true;
        },
        .void => return v.v == V.ValueValue.UnitKind,
    };
}

inline fn notOp(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.notOp.value);

    const v = machine.memoryState.pop();
    if (v.v != V.ValueValue.BoolKind) {
        try raiseExpectedTypeError(machine, e.position, &[_]V.ValueKind{V.ValueValue.BoolKind}, v.v);
    }

    try machine.memoryState.pushBoolValue(!v.v.BoolKind);
}

inline fn patternDeclaration(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.patternDeclaration.value);

    const value: *V.Value = machine.memoryState.peek(0);

    if (!try matchPattern(machine, e.kind.patternDeclaration.pattern, value)) {
        try raiseMatchError(machine, e.position, value);
    }
}

inline fn raise(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.raise.expr);
    try machine.appendErrorPosition(e.position);

    return Errors.RuntimeErrors.InterpreterError;
}

inline fn whilee(machine: *Machine, e: *AST.Expression) Errors.RuntimeErrors!void {
    while (true) {
        try evalExpr(machine, e.kind.whilee.condition);

        const condition = machine.memoryState.pop();

        if (condition.v != V.ValueValue.BoolKind or !condition.v.BoolKind) {
            break;
        }

        try evalExpr(machine, e.kind.whilee.body);

        _ = machine.memoryState.pop();
    }

    try machine.createVoidValue();
}

fn addBuiltin(state: *MS.MemoryState, name: []const u8, body: V.BuiltinFunctionType) !void {
    try state.addU8ToScope(name, try state.newBuiltinValue(body));
}

fn addRebo(state: *MS.MemoryState) !void {
    var args = try std.process.argsAlloc(state.allocator);
    defer std.process.argsFree(state.allocator, args);

    const value = try state.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(state.allocator) });
    try state.addU8ToScope("rebo", value);

    const reboArgs = try state.newValue(V.ValueValue{ .SequenceKind = try V.SequenceValue.init(state.allocator) });
    try value.v.RecordKind.setU8(state.stringPool, "args", reboArgs);

    for (args) |arg| {
        try reboArgs.v.SequenceKind.appendItem(try state.newStringValue(arg));
    }

    var env = try std.process.getEnvMap(state.allocator);
    defer env.deinit();
    const reboEnv = try state.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(state.allocator) });
    try value.v.RecordKind.setU8(state.stringPool, "env", reboEnv);

    var iterator = env.iterator();
    while (iterator.next()) |entry| {
        try reboEnv.v.RecordKind.setU8(state.stringPool, entry.key_ptr.*, try state.newStringValue(entry.value_ptr.*));
    }

    const exePath = std.fs.selfExePathAlloc(state.allocator) catch return;
    defer state.allocator.free(exePath);
    try value.v.RecordKind.setU8(state.stringPool, "exe", try state.newStringValue(exePath));

    const reboLang = try state.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(state.allocator) });
    try value.v.RecordKind.setU8(state.stringPool, "lang", reboLang);
    try reboLang.v.RecordKind.setU8(state.stringPool, "scope", try state.newBuiltinValue(@import("builtins/scope.zig").scope));
    try reboLang.v.RecordKind.setU8(state.stringPool, "scope.bind!", try state.newBuiltinValue(@import("builtins/scope.zig").bind));
    try reboLang.v.RecordKind.setU8(state.stringPool, "scope.open", try state.newBuiltinValue(@import("builtins/scope.zig").open));
    try reboLang.v.RecordKind.setU8(state.stringPool, "scope.super", try state.newBuiltinValue(@import("builtins/scope.zig").super));
    try reboLang.v.RecordKind.setU8(state.stringPool, "scope.super.assign!", try state.newBuiltinValue(@import("builtins/scope.zig").assign));

    const reboOS = try state.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(state.allocator) });
    try value.v.RecordKind.setU8(state.stringPool, "os", reboOS);

    var client = try state.allocator.create(std.http.Client);
    client.* = std.http.Client{ .allocator = state.allocator };
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client", try state.newValue(V.ValueValue{ .HttpClientKind = V.HttpClientValue.init(client) }));
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client.start", try state.newBuiltinValue(@import("builtins/httpRequest.zig").httpStart));
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client.status", try state.newBuiltinValue(@import("builtins/httpRequest.zig").httpStatus));
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client.request", try state.newBuiltinValue(@import("builtins/httpRequest.zig").httpRequest));
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client.response", try state.newBuiltinValue(@import("builtins/httpRequest.zig").httpResponse));
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client.wait", try state.newBuiltinValue(@import("builtins/httpRequest.zig").httpWait));
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client.finish", try state.newBuiltinValue(@import("builtins/httpRequest.zig").httpFinish));

    const reboImports = try state.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(state.allocator) });
    try value.v.RecordKind.setU8(state.stringPool, "imports", reboImports);
}

fn initMemoryState(allocator: std.mem.Allocator) !MS.MemoryState {
    var state = try MS.MemoryState.init(allocator);

    try state.openScope();

    try addBuiltin(&state, "close", &Builtins.close);
    try addBuiltin(&state, "cwd", &Builtins.cwd);
    try addBuiltin(&state, "eval", &Builtins.eval);
    try addBuiltin(&state, "exit", &Builtins.exit);
    try addBuiltin(&state, "gc", &Builtins.gc);
    try addBuiltin(&state, "import", &Builtins.import);
    try addBuiltin(&state, "int", &Builtins.int);
    try addBuiltin(&state, "float", &Builtins.float);
    try addBuiltin(&state, "keys", &Builtins.keys);
    try addBuiltin(&state, "len", &Builtins.len);
    try addBuiltin(&state, "listen", &Builtins.listen);
    try addBuiltin(&state, "ls", &Builtins.ls);
    try addBuiltin(&state, "milliTimestamp", &Builtins.milliTimestamp);
    try addBuiltin(&state, "open", &Builtins.open);
    try addBuiltin(&state, "print", &Builtins.print);
    try addBuiltin(&state, "println", &Builtins.println);
    try addBuiltin(&state, "read", &Builtins.read);
    try addBuiltin(&state, "scope", &Builtins.scope);
    try addBuiltin(&state, "socket", &Builtins.socket);
    try addBuiltin(&state, "str", &Builtins.str);
    try addBuiltin(&state, "typeof", &Builtins.typeof);
    try addBuiltin(&state, "write", &Builtins.write);

    try addRebo(&state);

    try state.openScope();

    return state;
}

pub const Machine = struct {
    memoryState: MS.MemoryState,

    pub fn init(allocator: std.mem.Allocator) !Machine {
        return Machine{
            .memoryState = try initMemoryState(allocator),
        };
    }

    pub fn deinit(self: *Machine) void {
        self.memoryState.deinit();
    }

    pub fn createVoidValue(self: *Machine) !void {
        try self.memoryState.pushUnitValue();
    }

    pub fn createBoolValue(self: *Machine, v: bool) !void {
        try self.memoryState.pushBoolValue(v);
    }

    pub fn createIntValue(self: *Machine, v: V.IntType) !void {
        try self.memoryState.pushIntValue(v);
    }

    pub fn createSequenceValue(self: *Machine, size: usize) !void {
        return self.memoryState.pushSequenceValue(size);
    }

    pub fn eval(self: *Machine, e: *AST.Expression) !void {
        try evalExpr(self, e);
    }

    pub fn parse(self: *Machine, name: []const u8, buffer: []const u8) !*AST.Expression {
        const allocator = self.memoryState.allocator;

        var l = Lexer.Lexer.init(allocator);

        l.initBuffer(name, buffer) catch |err| {
            var e = l.grabErr().?;
            defer e.deinit();

            try self.parserErrorHandler(err, e);
            return Errors.RuntimeErrors.InterpreterError;
        };

        var p = Parser.Parser.init(self.memoryState.stringPool, l);

        const ast = p.module() catch |err| {
            var e = p.grabErr().?;
            defer e.deinit();

            try self.parserErrorHandler(err, e);
            return Errors.RuntimeErrors.InterpreterError;
        };
        errdefer AST.destroy(allocator, ast);

        return ast;
    }

    fn parserErrorHandler(self: *Machine, err: Errors.ParserErrors, e: Errors.Error) !void {
        switch (err) {
            Errors.ParserErrors.FunctionValueExpectedError => {
                _ = try pushNamedUserError(self, "FunctionValueExpectedError", null);
                try self.appendErrorStackItem(e.stackItem);
            },
            Errors.ParserErrors.LiteralIntError => _ = try raiseNamedUserErrorFromError(self, "LiteralIntOverflowError", "value", e.detail.LiteralIntOverflowKind.lexeme, e),
            Errors.ParserErrors.LiteralFloatError => _ = try raiseNamedUserErrorFromError(self, "LiteralFloatOverflowError", "value", e.detail.LiteralFloatOverflowKind.lexeme, e),
            Errors.ParserErrors.SyntaxError => {
                const rec = try raiseNamedUserErrorFromError(self, "SyntaxError", "found", e.detail.ParserKind.lexeme, e);

                const expected = try self.memoryState.newEmptySequenceValue();
                try rec.v.RecordKind.setU8(self.memoryState.stringPool, "expected", expected);

                for (e.detail.ParserKind.expected) |vk| {
                    try expected.v.SequenceKind.appendItem(try self.memoryState.newStringValue(vk.toString()));
                }
            },
            Errors.ParserErrors.LexicalError => _ = try raiseNamedUserErrorFromError(self, "LexicalError", "found", e.detail.LexicalKind.lexeme, e),
            else => unreachable,
        }
    }

    fn raiseNamedUserErrorFromError(self: *Machine, kind: []const u8, name: []const u8, value: []const u8, e: Errors.Error) !*V.Value {
        const rec = try pushNamedUserError(self, kind, null);

        try rec.v.RecordKind.setU8(self.memoryState.stringPool, name, try self.memoryState.newStringValue(value));
        try rec.v.RecordKind.setU8(self.memoryState.stringPool, "stack", try self.memoryState.newEmptySequenceValue());
        try self.appendErrorStackItem(e.stackItem);

        return rec;
    }

    pub fn execute(self: *Machine, name: []const u8, buffer: []const u8) !void {
        const ast = try self.parse(name, buffer);
        defer ast.destroy(self.memoryState.allocator);

        try self.eval(ast);
    }

    pub fn pop(self: *Machine) *V.Value {
        return self.memoryState.pop();
    }

    pub fn topOfStack(self: *Machine) ?*V.Value {
        return self.memoryState.topOfStack();
    }

    pub fn reset(self: *Machine) !void {
        try self.memoryState.reset();
    }

    pub fn src(self: *Machine) ![]const u8 {
        const result = try self.memoryState.getU8FromScope("__FILE");

        return if (result == null) Errors.STREAM_SRC else if (result.?.v == V.ValueValue.StringKind) result.?.v.StringKind.slice() else Errors.STREAM_SRC;
    }

    inline fn appendErrorPosition(self: *Machine, position: ?Errors.Position) !void {
        if (position != null) {
            try self.appendErrorStackItem(Errors.StackItem{ .src = try self.src(), .position = position.? });
        }
    }

    fn appendErrorStackItem(self: *Machine, stackItem: Errors.StackItem) !void {
        const stack = try self.getErrorStack();

        if (stack != null) {
            const frameRecord = try self.memoryState.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(self.memoryState.allocator) });
            try stack.?.v.SequenceKind.appendItem(frameRecord);

            try frameRecord.v.RecordKind.setU8(self.memoryState.stringPool, "file", try self.memoryState.newStringValue(stackItem.src));
            const fromRecord = try self.memoryState.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(self.memoryState.allocator) });
            try frameRecord.v.RecordKind.setU8(self.memoryState.stringPool, "from", fromRecord);

            try fromRecord.v.RecordKind.setU8(self.memoryState.stringPool, "offset", try self.memoryState.newValue(V.ValueValue{ .IntKind = @intCast(stackItem.position.start) }));

            const toRecord = try self.memoryState.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(self.memoryState.allocator) });
            try frameRecord.v.RecordKind.setU8(self.memoryState.stringPool, "to", toRecord);

            try toRecord.v.RecordKind.setU8(self.memoryState.stringPool, "offset", try self.memoryState.newValue(V.ValueValue{ .IntKind = @intCast(stackItem.position.end) }));

            const position = try stackItem.location(self.memoryState.allocator);
            if (position != null) {
                try fromRecord.v.RecordKind.setU8(self.memoryState.stringPool, "line", try self.memoryState.newValue(V.ValueValue{ .IntKind = @intCast(position.?.from.line) }));
                try fromRecord.v.RecordKind.setU8(self.memoryState.stringPool, "column", try self.memoryState.newValue(V.ValueValue{ .IntKind = @intCast(position.?.from.column) }));
                try toRecord.v.RecordKind.setU8(self.memoryState.stringPool, "line", try self.memoryState.newValue(V.ValueValue{ .IntKind = @intCast(position.?.to.line) }));
                try toRecord.v.RecordKind.setU8(self.memoryState.stringPool, "column", try self.memoryState.newValue(V.ValueValue{ .IntKind = @intCast(position.?.to.column) }));
            }
        }
    }

    fn getErrorStack(self: *Machine) !?*V.Value {
        const v = self.memoryState.peek(0);

        if (v.v == V.ValueValue.RecordKind) {
            var record = v.v.RecordKind;

            var stack = try record.getU8(self.memoryState.stringPool, "stack");
            if (stack == null) {
                stack = try self.memoryState.newEmptySequenceValue();
                try record.setU8(self.memoryState.stringPool, "stack", stack.?);
            }
            if (stack.?.v != V.ValueValue.SequenceKind) {
                return null;
            }

            return stack;
        } else {
            return null;
        }
    }
};

pub fn raiseExpectedTypeError(machine: *Machine, position: ?Errors.Position, expected: []const V.ValueKind, found: V.ValueKind) !void {
    const rec = try pushNamedUserError(machine, "ExpectedTypeError", position);

    try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "found", try machine.memoryState.newStringValue(found.toString()));
    const expectedSeq = try machine.memoryState.newEmptySequenceValue();
    try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "expected", expectedSeq);

    for (expected) |vk| {
        try expectedSeq.v.SequenceKind.appendItem(try machine.memoryState.newStringValue(vk.toString()));
    }

    return Errors.RuntimeErrors.InterpreterError;
}

fn raiseIncompatibleOperandTypesError(machine: *Machine, position: Errors.Position, op: AST.Operator, left: V.ValueKind, right: V.ValueKind) !void {
    const rec = try pushNamedUserError(machine, "IncompatibleOperandTypesError", position);

    try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "op", try machine.memoryState.newStringValue(op.toString()));
    try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "left", try machine.memoryState.newStringValue(left.toString()));
    try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "right", try machine.memoryState.newStringValue(right.toString()));

    return Errors.RuntimeErrors.InterpreterError;
}

fn raiseIndexOutOfRangeError(machine: *Machine, position: Errors.Position, index: V.IntType, len: V.IntType) !void {
    const rec = try pushNamedUserError(machine, "IndexOutOfRangeError", position);

    try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "index", try machine.memoryState.newIntValue(index));
    try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "lower", try machine.memoryState.newIntValue(0));
    try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "upper", try machine.memoryState.newIntValue(len));

    return Errors.RuntimeErrors.InterpreterError;
}

fn raiseMatchError(machine: *Machine, position: Errors.Position, value: *V.Value) !void {
    const rec = try pushNamedUserError(machine, "MatchError", position);

    try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "value", value);

    return Errors.RuntimeErrors.InterpreterError;
}

pub fn pushNamedUserError(machine: *Machine, name: []const u8, position: ?Errors.Position) !*V.Value {
    try machine.memoryState.pushEmptyRecordValue();
    const record = machine.memoryState.peek(0);

    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "kind", try machine.memoryState.newStringValue(name));
    try machine.appendErrorPosition(position);

    return record;
}

fn raiseNamedUserError(machine: *Machine, name: []const u8, position: ?Errors.Position) !void {
    _ = try pushNamedUserError(machine, name, position);
    return Errors.RuntimeErrors.InterpreterError;
}

fn clamp(value: V.IntType, min: V.IntType, max: V.IntType) V.IntType {
    if (value < min) {
        return min;
    } else if (value > max) {
        return max;
    } else {
        return value;
    }
}
