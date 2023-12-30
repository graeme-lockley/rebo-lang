const std = @import("std");

const AST = @import("./../ast.zig");
pub const Errors = @import("./../errors.zig");
const M = @import("./../machine.zig");
const V = @import("./../value.zig");

pub const Expression = AST.Expression;
pub const IntType = V.IntType;
pub const Machine = M.Machine;
pub const MemoryState = @import("./../memory_state.zig");
pub const StringPool = @import("./../string_pool.zig").StringPool;
pub const Style = V.Style;
pub const Value = V.Value;
pub const ValueKind = V.ValueKind;
pub const ValueValue = V.ValueValue;

pub fn osError(machine: *Machine, operation: []const u8, err: anyerror) Errors.RuntimeErrors!void {
    try machine.memoryState.pushEmptyRecordValue();

    const record = machine.memoryState.peek(0);
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "kind", try machine.memoryState.newStringValue("SystemError"));
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "operation", try machine.memoryState.newStringValue(operation));

    var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{err});

    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "os", try machine.memoryState.newOwnedStringValue(try buffer.toOwnedSlice()));

    return Errors.RuntimeErrors.InterpreterError;
}

pub fn fatalErrorHandler(machine: *Machine, operation: []const u8, err: anyerror) void {
    const str = machine.memoryState.topOfStack().?.toString(machine.memoryState.allocator, V.Style.Pretty) catch return;
    defer machine.memoryState.allocator.free(str);
    std.log.err("Error: {s}: {}\n", .{ operation, err });
    std.log.err("{s}\n", .{str});
    std.os.exit(1);
}

fn reportExpectedTypeError(machine: *Machine, position: Errors.Position, expected: []const V.ValueKind, v: V.ValueKind) !void {
    try M.raiseExpectedTypeError(machine, position, expected, v);
}

fn reportPositionExpectedTypeError(machine: *Machine, position: usize, args: []*Expression, defaultPosition: Errors.Position, expected: []const V.ValueKind, v: V.ValueKind) !void {
    const pos = if (args.len > position) args[position].position else defaultPosition;
    try reportExpectedTypeError(machine, pos, expected, v);
}

pub fn getArgument(machine: *Machine, calleeAST: *Expression, argsAST: []*Expression, args: []*V.Value, position: usize, expected: []const ValueKind) !*Value {
    const value = if (0 <= position and position < args.len) args[position] else machine.memoryState.unitValue.?;

    for (expected) |expctd| {
        if (value.v == expctd) {
            return value;
        }
    }

    try reportPositionExpectedTypeError(machine, position, argsAST, calleeAST.position, expected, value.v);

    return machine.memoryState.unitValue.?;
}
