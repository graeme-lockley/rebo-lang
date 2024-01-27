const std = @import("std");

const AST = @import("./ast.zig");
const Builtins = @import("./builtins.zig");
const ER = @import("./error-reporting.zig");
const Errors = @import("./errors.zig");
const Lexer = @import("./lexer.zig");
const MS = @import("./runtime.zig");
const Parser = @import("./parser.zig");
const SP = @import("./string_pool.zig");
const V = @import("./value.zig");

fn evalExpr(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
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

inline fn evalExprInScope(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    if (e.kind == .exprs) try machine.memoryState.pushScope();
    defer if (e.kind == .exprs) machine.memoryState.popScope();

    try evalExpr(machine, e);
}

inline fn assignment(machine: *ASTInterpreter, lhs: *AST.Expression, value: *AST.Expression) Errors.RuntimeErrors!void {
    switch (lhs.kind) {
        .identifier => {
            try evalExpr(machine, value);

            if (!(try machine.memoryState.updateInScope(lhs.kind.identifier, machine.memoryState.peek(0)))) {
                const rec = try ER.pushNamedUserError(&machine.memoryState, "UnknownIdentifierError", lhs.position);
                try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "identifier", try machine.memoryState.newStringPoolValue(lhs.kind.identifier));
                return Errors.RuntimeErrors.InterpreterError;
            }
        },
        .dot => {
            try evalExpr(machine, lhs.kind.dot.record);
            const record = machine.memoryState.peek(0);

            if (record.v != V.ValueValue.RecordKind) {
                try ER.raiseExpectedTypeError(&machine.memoryState, lhs.kind.dot.record.position, &[_]V.ValueKind{V.ValueValue.RecordKind}, record.v);
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
                try ER.raiseExpectedTypeError(&machine.memoryState, lhs.kind.indexRange.expr.position, &[_]V.ValueKind{V.ValueValue.SequenceKind}, sequence.v);
            }

            const seqLen = sequence.v.SequenceKind.len();

            const start: V.IntType = clamp(try indexPoint(machine, lhs.kind.indexRange.start, 0), 0, @intCast(seqLen));
            const end: V.IntType = clamp(try indexPoint(machine, lhs.kind.indexRange.end, @intCast(seqLen)), start, @intCast(seqLen));

            try evalExpr(machine, value);
            const v = machine.memoryState.peek(0);

            switch (v.v) {
                V.ValueValue.SequenceKind => try sequence.v.SequenceKind.replaceRange(@intCast(start), @intCast(end), v.v.SequenceKind.items()),
                V.ValueValue.UnitKind => try sequence.v.SequenceKind.removeRange(@intCast(start), @intCast(end)),
                else => try ER.raiseExpectedTypeError(&machine.memoryState, lhs.kind.indexRange.expr.position, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.UnitKind }, v.v),
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
                        try ER.raiseExpectedTypeError(&machine.memoryState, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
                    }

                    try evalExpr(machine, value);

                    if (!(try expr.v.ScopeKind.update(index.v.StringKind.value, machine.memoryState.peek(0)))) {
                        const rec = try ER.pushNamedUserError(&machine.memoryState, "UnknownIdentifierError", indexA.position);
                        try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "identifier", index);
                        return Errors.RuntimeErrors.InterpreterError;
                    }
                },
                V.ValueValue.SequenceKind => {
                    try evalExpr(machine, indexA);
                    const index = machine.memoryState.peek(0);

                    if (index.v != V.ValueValue.IntKind) {
                        try ER.raiseExpectedTypeError(&machine.memoryState, indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
                    }

                    try evalExpr(machine, value);

                    const seq = expr.v.SequenceKind;
                    const idx = index.v.IntKind;

                    if (idx < 0 or idx >= seq.len()) {
                        try ER.raiseIndexOutOfRangeError(&machine.memoryState, indexA.position, idx, @intCast(seq.len()));
                    } else {
                        seq.set(@intCast(idx), machine.memoryState.peek(0));
                    }
                },
                V.ValueValue.RecordKind => {
                    try evalExpr(machine, indexA);
                    const index = machine.memoryState.peek(0);

                    if (index.v != V.ValueValue.StringKind) {
                        try ER.raiseExpectedTypeError(&machine.memoryState, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
                    }

                    try evalExpr(machine, value);

                    try expr.v.RecordKind.set(index.v.StringKind.value, machine.memoryState.peek(0));
                },
                else => {
                    machine.memoryState.popn(1);
                    try ER.raiseExpectedTypeError(&machine.memoryState, exprA.position, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.ScopeKind, V.ValueValue.SequenceKind }, expr.v);
                },
            }

            const v = machine.memoryState.pop();
            machine.memoryState.popn(2);
            try machine.memoryState.push(v);
        },
        else => try ER.raiseNamedUserError(&machine.memoryState, "InvalidLHSError", lhs.position),
    }
}

