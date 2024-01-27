const std = @import("std");

const AST = @import("./../ast.zig");
pub const Errors = @import("./../errors.zig");
pub const M = @import("./../ast-interpreter.zig");
pub const V = @import("./../value.zig");

pub const ER = @import("./../error-reporting.zig");
pub const Expression = AST.Expression;
pub const IntType = V.IntType;
pub const FloatType = V.FloatType;
pub const ASTInterpreter = M.ASTInterpreter;
pub const MemoryState = @import("./../runtime.zig");
pub const StringPool = @import("./../string_pool.zig").StringPool;
pub const Style = V.Style;
pub const Value = V.Value;
pub const ValueKind = V.ValueKind;
pub const ValueValue = V.ValueValue;

pub fn pushOsError(machine: *ASTInterpreter, operation: []const u8, err: anyerror) Errors.RuntimeErrors!*V.Value {
    try machine.runtime.pushEmptyRecordValue();

    const record = machine.runtime.peek(0);
    try record.v.RecordKind.setU8(machine.runtime.stringPool, "kind", try machine.runtime.newStringValue("SystemError"));
    try record.v.RecordKind.setU8(machine.runtime.stringPool, "operation", try machine.runtime.newStringValue(operation));

    var buffer = std.ArrayList(u8).init(machine.runtime.allocator);
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{err});

    try record.v.RecordKind.setU8(machine.runtime.stringPool, "os", try machine.runtime.newOwnedStringValue(try buffer.toOwnedSlice()));

    return record;
}

pub fn raiseOsError(machine: *ASTInterpreter, operation: []const u8, err: anyerror) Errors.RuntimeErrors!void {
    _ = try pushOsError(machine, operation, err);

    return Errors.RuntimeErrors.InterpreterError;
}

fn reportExpectedTypeError(machine: *ASTInterpreter, expected: []const V.ValueKind, v: V.ValueKind) !void {
    try ER.raiseExpectedTypeError(&machine.runtime, null, expected, v);
}

pub fn getArgument(machine: *ASTInterpreter, numberOfArgs: usize, position: usize, expected: []const ValueKind) !*Value {
    const value = if (0 <= position and position < numberOfArgs) machine.runtime.peek(numberOfArgs - position - 1) else machine.runtime.unitValue.?;

    for (expected) |expctd| {
        if (value.v == expctd) {
            return value;
        }
    }

    try reportExpectedTypeError(machine, expected, value.v);

    return machine.runtime.unitValue.?;
}
