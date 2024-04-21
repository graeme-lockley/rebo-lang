const std = @import("std");

const Code = @import("./../bc-interpreter.zig").Code;
const Debug = @import("./../debug.zig");
const ER = @import("./../error-reporting.zig");
const Errors = @import("./../errors.zig");
const Runtime = @import("./../runtime.zig").Runtime;
const Op = @import("./ops.zig").Op;
const SP = @import("./../string_pool.zig");
const V = @import("./../value.zig");

pub const IntTypeSize: usize = 8;
pub const FloatTypeSize: usize = 8;
pub const PositionTypeSize: usize = 2 * IntTypeSize;

pub fn eval(runtime: *Runtime, bytecode: []const u8) Errors.RuntimeErrors!void {
    try evalBlock(runtime, bytecode, 0);
}

fn evalBlock(runtime: *Runtime, bytecode: []const u8, startIp: usize) Errors.RuntimeErrors!void {
    var ip: usize = startIp;
    while (true) {
        switch (@as(Op, @enumFromInt(bytecode[ip]))) {
            .ret => return,
            .push_char => {
                try runtime.pushCharValue(bytecode[ip + 1]);
                ip += 2;
            },
            .push_false => {
                try runtime.pushBoolValue(false);
                ip += 1;
            },
            .push_float => {
                try runtime.pushFloatValue(readFloat(bytecode, ip + 1));
                ip += 1 + FloatTypeSize;
            },
            .push_identifier => {
                ip += 1;
                const name = @as(*SP.String, @ptrFromInt(@as(usize, @bitCast(readInt(bytecode, ip)))));
                ip += IntTypeSize;

                if (runtime.getFromScope(name)) |result| {
                    try runtime.push(result);
                } else {
                    const position = readPosition(bytecode, ip);
                    const rec = try ER.pushNamedUserError(runtime, "UnknownIdentifierError", position);
                    try rec.v.RecordKind.setU8(runtime.stringPool, "identifier", try runtime.newStringPoolValue(name));
                    return Errors.RuntimeErrors.InterpreterError;
                }

                ip += PositionTypeSize;
            },
            .push_int => {
                try runtime.pushIntValue(readInt(bytecode, ip + 1));
                ip += 1 + IntTypeSize;
            },
            .push_function => ip = try pushFunction(runtime, bytecode, ip),
            .push_record => {
                try runtime.pushEmptyRecordValue();
                ip += 1;
            },
            .push_sequence => {
                try runtime.pushEmptySequenceValue();
                ip += 1;
            },
            .push_string => {
                ip += 1;
                const str = @as(*SP.String, @ptrFromInt(@as(usize, @bitCast(readInt(bytecode, ip)))));
                ip += IntTypeSize;
                try runtime.pushStringPoolValue(str);
            },
            .push_true => {
                try runtime.pushBoolValue(true);
                ip += 1;
            },
            .push_unit => {
                try runtime.pushUnitValue();
                ip += 1;
            },
            .jmp => ip = @intCast(readInt(bytecode, ip + 1)),
            .jmp_true => {
                const condition = runtime.pop();
                if (!condition.isBool()) {
                    const position = readPosition(bytecode, ip + 1 + IntTypeSize);
                    try ER.raiseExpectedTypeError(runtime, position, &[_]V.ValueKind{V.ValueValue.BoolKind}, condition.v);
                }

                if (condition.v.BoolKind) {
                    ip = @intCast(readInt(bytecode, ip + 1));
                } else {
                    ip += 1 + IntTypeSize + PositionTypeSize;
                }
            },
            .jmp_false => {
                const condition = runtime.pop();
                if (!condition.isBool()) {
                    const position = readPosition(bytecode, ip + 1 + IntTypeSize);
                    try ER.raiseExpectedTypeError(runtime, position, &[_]V.ValueKind{V.ValueValue.BoolKind}, condition.v);
                }

                if (condition.v.BoolKind) {
                    ip += 1 + IntTypeSize + PositionTypeSize;
                } else {
                    ip = @intCast(readInt(bytecode, ip + 1));
                }
            },
            .raise => {
                const position = readPosition(bytecode, ip + 1);
                try ER.appendErrorPosition(runtime, position);
                return Errors.RuntimeErrors.InterpreterError;
            },
            .catche => {
                const ipStart = ip;
                const sp = runtime.stack.items.len;
                const scopeP = runtime.scopes.items.len;

                ip = @intCast(readInt(bytecode, ip + 1));
                evalBlock(runtime, bytecode, ipStart + 1 + IntTypeSize + IntTypeSize) catch {
                    const tos = runtime.pop();
                    runtime.popn(runtime.stack.items.len - sp);
                    runtime.scopes.items.len = scopeP;
                    try runtime.push(tos);
                    ip = @intCast(readInt(bytecode, ipStart + 1 + IntTypeSize));
                };
            },
            .is_record => {
                const v = runtime.pop();
                try runtime.pushBoolValue(v.isRecord());
                ip += 1;
            },
            .seq_len => {
                const v = runtime.pop();
                try runtime.pushIntValue(if (v.isSequence()) @intCast(v.v.SequenceKind.len()) else 0);
                ip += 1;
            },
            .seq_at => {
                const idx = readInt(bytecode, ip + 1);
                const v = runtime.pop();
                try runtime.push(if (v.isSequence()) v.v.SequenceKind.at(@intCast(idx)) else runtime.unitValue.?);
                ip += 1 + IntTypeSize;
            },
            .open_scope => {
                try runtime.openScope();
                ip += 1;
            },
            .close_scope => {
                runtime.restoreScope();
                ip += 1;
            },
            .call => {
                const numArgs = readInt(bytecode, ip + 1);

                runtime.callFn(@intCast(numArgs)) catch |err| {
                    const position = readPosition(bytecode, ip + 1 + IntTypeSize);
                    try ER.appendErrorPosition(runtime, position);
                    return err;
                };

                ip += 1 + IntTypeSize + PositionTypeSize;
            },
            .bind => {
                try runtime.bind();
                ip += 1;
            },
            .assign_dot => {
                const exprPosition = readPosition(bytecode, ip + 1);
                const namePosition = readPosition(bytecode, ip + 1 + PositionTypeSize);
                try runtime.assignDot(exprPosition, namePosition);
                ip += 1 + PositionTypeSize + PositionTypeSize;
            },
            .assign_identifier => {
                try runtime.assignIdentifier();
                ip += 1;
            },
            .assign_index => {
                const exprPosition = readPosition(bytecode, ip + 1);
                const indexPosition = readPosition(bytecode, ip + 1 + PositionTypeSize);
                try runtime.assignIndex(exprPosition, indexPosition);
                ip += 1 + PositionTypeSize + PositionTypeSize;
            },
            .assign_range => {
                const exprPosition = readPosition(bytecode, ip + 1);
                const fromPosition = readPosition(bytecode, ip + 1 + PositionTypeSize);
                const toPosition = readPosition(bytecode, ip + 1 + PositionTypeSize + PositionTypeSize);
                const valuePosition = readPosition(bytecode, ip + 1 + PositionTypeSize + PositionTypeSize + PositionTypeSize);

                try runtime.assignRange(exprPosition, fromPosition, toPosition, valuePosition);
                ip += 1 + PositionTypeSize + PositionTypeSize + PositionTypeSize + PositionTypeSize;
            },
            .assign_range_all => {
                const exprPosition = readPosition(bytecode, ip + 1);
                const valuePosition = readPosition(bytecode, ip + 1 + PositionTypeSize);

                try runtime.assignRangeAll(exprPosition, valuePosition);
                ip += 1 + PositionTypeSize + PositionTypeSize;
            },
            .assign_range_from => {
                const exprPosition = readPosition(bytecode, ip + 1);
                const fromPosition = readPosition(bytecode, ip + 1 + PositionTypeSize);
                const valuePosition = readPosition(bytecode, ip + 1 + PositionTypeSize + PositionTypeSize);

                try runtime.assignRangeFrom(exprPosition, fromPosition, valuePosition);
                ip += 1 + PositionTypeSize + PositionTypeSize + PositionTypeSize;
            },
            .assign_range_to => {
                const exprPosition = readPosition(bytecode, ip + 1);
                const toPosition = readPosition(bytecode, ip + 1 + PositionTypeSize);
                const valuePosition = readPosition(bytecode, ip + 1 + PositionTypeSize + PositionTypeSize);

                try runtime.assignRangeTo(exprPosition, toPosition, valuePosition);
                ip += 1 + PositionTypeSize + PositionTypeSize + PositionTypeSize;
            },
            .duplicate => {
                try runtime.duplicate();
                ip += 1;
            },
            .discard => {
                _ = runtime.pop();
                ip += 1;
            },
            .swap => {
                try runtime.swap();
                ip += 1;
            },
            .append_sequence_item_bang => {
                const seqPosition = readPosition(bytecode, ip + 1);

                try runtime.appendSequenceItemBang(seqPosition);
                ip += 1 + PositionTypeSize;
            },
            .append_sequence_items_bang => {
                const seqPosition = readPosition(bytecode, ip + 1);
                const itemPosition = readPosition(bytecode, ip + 1 + PositionTypeSize);

                try runtime.appendSequenceItemsBang(seqPosition, itemPosition);
                ip += 1 + PositionTypeSize + PositionTypeSize;
            },
            .set_record_item_bang => {
                const position = readPosition(bytecode, ip + 1);

                try runtime.setRecordItemBang(position);
                ip += 1 + PositionTypeSize;
            },
            .set_record_items_bang => {
                const position = readPosition(bytecode, ip + 1);

                try runtime.setRecordItemsBang(position);
                ip += 1 + PositionTypeSize;
            },
            .equals => {
                try runtime.equals();
                ip += 1;
            },
            .not_equals => {
                try runtime.notEquals();
                ip += 1;
            },
            .less_than => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.lessThan(position);
                ip += 1 + PositionTypeSize;
            },
            .less_equal => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.lessEqual(position);
                ip += 1 + PositionTypeSize;
            },
            .greater_than => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.greaterThan(position);
                ip += 1 + PositionTypeSize;
            },
            .greater_equal => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.greaterEqual(position);
                ip += 1 + PositionTypeSize;
            },
            .add => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.add(position);
                ip += 1 + PositionTypeSize;
            },
            .subtract => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.subtract(position);
                ip += 1 + PositionTypeSize;
            },
            .multiply => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.multiply(position);
                ip += 1 + PositionTypeSize;
            },
            .divide => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.divide(position);
                ip += 1 + PositionTypeSize;
            },
            .modulo => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.modulo(position);
                ip += 1 + PositionTypeSize;
            },
            .seq_append => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.appendSequenceItem(position);
                ip += 1 + PositionTypeSize;
            },
            .seq_append_bang => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.appendSequenceItemBang(position);
                ip += 1 + PositionTypeSize;
            },
            .seq_prepend => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.prependSequenceItem(position);
                ip += 1 + PositionTypeSize;
            },
            .seq_prepend_bang => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.prependSequenceItemBang(position);
                ip += 1 + PositionTypeSize;
            },
            .dot => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.dot(position);
                ip += 1 + PositionTypeSize;
            },
            .index => {
                const exprPosition = readPosition(bytecode, ip + 1);
                const indexPosition = readPosition(bytecode, ip + 1 + PositionTypeSize);
                try runtime.indexValue(exprPosition, indexPosition);
                ip += 1 + PositionTypeSize + PositionTypeSize;
            },
            .range => {
                const exprPosition = readPosition(bytecode, ip + 1);
                const startPosition = readPosition(bytecode, ip + 1 + PositionTypeSize);
                const endPosition = readPosition(bytecode, ip + 1 + PositionTypeSize + PositionTypeSize);
                try runtime.indexRange(exprPosition, startPosition, endPosition);

                ip += 1 + PositionTypeSize + PositionTypeSize + PositionTypeSize;
            },
            .rangeFrom => {
                const exprPosition = readPosition(bytecode, ip + 1);
                const startPosition = readPosition(bytecode, ip + 1 + PositionTypeSize);
                try runtime.indexRangeFrom(exprPosition, startPosition);

                ip += 1 + PositionTypeSize + PositionTypeSize;
            },
            .rangeTo => {
                const exprPosition = readPosition(bytecode, ip + 1);
                const endPosition = readPosition(bytecode, ip + 1 + PositionTypeSize);
                try runtime.indexRangeTo(exprPosition, endPosition);

                ip += 1 + PositionTypeSize + PositionTypeSize;
            },
            .not => {
                const exprPosition = readPosition(bytecode, ip + 1);
                try runtime.not(exprPosition);
                ip += 1 + PositionTypeSize;
            },
            .debug => {
                const depth = readInt(bytecode, ip + 1);

                const len: usize = @intCast(readInt(bytecode, ip + 1 + IntTypeSize));
                const msg = bytecode[ip + 1 + IntTypeSize + IntTypeSize .. ip + 1 + IntTypeSize + IntTypeSize + len];

                Debug.showStack(runtime, @intCast(depth), msg) catch {};

                ip += 1 + IntTypeSize + IntTypeSize + len;
            },

            // else => unreachable,
        }
    }
}

