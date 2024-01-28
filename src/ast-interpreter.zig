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
        .literalChar => try machine.runtime.pushCharValue(e.kind.literalChar),
        .literalFloat => try machine.runtime.pushFloatValue(e.kind.literalFloat),
        .literalFunction => try literalFunction(machine, e),
        .literalInt => try machine.createIntValue(e.kind.literalInt),
        .literalRecord => try literalRecord(machine, e),
        .literalSequence => try literalSequence(machine, e),
        .literalString => try machine.runtime.pushStringPoolValue(e.kind.literalString),
        .literalVoid => try machine.createVoidValue(),
        .match => try match(machine, e),
        .notOp => try notOp(machine, e),
        .patternDeclaration => try patternDeclaration(machine, e),
        .raise => try raise(machine, e),
        .whilee => try whilee(machine, e),
    }
}

inline fn evalExprInScope(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    if (e.kind == .exprs) try machine.runtime.pushScope();
    defer if (e.kind == .exprs) machine.runtime.popScope();

    try evalExpr(machine, e);
}

inline fn assignment(machine: *ASTInterpreter, lhs: *AST.Expression, value: *AST.Expression) Errors.RuntimeErrors!void {
    switch (lhs.kind) {
        .identifier => {
            try evalExpr(machine, value);

            if (!(try machine.runtime.updateInScope(lhs.kind.identifier, machine.runtime.peek(0)))) {
                const rec = try ER.pushNamedUserError(&machine.runtime, "UnknownIdentifierError", lhs.position);
                try rec.v.RecordKind.setU8(machine.runtime.stringPool, "identifier", try machine.runtime.newStringPoolValue(lhs.kind.identifier));
                return Errors.RuntimeErrors.InterpreterError;
            }
        },
        .dot => {
            try evalExpr(machine, lhs.kind.dot.record);
            const record = machine.runtime.peek(0);

            if (record.v != V.ValueValue.RecordKind) {
                try ER.raiseExpectedTypeError(&machine.runtime, lhs.kind.dot.record.position, &[_]V.ValueKind{V.ValueValue.RecordKind}, record.v);
            }
            try evalExpr(machine, value);

            try record.v.RecordKind.set(lhs.kind.dot.field, machine.runtime.peek(0));

            const v = machine.runtime.pop();
            _ = machine.runtime.pop();
            try machine.runtime.push(v);
        },
        .indexRange => {
            try evalExpr(machine, lhs.kind.indexRange.expr);
            const sequence = machine.runtime.peek(0);
            if (sequence.v != V.ValueValue.SequenceKind) {
                try ER.raiseExpectedTypeError(&machine.runtime, lhs.kind.indexRange.expr.position, &[_]V.ValueKind{V.ValueValue.SequenceKind}, sequence.v);
            }

            const seqLen = sequence.v.SequenceKind.len();

            const start: V.IntType = clamp(try indexPoint(machine, lhs.kind.indexRange.start, 0), 0, @intCast(seqLen));
            const end: V.IntType = clamp(try indexPoint(machine, lhs.kind.indexRange.end, @intCast(seqLen)), start, @intCast(seqLen));

            try evalExpr(machine, value);
            const v = machine.runtime.peek(0);

            switch (v.v) {
                V.ValueValue.SequenceKind => try sequence.v.SequenceKind.replaceRange(@intCast(start), @intCast(end), v.v.SequenceKind.items()),
                V.ValueValue.UnitKind => try sequence.v.SequenceKind.removeRange(@intCast(start), @intCast(end)),
                else => try ER.raiseExpectedTypeError(&machine.runtime, lhs.kind.indexRange.expr.position, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.UnitKind }, v.v),
            }
            machine.runtime.popn(2);
            try machine.runtime.push(v);
        },
        .indexValue => {
            const exprA = lhs.kind.indexValue.expr;
            const indexA = lhs.kind.indexValue.index;

            try evalExpr(machine, exprA);
            const expr = machine.runtime.peek(0);

            switch (expr.v) {
                V.ValueValue.ScopeKind => {
                    try evalExpr(machine, indexA);
                    const index = machine.runtime.peek(0);

                    if (index.v != V.ValueValue.StringKind) {
                        try ER.raiseExpectedTypeError(&machine.runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
                    }

                    try evalExpr(machine, value);

                    if (!(try expr.v.ScopeKind.update(index.v.StringKind.value, machine.runtime.peek(0)))) {
                        const rec = try ER.pushNamedUserError(&machine.runtime, "UnknownIdentifierError", indexA.position);
                        try rec.v.RecordKind.setU8(machine.runtime.stringPool, "identifier", index);
                        return Errors.RuntimeErrors.InterpreterError;
                    }
                },
                V.ValueValue.SequenceKind => {
                    try evalExpr(machine, indexA);
                    const index = machine.runtime.peek(0);

                    if (index.v != V.ValueValue.IntKind) {
                        try ER.raiseExpectedTypeError(&machine.runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
                    }

                    try evalExpr(machine, value);

                    const seq = expr.v.SequenceKind;
                    const idx = index.v.IntKind;

                    if (idx < 0 or idx >= seq.len()) {
                        try ER.raiseIndexOutOfRangeError(&machine.runtime, indexA.position, idx, @intCast(seq.len()));
                    } else {
                        seq.set(@intCast(idx), machine.runtime.peek(0));
                    }
                },
                V.ValueValue.RecordKind => {
                    try evalExpr(machine, indexA);
                    const index = machine.runtime.peek(0);

                    if (index.v != V.ValueValue.StringKind) {
                        try ER.raiseExpectedTypeError(&machine.runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
                    }

                    try evalExpr(machine, value);

                    try expr.v.RecordKind.set(index.v.StringKind.value, machine.runtime.peek(0));
                },
                else => {
                    machine.runtime.popn(1);
                    try ER.raiseExpectedTypeError(&machine.runtime, exprA.position, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.ScopeKind, V.ValueValue.SequenceKind }, expr.v);
                },
            }

            const v = machine.runtime.pop();
            machine.runtime.popn(2);
            try machine.runtime.push(v);
        },
        else => try ER.raiseNamedUserError(&machine.runtime, "InvalidLHSError", lhs.position),
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

            const right = machine.runtime.peek(0);
            const left = machine.runtime.peek(1);

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.runtime.popn(2);
                            try machine.runtime.pushIntValue(left.v.IntKind + right.v.IntKind);
                        },
                        V.ValueValue.FloatKind => {
                            machine.runtime.popn(2);
                            try machine.runtime.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) + right.v.FloatKind);
                        },
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.runtime.popn(2);
                            try machine.runtime.pushFloatValue(left.v.FloatKind + @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        },
                        V.ValueValue.FloatKind => {
                            machine.runtime.popn(2);
                            try machine.runtime.pushFloatValue(left.v.FloatKind + right.v.FloatKind);
                        },
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.SequenceKind => {
                    switch (right.v) {
                        V.ValueValue.SequenceKind => {
                            try machine.runtime.pushEmptySequenceValue();
                            const seq = machine.runtime.peek(0);
                            try seq.v.SequenceKind.appendSlice(left.v.SequenceKind.items());
                            try seq.v.SequenceKind.appendSlice(right.v.SequenceKind.items());
                            machine.runtime.popn(3);
                            try machine.runtime.push(seq);
                        },
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    switch (right.v) {
                        V.ValueValue.StringKind => {
                            machine.runtime.popn(2);

                            const slices = [_][]const u8{ left.v.StringKind.slice(), right.v.StringKind.slice() };
                            try machine.runtime.pushOwnedStringValue(try std.mem.concat(machine.runtime.allocator, u8, &slices));
                        },
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        V.ValueValue.IntKind => try machine.runtime.pushIntValue(left.v.IntKind - right.v.IntKind),
                        V.ValueValue.FloatKind => try machine.runtime.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) - right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.runtime.pushFloatValue(left.v.FloatKind - @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.runtime.pushFloatValue(left.v.FloatKind - right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        V.ValueValue.IntKind => try machine.runtime.pushIntValue(left.v.IntKind * right.v.IntKind),
                        V.ValueValue.FloatKind => try machine.runtime.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) * right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.runtime.pushFloatValue(left.v.FloatKind * @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.runtime.pushFloatValue(left.v.FloatKind * right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.IntKind) {
                        const mem = try machine.runtime.allocator.alloc(u8, left.v.StringKind.len() * @as(usize, @intCast(right.v.IntKind)));

                        for (0..@intCast(right.v.IntKind)) |index| {
                            std.mem.copyForwards(u8, mem[index * left.v.StringKind.len() ..], left.v.StringKind.slice());
                        }

                        try machine.runtime.pushOwnedStringValue(mem);
                    } else {
                        try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                                try ER.raiseNamedUserError(&machine.runtime, "DivideByZeroError", e.position);
                            }
                            try machine.runtime.pushIntValue(@divTrunc(left.v.IntKind, right.v.IntKind));
                        },
                        V.ValueValue.FloatKind => {
                            if (right.v.FloatKind == 0.0) {
                                try ER.raiseNamedUserError(&machine.runtime, "DivideByZeroError", e.position);
                            }
                            try machine.runtime.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) / right.v.FloatKind);
                        },
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            if (right.v.IntKind == 0) {
                                try ER.raiseNamedUserError(&machine.runtime, "DivideByZeroError", e.position);
                            }
                            try machine.runtime.pushFloatValue(left.v.FloatKind / @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        },
                        V.ValueValue.FloatKind => {
                            if (right.v.FloatKind == 0.0) {
                                try ER.raiseNamedUserError(&machine.runtime, "DivideByZeroError", e.position);
                            }
                            try machine.runtime.pushFloatValue(left.v.FloatKind / right.v.FloatKind);
                        },
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        V.ValueValue.IntKind => try machine.runtime.pushIntValue(std.math.pow(V.IntType, left.v.IntKind, right.v.IntKind)),
                        V.ValueValue.FloatKind => try machine.runtime.pushFloatValue(std.math.pow(V.FloatType, @as(V.FloatType, @floatFromInt(left.v.IntKind)), right.v.FloatKind)),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.runtime.pushFloatValue(std.math.pow(V.FloatType, left.v.FloatKind, @as(V.FloatType, @floatFromInt(right.v.IntKind)))),
                        V.ValueValue.FloatKind => try machine.runtime.pushFloatValue(std.math.pow(V.FloatType, left.v.FloatKind, right.v.FloatKind)),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
            }
        },
        AST.Operator.Modulo => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            if (left.v != V.ValueValue.IntKind or right.v != V.ValueValue.IntKind) {
                try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
            }
            if (right.v.IntKind == 0) {
                try ER.raiseNamedUserError(&machine.runtime, "DivideByZeroError", e.position);
            }
            try machine.runtime.pushIntValue(@mod(left.v.IntKind, right.v.IntKind));
        },
        AST.Operator.LessThan => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.runtime.pushBoolValue(left.v.IntKind < right.v.IntKind),
                        V.ValueValue.FloatKind => try machine.runtime.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) < right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.runtime.pushBoolValue(left.v.FloatKind < @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.runtime.pushBoolValue(left.v.FloatKind < right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.StringKind) {
                        try machine.runtime.pushBoolValue(std.mem.lessThan(u8, left.v.StringKind.slice(), right.v.StringKind.slice()));
                    } else {
                        try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        V.ValueValue.IntKind => try machine.runtime.pushBoolValue(left.v.IntKind <= right.v.IntKind),
                        V.ValueValue.FloatKind => try machine.runtime.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) <= right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.runtime.pushBoolValue(left.v.FloatKind <= @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.runtime.pushBoolValue(left.v.FloatKind <= right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.StringKind) {
                        try machine.runtime.pushBoolValue(std.mem.lessThan(u8, left.v.StringKind.slice(), right.v.StringKind.slice()) or std.mem.eql(u8, left.v.StringKind.slice(), right.v.StringKind.slice()));
                    } else {
                        try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        V.ValueValue.IntKind => try machine.runtime.pushBoolValue(left.v.IntKind > right.v.IntKind),
                        V.ValueValue.FloatKind => try machine.runtime.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) > right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.runtime.pushBoolValue(left.v.FloatKind > @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.runtime.pushBoolValue(left.v.FloatKind > right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.StringKind) {
                        try machine.runtime.pushBoolValue(std.mem.lessThan(u8, right.v.StringKind.slice(), left.v.StringKind.slice()));
                    } else {
                        try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
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
                        V.ValueValue.IntKind => try machine.runtime.pushBoolValue(left.v.IntKind >= right.v.IntKind),
                        V.ValueValue.FloatKind => try machine.runtime.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) >= right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => try machine.runtime.pushBoolValue(left.v.FloatKind >= @as(V.FloatType, @floatFromInt(right.v.IntKind))),
                        V.ValueValue.FloatKind => try machine.runtime.pushBoolValue(left.v.FloatKind >= right.v.FloatKind),
                        else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.StringKind) {
                        try machine.runtime.pushBoolValue(std.mem.lessThan(u8, right.v.StringKind.slice(), left.v.StringKind.slice()) or std.mem.eql(u8, right.v.StringKind.slice(), left.v.StringKind.slice()));
                    } else {
                        try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
                    }
                },
                else => try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v),
            }
        },
        AST.Operator.Equal => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            try machine.runtime.pushBoolValue(V.eq(left, right));
        },
        AST.Operator.NotEqual => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);

            const right = machine.pop();
            const left = machine.pop();

            try machine.runtime.pushBoolValue(!V.eq(left, right));
        },
        AST.Operator.And => {
            try evalExpr(machine, leftAST);

            const left = machine.runtime.peek(0);
            if (left.v != V.ValueValue.BoolKind) {
                try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, V.ValueKind.BoolKind);
            } else if (left.v.BoolKind) {
                _ = machine.pop();
                try evalExpr(machine, rightAST);
                const right = machine.runtime.peek(0);

                if (right.v != V.ValueValue.BoolKind) {
                    try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
                }
            }
        },
        AST.Operator.Or => {
            try evalExpr(machine, leftAST);

            const left = machine.runtime.peek(0);
            if (left.v != V.ValueValue.BoolKind) {
                try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, V.ValueKind.BoolKind);
            } else if (!left.v.BoolKind) {
                _ = machine.pop();
                try evalExpr(machine, rightAST);
                const right = machine.runtime.peek(0);

                if (right.v != V.ValueValue.BoolKind) {
                    try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
                }
            }
        },
        AST.Operator.Append => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);
            const left = machine.runtime.peek(1);
            const right = machine.runtime.peek(0);

            if (left.v != V.ValueValue.SequenceKind) {
                try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
            }

            try machine.runtime.pushEmptySequenceValue();
            const result = machine.runtime.peek(0);

            try result.v.SequenceKind.appendSlice(left.v.SequenceKind.items());
            try result.v.SequenceKind.appendItem(right);

            machine.runtime.popn(3);
            try machine.runtime.push(result);
        },
        AST.Operator.AppendUpdate => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);
            const left = machine.runtime.peek(1);
            const right = machine.runtime.peek(0);

            if (left.v != V.ValueValue.SequenceKind) {
                try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
            }

            try left.v.SequenceKind.appendItem(right);

            machine.runtime.popn(1);
        },
        AST.Operator.Prepend => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);
            const left = machine.runtime.peek(1);
            const right = machine.runtime.peek(0);

            if (right.v != V.ValueValue.SequenceKind) {
                try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
            }

            try machine.runtime.pushEmptySequenceValue();
            const result = machine.runtime.peek(0);

            try result.v.SequenceKind.appendItem(left);
            try result.v.SequenceKind.appendSlice(right.v.SequenceKind.items());

            machine.runtime.popn(3);
            try machine.runtime.push(result);
        },
        AST.Operator.PrependUpdate => {
            try evalExpr(machine, leftAST);
            try evalExpr(machine, rightAST);
            const left = machine.runtime.peek(1);
            const right = machine.runtime.peek(0);

            if (right.v != V.ValueValue.SequenceKind) {
                try ER.raiseIncompatibleOperandTypesError(&machine.runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
            }

            try right.v.SequenceKind.prependItem(left);

            machine.runtime.popn(2);
            try machine.runtime.push(right);
        },
        AST.Operator.Hook => {
            try evalExpr(machine, leftAST);

            const left = machine.runtime.peek(0);

            if (left.v == V.ValueValue.UnitKind) {
                _ = machine.runtime.pop();

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
        try ER.appendErrorPosition(&machine.runtime, Errors.Position{ .start = calleeAST.position.start, .end = e.position.end });
        return err;
    };
}

pub inline fn callFn(machine: *ASTInterpreter, numberOfArgs: usize) Errors.RuntimeErrors!void {
    const callee = machine.runtime.peek(@intCast(numberOfArgs));

    switch (callee.v) {
        V.ValueValue.FunctionKind => try callUserFn(machine, numberOfArgs),
        V.ValueValue.BuiltinKind => try callBuiltinFn(machine, numberOfArgs),
        else => try ER.raiseExpectedTypeError(&machine.runtime, null, &[_]V.ValueKind{V.ValueValue.FunctionKind}, callee.v),
    }

    const result = machine.runtime.pop();
    machine.runtime.popn(@intCast(numberOfArgs + 1));
    try machine.runtime.push(result);
}

inline fn callUserFn(machine: *ASTInterpreter, numberOfArgs: usize) !void {
    const enclosingScope = machine.runtime.scope().?;

    const callee = machine.runtime.peek(@intCast(numberOfArgs));

    try machine.runtime.openScopeFrom(callee.v.FunctionKind.scope);
    defer machine.runtime.restoreScope();

    try machine.runtime.addU8ToScope("__caller_scope__", enclosingScope);

    var lp: usize = 0;
    const maxArgs = @min(numberOfArgs, callee.v.FunctionKind.arguments.len);
    const sp = machine.runtime.stack.items.len - numberOfArgs;
    while (lp < maxArgs) {
        try machine.runtime.addToScope(callee.v.FunctionKind.arguments[lp].name, machine.runtime.stack.items[sp + lp]);
        lp += 1;
    }
    while (lp < callee.v.FunctionKind.arguments.len) {
        const value = callee.v.FunctionKind.arguments[lp].default orelse machine.runtime.unitValue.?;

        try machine.runtime.addToScope(callee.v.FunctionKind.arguments[lp].name, value);
        lp += 1;
    }

    if (callee.v.FunctionKind.restOfArguments != null) {
        if (numberOfArgs > callee.v.FunctionKind.arguments.len) {
            const rest = machine.runtime.stack.items[sp + callee.v.FunctionKind.arguments.len ..];
            try machine.runtime.addArrayValueToScope(callee.v.FunctionKind.restOfArguments.?, rest);
        } else {
            try machine.runtime.addToScope(callee.v.FunctionKind.restOfArguments.?, try machine.runtime.newEmptySequenceValue());
        }
    }

    try evalExpr(machine, callee.v.FunctionKind.body);
}

inline fn callBuiltinFn(machine: *ASTInterpreter, numberOfArgs: usize) !void {
    const callee = machine.runtime.peek(@intCast(numberOfArgs));

    try callee.v.BuiltinKind.body(machine, numberOfArgs);
}

inline fn catche(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    const sp = machine.runtime.stack.items.len;
    evalExpr(machine, e.kind.catche.value) catch |err| {
        const value = machine.runtime.peek(0);

        for (e.kind.catche.cases) |case| {
            try machine.runtime.pushScope();

            const matched = try matchPattern(machine, case.pattern, value);
            if (matched) {
                const result = evalExpr(machine, case.body);

                machine.runtime.popScope();
                const v = machine.runtime.pop();
                machine.runtime.stack.items.len = sp;
                try machine.runtime.push(v);

                return result;
            }
            machine.runtime.popScope();
        }
        return err;
    };
}

inline fn dot(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.dot.record);

    const record = machine.runtime.pop();

    if (record.v != V.ValueValue.RecordKind) {
        try ER.raiseExpectedTypeError(&machine.runtime, e.kind.dot.record.position, &[_]V.ValueKind{V.ValueValue.RecordKind}, record.v);
    }

    if (record.v.RecordKind.get(e.kind.dot.field)) |value| {
        try machine.runtime.push(value);
    } else {
        try machine.runtime.pushUnitValue();
    }
}

