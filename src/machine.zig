const std = @import("std");

const AST = @import("./ast.zig");
const Builtins = @import("./builtins.zig");
const Errors = @import("./errors.zig");
const Lexer = @import("./lexer.zig");
const MS = @import("./memory_state.zig");
const Parser = @import("./parser.zig");
const V = @import("./value.zig");

pub fn evalExpr(machine: *Machine, e: *AST.Expression) bool {
    switch (e.kind) {
        .assignment => return assignment(machine, e.kind.assignment.lhs, e.kind.assignment.value),
        .binaryOp => return binaryOp(machine, e),
        .call => return call(machine, e, e.kind.call.callee, e.kind.call.args),
        .catche => return catche(machine, e),
        .dot => return dot(machine, e),
        .exprs => return exprs(machine, e),
        .idDeclaration => return declaration(machine, e),
        .identifier => return identifier(machine, e),
        .ifte => return ifte(machine, e),
        .indexRange => return indexRange(machine, e.kind.indexRange.expr, e.kind.indexRange.start, e.kind.indexRange.end),
        .indexValue => return indexValue(machine, e.kind.indexValue.expr, e.kind.indexValue.index),
        .literalBool => machine.createBoolValue(e.kind.literalBool) catch |err| return errorHandler(err),
        .literalChar => machine.memoryState.pushCharValue(e.kind.literalChar) catch |err| return errorHandler(err),
        .literalFloat => machine.memoryState.pushFloatValue(e.kind.literalFloat) catch |err| return errorHandler(err),
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
        .literalInt => machine.createIntValue(e.kind.literalInt) catch |err| return errorHandler(err),
        .literalRecord => {
            machine.memoryState.pushEmptyMapValue() catch |err| return errorHandler(err);
            var map = machine.topOfStack().?;

            for (e.kind.literalRecord) |entry| {
                switch (entry) {
                    .value => {
                        if (evalExpr(machine, entry.value.value)) return true;

                        const value = machine.memoryState.pop();
                        map.v.RecordKind.set(machine.memoryState.allocator, entry.value.key.slice(), value) catch |err| return errorHandler(err);
                    },
                    .record => {
                        if (evalExpr(machine, entry.record)) return true;

                        const value = machine.memoryState.pop();
                        if (value.v != V.ValueValue.RecordKind) {
                            machine.replaceErr(Errors.expectedATypeError(machine.memoryState.allocator, machine.src(), entry.record.position, V.ValueValue.RecordKind, value.v) catch |err| return errorHandler(err));
                            return true;
                        }

                        var iterator = value.v.RecordKind.iterator();
                        while (iterator.next()) |rv| {
                            map.v.RecordKind.set(machine.memoryState.allocator, rv.key_ptr.*, rv.value_ptr.*) catch |err| return errorHandler(err);
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
                        seq.v.SequenceKind.appendItem(machine.memoryState.pop()) catch |err| return errorHandler(err);
                    },
                    .sequence => {
                        if (evalExpr(machine, v.sequence)) return true;
                        const vs = machine.memoryState.pop();

                        if (vs.v != V.ValueValue.SequenceKind) {
                            machine.replaceErr(Errors.expectedATypeError(machine.memoryState.allocator, machine.src(), v.sequence.position, V.ValueValue.SequenceKind, vs.v) catch |err| return errorHandler(err));
                            return true;
                        }

                        seq.v.SequenceKind.appendSlice(vs.v.SequenceKind.items()) catch |err| return errorHandler(err);
                    },
                }
            }
        },
        .literalString => machine.createStringValue(e.kind.literalString) catch |err| return errorHandler(err),
        .literalVoid => machine.createVoidValue() catch |err| return errorHandler(err),
        .match => return match(machine, e),
        .notOp => {
            if (evalExpr(machine, e.kind.notOp.value)) return true;

            const v = machine.memoryState.pop();
            if (v.v != V.ValueValue.BoolKind) {
                machine.replaceErr(Errors.expectedATypeError(machine.memoryState.allocator, machine.src(), e.position, V.ValueValue.BoolKind, v.v) catch |err| return errorHandler(err));
                return true;
            }

            machine.memoryState.pushBoolValue(!v.v.BoolKind) catch |err| return errorHandler(err);
        },
        .patternDeclaration => return patternDeclaration(machine, e),
        .raise => return raise(machine, e),
        .whilee => return whilee(machine, e),
    }

    return false;
}

fn assignment(machine: *Machine, lhs: *AST.Expression, value: *AST.Expression) bool {
    switch (lhs.kind) {
        .identifier => {
            if (evalExpr(machine, value)) return true;

            if (!(machine.memoryState.updateInScope(lhs.kind.identifier.slice(), machine.memoryState.peek(0)) catch |err| return errorHandler(err))) {
                machine.replaceErr(Errors.unknownIdentifierError(machine.memoryState.allocator, machine.src(), lhs.position, lhs.kind.identifier.slice()) catch |err| return errorHandler(err));
                return true;
            }
        },
        .dot => {
            if (evalExpr(machine, lhs.kind.dot.record)) return true;
            const record = machine.memoryState.peek(0);

            if (record.v != V.ValueValue.RecordKind) {
                machine.replaceErr(Errors.recordValueExpectedError(machine.memoryState.allocator, machine.src(), lhs.kind.dot.record.position, record.v) catch |err| return errorHandler(err));
                return true;
            }
            if (evalExpr(machine, value)) return true;

            record.v.RecordKind.set(machine.memoryState.allocator, lhs.kind.dot.field.slice(), machine.memoryState.peek(0)) catch |err| return errorHandler(err);

            const v = machine.memoryState.pop();
            _ = machine.memoryState.pop();
            machine.memoryState.push(v) catch |err| return errorHandler(err);
        },
        .indexRange => {
            if (evalExpr(machine, lhs.kind.indexRange.expr)) return true;
            const sequence = machine.memoryState.peek(0);
            if (sequence.v != V.ValueValue.SequenceKind) {
                machine.replaceErr(Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), lhs.kind.indexRange.expr.position, &[_]V.ValueKind{V.ValueValue.SequenceKind}, sequence.v) catch |err| return errorHandler(err));
                return true;
            }

            const seqLen = sequence.v.SequenceKind.len();

            const start: V.IntType = V.clamp(indexPoint(machine, lhs.kind.indexRange.start, 0) catch |err| return errorHandler(err), 0, @intCast(seqLen));
            const end: V.IntType = V.clamp(indexPoint(machine, lhs.kind.indexRange.end, @intCast(seqLen)) catch |err| return errorHandler(err), start, @intCast(seqLen));

            if (evalExpr(machine, value)) return true;
            const v = machine.memoryState.peek(0);

            if (v.v == V.ValueValue.SequenceKind) {
                sequence.v.SequenceKind.replaceRange(@intCast(start), @intCast(end), v.v.SequenceKind.items()) catch |err| return errorHandler(err);
            } else if (v.v == V.ValueValue.UnitKind) {
                sequence.v.SequenceKind.removeRange(@intCast(start), @intCast(end)) catch |err| return errorHandler(err);
            } else if (v.v != V.ValueValue.SequenceKind) {
                machine.replaceErr(Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), lhs.kind.indexRange.expr.position, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.UnitKind }, v.v) catch |err| return errorHandler(err));
                return true;
            }
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
                    machine.replaceErr(Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v) catch |err| return errorHandler(err));
                    return true;
                }

                if (evalExpr(machine, value)) return true;

                expr.v.RecordKind.set(machine.memoryState.allocator, index.v.StringKind.slice(), machine.memoryState.peek(0)) catch |err| return errorHandler(err);
            } else if (expr.v == V.ValueValue.SequenceKind) {
                if (evalExpr(machine, indexA)) return true;
                const index = machine.memoryState.peek(0);

                if (index.v != V.ValueValue.IntKind) {
                    machine.replaceErr(Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v) catch |err| return errorHandler(err));
                    return true;
                }

                if (evalExpr(machine, value)) return true;

                const seq = expr.v.SequenceKind;
                const idx = index.v.IntKind;

                if (idx < 0 or idx >= seq.len()) {
                    machine.replaceErr(Errors.indexOutOfRangeError(machine.memoryState.allocator, machine.src(), indexA.position, idx, 0, @intCast(seq.len())) catch |err| return errorHandler(err));
                    return true;
                } else {
                    seq.set(@intCast(idx), machine.memoryState.peek(0));
                }
            } else {
                machine.memoryState.popn(1);

                machine.replaceErr(Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), exprA.position, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.SequenceKind }, expr.v) catch |err| return errorHandler(err));
                return true;
            }

            const v = machine.memoryState.pop();
            machine.memoryState.popn(2);
            machine.memoryState.push(v) catch |err| return errorHandler(err);
        },
        else => {
            machine.replaceErr(Errors.invalidLHSError(machine.memoryState.allocator, machine.src(), lhs.position) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                            return true;
                        },
                    }
                },
                V.ValueValue.StringKind => {
                    switch (right.v) {
                        V.ValueValue.StringKind => {
                            machine.memoryState.popn(2);

                            const slices = [_][]const u8{ left.v.StringKind.slice(), right.v.StringKind.slice() };
                            machine.memoryState.pushOwnedStringValue(std.mem.concat(machine.memoryState.allocator, u8, &slices) catch |err| return errorHandler(err)) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                            return true;
                        },
                    }
                },
                V.ValueValue.StringKind => {
                    if (right.v == V.ValueValue.IntKind) {
                        const mem = machine.memoryState.allocator.alloc(u8, left.v.StringKind.len() * @as(usize, @intCast(right.v.IntKind))) catch |err| return errorHandler(err);

                        for (0..@intCast(right.v.IntKind)) |index| {
                            std.mem.copyForwards(u8, mem[index * left.v.StringKind.len() ..], left.v.StringKind.slice());
                        }

                        machine.memoryState.pushOwnedStringValue(mem) catch |err| return errorHandler(err);
                    } else {
                        machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                        return true;
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                                machine.replaceErr(Errors.divideByZeroError(machine.memoryState.allocator, machine.src(), e.position) catch |err| return errorHandler(err));

                                return true;
                            }
                            machine.memoryState.pushIntValue(@divTrunc(left.v.IntKind, right.v.IntKind)) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            if (right.v.FloatKind == 0.0) {
                                machine.replaceErr(Errors.divideByZeroError(machine.memoryState.allocator, machine.src(), e.position) catch |err| return errorHandler(err));

                                return true;
                            }
                            machine.memoryState.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) / right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                            return true;
                        },
                    }
                },
                V.ValueValue.FloatKind => {
                    switch (right.v) {
                        V.ValueValue.IntKind => {
                            if (right.v.IntKind == 0) {
                                machine.replaceErr(Errors.divideByZeroError(machine.memoryState.allocator, machine.src(), e.position) catch |err| return errorHandler(err));

                                return true;
                            }
                            machine.memoryState.pushFloatValue(left.v.FloatKind / @as(V.FloatType, @floatFromInt(right.v.IntKind))) catch |err| return errorHandler(err);
                        },
                        V.ValueValue.FloatKind => {
                            if (right.v.FloatKind == 0.0) {
                                machine.replaceErr(Errors.divideByZeroError(machine.memoryState.allocator, machine.src(), e.position) catch |err| return errorHandler(err));

                                return true;
                            }
                            machine.memoryState.pushFloatValue(left.v.FloatKind / right.v.FloatKind) catch |err| return errorHandler(err);
                        },
                        else => {
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));

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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                            machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                            return true;
                        },
                    }
                },
                else => {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
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
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, V.ValueValue.BoolKind) catch |err| return errorHandler(err));
                return true;
            } else if (left.v.BoolKind) {
                _ = machine.pop();
                if (evalExpr(machine, rightAST)) return true;
                const right = machine.memoryState.peek(0);

                if (right.v != V.ValueValue.BoolKind) {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, V.ValueValue.BoolKind, right.v) catch |err| return errorHandler(err));
                    return true;
                }
            }
        },
        AST.Operator.Or => {
            if (evalExpr(machine, leftAST)) return true;

            const left = machine.memoryState.peek(0);
            if (left.v != V.ValueValue.BoolKind) {
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, V.ValueValue.BoolKind) catch |err| return errorHandler(err));
                return true;
            } else if (!left.v.BoolKind) {
                _ = machine.pop();
                if (evalExpr(machine, rightAST)) return true;
                const right = machine.memoryState.peek(0);

                if (right.v != V.ValueValue.BoolKind) {
                    machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, V.ValueValue.BoolKind, right.v) catch |err| return errorHandler(err));
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
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                return true;
            }

            machine.memoryState.pushEmptySequenceValue() catch |err| return errorHandler(err);
            const result = machine.memoryState.peek(0);

            result.v.SequenceKind.appendSlice(left.v.SequenceKind.items()) catch |err| return errorHandler(err);
            result.v.SequenceKind.appendItem(right) catch |err| return errorHandler(err);

            machine.memoryState.popn(3);
            machine.memoryState.push(result) catch |err| return errorHandler(err);
        },
        AST.Operator.AppendUpdate => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;
            const left = machine.memoryState.peek(1);
            const right = machine.memoryState.peek(0);

            if (left.v != V.ValueValue.SequenceKind) {
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                return true;
            }

            left.v.SequenceKind.appendItem(right) catch |err| return errorHandler(err);

            machine.memoryState.popn(1);
        },
        AST.Operator.Prepend => {
            if (evalExpr(machine, leftAST)) return true;
            if (evalExpr(machine, rightAST)) return true;
            const left = machine.memoryState.peek(1);
            const right = machine.memoryState.peek(0);

            if (right.v != V.ValueValue.SequenceKind) {
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                return true;
            }

            machine.memoryState.pushEmptySequenceValue() catch |err| return errorHandler(err);
            const result = machine.memoryState.peek(0);

            result.v.SequenceKind.appendItem(left) catch |err| return errorHandler(err);
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
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, machine.src(), e.position, e.kind.binaryOp.op, left.v, right.v) catch |err| return errorHandler(err));
                return true;
            }

            right.v.SequenceKind.prependItem(left) catch |err| return errorHandler(err);

            machine.memoryState.popn(2);
            machine.memoryState.push(right) catch |err| return errorHandler(err);
        },
        AST.Operator.Hook => {
            if (evalExpr(machine, leftAST)) return true;

            const left = machine.memoryState.peek(0);

            if (left.v == V.ValueValue.UnitKind) {
                _ = machine.memoryState.pop();

                if (evalExpr(machine, rightAST)) return true;
            }
        },

        // else => unreachable,
    }

    return false;
}

