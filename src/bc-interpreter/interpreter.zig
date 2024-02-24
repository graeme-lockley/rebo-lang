const std = @import("std");

const ER = @import("./../error-reporting.zig");
const Errors = @import("./../errors.zig");
const Runtime = @import("./../runtime.zig").Runtime;
const Op = @import("./ops.zig").Op;
const V = @import("./../value.zig");

const IntTypeSize: usize = 8;
const FloatTypeSize: usize = 8;
const PositionTypeSize: usize = 2 * IntTypeSize;

pub fn eval(runtime: *Runtime, bytecode: []const u8) Errors.RuntimeErrors!void {
    var ip: usize = 0;
    while (true) {
        switch (@as(Op, @enumFromInt(bytecode[ip]))) {
            Op.ret => return,
            Op.push_char => {
                try runtime.pushCharValue(bytecode[ip + 1]);
                ip += 2;
            },
            Op.push_false => {
                try runtime.pushBoolValue(false);
                ip += 1;
            },
            Op.push_float => {
                try runtime.pushFloatValue(readFloat(bytecode, ip + 1));
                ip += 1 + FloatTypeSize;
            },
            Op.push_identifier => {
                const len: usize = @intCast(readInt(bytecode, ip + 1));
                const str = bytecode[ip + 9 .. ip + 9 + len];
                const name = try runtime.stringPool.intern(str);
                defer name.decRef();

                if (runtime.getFromScope(name)) |result| {
                    try runtime.push(result);
                } else {
                    const position = readPosition(bytecode, ip + 1 + IntTypeSize + len);
                    const rec = try ER.pushNamedUserError(runtime, "UnknownIdentifierError", position);
                    try rec.v.RecordKind.setU8(runtime.stringPool, "identifier", try runtime.newStringPoolValue(name));
                    return Errors.RuntimeErrors.InterpreterError;
                }

                ip += 1 + IntTypeSize + len + PositionTypeSize;
            },
            Op.push_int => {
                try runtime.pushIntValue(readInt(bytecode, ip + 1));
                ip += 1 + IntTypeSize;
            },
            Op.push_function => {
                ip = try pushFunction(runtime, bytecode, ip);
            },
            Op.push_record => {
                try runtime.pushEmptyRecordValue();
                ip += 1;
            },
            Op.push_sequence => {
                try runtime.pushEmptySequenceValue();
                ip += 1;
            },
            Op.push_string => {
                const len: usize = @intCast(readInt(bytecode, ip + 1));
                const str = bytecode[ip + 9 .. ip + 9 + len];
                try runtime.pushStringValue(str);
                ip += 1 + IntTypeSize + len;
            },
            Op.push_true => {
                try runtime.pushBoolValue(true);
                ip += 1;
            },
            Op.push_unit => {
                try runtime.pushUnitValue();
                ip += 1;
            },
            Op.jmp => ip = @intCast(readInt(bytecode, ip + 1)),
            Op.jmp_true => {
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
            Op.jmp_false => {
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
            .is_sequence => {
                const v = runtime.pop();
                try runtime.pushBoolValue(v.isSequence());
                ip += 1;
            },
            .seq_len => {
                const v = runtime.pop();
                try runtime.pushIntValue(if (v.isSequence()) @intCast(v.v.SequenceKind.len()) else 0);
                ip += 1;
            },
            .seq_at => {
                ip += 1;
                unreachable;
            },
            .open_scope => {
                try runtime.openScope();
                ip += 1;
            },
            .close_scope => {
                runtime.popScope();
                ip += 1;
            },
            Op.call => {
                const numArgs = readInt(bytecode, ip + 1);

                runtime.callFn(@intCast(numArgs)) catch |err| {
                    const position = readPosition(bytecode, ip + 1 + IntTypeSize);
                    try ER.appendErrorPosition(runtime, position);
                    return err;
                };

                ip += 1 + IntTypeSize + PositionTypeSize;
            },
            Op.bind => {
                try runtime.bind();
                ip += 1;
            },
            .assign_dot => {
                const exprPosition = readPosition(bytecode, ip + 1);
                const namePosition = readPosition(bytecode, ip + 1 + PositionTypeSize);
                try runtime.assignIndex(exprPosition, namePosition);
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
            Op.duplicate => {
                try runtime.duplicate();
                ip += 1;
            },
            Op.discard => {
                _ = runtime.pop();
                ip += 1;
            },
            Op.append_sequence_item_bang => {
                const seqPosition = readPosition(bytecode, ip + 1);

                try runtime.appendSequenceItemBang(seqPosition);
                ip += 1 + PositionTypeSize;
            },
            Op.append_sequence_items_bang => {
                const seqPosition = readPosition(bytecode, ip + 1);
                const itemPosition = readPosition(bytecode, ip + 1 + PositionTypeSize);

                try runtime.appendSequenceItemsBang(seqPosition, itemPosition);
                ip += 1 + PositionTypeSize + PositionTypeSize;
            },
            Op.set_record_item_bang => {
                const position = readPosition(bytecode, ip + 1);

                try runtime.setRecordItemBang(position);
                ip += 1 + PositionTypeSize;
            },
            Op.set_record_items_bang => {
                const position = readPosition(bytecode, ip + 1);

                try runtime.setRecordItemsBang(position);
                ip += 1 + PositionTypeSize;
            },
            Op.equals => {
                try runtime.equals();
                ip += 1;
            },
            Op.not_equals => {
                try runtime.notEquals();
                ip += 1;
            },
            Op.less_than => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.lessThan(position);
                ip += 1 + PositionTypeSize;
            },
            Op.less_equal => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.lessEqual(position);
                ip += 1 + PositionTypeSize;
            },
            Op.greater_than => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.greaterThan(position);
                ip += 1 + PositionTypeSize;
            },
            Op.greater_equal => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.greaterEqual(position);
                ip += 1 + PositionTypeSize;
            },
            Op.add => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.add(position);
                ip += 1 + PositionTypeSize;
            },
            Op.subtract => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.subtract(position);
                ip += 1 + PositionTypeSize;
            },
            Op.multiply => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.multiply(position);
                ip += 1 + PositionTypeSize;
            },
            Op.divide => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.divide(position);
                ip += 1 + PositionTypeSize;
            },
            Op.modulo => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.modulo(position);
                ip += 1 + PositionTypeSize;
            },
            Op.seq_append => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.appendSequenceItem(position);
                ip += 1 + PositionTypeSize;
            },
            Op.seq_append_bang => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.appendSequenceItemBang(position);
                ip += 1 + PositionTypeSize;
            },
            Op.seq_prepend => {
                const position = readPosition(bytecode, ip + 1);
                try runtime.prependSequenceItem(position);
                ip += 1 + PositionTypeSize;
            },
            Op.seq_prepend_bang => {
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

fn readString(bytecode: []const u8, ip: usize) []const u8 {
    const len: usize = @intCast(readInt(bytecode, ip));
    return bytecode[ip + 8 .. ip + 8 + len];
}

inline fn pushFunction(runtime: *Runtime, bytecode: []const u8, ipStart: usize) !usize {
    var ip = ipStart;

    const numberOfParameters: usize = @intCast(readInt(bytecode, ip + 1));
    ip = ip + 1 + IntTypeSize;

    var parameters: []V.FunctionArgument = try runtime.allocator.alloc(V.FunctionArgument, numberOfParameters);
    errdefer runtime.allocator.free(parameters);

    const sp = runtime.stack.items.len;

    for (0..numberOfParameters) |index| {
        const name = readString(bytecode, ip);
        const code = readString(bytecode, ip + IntTypeSize + name.len);

        if (code.len == 0) {
            parameters[index] = V.FunctionArgument{ .name = try runtime.stringPool.intern(name), .default = null };
        } else {
            try eval(runtime, code);
            const v = runtime.peek(0);
            const vv = try v.toString(runtime.allocator, V.Style.Pretty);
            defer runtime.allocator.free(vv);

            parameters[index] = V.FunctionArgument{ .name = try runtime.stringPool.intern(name), .default = runtime.peek(0) };
        }

        ip += IntTypeSize + name.len + IntTypeSize + code.len;
    }

    const restName = readString(bytecode, ip);
    ip += IntTypeSize + restName.len;

    const body = readString(bytecode, ip);
    ip += IntTypeSize + body.len;

    const result = try runtime.pushValue(V.ValueValue{ .BCFunctionKind = V.BCFunctionValue{
        .scope = runtime.scope(),
        .arguments = parameters,
        .restOfArguments = if (restName.len == 0) null else try runtime.stringPool.intern(restName),
        .body = try runtime.allocator.dupe(u8, body),
    } });

    runtime.popn(runtime.stack.items.len - sp);
    try runtime.push(result);

    return ip;
}
