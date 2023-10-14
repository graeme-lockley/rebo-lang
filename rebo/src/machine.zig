const std = @import("std");

const AST = @import("./ast.zig");
const Builtins = @import("./builtins.zig");
const Errors = @import("./errors.zig");
const Lexer = @import("./lexer.zig");
const MS = @import("./memory_state.zig");
const Parser = @import("./parser.zig");
const V = @import("./value.zig");

fn evalExpr(machine: *Machine, e: *AST.Expression) bool {
    switch (e.kind) {
        .assignment => return assignment(machine, e.kind.assignment.lhs, e.kind.assignment.value),
        .binaryOp => return binaryOp(machine, e),
        .call => return call(machine, e.kind.call.callee, e.kind.call.args),
        .declaration => return declaration(machine, e),
        .dot => return dot(machine, e),
        .exprs => return exprs(machine, e),
        .identifier => return identifier(machine, e),
        .ifte => return ifte(machine, e),
        .indexRange => return indexRange(machine, e.kind.indexRange.expr, e.kind.indexRange.start, e.kind.indexRange.end),
        .indexValue => return indexValue(machine, e.kind.indexValue.expr, e.kind.indexValue.index),
        .literalBool => {
            machine.createBoolValue(e.kind.literalBool) catch |err| return errorHandler(err);
        },
        .literalChar => {
            machine.memoryState.pushCharValue(e.kind.literalChar) catch |err| return errorHandler(err);
        },
        .literalFloat => {
            machine.memoryState.pushFloatValue(e.kind.literalFloat) catch |err| return errorHandler(err);
        },
        .literalFunction => {
            var arguments = machine.memoryState.allocator.alloc(V.FunctionArgument, e.kind.literalFunction.params.len) catch |err| return errorHandler(err);

            for (e.kind.literalFunction.params, 0..) |param, index| {
                arguments[index] = V.FunctionArgument{ .name = machine.memoryState.allocator.dupe(u8, param.name) catch |err| return errorHandler(err), .default = null };
            }

            _ = machine.memoryState.pushValue(V.ValueValue{ .FunctionKind = V.FunctionValue{
                .scope = machine.memoryState.scope(),
                .arguments = arguments,
                .restOfArguments = if (e.kind.literalFunction.restOfParams == null) null else machine.memoryState.allocator.dupe(u8, e.kind.literalFunction.restOfParams.?) catch |err| return errorHandler(err),
                .body = e.kind.literalFunction.body,
            } }) catch |err| return errorHandler(err);

            for (e.kind.literalFunction.params, 0..) |param, index| {
                if (param.default != null) {
                    if (evalExpr(machine, param.default.?)) return true;
                    arguments[index].default = machine.pop();
                }
            }
        },
        .literalInt => {
            machine.createIntValue(e.kind.literalInt) catch |err| return errorHandler(err);
        },
        .literalRecord => {
            machine.memoryState.pushEmptyMapValue() catch |err| return errorHandler(err);
            var map = machine.topOfStack().?;

            for (e.kind.literalRecord) |entry| {
                switch (entry) {
                    .value => {
                        if (evalExpr(machine, entry.value.value)) return true;

                        const value = machine.memoryState.pop();
                        V.recordSet(machine.memoryState.allocator, &map.v.RecordKind, entry.value.key, value) catch |err| return errorHandler(err);
                    },
                    .record => {
                        if (evalExpr(machine, entry.record)) return true;

                        const value = machine.memoryState.pop();
                        if (value.v != V.ValueValue.RecordKind) {
                            machine.replaceErr(Errors.expectedATypeError(machine.memoryState.allocator, entry.record.position, V.ValueValue.RecordKind, value.v) catch |err| return errorHandler(err));
                            return true;
                        }

                        var iterator = value.v.RecordKind.iterator();
                        while (iterator.next()) |rv| {
                            V.recordSet(machine.memoryState.allocator, &map.v.RecordKind, rv.key_ptr.*, rv.value_ptr.*) catch |err| return errorHandler(err);
                        }
                    },
                }
            }
        },
        .literalSequence => {
            machine.memoryState.pushEmptySequenceValue() catch |err| return errorHandler(err);
            const seq = machine.memoryState.peek(0);

            for (e.kind.literalSequence) |v| {
                switch (v) {
                    .value => {
                        if (evalExpr(machine, v.value)) return true;
                        seq.v.SequenceKind.append(machine.memoryState.pop()) catch |err| return errorHandler(err);
                    },
                    .sequence => {
                        if (evalExpr(machine, v.sequence)) return true;
                        const vs = machine.memoryState.pop();

                        if (vs.v != V.ValueValue.SequenceKind) {
                            machine.replaceErr(Errors.expectedATypeError(machine.memoryState.allocator, v.sequence.position, V.ValueValue.SequenceKind, vs.v) catch |err| return errorHandler(err));
                            return true;
                        }

                        seq.v.SequenceKind.appendSlice(vs.v.SequenceKind.items()) catch |err| return errorHandler(err);
                    },
                }
            }
        },
        .literalString => machine.createStringValue(e.kind.literalString) catch |err| return errorHandler(err),
        .literalVoid => machine.createVoidValue() catch |err| return errorHandler(err),
        .notOp => {
            if (evalExpr(machine, e.kind.notOp.value)) return true;

            const v = machine.memoryState.pop();
            if (v.v != V.ValueValue.BoolKind) {
                machine.replaceErr(Errors.expectedATypeError(machine.memoryState.allocator, e.position, V.ValueValue.BoolKind, v.v) catch |err| return errorHandler(err));
                return true;
            }

            machine.memoryState.pushBoolValue(!v.v.BoolKind) catch |err| return errorHandler(err);
        },
        .whilee => return whilee(machine, e),
    }

    return false;
}