fn call(machine: *Machine, e: *AST.Expression, calleeAST: *AST.Expression, argsAST: []*AST.Expression) bool {
    const sp = machine.memoryState.stack.items.len;

    if (evalExpr(machine, calleeAST)) return true;

    const callee = machine.memoryState.peek(0);

    if (callee.v != V.ValueValue.FunctionKind and callee.v != V.ValueValue.BuiltinKind) {
        machine.replaceErr(Errors.functionValueExpectedError(machine.memoryState.allocator, machine.src(), calleeAST.position, callee.v) catch |err| return errorHandler(err));
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
    errdefer machine.memoryState.restoreScope();

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
        if (evalExpr(machine, callee.v.FunctionKind.body)) {
            machine.memoryState.restoreScope();
            machine.appendStackItem(Errors.Position{ .start = calleeAST.position.start, .end = e.position.end }) catch |err| return errorHandler(err);
            return true;
        }
    } else {
        callee.v.BuiltinKind.body(machine, calleeAST, argsAST) catch |err| {
            machine.memoryState.restoreScope();
            machine.appendStackItem(Errors.Position{ .start = calleeAST.position.start, .end = e.position.end }) catch |err2| return errorHandler(err2);
            return errorHandler(err);
        };
    }

    const result = machine.memoryState.pop();
    _ = machine.memoryState.pop();
    machine.memoryState.push(result) catch |err| return errorHandler(err);

    machine.memoryState.restoreScope();

    return false;
}

