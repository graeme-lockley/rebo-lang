const std = @import("std");
const Helper = @import("./helper.zig");

pub fn socket(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression, args: []*Helper.Value) !void {
    const name = (try Helper.getArgument(machine, calleeAST, argsAST, args, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind})).v.StringKind.slice();
    const port = (try Helper.getArgument(machine, calleeAST, argsAST, args, 1, &[_]Helper.ValueKind{Helper.ValueValue.IntKind})).v.IntKind;

    const stream = std.net.tcpConnectToHost(machine.memoryState.allocator, name, @intCast(port)) catch |err| return Helper.osError(machine, "socket", err);
    try machine.memoryState.push(try machine.memoryState.newStreamValue(stream));
}