fn assignment(machine: *Machine, lhs: *AST.Expression, value: *AST.Expression) bool {
    switch (lhs.kind) {
        .identifier => {
            if (evalExpr(machine, value)) return true;

            if (!(machine.memoryState.updateInScope(lhs.kind.identifier, machine.memoryState.peek(0)) catch |err| return errorHandler(err))) {
                machine.replaceErr(Errors.unknownIdentifierError(machine.memoryState.allocator, lhs.position, lhs.kind.identifier) catch |err| return errorHandler(err));
                return true;
            }
        },
        .dot => {
            if (evalExpr(machine, lhs.kind.dot.record)) return true;
            const record = machine.memoryState.peek(0);

            if (record.v != V.ValueValue.RecordKind) {
                machine.replaceErr(Errors.recordValueExpectedError(machine.memoryState.allocator, lhs.kind.dot.record.position));
                return true;
            }
            if (evalExpr(machine, value)) return true;

            V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, lhs.kind.dot.field, machine.memoryState.peek(0)) catch |err| return errorHandler(err);

            const v = machine.memoryState.pop();
            _ = machine.memoryState.pop();
            machine.memoryState.push(v) catch |err| return errorHandler(err);
        },
        .indexRange => {
            if (evalExpr(machine, lhs.kind.indexRange.expr)) return true;
            const sequence = machine.memoryState.peek(0);
            if (sequence.v != V.ValueValue.SequenceKind) {
                machine.replaceErr(Errors.recordValueExpectedError(machine.memoryState.allocator, lhs.kind.indexRange.expr.position));
                return true;
            }

            const seqLen = sequence.v.SequenceKind.len();

            const start: V.IntType = V.clamp(indexPoint(machine, lhs.kind.indexRange.start, 0) catch |err| return errorHandler(err), 0, @intCast(seqLen));
            const end: V.IntType = V.clamp(indexPoint(machine, lhs.kind.indexRange.end, @intCast(seqLen)) catch |err| return errorHandler(err), start, @intCast(seqLen));

            if (evalExpr(machine, value)) return true;
            const v = machine.memoryState.peek(0);

            if (v.v != V.ValueValue.SequenceKind) {
                machine.replaceErr(Errors.expectedATypeError(machine.memoryState.allocator, lhs.kind.indexRange.expr.position, V.ValueValue.RecordKind, v.v) catch |err| return errorHandler(err));
                return true;
            }

            sequence.v.SequenceKind.replaceRange(@intCast(start), @intCast(end), v.v.SequenceKind.items()) catch |err| return errorHandler(err);

            machine.memoryState.popn(2);
            machine.memoryState.push(v) catch |err| return errorHandler(err);
        },
        .indexValue => {
            const exprA = lhs.kind.indexValue.expr;
            const indexA = lhs.kind.indexValue.index;

            if (evalExpr(machine, exprA)) return true;
            const expr = machine.memoryState.peek(0);

            if (expr.v == V.ValueValue.RecordKind) {
                if (evalExpr(machine, indexA)) return true;
                const index = machine.memoryState.peek(0);

                if (index.v != V.ValueValue.StringKind) {
                    var expected = machine.memoryState.allocator.alloc(V.ValueKind, 1) catch |err| return errorHandler(err);
                    errdefer machine.memoryState.allocator.free(expected);

                    expected[0] = V.ValueValue.StringKind;

                    machine.replaceErr(Errors.expectedTypeError(machine.memoryState.allocator, indexA.position, expected, index.v));
                    return true;
                }

                if (evalExpr(machine, value)) return true;

                V.recordSet(machine.memoryState.allocator, &expr.v.RecordKind, index.v.StringKind, machine.memoryState.peek(0)) catch |err| return errorHandler(err);
            } else if (expr.v == V.ValueValue.SequenceKind) {
                if (evalExpr(machine, indexA)) return true;
                const index = machine.memoryState.peek(0);

                if (index.v != V.ValueValue.IntKind) {
                    var expected = machine.memoryState.allocator.alloc(V.ValueKind, 1) catch |err| return errorHandler(err);
                    errdefer machine.memoryState.allocator.free(expected);

                    expected[0] = V.ValueValue.IntKind;

                    machine.replaceErr(Errors.expectedTypeError(machine.memoryState.allocator, indexA.position, expected, index.v));
                    return true;
                }

                if (evalExpr(machine, value)) return true;

                const seq = expr.v.SequenceKind;
                const idx = index.v.IntKind;

                if (idx < 0 or idx >= seq.len()) {
                    machine.replaceErr(Errors.indexOutOfRangeError(indexA.position, idx, 0, @intCast(seq.len())));
                    return true;
                } else {
                    seq.set(@intCast(idx), machine.memoryState.peek(0));
                }
            } else {
                machine.memoryState.popn(1);

                var expected = machine.memoryState.allocator.alloc(V.ValueKind, 2) catch |err| return errorHandler(err);
                errdefer machine.memoryState.allocator.free(expected);

                expected[0] = V.ValueValue.RecordKind;
                expected[1] = V.ValueValue.SequenceKind;

                machine.replaceErr(Errors.expectedTypeError(machine.memoryState.allocator, exprA.position, expected, expr.v));
                return true;
            }

            const v = machine.memoryState.pop();
            machine.memoryState.popn(2);
            machine.memoryState.push(v) catch |err| return errorHandler(err);
        },
        else => {
            machine.replaceErr(Errors.invalidLHSError(machine.memoryState.allocator, lhs.position));
            return true;
        },
    }

    return false;
}