fn catche(machine: *Machine, e: *AST.Expression) bool {
    const sp = machine.memoryState.stack.items.len;
    if (evalExpr(machine, e.kind.catche.value)) {
        const value = machine.memoryState.peek(0);

        for (e.kind.catche.cases) |case| {
            machine.memoryState.openScope() catch |err| return errorHandler(err);

            const matched = matchPattern(machine, case.pattern, value);
            if (matched) {
                const result = evalExpr(machine, case.body);

                if (!result) {
                    machine.eraseErr();
                }

                machine.memoryState.restoreScope();
                const v = machine.memoryState.pop();
                while (machine.memoryState.stack.items.len > sp) {
                    _ = machine.memoryState.pop();
                }
                machine.memoryState.push(v) catch |err| return errorHandler(err);
                return result;
            }
            machine.memoryState.restoreScope();
        }
        return true;
    } else {
        return false;
    }
}

fn declaration(machine: *Machine, e: *AST.Expression) bool {
    if (evalExpr(machine, e.kind.idDeclaration.value)) return true;

    const value: *V.Value = machine.memoryState.peek(0);

    machine.memoryState.addToScope(e.kind.idDeclaration.name.slice(), value) catch |err| return errorHandler(err);

    return false;
}

fn dot(machine: *Machine, e: *AST.Expression) bool {
    if (evalExpr(machine, e.kind.dot.record)) return true;

    const record = machine.memoryState.pop();

    if (record.v != V.ValueValue.RecordKind) {
        machine.replaceErr(Errors.recordValueExpectedError(machine.memoryState.allocator, machine.src(), e.kind.dot.record.position, record.v) catch |err| return errorHandler(err));
        return true;
    }

    const value = record.v.RecordKind.get(e.kind.dot.field.slice());

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
    const result = machine.memoryState.getFromScope(e.kind.identifier.slice());

    if (result == null) {
        machine.replaceErr(Errors.unknownIdentifierError(machine.memoryState.allocator, machine.src(), e.position, e.kind.identifier.slice()) catch |err| return errorHandler(err));
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
        const str = expr.v.StringKind.slice();

        const start: V.IntType = V.clamp(indexPoint(machine, startA, 0) catch |err| return errorHandler(err), 0, @intCast(str.len));
        const end: V.IntType = V.clamp(indexPoint(machine, endA, @intCast(str.len)) catch |err| return errorHandler(err), start, @intCast(str.len));

        machine.memoryState.pushStringValue(str[@intCast(start)..@intCast(end)]) catch |err| return errorHandler(err);
    } else {
        machine.memoryState.popn(1);
        machine.replaceErr(Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), exprA.position, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v) catch |err| return errorHandler(err));
        return true;
    }

    const result = machine.memoryState.pop();
    _ = machine.memoryState.pop();
    machine.memoryState.push(result) catch |err| return errorHandler(err);

    return false;
}