inline fn binaryOp(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
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
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    switch (right.v) {
                        V.ValueValue.StringKind => {
                            machine.memoryState.popn(2);

                            const slices = [_][]const u8{ left.v.StringKind.slice(), right.v.StringKind.slice() };
                            try machine.memoryState.pushOwnedStringValue(try std.mem.concat(machine.memoryState.allocator, u8, &slices));
                        },
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushFloatValue(left.v.FloatKind - @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushFloatValue(left.v.FloatKind - right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushFloatValue(left.v.FloatKind * @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushFloatValue(left.v.FloatKind * right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                                try ER.raiseNamedUserError(&machine.memoryState, "DivideByZeroError", e.position);
                            }
                            try machine.memoryState.pushIntValue(@divTrunc(left.v.IntKind, right.v.IntKind));
                        },
                        V.ValueValue.FloatKind => {
                            if (right.v.FloatKind == 0.0) {
                                try ER.raiseNamedUserError(&machine.memoryState, "DivideByZeroError", e.position);
                            }
                            try machine.memoryState.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) / right.v.FloatKind);
                        },
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            if (right.v.IntKind == 0) {
                                try ER.raiseNamedUserError(&machine.memoryState, "DivideByZeroError", e.position);
                            }
                            try machine.memoryState.pushFloatValue(left.v.FloatKind / @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        },
                        V.ValueValue.FloatKind => {
                            if (right.v.FloatKind == 0.0) {
                                try ER.raiseNamedUserError(&machine.memoryState, "DivideByZeroError", e.position);
                            }
                            try machine.memoryState.pushFloatValue(left.v.FloatKind / right.v.FloatKind);
                        },
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushFloatValue(std.math.pow(V.FloatType, left.v.FloatKind, @as(V.FloatType, @floatFromInt(right.v.IntKind)))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushFloatValue(std.math.pow(V.FloatType, left.v.FloatKind, right.v.FloatKind)),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
            }
        },
        AST.Operator.Modulo => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            if (left.v != V.ValueValue.IntKind or right.v != V.ValueValue.IntKind) {
                try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v);
            }
            if (right.v.IntKind == 0) {
                try ER.raiseNamedUserError(&machine.memoryState, "DivideByZeroError", e.position);
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
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushBoolValue(left.v.FloatKind < @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushBoolValue(left.v.FloatKind < right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.StringKind) {
                        try machine.memoryState.pushBoolValue(std.mem.lessThan(u8, left.v.StringKind.slice(), right.v.StringKind.slice()));
                    } else {
                        try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushBoolValue(left.v.FloatKind <= @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushBoolValue(left.v.FloatKind <= right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.StringKind) {
                        try machine.memoryState.pushBoolValue(std.mem.lessThan(u8, left.v.StringKind.slice(), right.v.StringKind.slice()) or std.mem.eql(u8, left.v.StringKind.slice(), right.v.StringKind.slice()));
                    } else {
                        try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushBoolValue(left.v.FloatKind > @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushBoolValue(left.v.FloatKind > right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.StringKind) {
                        try machine.memoryState.pushBoolValue(std.mem.lessThan(u8, right.v.StringKind.slice(), left.v.StringKind.slice()));
                    } else {
                        try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.memoryState.pushBoolValue(left.v.FloatKind >= @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.memoryState.pushBoolValue(left.v.FloatKind >= right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.StringKind) {
                        try machine.memoryState.pushBoolValue(std.mem.lessThan(u8, right.v.StringKind.slice(), left.v.StringKind.slice()) or std.mem.eql(u8, right.v.StringKind.slice(), left.v.StringKind.slice()));
                    } else {
                        try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, V.ValueKind.BoolKind);
            } else if (left.v.BoolKind) {
                _ = machine.pop();
                try evalExpr(machine, rightAST);
                const right = machine.memoryState.peek(0);

                if (right.v != V.ValueValue.BoolKind) {
                    try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v);
                }
            }
        },
        AST.Operator.Or => {
            try evalExpr(machine, leftAST);

            const left = machine.memoryState.peek(0);
            if (left.v != V.ValueValue.BoolKind) {
                try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, V.ValueKind.BoolKind);
            } else if (!left.v.BoolKind) {
                _ = machine.pop();
                try evalExpr(machine, rightAST);
                const right = machine.memoryState.peek(0);

                if (right.v != V.ValueValue.BoolKind) {
                    try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v);
                }
            }
        },
        AST.Operator.Append => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);
            const left = machine.memoryState.peek(1);
            const right = machine.memoryState.peek(0);

            if (left.v != V.ValueValue.SequenceKind) {
                try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v);
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
                try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v);
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
                try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v);
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
                try ER.raiseIncompatibleOperandTypesError(&machine.memoryState, e.position, e.kind.binaryOp.op, left.v, right.v);
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

