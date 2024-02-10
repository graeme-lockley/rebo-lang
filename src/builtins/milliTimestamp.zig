const std = @import("std");
const Helper = @import("./helper.zig");

pub fn milliTimestamp(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    _ = numberOfArgs;
    try machine.pushIntValue(@intCast(std.time.milliTimestamp()));
}
