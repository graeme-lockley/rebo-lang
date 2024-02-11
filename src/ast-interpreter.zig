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

const Runtime = MS.Runtime;

pub fn evalExpr(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    switch (e.kind) {
        .assignment => try assignment(runtime, e.kind.assignment.lhs, e.kind.assignment.value),
        .binaryOp => try binaryOp(runtime, e),
        .call => try call(runtime, e, e.kind.call.callee, e.kind.call.args),
        .catche => try catche(runtime, e),
        .dot => try dot(runtime, e),
        .exprs => try exprs(runtime, e),
        .idDeclaration => try idDeclaration(runtime, e),
        .identifier => try identifier(runtime, e),
        .ifte => try ifte(runtime, e),
        .indexRange => try indexRange(runtime, e.kind.indexRange.expr, e.kind.indexRange.start, e.kind.indexRange.end),
        .indexValue => try indexValue(runtime, e.kind.indexValue.expr, e.kind.indexValue.index),
        .literalBool => try runtime.pushBoolValue(e.kind.literalBool),
        .literalChar => try runtime.pushCharValue(e.kind.literalChar),
        .literalFloat => try runtime.pushFloatValue(e.kind.literalFloat),
        .literalFunction => try literalFunction(runtime, e),
        .literalInt => try runtime.pushIntValue(e.kind.literalInt),
        .literalRecord => try literalRecord(runtime, e),
        .literalSequence => try literalSequence(runtime, e),
        .literalString => try runtime.pushStringPoolValue(e.kind.literalString),
        .literalVoid => try runtime.pushUnitValue(),
        .match => try match(runtime, e),
        .notOp => try notOp(runtime, e),
        .patternDeclaration => try patternDeclaration(runtime, e),
        .raise => try raise(runtime, e),
        .whilee => try whilee(runtime, e),
    }
}

fn evalExprInScope(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    if (e.kind == .exprs) try runtime.pushScope();
    defer if (e.kind == .exprs) runtime.popScope();

    try evalExpr(runtime, e);
}

