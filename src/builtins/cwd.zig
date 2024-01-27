const std = @import("std");
const Helper = @import("./helper.zig");

pub fn cwd(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    _ = numberOfArgs;
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    const c = std.os.getcwd(&buf) catch {
        try machine.memoryState.pushStringValue("./");
        return;
    };

    try machine.memoryState.pushStringValue(c);
}
