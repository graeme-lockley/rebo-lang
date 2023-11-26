const Helper = @import("./helper.zig");

pub fn write(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    const handle = machine.memoryState.getFromScope("handle") orelse machine.memoryState.unitValue;
    const bytes = machine.memoryState.getFromScope("bytes") orelse machine.memoryState.unitValue;

    if (bytes.?.v != Helper.ValueKind.StringKind) {
        try Helper.reportPositionExpectedTypeError(machine, 1, argsAST, calleeAST.position, &[_]Helper.ValueKind{Helper.ValueValue.StringKind}, bytes.?.v);
    }

    const bytesWritten: usize = switch (handle.?.v) {
        Helper.ValueKind.FileKind => handle.?.v.FileKind.file.write(bytes.?.v.StringKind),
        Helper.ValueKind.StreamKind => handle.?.v.StreamKind.stream.write(bytes.?.v.StringKind),
        else => return Helper.reportPositionExpectedTypeError(machine, 0, argsAST, calleeAST.position, &[_]Helper.ValueKind{ Helper.ValueValue.FileKind, Helper.ValueValue.StreamKind }, handle.?.v),
    } catch |err| return Helper.osError(machine, "write", err);

    try machine.memoryState.pushIntValue(@intCast(bytesWritten));
}
