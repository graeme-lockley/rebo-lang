const std = @import("std");

const AST = @import("./../ast.zig");
pub const Errors = @import("./../errors.zig");
pub const M = @import("./../ast-interpreter.zig");
pub const V = @import("./../value.zig");

pub const Expression = AST.Expression;
pub const IntType = V.IntType;
pub const FloatType = V.FloatType;
pub const ASTInterpreter = M.ASTInterpreter;
pub const MemoryState = @import("./../memory_state.zig");
pub const StringPool = @import("./../string_pool.zig").StringPool;
pub const Style = V.Style;
pub const Value = V.Value;
pub const ValueKind = V.ValueKind;
pub const ValueValue = V.ValueValue;

pub fn pushOsError(machine: *ASTInterpreter, operation: []const u8, err: anyerror) Errors.RuntimeErrors!*V.Value {
    try machine.memoryState.pushEmptyRecordValue();

    const record = machine.memoryState.peek(0);
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "kind", try machine.memoryState.newStringValue("SystemError"));
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "operation", try machine.memoryState.newStringValue(operation));

    var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{err});

    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "os", try machine.memoryState.newOwnedStringValue(try buffer.toOwnedSlice()));

    return record;
}

pub fn raiseOsError(machine: *ASTInterpreter, operation: []const u8, err: anyerror) Errors.RuntimeErrors!void {
    _ = try pushOsError(machine, operation, err);

    return Errors.RuntimeErrors.InterpreterError;
}

fn reportExpectedTypeError(machine: *ASTInterpreter, expected: []const V.ValueKind, v: V.ValueKind) !void {
    try M.raiseExpectedTypeError(machine, null, expected, v);
}

pub fn getArgument(machine: *ASTInterpreter, numberOfArgs: usize, position: usize, expected: []const ValueKind) !*Value {
    const value = if (0 <= position and position < numberOfArgs) machine.memoryState.peek(numberOfArgs - position - 1) else machine.memoryState.unitValue.?;

    for (expected) |expctd| {
        if (value.v == expctd) {
            return value;
        }
    }

    try reportExpectedTypeError(machine, expected, value.v);

    return machine.memoryState.unitValue.?;
}
