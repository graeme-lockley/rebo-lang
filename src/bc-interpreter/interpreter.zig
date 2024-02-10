const ER = @import("./../error-reporting.zig");
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
            Op.call => {
                const numArgs = readInt(bytecode, ip + 1);

                runtime.callFn(@intCast(numArgs)) catch |err| {
                    const position = readPosition(bytecode, ip + 1 + IntTypeSize);
                    try ER.appendErrorPosition(runtime, position);
                    return err;
                };

                ip += 1 + IntTypeSize + PositionTypeSize;
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
    return bytecode[ip + 9 .. ip + 9 + len];
}