fn binaryOp(machine: *Machine, e: *AST.Expression) bool {
    const leftAST = e.kind.binaryOp.left;
    const op = e.kind.binaryOp.op;
    const rightAST = e.kind.binaryOp.right;

    switch (op) {
        AST.Operator.Plus => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;

            const right = machine.memoryState.peek(0);
            const left = machine.memoryState.peek(1);

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.popn(2);
                            machine.memoryState.pushIntValue(left.v.IntKind + right.v.IntKind) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.popn(2);
                            machine.memoryState.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) + right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.popn(2);
                            machine.memoryState.pushFloatValue(left.v.FloatKind + @as(V.FloatType, @floatFromInt(right.v.IntKind))) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.popn(2);
                            machine.memoryState.pushFloatValue(left.v.FloatKind + right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                V.ValueValue.SequenceKind => {
                    switch (right.v) {
                        V.ValueValue.SequenceKind => {
                            machine.memoryState.pushEmptySequenceValue() catch |err| return errorHandler(err);
                            const seq = machine.memoryState.peek(0);
                            seq.v.SequenceKind.appendSlice(left.v.SequenceKind.items()) catch |err| return errorHandler(err);
                            seq.v.SequenceKind.appendSlice(right.v.SequenceKind.items()) catch |err| return errorHandler(err);
                            machine.memoryState.popn(3);
                            machine.memoryState.push(seq) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                V.ValueValue.StringKind => {
                    switch (right.v) {
                        V.ValueValue.StringKind => {
                            machine.memoryState.popn(2);

                            const slices = [_][]u8{ left.v.StringKind, right.v.StringKind };
                            machine.memoryState.pushOwnedStringValue(std.mem.concat(machine.memoryState.allocator, u8, &slices) catch |err| return errorHandler(err)) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                    return true;
                },
            }
        },
        AST.Operator.Minus => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.pushIntValue(left.v.IntKind - right.v.IntKind) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) - right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.pushFloatValue(left.v.FloatKind - @as(V.FloatType, @floatFromInt(right.v.IntKind))) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.pushFloatValue(left.v.FloatKind - right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                    return true;
                },
            }
        },
        AST.Operator.Times => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.pushIntValue(left.v.IntKind * right.v.IntKind) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) * right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.pushFloatValue(left.v.FloatKind * @as(V.FloatType, @floatFromInt(right.v.IntKind))) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.pushFloatValue(left.v.FloatKind * right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                    return true;
                },
            }
        },
        AST.Operator.Divide => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            if (right.v.IntKind == 0) {
                                machine.replaceErr(Errors.divideByZeroError(machine.memoryState.allocator, e.position));

                                return true;
                            }
                            machine.memoryState.pushIntValue(@divTrunc(left.v.IntKind, right.v.IntKind)) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            if (right.v.FloatKind == 0.0) {
                                machine.replaceErr(Errors.divideByZeroError(machine.memoryState.allocator, e.position));

                                return true;
                            }
                            machine.memoryState.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) / right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            if (right.v.IntKind == 0) {
                                machine.replaceErr(Errors.divideByZeroError(machine.memoryState.allocator, e.position));

                                return true;
                            }
                            machine.memoryState.pushFloatValue(left.v.FloatKind / @as(V.FloatType, @floatFromInt(right.v.IntKind))) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            if (right.v.FloatKind == 0.0) {
                                machine.replaceErr(Errors.divideByZeroError(machine.memoryState.allocator, e.position));

                                return true;
                            }
                            machine.memoryState.pushFloatValue(left.v.FloatKind / right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                    return true;
                },
            }
        },
        AST.Operator.Modulo => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;

            const right = machine.pop();
            const left = machine.pop();

            if (left.v != V.ValueValue.IntKind or right.v != V.ValueValue.IntKind) {
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));

                return true;
            }
            machine.memoryState.pushIntValue(@mod(left.v.IntKind, right.v.IntKind)) catch |err| return errorHandler(err);
        },
        AST.Operator.LessThan => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.pushBoolValue(left.v.IntKind < right.v.IntKind) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) < right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.pushBoolValue(left.v.FloatKind < @as(V.FloatType, @floatFromInt(right.v.IntKind))) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.pushBoolValue(left.v.FloatKind < right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                    return true;
                },
            }
        },
        AST.Operator.LessEqual => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.pushBoolValue(left.v.IntKind <= right.v.IntKind) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) <= right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.pushBoolValue(left.v.FloatKind <= @as(V.FloatType, @floatFromInt(right.v.IntKind))) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.pushBoolValue(left.v.FloatKind <= right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                    return true;
                },
            }
        },
        AST.Operator.GreaterThan => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.pushBoolValue(left.v.IntKind > right.v.IntKind) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) > right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.pushBoolValue(left.v.FloatKind > @as(V.FloatType, @floatFromInt(right.v.IntKind))) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.pushBoolValue(left.v.FloatKind > right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                    return true;
                },
            }
        },
        AST.Operator.GreaterEqual => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;

            const right = machine.pop();
            const left = machine.pop();

            switch (left.v) {
                V.ValueValue.IntKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.pushBoolValue(left.v.IntKind >= right.v.IntKind) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) >= right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            machine.memoryState.pushBoolValue(left.v.FloatKind >= @as(V.FloatType, @floatFromInt(right.v.IntKind))) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            machine.memoryState.pushBoolValue(left.v.FloatKind >= right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                    return true;
                },
            }
        },
        AST.Operator.Equal => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;

            const right = machine.pop();
            const left = machine.pop();

            machine.memoryState.pushBoolValue(V.eq(left, right)) catch |err| return errorHandler(err);
        },
        AST.Operator.NotEqual => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;

            const right = machine.pop();
            const left = machine.pop();

            machine.memoryState.pushBoolValue(!V.eq(left, right)) catch |err| return errorHandler(err);
        },
        AST.Operator.And => {
            if (evalExpr(machine, leftAST)) return true;

            const left = machine.memoryState.peek(0);
            if (left.v != V.ValueValue.BoolKind) {
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, V.ValueValue.BoolKind));
                return true;
            } else if (left.v.BoolKind) {
                _ = machine.pop();
                if (evalExpr(machine, rightAST)) return true;
                const right = machine.memoryState.peek(0);

                if (right.v != V.ValueValue.BoolKind) {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, V.ValueValue.BoolKind, right.v));
                    return true;
                }
            }
        },
        AST.Operator.Or => {
            if (evalExpr(machine, leftAST)) return true;

            const left = machine.memoryState.peek(0);
            if (left.v != V.ValueValue.BoolKind) {
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, V.ValueValue.BoolKind));
                return true;
            } else if (!left.v.BoolKind) {
                _ = machine.pop();
                if (evalExpr(machine, rightAST)) return true;
                const right = machine.memoryState.peek(0);

                if (right.v != V.ValueValue.BoolKind) {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, V.ValueValue.BoolKind, right.v));
                    return true;
                }
            }
        },
        AST.Operator.Append => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;
            const left = machine.memoryState.peek(1);
            const right = machine.memoryState.peek(0);

            if (left.v != V.ValueValue.SequenceKind) {
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                return true;
            }

            machine.memoryState.pushEmptySequenceValue() catch |err| return errorHandler(err);
            const result = machine.memoryState.peek(0);

            result.v.SequenceKind.appendSlice(left.v.SequenceKind.items()) catch |err| return errorHandler(err);
            result.v.SequenceKind.append(right) catch |err| return errorHandler(err);

            machine.memoryState.popn(3);
            machine.memoryState.push(result) catch |err| return errorHandler(err);
        },
        AST.Operator.AppendUpdate => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;
            const left = machine.memoryState.peek(1);
            const right = machine.memoryState.peek(0);

            if (left.v != V.ValueValue.SequenceKind) {
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                return true;
            }

            left.v.SequenceKind.append(right) catch |err| return errorHandler(err);

            machine.memoryState.popn(1);
        },
        AST.Operator.Prepend => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;
            const left = machine.memoryState.peek(1);
            const right = machine.memoryState.peek(0);

            if (right.v != V.ValueValue.SequenceKind) {
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                return true;
            }

            machine.memoryState.pushEmptySequenceValue() catch |err| return errorHandler(err);
            const result = machine.memoryState.peek(0);

            result.v.SequenceKind.append(left) catch |err| return errorHandler(err);
            result.v.SequenceKind.appendSlice(right.v.SequenceKind.items()) catch |err| return errorHandler(err);

            machine.memoryState.popn(3);
            machine.memoryState.push(result) catch |err| return errorHandler(err);
        },
        AST.Operator.PrependUpdate => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;
            const left = machine.memoryState.peek(1);
            const right = machine.memoryState.peek(0);

            if (right.v != V.ValueValue.SequenceKind) {
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.position, e.kind.binaryOp.op, left.v, right.v));
                return true;
            }

            right.v.SequenceKind.prepend(left) catch |err| return errorHandler(err);

            machine.memoryState.popn(2);
            machine.memoryState.push(right) catch |err| return errorHandler(err);
        },

        // else => unreachable,
    }

    return false;
}