pub fn readFloat(bytecode: []const u8, ip: usize) V.FloatType {
    return @as(V.FloatType, @bitCast(readInt(bytecode, ip)));
}

pub fn readInt(bytecode: []const u8, ip: usize) V.IntType {
    const v: V.IntType = @bitCast(@as(u64, (bytecode[ip])) |
        (@as(u64, bytecode[ip + 1]) << 8) |
        (@as(u64, bytecode[ip + 2]) << 16) |
        (@as(u64, bytecode[ip + 3]) << 24) |
        (@as(u64, bytecode[ip + 4]) << 32) |
        (@as(u64, bytecode[ip + 5]) << 40) |
        (@as(u64, bytecode[ip + 6]) << 48) |
        (@as(u64, bytecode[ip + 7]) << 56));

    return v;
}

fn readPosition(bytecode: []const u8, ip: usize) Errors.Position {
    return .{
        .start = @intCast(readInt(bytecode, ip)),
        .end = @intCast(readInt(bytecode, ip + 8)),
    };
}

fn readString(bytecode: []const u8, ip: usize) ?*SP.String {
    return @as(?*SP.String, @ptrFromInt(@as(usize, @bitCast(readInt(bytecode, ip)))));
}

fn pushFunction(runtime: *Runtime, bytecode: []const u8, ipStart: usize) !usize {
    var ip = ipStart;

    const numberOfParameters: usize = @intCast(readInt(bytecode, ip + 1));
    ip = ip + 1 + IntTypeSize;

    var parameters: []V.FunctionArgument = try runtime.allocator.alloc(V.FunctionArgument, numberOfParameters);
    errdefer runtime.allocator.free(parameters);

    const sp = runtime.stack.items.len;

    for (0..numberOfParameters) |index| {
        const name = readString(bytecode, ip);
        const codePtr = @as(?*Code, @ptrFromInt(@as(usize, @bitCast(readInt(bytecode, ip + IntTypeSize)))));

        if (codePtr) |code| {
            try code.eval(runtime);
            const v = runtime.peek(0);
            const vv = try v.toString(runtime.allocator, V.Style.Pretty);
            defer runtime.allocator.free(vv);

            parameters[index] = V.FunctionArgument{ .name = name.?.incRefR(), .default = runtime.peek(0) };
        } else {
            parameters[index] = V.FunctionArgument{ .name = name.?.incRefR(), .default = null };
        }

        ip += IntTypeSize + IntTypeSize;
    }

    const restName = readString(bytecode, ip);
    ip += IntTypeSize;

    const code = @as(*Code, @ptrFromInt(@as(usize, @bitCast(readInt(bytecode, ip)))));
    ip += IntTypeSize;

    const result = try runtime.pushValue(V.ValueValue{ .BCFunctionKind = V.BCFunctionValue{
        .scope = runtime.scope(),
        .arguments = parameters,
        .restOfArguments = if (restName) |n| n.incRefR() else null,
        .code = code.incRefR(),
    } });

    runtime.popn(runtime.stack.items.len - sp);
    try runtime.push(result);

    return ip;
}
