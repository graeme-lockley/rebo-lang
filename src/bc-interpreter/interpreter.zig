const Errors = @import("./../errors.zig");
const Runtime = @import("./../runtime.zig").Runtime;
const Op = @import("./ops.zig").Op;
const V = @import("./../value.zig");

const IntTypeSize = 8;
const FloatTypeSize = 8;
const PositionTypeSize = 2 * IntTypeSize;

pub fn eval(runtime: *Runtime, bytecode: []const u8) !void {
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
            Op.push_int => {
                try runtime.pushIntValue(readInt(bytecode, ip + 1));
                ip += 1 + IntTypeSize;
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

            // else => unreachable,
        }
    }
}

fn readFloat(bytecode: []const u8, ip: usize) V.FloatType {
    return @as(V.FloatType, @bitCast(readInt(bytecode, ip)));
}

fn readInt(bytecode: []const u8, ip: usize) V.IntType {
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