fn assignment(runtime: *Runtime, lhs: *AST.Expression, value: *AST.Expression) Errors.RuntimeErrors!void {
    switch (lhs.kind) {
        .identifier => {
            try evalExpr(runtime, value);
            try runtime.pushStringPoolValue(lhs.kind.identifier);
            try runtime.assign();
        },
        .dot => {
            try evalExpr(runtime, lhs.kind.dot.record);
            const record = runtime.peek(0);

            if (record.v != V.ValueValue.RecordKind) {
                try ER.raiseExpectedTypeError(runtime, lhs.kind.dot.record.position, &[_]V.ValueKind{V.ValueValue.RecordKind}, record.v);
            }
            try evalExpr(runtime, value);

            try record.v.RecordKind.set(lhs.kind.dot.field, runtime.peek(0));

            const v = runtime.pop();
            _ = runtime.pop();
            try runtime.push(v);
        },
        .indexRange => {
            try evalExpr(runtime, lhs.kind.indexRange.expr);
            const sequence = runtime.peek(0);
            if (sequence.v != V.ValueValue.SequenceKind) {
                try ER.raiseExpectedTypeError(runtime, lhs.kind.indexRange.expr.position, &[_]V.ValueKind{V.ValueValue.SequenceKind}, sequence.v);
            }

            const seqLen = sequence.v.SequenceKind.len();

            const start: V.IntType = clamp(try indexPoint(runtime, lhs.kind.indexRange.start, 0), 0, @intCast(seqLen));
            const end: V.IntType = clamp(try indexPoint(runtime, lhs.kind.indexRange.end, @intCast(seqLen)), start, @intCast(seqLen));

            try evalExpr(runtime, value);
            const v = runtime.peek(0);

            switch (v.v) {
                V.ValueValue.SequenceKind => try sequence.v.SequenceKind.replaceRange(@intCast(start), @intCast(end), v.v.SequenceKind.items()),
                V.ValueValue.UnitKind => try sequence.v.SequenceKind.removeRange(@intCast(start), @intCast(end)),
                else => try ER.raiseExpectedTypeError(runtime, lhs.kind.indexRange.expr.position, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.UnitKind }, v.v),
            }
            runtime.popn(2);
            try runtime.push(v);
        },
        .indexValue => {
            const exprA = lhs.kind.indexValue.expr;
            const indexA = lhs.kind.indexValue.index;

            try evalExpr(runtime, exprA);
            const expr = runtime.peek(0);

            switch (expr.v) {
                V.ValueValue.ScopeKind => {
                    try evalExpr(runtime, indexA);
                    const index = runtime.peek(0);

                    if (index.v != V.ValueValue.StringKind) {
                        try ER.raiseExpectedTypeError(runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
                    }

                    try evalExpr(runtime, value);

                    if (!(try expr.v.ScopeKind.update(index.v.StringKind.value, runtime.peek(0)))) {
                        const rec = try ER.pushNamedUserError(runtime, "UnknownIdentifierError", indexA.position);
                        try rec.v.RecordKind.setU8(runtime.stringPool, "identifier", index);
                        return Errors.RuntimeErrors.InterpreterError;
                    }
                },
                V.ValueValue.SequenceKind => {
                    try evalExpr(runtime, indexA);
                    const index = runtime.peek(0);

                    if (index.v != V.ValueValue.IntKind) {
                        try ER.raiseExpectedTypeError(runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
                    }

                    try evalExpr(runtime, value);

                    const seq = expr.v.SequenceKind;
                    const idx = index.v.IntKind;

                    if (idx < 0 or idx >= seq.len()) {
                        try ER.raiseIndexOutOfRangeError(runtime, indexA.position, idx, @intCast(seq.len()));
                    } else {
                        seq.set(@intCast(idx), runtime.peek(0));
                    }
                },
                V.ValueValue.RecordKind => {
                    try evalExpr(runtime, indexA);
                    const index = runtime.peek(0);

                    if (index.v != V.ValueValue.StringKind) {
                        try ER.raiseExpectedTypeError(runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
                    }

                    try evalExpr(runtime, value);

                    try expr.v.RecordKind.set(index.v.StringKind.value, runtime.peek(0));
                },
                else => {
                    runtime.popn(1);
                    try ER.raiseExpectedTypeError(runtime, exprA.position, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.ScopeKind, V.ValueValue.SequenceKind }, expr.v);
                },
            }

            const v = runtime.pop();
            runtime.popn(2);
            try runtime.push(v);
        },
        else => try ER.raiseNamedUserError(runtime, "InvalidLHSError", lhs.position),
    }
}

fn binaryOp(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    const leftAST = e.kind.binaryOp.left;
    const op = e.kind.binaryOp.op;
    const rightAST = e.kind.binaryOp.right;

    switch (op) {
        AST.Operator.Plus => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.add(e.position);
        },
        AST.Operator.Minus => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.subtract(e.position);
        },
        AST.Operator.Times => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.multiply(e.position);
        },
        AST.Operator.Divide => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.divide(e.position);
        },
        AST.Operator.Power => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.power(e.position);
        },
        AST.Operator.Modulo => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.modulo(e.position);
        },
        AST.Operator.LessThan => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.lessThan(e.position);
        },
        AST.Operator.LessEqual => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.lessEqual(e.position);
        },
        AST.Operator.GreaterThan => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.greaterThan(e.position);
        },
        AST.Operator.GreaterEqual => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.greaterEqual(e.position);
        },
        AST.Operator.Equal => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.equals();
        },
        AST.Operator.NotEqual => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.notEquals();
        },
        AST.Operator.And => {
            try evalExpr(runtime, leftAST);

            const left = runtime.peek(0);
            if (left.v != V.ValueValue.BoolKind) {
                try ER.raiseIncompatibleOperandTypesError(runtime, e.position, e.kind.binaryOp.op, left.v, V.ValueKind.BoolKind);
            } else if (left.v.BoolKind) {
                _ = runtime.pop();
                try evalExpr(runtime, rightAST);
                const right = runtime.peek(0);

                if (right.v != V.ValueValue.BoolKind) {
                    try ER.raiseIncompatibleOperandTypesError(runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
                }
            }
        },
        AST.Operator.Or => {
            try evalExpr(runtime, leftAST);

            const left = runtime.peek(0);
            if (left.v != V.ValueValue.BoolKind) {
                try ER.raiseIncompatibleOperandTypesError(runtime, e.position, e.kind.binaryOp.op, left.v, V.ValueKind.BoolKind);
            } else if (!left.v.BoolKind) {
                _ = runtime.pop();
                try evalExpr(runtime, rightAST);
                const right = runtime.peek(0);

                if (right.v != V.ValueValue.BoolKind) {
                    try ER.raiseIncompatibleOperandTypesError(runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
                }
            }
        },
        AST.Operator.Append => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);
            const left = runtime.peek(1);
            const right = runtime.peek(0);

            if (left.v != V.ValueValue.SequenceKind) {
                try ER.raiseIncompatibleOperandTypesError(runtime, e.position, e.kind.binaryOp.op, left.v, right.v);
            }

            try runtime.appendSequenceItem(e.position);
        },
        AST.Operator.AppendUpdate => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.appendSequenceItemBang(e.position);
        },
        AST.Operator.Prepend => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.prependSequenceItem(e.position);
        },
        AST.Operator.PrependUpdate => {
            try evalExpr(runtime, leftAST);
            try evalExpr(runtime, rightAST);

            try runtime.prependSequenceItemBang(e.position);
        },
        AST.Operator.Hook => {
            try evalExpr(runtime, leftAST);

            const left = runtime.peek(0);

            if (left.v == V.ValueValue.UnitKind) {
                _ = runtime.pop();

                try evalExpr(runtime, rightAST);
            }
        },

        // else => unreachable,
    }
}

