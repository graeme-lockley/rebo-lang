const std = @import("std");
const Helper = @import("./helper.zig");

pub fn milliTimestamp(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression, args: []*Helper.Value) !void {
    _ = args;
    _ = argsAST;
    _ = calleeAST;
    try machine.memoryState.pushIntValue(@intCast(std.time.milliTimestamp()));
}
