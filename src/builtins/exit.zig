const std = @import("std");
const Helper = @import("./helper.zig");

pub fn exit(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    const v = try Helper.getArgument(machine, calleeAST, argsAST, "v", 0, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueKind.UnitKind });

    if (v.v == Helper.ValueKind.IntKind) {
        std.os.exit(@intCast(v.v.IntKind));
    } else {
        std.os.exit(0);
    }
}