fn call(runtime: *Runtime, e: *AST.Expression, calleeAST: *AST.Expression, argsAST: []*AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(runtime, calleeAST);
    for (argsAST) |arg| {
        try evalExpr(runtime, arg);
    }

    runtime.callFn(argsAST.len) catch |err| {
        try ER.appendErrorPosition(runtime, Errors.Position{ .start = calleeAST.position.start, .end = e.position.end });
        return err;
    };
}

fn catche(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    const sp = runtime.stack.items.len;
    evalExpr(runtime, e.kind.catche.value) catch |err| {
        const value = runtime.peek(0);

        for (e.kind.catche.cases) |case| {
            try runtime.pushScope();

            const matched = try matchPattern(runtime, case.pattern, value);
            if (matched) {
                const result = evalExpr(runtime, case.body);

                runtime.popScope();
                const v = runtime.pop();
                runtime.stack.items.len = sp;
                try runtime.push(v);

                return result;
            }
            runtime.popScope();
        }
        return err;
    };
}

fn dot(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(runtime, e.kind.dot.record);

    const record = runtime.pop();

    if (record.v != V.ValueValue.RecordKind) {
        try ER.raiseExpectedTypeError(runtime, e.kind.dot.record.position, &[_]V.ValueKind{V.ValueValue.RecordKind}, record.v);
    }

    if (record.v.RecordKind.get(e.kind.dot.field)) |value| {
        try runtime.push(value);
    } else {
        try runtime.pushUnitValue();
    }
}

fn exprs(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    if (e.kind.exprs.len == 0) {
        try runtime.pushUnitValue();
    } else {
        var isFirst = true;

        for (e.kind.exprs) |expr| {
            if (isFirst) {
                isFirst = false;
            } else {
                _ = runtime.pop();
            }

            try evalExprInScope(runtime, expr);
        }
    }
}

