const std = @import("std");
const Helper = @import("./helper.zig");

pub fn cwd(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    _ = numberOfArgs;
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    const c = std.posix.getcwd(&buf) catch {
        try machine.pushStringValue("./");
        return;
    };

    try machine.pushStringValue(c);
}
