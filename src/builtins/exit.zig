const std = @import("std");
const Helper = @import("./helper.zig");

pub fn exit(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueKind.UnitKind });

    if (v.v == Helper.ValueKind.IntKind) {
        std.posix.exit(@intCast(v.v.IntKind));
    } else {
        std.posix.exit(0);
    }
}