inline fn call(machine: *ASTInterpreter, e: *AST.Expression, calleeAST: *AST.Expression, argsAST: []*AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, calleeAST);
    for (argsAST) |arg| {
        try evalExpr(machine, arg);
    }

    callFn(machine, argsAST.len) catch |err| {
        try ER.appendErrorPosition(&machine.memoryState, Errors.Position{ .start = calleeAST.position.start, .end = e.position.end });
        return err;
    };
}

pub inline fn callFn(machine: *ASTInterpreter, numberOfArgs: usize) Errors.RuntimeErrors!void {
    const callee = machine.memoryState.peek(@intCast(numberOfArgs));

    switch (callee.v) {
        V.ValueValue.FunctionKind => try callUserFn(machine, numberOfArgs),
        V.ValueValue.BuiltinKind => try callBuiltinFn(machine, numberOfArgs),
        else => try ER.raiseExpectedTypeError(&machine.memoryState, null, &[_]V.ValueKind{V.ValueValue.FunctionKind}, callee.v),
    }

    const result = machine.memoryState.pop();
    machine.memoryState.popn(@intCast(numberOfArgs + 1));
    try machine.memoryState.push(result);
}

inline fn callUserFn(machine: *ASTInterpreter, numberOfArgs: usize) !void {
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

inline fn callBuiltinFn(machine: *ASTInterpreter, numberOfArgs: usize) !void {
    const callee = machine.memoryState.peek(@intCast(numberOfArgs));

    try callee.v.BuiltinKind.body(machine, numberOfArgs);
}

inline fn catche(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    const sp = machine.memoryState.stack.items.len;
    evalExpr(machine, e.kind.catche.value) catch |err| {
        const value = machine.memoryState.peek(0);

        for (e.kind.catche.cases) |case| {
            try machine.memoryState.pushScope();

            const matched = try matchPattern(machine, case.pattern, value);
            if (matched) {
                const result = evalExpr(machine, case.body);

                machine.memoryState.popScope();
                const v = machine.memoryState.pop();
                machine.memoryState.stack.items.len = sp;
                try machine.memoryState.push(v);

                return result;
            }
            machine.memoryState.popScope();
        }
        return err;
    };
}

inline fn dot(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.dot.record);

    const record = machine.memoryState.pop();

    if (record.v != V.ValueValue.RecordKind) {
        try ER.raiseExpectedTypeError(&machine.memoryState, e.kind.dot.record.position, &[_]V.ValueKind{V.ValueValue.RecordKind}, record.v);
    }

    if (record.v.RecordKind.get(e.kind.dot.field)) |value| {
        try machine.memoryState.push(value);
    } else {
        try machine.memoryState.pushUnitValue();
    }
}

