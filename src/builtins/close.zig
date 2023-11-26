const Helper = @import("./helper.zig");

pub fn close(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    const handle = machine.memoryState.getFromScope("handle") orelse machine.memoryState.unitValue;

    switch (handle.?.v) {
        Helper.ValueKind.FileKind => handle.?.v.FileKind.close(),
        Helper.ValueKind.StreamKind => handle.?.v.StreamKind.close(),
        else => try Helper.reportPositionExpectedTypeError(machine, 0, argsAST, calleeAST.position, &[_]Helper.ValueKind{ Helper.ValueValue.FileKind, Helper.ValueKind.StreamKind }, handle.?.v),
    }

    try machine.memoryState.pushUnitValue();
}