inline fn exprs(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    if (e.kind.exprs.len == 0) {
        try machine.runtime.pushUnitValue();
    } else {
        var isFirst = true;

        for (e.kind.exprs) |expr| {
            if (isFirst) {
                isFirst = false;
            } else {
                _ = machine.runtime.pop();
            }

            try evalExprInScope(machine, expr);
        }
    }
}

inline fn idDeclaration(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.idDeclaration.value);
    try machine.runtime.addToScope(e.kind.idDeclaration.name, machine.runtime.peek(0));
}

inline fn identifier(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    if (machine.runtime.getFromScope(e.kind.identifier)) |result| {
        try machine.runtime.push(result);
    } else {
        const rec = try ER.pushNamedUserError(&machine.runtime, "UnknownIdentifierError", e.position);
        try rec.v.RecordKind.setU8(machine.runtime.stringPool, "identifier", try machine.runtime.newStringPoolValue(e.kind.identifier));
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

        const condition = machine.runtime.pop();

        if (condition.v == V.ValueValue.BoolKind and condition.v.BoolKind) {
            try evalExpr(machine, case.then);
            return;
        }
    }

    try machine.createVoidValue();
}

inline fn indexRange(machine: *ASTInterpreter, exprA: *AST.Expression, startA: ?*AST.Expression, endA: ?*AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, exprA);
    const expr = machine.runtime.peek(0);

    switch (expr.v) {
        V.ValueValue.SequenceKind => {
            const seq = expr.v.SequenceKind;

            const start: V.IntType = clamp(try indexPoint(machine, startA, 0), 0, @intCast(seq.len()));
            const end: V.IntType = clamp(try indexPoint(machine, endA, @intCast(seq.len())), start, @intCast(seq.len()));

            try machine.runtime.pushEmptySequenceValue();
            try machine.runtime.peek(0).v.SequenceKind.appendSlice(seq.items()[@intCast(start)..@intCast(end)]);
        },
        V.ValueValue.StringKind => {
            const str = expr.v.StringKind.slice();

            const start: V.IntType = clamp(try indexPoint(machine, startA, 0), 0, @intCast(str.len));
            const end: V.IntType = clamp(try indexPoint(machine, endA, @intCast(str.len)), start, @intCast(str.len));

            try machine.runtime.pushStringValue(str[@intCast(start)..@intCast(end)]);
        },
        else => {
            machine.runtime.popn(1);
            try ER.raiseExpectedTypeError(&machine.runtime, exprA.position, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v);
        },
    }

    const result = machine.runtime.pop();
    _ = machine.runtime.pop();
    try machine.runtime.push(result);
}

