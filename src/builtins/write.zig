const Helper = @import("./helper.zig");

pub fn write(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    const handle = try Helper.getArgument(machine, calleeAST, argsAST, "handle", 0, &[_]Helper.ValueKind{ Helper.ValueValue.FileKind, Helper.ValueKind.StreamKind });
    const bytes = try Helper.getArgument(machine, calleeAST, argsAST, "bytes", 1, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});

    const bytesWritten: usize = switch (handle.v) {
        Helper.ValueKind.FileKind => handle.v.FileKind.file.write(bytes.v.StringKind),
        Helper.ValueKind.StreamKind => handle.v.StreamKind.stream.write(bytes.v.StringKind),
        else => unreachable,
    } catch |err| return Helper.osError(machine, "write", err);

    try machine.memoryState.pushIntValue(@intCast(bytesWritten));
}