fn indexPoint(machine: *Machine, point: ?*AST.Expression, def: V.IntType) !V.IntType {
    if (point == null) {
        return def;
    } else {
        if (evalExpr(machine, point.?)) {
            return error.InterpreterError;
        }
        const pointV = machine.memoryState.peek(0);
        if (pointV.v != V.ValueValue.IntKind) {
            machine.replaceErr(try Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), point.?.position, &[_]V.ValueKind{V.ValueValue.IntKind}, pointV.v));
            return error.InterpreterError;
        }

        const v = pointV.v.IntKind;
        _ = machine.memoryState.pop();
        return v;
    }
}

fn indexValue(machine: *Machine, exprA: *AST.Expression, indexA: *AST.Expression) bool {
    if (evalExpr(machine, exprA)) return true;
    const expr = machine.memoryState.peek(0);

    if (expr.v == V.ValueValue.RecordKind) {
        if (evalExpr(machine, indexA)) return true;
        const index = machine.memoryState.peek(0);

        if (index.v != V.ValueValue.StringKind) {
            machine.replaceErr(Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), indexA.position, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v) catch |err| return errorHandler(err));
            return true;
        }

        machine.memoryState.popn(2);

        const value = expr.v.RecordKind.get(index.v.StringKind.slice());

        if (value == null) {
            machine.memoryState.pushUnitValue() catch |err| return errorHandler(err);
        } else {
            machine.memoryState.push(value.?) catch |err| return errorHandler(err);
        }
    } else if (expr.v == V.ValueValue.SequenceKind) {
        if (evalExpr(machine, indexA)) return true;
        const index = machine.memoryState.peek(0);

        if (index.v != V.ValueValue.IntKind) {
            machine.replaceErr(Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v) catch |err| return errorHandler(err));
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
            machine.replaceErr(Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), indexA.position, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v) catch |err| return errorHandler(err));
            return true;
        }

        machine.memoryState.popn(2);

        const str = expr.v.StringKind.slice();
        const idx = index.v.IntKind;

        if (idx < 0 or idx >= str.len) {
            machine.memoryState.pushUnitValue() catch |err| return errorHandler(err);
        } else {
            machine.memoryState.pushCharValue(str[@intCast(idx)]) catch |err| return errorHandler(err);
        }
    } else {
        machine.memoryState.popn(1);
        machine.replaceErr(Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), exprA.position, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v) catch |err| return errorHandler(err));
        return true;
    }

    return false;
}

