const Helper = @import("./helper.zig");

pub fn write(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const handle = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{ Helper.ValueValue.FileKind, Helper.ValueValue.HttpClientRequestKind, Helper.ValueKind.StreamKind });
    const bytes = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});

    const bytesWritten: usize = switch (handle.v) {
        Helper.ValueKind.FileKind => handle.v.FileKind.file.write(bytes.v.StringKind.slice()),
        Helper.ValueKind.HttpClientRequestKind => handle.v.HttpClientRequestKind.write(bytes.v.StringKind.slice()),
        Helper.ValueKind.StreamKind => handle.v.StreamKind.stream.write(bytes.v.StringKind.slice()),
        else => unreachable,
    } catch |err| return Helper.raiseOsError(machine, "write", err);

    try machine.pushIntValue(@intCast(bytesWritten));
}
