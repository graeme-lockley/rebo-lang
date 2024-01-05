const Helper = @import("./helper.zig");

pub fn scope(machine: *Helper.Machine, numberOfArgs: usize) !void {
    _ = numberOfArgs;
    try machine.memoryState.push(machine.memoryState.scope().?);
}
