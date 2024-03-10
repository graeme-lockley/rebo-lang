const std = @import("std");

const AST = @import("./../ast.zig");
pub const Errors = @import("./../errors.zig");
pub const M = @import("./../ast-interpreter.zig");
pub const B = @import("./../bc-interpreter.zig");
pub const V = @import("./../value.zig");

pub const ER = @import("./../error-reporting.zig");
pub const Expression = AST.Expression;
pub const IntType = V.IntType;
pub const FloatType = V.FloatType;
pub const MemoryState = @import("./../runtime.zig");
pub const Runtime = MemoryState.Runtime;
pub const StringPool = @import("./../string_pool.zig").StringPool;
pub const Style = V.Style;
pub const Value = V.Value;
pub const ValueKind = V.ValueKind;
pub const ValueValue = V.ValueValue;

pub fn pushOsError(runtime: *Runtime, operation: []const u8, err: anyerror) Errors.RuntimeErrors!*V.Value {
    try runtime.pushEmptyRecordValue();

    const record = runtime.peek(0);
    try record.v.RecordKind.setU8(runtime.stringPool, "kind", try runtime.newStringValue("SystemError"));
    try record.v.RecordKind.setU8(runtime.stringPool, "operation", try runtime.newStringValue(operation));

    var buffer = std.ArrayList(u8).init(runtime.allocator);
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{err});

    try record.v.RecordKind.setU8(runtime.stringPool, "os", try runtime.newOwnedStringValue(try buffer.toOwnedSlice()));

    return record;
}

pub fn raiseOsError(runtime: *Runtime, operation: []const u8, err: anyerror) Errors.RuntimeErrors!void {
    _ = try pushOsError(runtime, operation, err);

    return Errors.RuntimeErrors.InterpreterError;
}

fn reportExpectedTypeError(runtime: *Runtime, expected: []const V.ValueKind, v: V.ValueKind) !void {
    try ER.raiseExpectedTypeError(runtime, null, expected, v);
}

pub fn getArgument(runtime: *Runtime, numberOfArgs: usize, position: usize, expected: []const ValueKind) !*Value {
    const value = if (0 <= position and position < numberOfArgs) runtime.peek(numberOfArgs - position - 1) else runtime.unitValue.?;

    for (expected) |expctd| {
        if (value.v == expctd) {
            return value;
        }
    }

    try reportExpectedTypeError(runtime, expected, value.v);

    return runtime.unitValue.?;
}
