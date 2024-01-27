const std = @import("std");
const Helper = @import("./helper.zig");

pub fn fexists(name: []const u8) bool {
    std.fs.Dir.access(std.fs.cwd(), name, .{}) catch return false;
    return true;
}

pub fn exists(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const fileName = (try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind})).v.StringKind.slice();

    try machine.memoryState.pushBoolValue(fexists(fileName));
}

pub fn absolute(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const fileName = (try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind})).v.StringKind.slice();

    const absolutePath = std.fs.cwd().realpathAlloc(machine.memoryState.allocator, fileName) catch |err| {
        const record = try Helper.pushOsError(machine, "absolute", err);
        try record.v.RecordKind.setU8(machine.memoryState.stringPool, "file", try machine.memoryState.newStringValue(fileName));
        return Helper.Errors.RuntimeErrors.InterpreterError;
    };

    try machine.memoryState.pushOwnedStringValue(absolutePath);
}
