const std = @import("std");

const AST = @import("./../ast.zig");
const Errors = @import("./../errors.zig");
const M = @import("./../machine.zig");
const V = @import("./../value.zig");

pub const evalExpr = M.evalExpr;
pub const Expression = AST.Expression;
pub const IntType = V.IntType;
pub const Machine = M.Machine;
pub const MemoryState = @import("./../memory_state.zig");
pub const Style = V.Style;
pub const Value = V.Value;
pub const ValueKind = V.ValueKind;
pub const ValueValue = V.ValueValue;

pub fn osError(machine: *Machine, operation: []const u8, err: anyerror) !void {
    try machine.memoryState.pushEmptyMapValue();

    const record = machine.memoryState.peek(0);
    try record.v.RecordKind.set(machine.memoryState.allocator, "error", try machine.memoryState.newStringValue("SystemError"));
    try record.v.RecordKind.set(machine.memoryState.allocator, "operation", try machine.memoryState.newStringValue(operation));

    var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{err});

    try record.v.RecordKind.set(machine.memoryState.allocator, "kind", try machine.memoryState.newOwnedStringValue(&buffer));
}

pub fn silentOsError(machine: *Machine, operation: []const u8, err: anyerror) void {
    osError(machine, operation, err) catch {};
}

pub fn fatalErrorHandler(machine: *Machine, operation: []const u8, err: anyerror) void {
    var e = machine.grabErr();
    if (e == null) {
        std.log.err("Error: {s}: {}\n", .{ operation, err });
    } else {
        std.log.err("Error: {s}: {}\n", .{ operation, err });
        e.?.print() catch |err2| {
            std.log.err("Error: {}: {}\n", .{ err, err2 });
        };
        e.?.deinit();
    }
    std.os.exit(1);
}

pub fn reportExpectedTypeError(machine: *Machine, position: Errors.Position, expected: []const V.ValueKind, v: V.ValueKind) !void {
    machine.replaceErr(try Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), position, expected, v));
    return Errors.err.InterpreterError;
}

pub fn reportPositionExpectedTypeError(machine: *Machine, position: usize, args: []*Expression, defaultPosition: Errors.Position, expected: []const V.ValueKind, v: V.ValueKind) !void {
    const pos = if (args.len > position) args[position].position else defaultPosition;
    try reportExpectedTypeError(machine, pos, expected, v);
}

pub fn getArgument(machine: *Machine, calleeAST: *Expression, argsAST: []*Expression, name: []const u8, position: usize, expected: []const ValueKind) !*Value {
    const value = machine.memoryState.getFromScope(name) orelse machine.memoryState.unitValue.?;

    for (expected) |expctd| {
        if (value.v == expctd) {
            return value;
        }
    }

    try reportPositionExpectedTypeError(machine, position, argsAST, calleeAST.position, expected, value.v);

    return machine.memoryState.unitValue.?;
}