fn call(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) bool {
    const sp = machine.memoryState.stack.items.len;

    if (evalExpr(machine, calleeAST)) return true;

    const callee = machine.memoryState.peek(0);

    if (callee.v != V.ValueValue.FunctionKind and callee.v != V.ValueValue.BuiltinKind) {
        machine.replaceErr(Errors.functionValueExpectedError(machine.memoryState.allocator, calleeAST.position));
        return true;
    }
    const args = if (callee.v == V.ValueValue.FunctionKind) callee.v.FunctionKind.arguments else callee.v.BuiltinKind.arguments;
    const restOfArgs = if (callee.v == V.ValueValue.FunctionKind) callee.v.FunctionKind.restOfArguments else callee.v.BuiltinKind.restOfArguments;

    var index: u8 = 0;
    while (index < argsAST.len) {
        if (evalExpr(machine, argsAST[index])) return true;
        index += 1;
    }

    while (index < args.len) {
        if (args[index].default == null) {
            machine.memoryState.pushUnitValue() catch |err| return errorHandler(err);
        } else {
            machine.memoryState.push(args[index].default.?) catch |err| return errorHandler(err);
        }
        index += 1;
    }

    if (callee.v == V.ValueValue.FunctionKind) {
        machine.memoryState.openScopeFrom(callee.v.FunctionKind.scope) catch |err| return errorHandler(err);
    } else {
        machine.memoryState.openScope() catch |err| return errorHandler(err);
    }
    defer machine.memoryState.restoreScope();

    var lp: u8 = 0;
    while (lp < args.len) {
        machine.memoryState.addToScope(args[lp].name, machine.memoryState.stack.items[sp + lp + 1]) catch |err| return errorHandler(err);
        lp += 1;
    }

    if (restOfArgs != null) {
        const rest = machine.memoryState.stack.items[sp + lp + 1 ..];
        machine.memoryState.addArrayValueToScope(restOfArgs.?, rest) catch |err| return errorHandler(err);
    }

    machine.memoryState.popn(index);
    if (callee.v == V.ValueValue.FunctionKind) {
        if (evalExpr(machine, callee.v.FunctionKind.body)) return true;
    } else {
        callee.v.BuiltinKind.body(machine, calleeAST, argsAST) catch |err| return errorHandler(err);
    }

    const result = machine.memoryState.pop();
    _ = machine.memoryState.pop();
    machine.memoryState.push(result) catch |err| return errorHandler(err);

    return false;
}

