const std = @import("std");
const Helper = @import("./helper.zig");

pub fn socket(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const name = (try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind})).v.StringKind.slice();
    const port = (try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.IntKind})).v.IntKind;

    const stream = std.net.tcpConnectToHost(machine.allocator, name, @intCast(port)) catch |err| return Helper.raiseOsError(machine, "socket", err);
    try machine.push(try machine.newStreamValue(stream));
}