inline fn exprs(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
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

            try evalExprInScope(machine, expr);
        }
    }
}

inline fn idDeclaration(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.idDeclaration.value);
    try machine.memoryState.addToScope(e.kind.idDeclaration.name, machine.memoryState.peek(0));
}

inline fn identifier(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    if (machine.memoryState.getFromScope(e.kind.identifier)) |result| {
        try machine.memoryState.push(result);
    } else {
        const rec = try ER.pushNamedUserError(&machine.memoryState, "UnknownIdentifierError", e.position);
        try rec.v.RecordKind.setU8(machine.memoryState.stringPool, "identifier", try machine.memoryState.newStringPoolValue(e.kind.identifier));
        return Errors.RuntimeErrors.InterpreterError;
    }
}

inline fn ifte(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
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

inline fn indexRange(machine: *ASTInterpreter, exprA: *AST.Expression, startA: ?*AST.Expression, endA: ?*AST.Expression) Errors.RuntimeErrors!void {
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
            try ER.raiseExpectedTypeError(&machine.memoryState, exprA.position, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v);
        },
    }

    const result = machine.memoryState.pop();
    _ = machine.memoryState.pop();
    try machine.memoryState.push(result);
}

inline fn indexPoint(machine: *ASTInterpreter, point: ?*AST.Expression, def: V.IntType) Errors.RuntimeErrors!V.IntType {
    if (point == null) {
        return def;
    } else {
        try evalExpr(machine, point.?);
        const pointV = machine.memoryState.peek(0);
        if (pointV.v != V.ValueValue.IntKind) {
            try ER.raiseExpectedTypeError(&machine.memoryState, point.?.position, &[_]V.ValueKind{V.ValueValue.IntKind}, pointV.v);
        }

        const v = pointV.v.IntKind;
        _ = machine.memoryState.pop();
        return v;
    }
}

inline fn indexValue(machine: *ASTInterpreter, exprA: *AST.Expression, indexA: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, exprA);
    const expr = machine.memoryState.peek(0);

    switch (expr.v) {
        V.ValueValue.RecordKind => {
            try evalExpr(machine, indexA);
            const index = machine.memoryState.peek(0);

            if (index.v != V.ValueValue.StringKind) {
                try ER.raiseExpectedTypeError(&machine.memoryState, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
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
                try ER.raiseExpectedTypeError(&machine.memoryState, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
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
                try ER.raiseExpectedTypeError(&machine.memoryState, indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
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
                try ER.raiseExpectedTypeError(&machine.memoryState, indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
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
            try ER.raiseExpectedTypeError(&machine.memoryState, exprA.position, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v);
        },
    }
}

inline fn literalFunction(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
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

inline fn literalRecord(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
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
                    try ER.raiseExpectedTypeError(&machine.memoryState, entry.record.position, &[_]V.ValueKind{V.ValueValue.RecordKind}, value.v);
                }

                var iterator = value.v.RecordKind.iterator();
                while (iterator.next()) |rv| {
                    try map.v.RecordKind.set(rv.key_ptr.*, rv.value_ptr.*);
                }
            },
        }
    }
}

inline fn literalSequence(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
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
                    try ER.raiseExpectedTypeError(&machine.memoryState, v.sequence.position, &[_]V.ValueKind{V.ValueValue.SequenceKind}, vs.v);
                }

                try seq.v.SequenceKind.appendSlice(vs.v.SequenceKind.items());
            },
        }
    }
}