fn declaration(machine: *Machine, e: *AST.Expression) bool {
    if (evalExpr(machine, e.kind.declaration.value)) return true;

    const value: *V.Value = machine.memoryState.peek(0);

    machine.memoryState.addToScope(e.kind.declaration.name, value) catch |err| return errorHandler(err);

    return false;
}

fn dot(machine: *Machine, e: *AST.Expression) bool {
    if (evalExpr(machine, e.kind.dot.record)) return true;

    const record = machine.memoryState.pop();

    if (record.v != V.ValueValue.RecordKind) {
        machine.replaceErr(Errors.recordValueExpectedError(machine.memoryState.allocator, e.kind.dot.record.position));
        return true;
    }

    const value = record.v.RecordKind.get(e.kind.dot.field);

    if (value == null) {
        machine.memoryState.pushUnitValue() catch |err| return errorHandler(err);
    } else {
        machine.memoryState.push(value.?) catch |err| return errorHandler(err);
    }

    return false;
}

fn exprs(machine: *Machine, e: *AST.Expression) bool {
    if (e.kind.exprs.len == 0) {
        machine.createVoidValue() catch |err| return errorHandler(err);
    } else {
        var isFirst = true;

        for (e.kind.exprs) |expr| {
            if (isFirst) {
                isFirst = false;
            } else {
                _ = machine.memoryState.pop();
            }

            if (evalExpr(machine, expr)) return true;
        }
    }
    return false;
}

