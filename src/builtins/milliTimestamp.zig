const std = @import("std");
const Helper = @import("./helper.zig");

pub fn milliTimestamp(machine: *Helper.Machine, numberOfArgs: usize) !void {
    _ = numberOfArgs;
    try machine.memoryState.pushIntValue(@intCast(std.time.milliTimestamp()));
}