inline fn indexPoint(machine: *ASTInterpreter, point: ?*AST.Expression, def: V.IntType) Errors.RuntimeErrors!V.IntType {
    if (point == null) {
        return def;
    } else {
        try evalExpr(machine, point.?);
        const pointV = machine.runtime.peek(0);
        if (pointV.v != V.ValueValue.IntKind) {
            try ER.raiseExpectedTypeError(&machine.runtime, point.?.position, &[_]V.ValueKind{V.ValueValue.IntKind}, pointV.v);
        }

        const v = pointV.v.IntKind;
        _ = machine.runtime.pop();
        return v;
    }
}

inline fn indexValue(machine: *ASTInterpreter, exprA: *AST.Expression, indexA: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, exprA);
    const expr = machine.runtime.peek(0);

    switch (expr.v) {
        V.ValueValue.RecordKind => {
            try evalExpr(machine, indexA);
            const index = machine.runtime.peek(0);

            if (index.v != V.ValueValue.StringKind) {
                try ER.raiseExpectedTypeError(&machine.runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
            }

            machine.runtime.popn(2);

            const value = expr.v.RecordKind.get(index.v.StringKind.value);

            if (value == null) {
                try machine.runtime.pushUnitValue();
            } else {
                try machine.runtime.push(value.?);
            }
        },
        V.ValueValue.ScopeKind => {
            try evalExpr(machine, indexA);
            const index = machine.runtime.peek(0);

            if (index.v != V.ValueValue.StringKind) {
                try ER.raiseExpectedTypeError(&machine.runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
            }

            machine.runtime.popn(2);

            const value = expr.v.ScopeKind.get(index.v.StringKind.value);

            if (value == null) {
                try machine.runtime.pushUnitValue();
            } else {
                try machine.runtime.push(value.?);
            }
        },
        V.ValueValue.SequenceKind => {
            try evalExpr(machine, indexA);
            const index = machine.runtime.peek(0);

            if (index.v != V.ValueValue.IntKind) {
                try ER.raiseExpectedTypeError(&machine.runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
            }

            machine.runtime.popn(2);

            const seq = expr.v.SequenceKind;
            const idx = index.v.IntKind;

            if (idx < 0 or idx >= seq.len()) {
                try machine.runtime.pushUnitValue();
            } else {
                try machine.runtime.push(seq.at(@intCast(idx)));
            }
        },
        V.ValueValue.StringKind => {
            try evalExpr(machine, indexA);
            const index = machine.runtime.peek(0);

            if (index.v != V.ValueValue.IntKind) {
                try ER.raiseExpectedTypeError(&machine.runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
            }

            machine.runtime.popn(2);

            const str = expr.v.StringKind.slice();
            const idx = index.v.IntKind;

            if (idx < 0 or idx >= str.len) {
                try machine.runtime.pushUnitValue();
            } else {
                try machine.runtime.pushCharValue(str[@intCast(idx)]);
            }
        },
        else => {
            machine.runtime.popn(1);
            try ER.raiseExpectedTypeError(&machine.runtime, exprA.position, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v);
        },
    }
}

inline fn literalFunction(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    var arguments = try machine.runtime.allocator.alloc(V.FunctionArgument, e.kind.literalFunction.params.len);

    for (e.kind.literalFunction.params, 0..) |param, index| {
        arguments[index] = V.FunctionArgument{ .name = param.name.incRefR(), .default = null };
    }

    _ = try machine.runtime.pushValue(V.ValueValue{ .FunctionKind = V.FunctionValue{
        .scope = machine.runtime.scope(),
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
    try machine.runtime.pushEmptyRecordValue();
    var map = machine.topOfStack().?;

    for (e.kind.literalRecord) |entry| {
        switch (entry) {
            .value => {
                try evalExpr(machine, entry.value.value);

                const value = machine.runtime.pop();
                try map.v.RecordKind.set(entry.value.key, value);
            },
            .record => {
                try evalExpr(machine, entry.record);

                const value = machine.runtime.pop();
                if (value.v != V.ValueValue.RecordKind) {
                    try ER.raiseExpectedTypeError(&machine.runtime, entry.record.position, &[_]V.ValueKind{V.ValueValue.RecordKind}, value.v);
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
    try machine.runtime.pushEmptySequenceValue();

    for (e.kind.literalSequence) |v| {
        switch (v) {
            .value => {
                try evalExpr(machine, v.value);
                try machine.runtime.appendSequenceItemBang();
            },
            .sequence => {
                try evalExpr(machine, v.sequence);
                try machine.runtime.appendSequenceItemsBang();
            },
        }
    }
}

inline fn match(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.match.value);

    const value = machine.runtime.peek(0);

    for (e.kind.match.cases) |case| {
        try machine.runtime.pushScope();

        const matched = try matchPattern(machine, case.pattern, value);
        if (matched) {
            const result = evalExpr(machine, case.body);

            machine.runtime.popScope();
            const v = machine.runtime.pop();
            _ = machine.runtime.pop();
            try machine.runtime.push(v);

            return result;
        }
        machine.runtime.popScope();
    }

    try ER.raiseMatchError(&machine.runtime, e.position, value);
}

fn matchPattern(machine: *ASTInterpreter, p: *AST.Pattern, v: *V.Value) !bool {
    return switch (p.kind) {
        .identifier => {
            if (!std.mem.eql(u8, p.kind.identifier.slice(), "_")) {
                try machine.runtime.addToScope(p.kind.identifier, v);
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
                    try machine.runtime.addToScope(if (entry.id == null) entry.key else entry.id.?, value.?);
                } else if (entry.pattern != null and !try matchPattern(machine, entry.pattern.?, value.?)) {
                    return false;
                }
            }

            if (p.kind.record.id != null) {
                try machine.runtime.addToScope(p.kind.record.id.?, v);
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
                var newSeq = try V.SequenceValue.init(machine.runtime.allocator);
                if (seq.len() > p.kind.sequence.patterns.len) {
                    try newSeq.appendSlice(seq.items()[p.kind.sequence.patterns.len..]);
                }
                try machine.runtime.addToScope(p.kind.sequence.restOfPatterns.?, try machine.runtime.newValue(V.ValueValue{ .SequenceKind = newSeq }));
            }

            if (p.kind.sequence.id != null) {
                try machine.runtime.addToScope(p.kind.sequence.id.?, v);
            }

            return true;
        },
        .void => return v.v == V.ValueValue.UnitKind,
    };
}

inline fn notOp(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.notOp.value);

    const v = machine.runtime.pop();
    if (v.v != V.ValueValue.BoolKind) {
        try ER.raiseExpectedTypeError(&machine.runtime, e.position, &[_]V.ValueKind{V.ValueValue.BoolKind}, v.v);
    }

    try machine.runtime.pushBoolValue(!v.v.BoolKind);
}

inline fn patternDeclaration(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.patternDeclaration.value);

    const value: *V.Value = machine.runtime.peek(0);

    if (!try matchPattern(machine, e.kind.patternDeclaration.pattern, value)) {
        try ER.raiseMatchError(&machine.runtime, e.position, value);
    }
}

inline fn raise(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(machine, e.kind.raise.expr);
    try ER.appendErrorPosition(&machine.runtime, e.position);

    return Errors.RuntimeErrors.InterpreterError;
}

inline fn whilee(machine: *ASTInterpreter, e: *AST.Expression) Errors.RuntimeErrors!void {
    while (true) {
        try evalExpr(machine, e.kind.whilee.condition);

        const condition = machine.runtime.pop();

        if (condition.v != V.ValueValue.BoolKind or !condition.v.BoolKind) {
            break;
        }

        try evalExpr(machine, e.kind.whilee.body);

        _ = machine.runtime.pop();
    }

    try machine.createVoidValue();
}

pub const ASTInterpreter = struct {
    runtime: MS.Runtime,

    pub fn init(allocator: std.mem.Allocator) !ASTInterpreter {
        return ASTInterpreter{
            .runtime = try MS.Runtime.init(allocator),
        };
    }

    pub fn deinit(self: *ASTInterpreter) void {
        self.runtime.deinit();
    }

    pub fn createVoidValue(self: *ASTInterpreter) !void {
        try self.runtime.pushUnitValue();
    }

    pub fn createBoolValue(self: *ASTInterpreter, v: bool) !void {
        try self.runtime.pushBoolValue(v);
    }

    pub fn createIntValue(self: *ASTInterpreter, v: V.IntType) !void {
        try self.runtime.pushIntValue(v);
    }

    pub fn createSequenceValue(self: *ASTInterpreter, size: usize) !void {
        return self.runtime.pushSequenceValue(size);
    }

    pub fn eval(self: *ASTInterpreter, e: *AST.Expression) !void {
        try evalExpr(self, e);
    }

    pub fn parse(self: *ASTInterpreter, name: []const u8, buffer: []const u8) !*AST.Expression {
        const allocator = self.runtime.allocator;

        var l = Lexer.Lexer.init(allocator);

        l.initBuffer(name, buffer) catch |err| {
            var e = l.grabErr().?;
            defer e.deinit();

            try ER.parserErrorHandler(&self.runtime, err, e);
            return Errors.RuntimeErrors.InterpreterError;
        };

        var p = Parser.Parser.init(self.runtime.stringPool, l);

        const ast = p.module() catch |err| {
            var e = p.grabErr().?;
            defer e.deinit();

            try ER.parserErrorHandler(&self.runtime, err, e);
            return Errors.RuntimeErrors.InterpreterError;
        };
        errdefer AST.destroy(allocator, ast);

        return ast;
    }

    pub fn execute(self: *ASTInterpreter, name: []const u8, buffer: []const u8) !void {
        const ast = try self.parse(name, buffer);
        defer ast.destroy(self.runtime.allocator);

        try self.eval(ast);
    }

    pub fn pop(self: *ASTInterpreter) *V.Value {
        return self.runtime.pop();
    }

    pub fn topOfStack(self: *ASTInterpreter) ?*V.Value {
        return self.runtime.topOfStack();
    }

    pub fn reset(self: *ASTInterpreter) !void {
        try self.runtime.reset();
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