fn identifier(machine: *Machine, e: *AST.Expression) bool {
    const result = machine.memoryState.getFromScope(e.kind.identifier);

    if (result == null) {
        machine.replaceErr(Errors.unknownIdentifierError(machine.memoryState.allocator, e.position, e.kind.identifier) catch |err| return errorHandler(err));
        return true;
    } else {
        machine.memoryState.push(result.?) catch |err| return errorHandler(err);
        return false;
    }
}

fn ifte(machine: *Machine, e: *AST.Expression) bool {
    for (e.kind.ifte) |case| {
        if (case.condition == null) {
            if (evalExpr(machine, case.then)) return true;
            return false;
        }

        if (evalExpr(machine, case.condition.?)) return true;

        const condition = machine.memoryState.pop();

        if (condition.v == V.ValueValue.BoolKind and condition.v.BoolKind) {
            if (evalExpr(machine, case.then)) return true;
            return false;
        }
    }

    machine.createVoidValue() catch |err| return errorHandler(err);

    return false;
}

fn indexRange(machine: *Machine, exprA: *AST.Expression, startA: ?*AST.Expression, endA: ?*AST.Expression) bool {
    if (evalExpr(machine, exprA)) return true;
    const expr = machine.memoryState.peek(0);

    if (expr.v == V.ValueValue.SequenceKind) {
        const seq = expr.v.SequenceKind;

        const start: V.IntType = V.clamp(indexPoint(machine, startA, 0) catch |err| return errorHandler(err), 0, @intCast(seq.len()));
        const end: V.IntType = V.clamp(indexPoint(machine, endA, @intCast(seq.len())) catch |err| return errorHandler(err), start, @intCast(seq.len()));

        machine.memoryState.pushEmptySequenceValue() catch |err| return errorHandler(err);
        machine.memoryState.peek(0).v.SequenceKind.appendSlice(seq.items()[@intCast(start)..@intCast(end)]) catch |err| return errorHandler(err);
    } else if (expr.v == V.ValueValue.StringKind) {
        const str = expr.v.StringKind;

        const start: V.IntType = V.clamp(indexPoint(machine, startA, 0) catch |err| return errorHandler(err), 0, @intCast(str.len));
        const end: V.IntType = V.clamp(indexPoint(machine, endA, @intCast(str.len)) catch |err| return errorHandler(err), start, @intCast(str.len));

        machine.memoryState.pushOwnedStringValue(machine.memoryState.allocator.dupe(u8, str[@intCast(start)..@intCast(end)]) catch |err| return errorHandler(err)) catch |err| return errorHandler(err);
    } else {
        machine.memoryState.popn(1);

        var expected = machine.memoryState.allocator.alloc(V.ValueKind, 2) catch |err| return errorHandler(err);
        errdefer machine.memoryState.allocator.free(expected);

        expected[0] = V.ValueValue.SequenceKind;
        expected[1] = V.ValueValue.StringKind;

        machine.replaceErr(Errors.expectedTypeError(machine.memoryState.allocator, exprA.position, expected, expr.v));
        return true;
    }

    const result = machine.memoryState.pop();
    _ = machine.memoryState.pop();
    machine.memoryState.push(result) catch |err| return errorHandler(err);

    return false;
}

