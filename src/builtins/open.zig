const std = @import("std");
const Helper = @import("./helper.zig");

fn booleanOption(stringPool: *Helper.StringPool, options: *Helper.Value, name: []const u8, default: bool) !bool {
    const option = try options.v.RecordKind.getU8(stringPool, name);

    if (option == null or option.?.v != Helper.ValueKind.BoolKind) {
        return default;
    }

    return option.?.v.BoolKind;
}

pub fn open(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const path = (try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind})).v.StringKind.slice();
    const options = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.RecordKind, Helper.ValueValue.UnitKind });

    if (options.v == Helper.ValueKind.UnitKind) {
        try machine.memoryState.push(try machine.memoryState.newFileValue(std.fs.cwd().openFile(path, .{}) catch |err| return Helper.raiseOsError(machine, "open", err)));
        return;
    }

    const readF = try booleanOption(machine.memoryState.stringPool, options, "read", false);
    const writeF = try booleanOption(machine.memoryState.stringPool, options, "write", false);
    const appendF = try booleanOption(machine.memoryState.stringPool, options, "append", false);
    const truncateF = try booleanOption(machine.memoryState.stringPool, options, "truncate", false);
    const createF = try booleanOption(machine.memoryState.stringPool, options, "create", false);

    if (createF) {
        const file = std.fs.cwd().createFile(path, .{ .read = readF, .truncate = truncateF, .exclusive = false }) catch |err| return Helper.raiseOsError(machine, "open", err);
        try machine.memoryState.push(try machine.memoryState.newFileValue(file));
    } else {
        const mode = if (readF and writeF) std.fs.File.OpenMode.read_write else if (readF) std.fs.File.OpenMode.read_only else std.fs.File.OpenMode.write_only;
        var file = std.fs.cwd().openFile(path, .{ .mode = mode }) catch |err| return Helper.raiseOsError(machine, "open", err);

        try machine.memoryState.push(try machine.memoryState.newFileValue(file));

        if (appendF) {
            file.seekFromEnd(0) catch |err| return Helper.raiseOsError(machine, "open", err);
        }
    }
}