fn match(machine: *Machine, e: *AST.Expression) bool {
    if (evalExpr(machine, e.kind.match.value)) return true;

    const value = machine.memoryState.peek(0);

    for (e.kind.match.cases) |case| {
        machine.memoryState.openScope() catch |err| return errorHandler(err);

        const matched = matchPattern(machine, case.pattern, value);
        if (matched) {
            const result = evalExpr(machine, case.body);

            machine.memoryState.restoreScope();
            const v = machine.memoryState.pop();
            _ = machine.memoryState.pop();
            machine.memoryState.push(v) catch |err| return errorHandler(err);
            return result;
        }
        machine.memoryState.restoreScope();
    }

    machine.replaceErr(Errors.noMatchError(machine.memoryState.allocator, machine.src(), e.position) catch |err| return errorHandler(err));

    return true;
}

fn matchPattern(machine: *Machine, p: *AST.Pattern, v: *V.Value) bool {
    return switch (p.kind) {
        .identifier => {
            if (!std.mem.eql(u8, p.kind.identifier, "_")) {
                machine.memoryState.addToScope(p.kind.identifier, v) catch |err| return errorHandler(err);
            }
            return true;
        },
        .literalBool => return v.v == V.ValueValue.BoolKind and v.v.BoolKind == p.kind.literalBool,
        .literalChar => return v.v == V.ValueValue.CharKind and v.v.CharKind == p.kind.literalChar,
        .literalFloat => return v.v == V.ValueValue.FloatKind and v.v.FloatKind == p.kind.literalFloat or v.v == V.ValueValue.IntKind and v.v.IntKind == @as(V.IntType, @intFromFloat(p.kind.literalFloat)),
        .literalInt => return v.v == V.ValueValue.IntKind and v.v.IntKind == p.kind.literalInt or v.v == V.ValueValue.FloatKind and v.v.FloatKind == @as(V.FloatType, @floatFromInt(p.kind.literalInt)),
        .literalString => return v.v == V.ValueValue.StringKind and std.mem.eql(u8, v.v.StringKind.slice(), p.kind.literalString),
        .record => {
            if (v.v != V.ValueValue.RecordKind) return false;

            const record = v.v.RecordKind;

            for (p.kind.record.entries) |entry| {
                const value = record.get(entry.key);

                if (value == null) return false;

                if (entry.pattern == null) {
                    machine.memoryState.addToScope(if (entry.id == null) entry.key else entry.id.?, value.?) catch |err| return errorHandler(err);
                } else if (entry.pattern != null and !matchPattern(machine, entry.pattern.?, value.?)) {
                    return false;
                }
            }

            if (p.kind.record.id != null) {
                machine.memoryState.addToScope(p.kind.record.id.?, v) catch |err| return errorHandler(err);
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
                if (!matchPattern(machine, p.kind.sequence.patterns[index], seq.at(index))) return false;
                index += 1;
            }

            if (p.kind.sequence.restOfPatterns != null and !std.mem.eql(u8, p.kind.sequence.restOfPatterns.?, "_")) {
                var newSeq = try V.SequenceValue.init(machine.memoryState.allocator);
                if (seq.len() > p.kind.sequence.patterns.len) {
                    newSeq.appendSlice(seq.items()[p.kind.sequence.patterns.len..]) catch |err| return errorHandler(err);
                }
                machine.memoryState.addToScope(p.kind.sequence.restOfPatterns.?, machine.memoryState.newValue(V.ValueValue{ .SequenceKind = newSeq }) catch |err| return errorHandler(err)) catch |err| return errorHandler(err);
            }

            if (p.kind.sequence.id != null) {
                machine.memoryState.addToScope(p.kind.sequence.id.?, v) catch |err| return errorHandler(err);
            }

            return true;
        },
        .void => return v.v == V.ValueValue.UnitKind,
    };
}