fn indexPoint(machine: *Machine, point: ?*AST.Expression, def: V.IntType) !V.IntType {
    if (point != null) {
        if (evalExpr(machine, point.?)) {
            return error.InterpreterError;
        }
        const pointV = machine.memoryState.peek(0);
        if (pointV.v != V.ValueValue.IntKind) {
            var expected = try machine.memoryState.allocator.alloc(V.ValueKind, 1);
            errdefer machine.memoryState.allocator.free(expected);

            expected[0] = V.ValueValue.IntKind;

            machine.replaceErr(Errors.expectedTypeError(machine.memoryState.allocator, point.?.position, expected, pointV.v));
            return error.InterpreterError;
        }

        const v = pointV.v.IntKind;
        _ = machine.memoryState.pop();
        return v;
    } else {
        return def;
    }
}

fn indexValue(machine: *Machine, exprA: *AST.Expression, indexA: *AST.Expression) bool {
    if (evalExpr(machine, exprA)) return true;
    const expr = machine.memoryState.peek(0);

    if (expr.v == V.ValueValue.RecordKind) {
        if (evalExpr(machine, indexA)) return true;
        const index = machine.memoryState.peek(0);

        if (index.v != V.ValueValue.StringKind) {
            var expected = machine.memoryState.allocator.alloc(V.ValueKind, 1) catch |err| return errorHandler(err);
            errdefer machine.memoryState.allocator.free(expected);

            expected[0] = V.ValueValue.StringKind;

            machine.replaceErr(Errors.expectedTypeError(machine.memoryState.allocator, indexA.position, expected, index.v));
            return true;
        }

        machine.memoryState.popn(2);

        const value = expr.v.RecordKind.get(index.v.StringKind);

        if (value == null) {
            machine.memoryState.pushUnitValue() catch |err| return errorHandler(err);
        } else {
            machine.memoryState.push(value.?) catch |err| return errorHandler(err);
        }
    } else if (expr.v == V.ValueValue.SequenceKind) {
        if (evalExpr(machine, indexA)) return true;
        const index = machine.memoryState.peek(0);

        if (index.v != V.ValueValue.IntKind) {
            var expected = machine.memoryState.allocator.alloc(V.ValueKind, 1) catch |err| return errorHandler(err);
            errdefer machine.memoryState.allocator.free(expected);

            expected[0] = V.ValueValue.IntKind;

            machine.replaceErr(Errors.expectedTypeError(machine.memoryState.allocator, indexA.position, expected, index.v));
            return true;
        }

        machine.memoryState.popn(2);

        const seq = expr.v.SequenceKind;
        const idx = index.v.IntKind;

        if (idx < 0 or idx >= seq.len()) {
            machine.memoryState.pushUnitValue() catch |err| return errorHandler(err);
        } else {
            machine.memoryState.push(seq.at(@intCast(idx))) catch |err| return errorHandler(err);
        }
    } else if (expr.v == V.ValueValue.StringKind) {
        if (evalExpr(machine, indexA)) return true;
        const index = machine.memoryState.peek(0);

        if (index.v != V.ValueValue.IntKind) {
            var expected = machine.memoryState.allocator.alloc(V.ValueKind, 1) catch |err| return errorHandler(err);
            errdefer machine.memoryState.allocator.free(expected);

            expected[0] = V.ValueValue.IntKind;

            machine.replaceErr(Errors.expectedTypeError(machine.memoryState.allocator, indexA.position, expected, index.v));
            return true;
        }

        machine.memoryState.popn(2);

        const str = expr.v.StringKind;
        const idx = index.v.IntKind;

        if (idx < 0 or idx >= str.len) {
            machine.memoryState.pushUnitValue() catch |err| return errorHandler(err);
        } else {
            machine.memoryState.pushCharValue(str[@intCast(idx)]) catch |err| return errorHandler(err);
        }
    } else {
        machine.memoryState.popn(1);

        var expected = machine.memoryState.allocator.alloc(V.ValueKind, 3) catch |err| return errorHandler(err);
        errdefer machine.memoryState.allocator.free(expected);

        expected[0] = V.ValueValue.RecordKind;
        expected[1] = V.ValueValue.SequenceKind;
        expected[2] = V.ValueValue.StringKind;

        machine.replaceErr(Errors.expectedTypeError(machine.memoryState.allocator, exprA.position, expected, expr.v));
        return true;
    }

    return false;
}

fn whilee(machine: *Machine, e: *AST.Expression) bool {
    while (true) {
        if (evalExpr(machine, e.kind.whilee.condition)) return true;

        const condition = machine.memoryState.pop();

        if (condition.v != V.ValueValue.BoolKind or !condition.v.BoolKind) {
            break;
        }

        if (evalExpr(machine, e.kind.whilee.body)) return true;

        _ = machine.memoryState.pop();
    }

    machine.createVoidValue() catch |err| return errorHandler(err);

    return false;
}