fn idDeclaration(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(runtime, e.kind.idDeclaration.value);
    try runtime.pushStringPoolValue(e.kind.idDeclaration.name);
    try runtime.bind();
}

fn identifier(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    if (runtime.getFromScope(e.kind.identifier)) |result| {
        try runtime.push(result);
    } else {
        const rec = try ER.pushNamedUserError(runtime, "UnknownIdentifierError", e.position);
        try rec.v.RecordKind.setU8(runtime.stringPool, "identifier", try runtime.newStringPoolValue(e.kind.identifier));
        return Errors.RuntimeErrors.InterpreterError;
    }
}

fn ifte(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    for (e.kind.ifte) |case| {
        if (case.condition == null) {
            try evalExpr(runtime, case.then);
            return;
        }

        try evalExpr(runtime, case.condition.?);

        const condition = runtime.pop();

        if (condition.v == V.ValueValue.BoolKind and condition.v.BoolKind) {
            try evalExpr(runtime, case.then);
            return;
        }
    }

    try runtime.pushUnitValue();
}

fn indexRange(runtime: *Runtime, exprA: *AST.Expression, startA: ?*AST.Expression, endA: ?*AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(runtime, exprA);
    const expr = runtime.peek(0);

    switch (expr.v) {
        V.ValueValue.SequenceKind => {
            const seq = expr.v.SequenceKind;

            const start: V.IntType = clamp(try indexPoint(runtime, startA, 0), 0, @intCast(seq.len()));
            const end: V.IntType = clamp(try indexPoint(runtime, endA, @intCast(seq.len())), start, @intCast(seq.len()));

            try runtime.pushEmptySequenceValue();
            try runtime.peek(0).v.SequenceKind.appendSlice(seq.items()[@intCast(start)..@intCast(end)]);
        },
        V.ValueValue.StringKind => {
            const str = expr.v.StringKind.slice();

            const start: V.IntType = clamp(try indexPoint(runtime, startA, 0), 0, @intCast(str.len));
            const end: V.IntType = clamp(try indexPoint(runtime, endA, @intCast(str.len)), start, @intCast(str.len));

            try runtime.pushStringValue(str[@intCast(start)..@intCast(end)]);
        },
        else => {
            runtime.popn(1);
            try ER.raiseExpectedTypeError(runtime, exprA.position, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v);
        },
    }

    const result = runtime.pop();
    _ = runtime.pop();
    try runtime.push(result);
}

fn indexPoint(runtime: *Runtime, point: ?*AST.Expression, def: V.IntType) Errors.RuntimeErrors!V.IntType {
    if (point == null) {
        return def;
    } else {
        try evalExpr(runtime, point.?);
        const pointV = runtime.peek(0);
        if (pointV.v != V.ValueValue.IntKind) {
            try ER.raiseExpectedTypeError(runtime, point.?.position, &[_]V.ValueKind{V.ValueValue.IntKind}, pointV.v);
        }

        const v = pointV.v.IntKind;
        _ = runtime.pop();
        return v;
    }
}