fn patternDeclaration(machine: *Machine, e: *AST.Expression) bool {
    if (evalExpr(machine, e.kind.patternDeclaration.value)) return true;

    const value: *V.Value = machine.memoryState.peek(0);

    if (matchPattern(machine, e.kind.patternDeclaration.pattern, value)) {
        return false;
    }

    machine.replaceErr(Errors.noMatchError(machine.memoryState.allocator, machine.src(), e.position) catch |err| return errorHandler(err));

    return true;
}

fn raise(machine: *Machine, e: *AST.Expression) bool {
    if (evalExpr(machine, e.kind.raise.expr)) return true;

    machine.replaceErr(Errors.userError(machine.memoryState.allocator, machine.src(), e.position) catch |err| return errorHandler(err));

    return true;
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

fn addRebo(state: *MS.MemoryState) !void {
    var args = try std.process.argsAlloc(state.allocator);
    defer std.process.argsFree(state.allocator, args);

    const value = try state.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(state.allocator) });
    try state.addToScope("rebo", value);

    const reboArgs = try state.newValue(V.ValueValue{ .SequenceKind = try V.SequenceValue.init(state.allocator) });
    try value.v.RecordKind.set(state.allocator, "args", reboArgs);

    for (args) |arg| {
        try reboArgs.v.SequenceKind.appendItem(try state.newStringValue(arg));
    }

    var env = try std.process.getEnvMap(state.allocator);
    defer env.deinit();
    const reboEnv = try state.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(state.allocator) });
    try value.v.RecordKind.set(state.allocator, "env", reboEnv);

    var iterator = env.iterator();
    while (iterator.next()) |entry| {
        try value.v.RecordKind.set(state.allocator, entry.key_ptr.*, try state.newStringValue(entry.value_ptr.*));
    }
}

