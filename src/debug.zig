const std = @import("std");

const Value = @import("./value.zig");
const Runtime = @import("./runtime.zig").Runtime;

pub fn showStack(runtime: *Runtime, depth: usize, msg: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    const stack = runtime.stack.items;

    try stdout.print("Stack trace: {s}\n", .{msg});
    var d = @max(0, stack.len - depth);

    while (d < stack.len) {
        const frame = stack[d];
        var value = try frame.toString(runtime.allocator, Value.Style.Pretty);
        defer runtime.allocator.free(value);

        try stdout.print("  {d} [{d}]: {s}\n", .{ d, stack.len - d - 1, value });

        d += 1;
    }
}
