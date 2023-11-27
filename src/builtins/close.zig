const Helper = @import("./helper.zig");

pub fn close(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    const handle = try Helper.getArgument(machine, calleeAST, argsAST, "handle", 0, &[_]Helper.ValueKind{ Helper.ValueValue.FileKind, Helper.ValueKind.StreamKind });

    switch (handle.v) {
        Helper.ValueKind.FileKind => handle.v.FileKind.close(),
        Helper.ValueKind.StreamKind => handle.v.StreamKind.close(),
        else => unreachable,
    }

    try machine.memoryState.pushUnitValue();
}