fn addBuiltin(
    state: *MS.MemoryState,
    name: []const u8,
    arguments: []const V.FunctionArgument,
    restOfArguments: ?[]const u8,
    body: *const fn (machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) Errors.err!void,
) !void {
    var vv = V.ValueValue{ .BuiltinKind = .{
        .arguments = arguments,
        .restOfArguments = restOfArguments,
        .body = body,
    } };

    const value = try state.newValue(vv);

    try state.addToScope(name, value);
}

fn initMemoryState(allocator: std.mem.Allocator) !MS.MemoryState {
    const default_colour = V.Colour.White;

    var state = MS.MemoryState{
        .allocator = allocator,
        .stack = std.ArrayList(*V.Value).init(allocator),
        .colour = default_colour,
        .root = null,
        .memory_size = 0,
        .memory_capacity = 2,
        .scopes = std.ArrayList(*V.Value).init(allocator),
        .imports = MS.Imports.init(allocator),
        .unitValue = null,
    };

    state.unitValue = try state.newValue(V.ValueValue{ .VoidKind = void{} });

    try state.openScope();

    try addBuiltin(&state, "gc", &[0]V.FunctionArgument{}, null, &Builtins.gc);
    try addBuiltin(&state, "import", &[_]V.FunctionArgument{V.FunctionArgument{
        .name = "file",
        .default = null,
    }}, null, &Builtins.import);

    try addBuiltin(&state, "imports", &[0]V.FunctionArgument{}, null, &Builtins.imports);

    try addBuiltin(&state, "len", &[_]V.FunctionArgument{V.FunctionArgument{
        .name = "v",
        .default = null,
    }}, null, &Builtins.len);

    try addBuiltin(&state, "milliTimestamp", &[0]V.FunctionArgument{}, null, &Builtins.milliTimestamp);

    try addBuiltin(&state, "print", &[_]V.FunctionArgument{}, "vs", &Builtins.print);

    try addBuiltin(&state, "println", &[_]V.FunctionArgument{}, "vs", &Builtins.println);

    try addBuiltin(&state, "typeof", &[_]V.FunctionArgument{V.FunctionArgument{
        .name = "v",
        .default = null,
    }}, null, &Builtins.typeof);

    try state.openScope();

    return state;
}

pub const Machine = struct {
    memoryState: MS.MemoryState,
    err: ?Errors.Error,

    pub fn init(allocator: std.mem.Allocator) !Machine {
        return Machine{
            .memoryState = try initMemoryState(allocator),
            .err = null,
        };
    }

    pub fn deinit(self: *Machine) void {
        self.eraseErr();
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

    pub fn createStringValue(self: *Machine, v: []const u8) !void {
        try self.memoryState.pushStringValue(v);
    }

    pub fn createSequenceValue(self: *Machine, size: usize) !void {
        return self.memoryState.pushSequenceValue(size);
    }

    pub fn eval(self: *Machine, e: *AST.Expression) !void {
        if (evalExpr(self, e)) {
            return error.InterpreterError;
        }
    }

    pub fn parse(self: *Machine, name: []const u8, buffer: []const u8) !*AST.Expression {
        const allocator = self.memoryState.allocator;

        var l = Lexer.Lexer.init(allocator);

        l.initBuffer(name, buffer) catch |err| {
            self.err = l.grabErr();
            return err;
        };

        var p = Parser.Parser.init(allocator, l);

        const ast = p.module() catch |err| {
            self.err = p.grabErr();
            return err;
        };
        errdefer AST.destroy(allocator, ast);

        return ast;
    }

    pub fn execute(self: *Machine, name: []const u8, buffer: []const u8) !void {
        const ast = try self.parse(name, buffer);
        errdefer AST.destroy(self.memoryState.allocator, ast);

        try self.eval(ast);

        try self.memoryState.imports.addAnnie(ast);
    }

    pub fn replaceErr(self: *Machine, err: Errors.Error) void {
        self.eraseErr();
        self.err = err;
    }

    pub fn eraseErr(self: *Machine) void {
        if (self.err != null) {
            self.err.?.deinit();
            self.err = null;
        }
    }

    pub fn grabErr(self: *Machine) ?Errors.Error {
        const err = self.err;
        self.err = null;

        return err;
    }

    pub fn pop(self: *Machine) *V.Value {
        return self.memoryState.pop();
    }

    pub fn topOfStack(self: *Machine) ?*V.Value {
        return self.memoryState.topOfStack();
    }

    pub fn reset(self: *Machine) !void {
        self.eraseErr();
        try self.memoryState.reset();
    }
};

fn errorHandler(err: anyerror) bool {
    std.debug.print("Error: {}\n", .{err});

    return true;
}