inline fn match(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.match.value);

    const value = machine.memoryState.peek(0);

    for (e.kind.match.cases) |case| {
        try machine.memoryState.pushScope();

        const matched = try matchPattern(machine, case.pattern, value);
        if (matched) {
            const result = evalExpr(machine, case.body);

            machine.memoryState.popScope();
            const v = machine.memoryState.pop();
            _ = machine.memoryState.pop();
            try machine.memoryState.push(v);

            return result;
        }
        machine.memoryState.popScope();
    }

    try ER.raiseMatchError(&machine.memoryState, e.position, value);
}

fn matchPattern(machine: *ASTInterpreter, p: *AST.Pattern, v: *V.Value) !bool {
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

inline fn notOp(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.notOp.value);

    const v = machine.memoryState.pop();
    if (v.v != V.ValueValue.BoolKind) {
        try ER.raiseExpectedTypeError(&machine.memoryState, e.position, &[_]V.ValueKind{V.ValueValue.BoolKind}, v.v);
    }

    try machine.memoryState.pushBoolValue(!v.v.BoolKind);
}

inline fn patternDeclaration(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.patternDeclaration.value);

    const value: *V.Value = machine.memoryState.peek(0);

    if (!try matchPattern(machine, e.kind.patternDeclaration.pattern, value)) {
        try ER.raiseMatchError(&machine.memoryState, e.position, value);
    }
}

inline fn raise(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.raise.expr);
    try ER.appendErrorPosition(&machine.memoryState, e.position);

    return Errors.RuntimeErrors.InterpreterError;
}

inline fn whilee(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
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

pub const ASTInterpreter = struct {
    memoryState: MS.Runtime,

    pub fn init(allocator: std.mem.Allocator) !ASTInterpreter {
        return ASTInterpreter{
            .memoryState = try MS.Runtime.init(allocator),
        };
    }

    pub fn deinit(self: *ASTInterpreter) void {
        self.memoryState.deinit();
    }

    pub fn createVoidValue(self: *ASTInterpreter) !void {
        try self.memoryState.pushUnitValue();
    }

    pub fn createBoolValue(self: *ASTInterpreter, v: bool) !void {
        try self.memoryState.pushBoolValue(v);
    }

    pub fn createIntValue(self: *ASTInterpreter, v: V.IntType) !void {
        try self.memoryState.pushIntValue(v);
    }

    pub fn createSequenceValue(self: *ASTInterpreter, size: usize) !void {
        return self.memoryState.pushSequenceValue(size);
    }

    pub fn eval(self: *ASTInterpreter, e: *AST.Expression) !void {
        try evalExpr(self, e);
    }

    pub fn parse(self: *ASTInterpreter, name: []const u8, buffer: []const u8) !*AST.Expression {
        const allocator = self.memoryState.allocator;

        var l = Lexer.Lexer.init(allocator);

        l.initBuffer(name, buffer) catch |err| {
            var e = l.grabErr().?;
            defer e.deinit();

            try ER.parserErrorHandler(&self.memoryState, err, e);
            return Errors.RuntimeErrors.InterpreterError;
        };

        var p = Parser.Parser.init(self.memoryState.stringPool, l);

        const ast = p.module() catch |err| {
            var e = p.grabErr().?;
            defer e.deinit();

            try ER.parserErrorHandler(&self.memoryState, err, e);
            return Errors.RuntimeErrors.InterpreterError;
        };
        errdefer AST.destroy(allocator, ast);

        return ast;
    }

    pub fn execute(self: *ASTInterpreter, name: []const u8, buffer: []const u8) !void {
        const ast = try self.parse(name, buffer);
        defer ast.destroy(self.memoryState.allocator);

        try self.eval(ast);
    }

    pub fn pop(self: *ASTInterpreter) *V.Value {
        return self.memoryState.pop();
    }

    pub fn topOfStack(self: *ASTInterpreter) ?*V.Value {
        return self.memoryState.topOfStack();
    }

    pub fn reset(self: *ASTInterpreter) !void {
        try self.memoryState.reset();
    }
};

fn clamp(value: V.IntType, min: V.IntType, max: V.IntType) V.IntType {
    if (value < min) {
        return min;
    } else if (value > max) {
        return max;
    } else {
        return value;
    }
}
