const Helper = @import("./helper.zig");

fn bytesToRead(arg: ?*Helper.Value) usize {
    return if (arg == null) 4096 else @intCast(arg.?.v.IntKind);
}

pub fn read(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const handle = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{ Helper.ValueValue.FileKind, Helper.ValueValue.StreamKind });
    const bytes = bytesToRead(try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueValue.UnitKind }));

    const buffer = try machine.memoryState.allocator.alloc(u8, @intCast(bytes));
    defer machine.memoryState.allocator.free(buffer);

    const bytesRead = switch (handle.v) {
        Helper.ValueKind.FileKind => handle.v.FileKind.file.read(buffer) catch |err| return Helper.raiseOsError(machine, "read", err),
        Helper.ValueKind.StreamKind => handle.v.StreamKind.stream.read(buffer) catch |err| return Helper.raiseOsError(machine, "read", err),
        else => unreachable,
    };

    try machine.memoryState.push(try machine.memoryState.newStringValue(buffer[0..bytesRead]));
}