fn initMemoryState(allocator: std.mem.Allocator) !MS.MemoryState {
    var state = try MS.MemoryState.init(allocator);

    try state.openScope();

    try addBuiltin(&state, "close", &[_]V.FunctionArgument{V.FunctionArgument{
        .name = "handle",
        .default = null,
    }}, null, &Builtins.close);
    try addBuiltin(&state, "cwd", &[0]V.FunctionArgument{}, null, &Builtins.cwd);
    try addBuiltin(&state, "eval", &[_]V.FunctionArgument{V.FunctionArgument{
        .name = "code",
        .default = null,
    }}, null, &Builtins.eval);
    try addBuiltin(&state, "exit", &[_]V.FunctionArgument{V.FunctionArgument{
        .name = "v",
        .default = null,
    }}, null, &Builtins.exit);
    try addBuiltin(&state, "gc", &[0]V.FunctionArgument{}, null, &Builtins.gc);
    try addBuiltin(&state, "import", &[_]V.FunctionArgument{V.FunctionArgument{
        .name = "file",
        .default = null,
    }}, null, &Builtins.import);
    try addBuiltin(&state, "imports", &[0]V.FunctionArgument{}, null, &Builtins.imports);
    try addBuiltin(&state, "int", &[_]V.FunctionArgument{ V.FunctionArgument{
        .name = "value",
        .default = null,
    }, V.FunctionArgument{
        .name = "default",
        .default = null,
    }, V.FunctionArgument{
        .name = "base",
        .default = null,
    } }, null, &Builtins.int);
    try addBuiltin(&state, "keys", &[_]V.FunctionArgument{V.FunctionArgument{
        .name = "v",
        .default = null,
    }}, null, &Builtins.keys);
    try addBuiltin(&state, "len", &[_]V.FunctionArgument{V.FunctionArgument{
        .name = "v",
        .default = null,
    }}, null, &Builtins.len);
    try addBuiltin(&state, "listen", &[_]V.FunctionArgument{ V.FunctionArgument{
        .name = "host",
        .default = null,
    }, V.FunctionArgument{
        .name = "port",
        .default = null,
    }, V.FunctionArgument{
        .name = "cb",
        .default = null,
    } }, null, &Builtins.listen);
    try addBuiltin(&state, "ls", &[_]V.FunctionArgument{V.FunctionArgument{
        .name = "path",
        .default = null,
    }}, null, &Builtins.ls);
    try addBuiltin(&state, "milliTimestamp", &[0]V.FunctionArgument{}, null, &Builtins.milliTimestamp);
    try addBuiltin(&state, "open", &[_]V.FunctionArgument{ V.FunctionArgument{
        .name = "path",
        .default = null,
    }, V.FunctionArgument{
        .name = "options",
        .default = null,
    } }, null, &Builtins.open);
    try addBuiltin(&state, "print", &[_]V.FunctionArgument{}, "vs", &Builtins.print);
    try addBuiltin(&state, "println", &[_]V.FunctionArgument{}, "vs", &Builtins.println);
    try addBuiltin(&state, "read", &[_]V.FunctionArgument{ V.FunctionArgument{
        .name = "handle",
        .default = null,
    }, V.FunctionArgument{
        .name = "bytes",
        .default = null,
    } }, null, &Builtins.read);
    try addBuiltin(&state, "socket", &[_]V.FunctionArgument{ V.FunctionArgument{
        .name = "name",
        .default = null,
    }, V.FunctionArgument{
        .name = "port",
        .default = null,
    } }, null, &Builtins.socket);
    try addBuiltin(&state, "str", &[_]V.FunctionArgument{ V.FunctionArgument{
        .name = "value",
        .default = null,
    }, V.FunctionArgument{
        .name = "literal",
        .default = null,
    } }, null, &Builtins.str);
    try addBuiltin(&state, "typeof", &[_]V.FunctionArgument{V.FunctionArgument{
        .name = "v",
        .default = null,
    }}, null, &Builtins.typeof);
    try addBuiltin(&state, "write", &[_]V.FunctionArgument{ V.FunctionArgument{
        .name = "handle",
        .default = null,
    }, V.FunctionArgument{
        .name = "bytes",
        .default = null,
    } }, null, &Builtins.write);

    try addRebo(&state);

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

        var p = Parser.Parser.init(self.memoryState.stringPool, l);

        const ast = p.module() catch |err| {
            self.err = p.grabErr();
            return err;
        };
        errdefer AST.destroy(allocator, ast);

        return ast;
    }

    pub fn execute(self: *Machine, name: []const u8, buffer: []const u8) !void {
        const ast = try self.parse(name, buffer);
        errdefer ast.destroy(self.memoryState.allocator);

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

    pub fn src(self: *Machine) []const u8 {
        const result = self.memoryState.getFromScope("__FILE");

        return if (result == null) Errors.STREAM_SRC else if (result.?.v == V.ValueValue.StringKind) result.?.v.StringKind.slice() else Errors.STREAM_SRC;
    }

    pub fn appendStackItem(self: *Machine, position: Errors.Position) !void {
        if (self.err != null) {
            try self.err.?.appendStackItem(self.src(), position);
        }
    }
};

fn errorHandler(err: anyerror) bool {
    std.debug.print("Error: {}\n", .{err});

    return true;
}