fn indexValue(runtime: *Runtime, exprA: *AST.Expression, indexA: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(runtime, exprA);
    const expr = runtime.peek(0);

    switch (expr.v) {
        V.ValueValue.RecordKind => {
            try evalExpr(runtime, indexA);
            const index = runtime.peek(0);

            if (index.v != V.ValueValue.StringKind) {
                try ER.raiseExpectedTypeError(runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
            }

            runtime.popn(2);

            const value = expr.v.RecordKind.get(index.v.StringKind.value);

            if (value == null) {
                try runtime.pushUnitValue();
            } else {
                try runtime.push(value.?);
            }
        },
        V.ValueValue.ScopeKind => {
            try evalExpr(runtime, indexA);
            const index = runtime.peek(0);

            if (index.v != V.ValueValue.StringKind) {
                try ER.raiseExpectedTypeError(runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
            }

            runtime.popn(2);

            const value = expr.v.ScopeKind.get(index.v.StringKind.value);

            if (value == null) {
                try runtime.pushUnitValue();
            } else {
                try runtime.push(value.?);
            }
        },
        V.ValueValue.SequenceKind => {
            try evalExpr(runtime, indexA);
            const index = runtime.peek(0);

            if (index.v != V.ValueValue.IntKind) {
                try ER.raiseExpectedTypeError(runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
            }

            runtime.popn(2);

            const seq = expr.v.SequenceKind;
            const idx = index.v.IntKind;

            if (idx < 0 or idx >= seq.len()) {
                try runtime.pushUnitValue();
            } else {
                try runtime.push(seq.at(@intCast(idx)));
            }
        },
        V.ValueValue.StringKind => {
            try evalExpr(runtime, indexA);
            const index = runtime.peek(0);

            if (index.v != V.ValueValue.IntKind) {
                try ER.raiseExpectedTypeError(runtime, indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
            }

            runtime.popn(2);

            const str = expr.v.StringKind.slice();
            const idx = index.v.IntKind;

            if (idx < 0 or idx >= str.len) {
                try runtime.pushUnitValue();
            } else {
                try runtime.pushCharValue(str[@intCast(idx)]);
            }
        },
        else => {
            runtime.popn(1);
            try ER.raiseExpectedTypeError(runtime, exprA.position, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v);
        },
    }
}

fn literalFunction(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    var arguments = try runtime.allocator.alloc(V.FunctionArgument, e.kind.literalFunction.params.len);

    for (e.kind.literalFunction.params, 0..) |param, index| {
        arguments[index] = V.FunctionArgument{ .name = param.name.incRefR(), .default = null };
    }

    _ = try runtime.pushValue(V.ValueValue{ .ASTFunctionKind = V.ASTFunctionValue{
        .scope = runtime.scope(),
        .arguments = arguments,
        .restOfArguments = if (e.kind.literalFunction.restOfParams == null) null else e.kind.literalFunction.restOfParams.?.incRefR(),
        .body = e.kind.literalFunction.body.incRefR(),
    } });

    for (e.kind.literalFunction.params, 0..) |param, index| {
        if (param.default != null) {
            try evalExpr(runtime, param.default.?);
            arguments[index].default = runtime.pop();
        }
    }
}

fn literalRecord(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    try runtime.pushEmptyRecordValue();
    var map = runtime.topOfStack().?;

    for (e.kind.literalRecord) |entry| {
        switch (entry) {
            .value => {
                try runtime.pushStringPoolValue(entry.value.key);
                try evalExpr(runtime, entry.value.value);
                try runtime.setRecordItemBang(e.position);
            },
            .record => {
                try evalExpr(runtime, entry.record);

                const value = runtime.pop();
                if (value.v != V.ValueValue.RecordKind) {
                    try ER.raiseExpectedTypeError(runtime, entry.record.position, &[_]V.ValueKind{V.ValueValue.RecordKind}, value.v);
                }

                var iterator = value.v.RecordKind.iterator();
                while (iterator.next()) |rv| {
                    try map.v.RecordKind.set(rv.key_ptr.*, rv.value_ptr.*);
                }
            },
        }
    }
}

fn literalSequence(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    try runtime.pushEmptySequenceValue();

    for (e.kind.literalSequence) |v| {
        switch (v) {
            .value => {
                try evalExpr(runtime, v.value);
                try runtime.appendSequenceItemBang(e.position);
            },
            .sequence => {
                try evalExpr(runtime, v.sequence);
                try runtime.appendSequenceItemsBang(e.position, v.sequence.position);
            },
        }
    }
}

fn match(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(runtime, e.kind.match.value);

    const value = runtime.peek(0);

    for (e.kind.match.cases) |case| {
        try runtime.pushScope();

        const matched = try matchPattern(runtime, case.pattern, value);
        if (matched) {
            const result = evalExpr(runtime, case.body);

            runtime.popScope();
            const v = runtime.pop();
            _ = runtime.pop();
            try runtime.push(v);

            return result;
        }
        runtime.popScope();
    }

    try ER.raiseMatchError(runtime, e.position, value);
}

fn matchPattern(runtime: *Runtime, p: *AST.Pattern, v: *V.Value) !bool {
    return switch (p.kind) {
        .identifier => {
            if (!std.mem.eql(u8, p.kind.identifier.slice(), "_")) {
                try runtime.addToScope(p.kind.identifier, v);
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
                    try runtime.addToScope(if (entry.id == null) entry.key else entry.id.?, value.?);
                } else if (entry.pattern != null and !try matchPattern(runtime, entry.pattern.?, value.?)) {
                    return false;
                }
            }

            if (p.kind.record.id != null) {
                try runtime.addToScope(p.kind.record.id.?, v);
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
                if (!try matchPattern(runtime, p.kind.sequence.patterns[index], seq.at(index))) return false;
                index += 1;
            }

            if (p.kind.sequence.restOfPatterns != null and !std.mem.eql(u8, p.kind.sequence.restOfPatterns.?.slice(), "_")) {
                var newSeq = try V.SequenceValue.init(runtime.allocator);
                if (seq.len() > p.kind.sequence.patterns.len) {
                    try newSeq.appendSlice(seq.items()[p.kind.sequence.patterns.len..]);
                }
                try runtime.addToScope(p.kind.sequence.restOfPatterns.?, try runtime.newValue(V.ValueValue{ .SequenceKind = newSeq }));
            }

            if (p.kind.sequence.id != null) {
                try runtime.addToScope(p.kind.sequence.id.?, v);
            }

            return true;
        },
        .void => return v.v == V.ValueValue.UnitKind,
    };
}

fn notOp(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(runtime, e.kind.notOp.value);

    const v = runtime.pop();
    if (v.v != V.ValueValue.BoolKind) {
        try ER.raiseExpectedTypeError(runtime, e.position, &[_]V.ValueKind{V.ValueValue.BoolKind}, v.v);
    }

    try runtime.pushBoolValue(!v.v.BoolKind);
}

fn patternDeclaration(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(runtime, e.kind.patternDeclaration.value);

    const value: *V.Value = runtime.peek(0);

    if (!try matchPattern(runtime, e.kind.patternDeclaration.pattern, value)) {
        try ER.raiseMatchError(runtime, e.position, value);
    }
}

fn raise(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    try evalExpr(runtime, e.kind.raise.expr);
    try ER.appendErrorPosition(runtime, e.position);

    return Errors.RuntimeErrors.InterpreterError;
}

fn whilee(runtime: *Runtime, e: *AST.Expression) Errors.RuntimeErrors!void {
    while (true) {
        try evalExpr(runtime, e.kind.whilee.condition);

        const condition = runtime.pop();

        if (condition.v != V.ValueValue.BoolKind or !condition.v.BoolKind) {
            break;
        }

        try evalExpr(runtime, e.kind.whilee.body);

        _ = runtime.pop();
    }

    try runtime.pushUnitValue();
}

pub fn parse(self: *Runtime, name: []const u8, buffer: []const u8) !*AST.Expression {
    const allocator = self.allocator;

    var l = Lexer.Lexer.init(allocator);

    l.initBuffer(name, buffer) catch |err| {
        var e = l.grabErr().?;
        defer e.deinit();

        try ER.parserErrorHandler(self, err, e);
        return Errors.RuntimeErrors.InterpreterError;
    };

    var p = Parser.Parser.init(self.stringPool, l);

    const ast = p.module() catch |err| {
        var e = p.grabErr().?;
        defer e.deinit();

        try ER.parserErrorHandler(self, err, e);
        return Errors.RuntimeErrors.InterpreterError;
    };
    errdefer AST.destroy(allocator, ast);

    return ast;
}

pub fn execute(self: *Runtime, name: []const u8, buffer: []const u8) !void {
    const ast = try parse(self, name, buffer);
    defer ast.destroy(self.allocator);

    try evalExpr(self, ast);
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
