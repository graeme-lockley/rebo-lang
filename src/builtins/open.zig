const std = @import("std");
const Helper = @import("./helper.zig");

pub fn open(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const path = (try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind})).v.StringKind.slice();
    const options = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.RecordKind, Helper.ValueValue.UnitKind });

    if (options.v == Helper.ValueKind.UnitKind) {
        try machine.push(try machine.newFileValue(std.fs.cwd().openFile(path, .{}) catch |err| return Helper.raiseOsError(machine, "open", err)));
        return;
    }

    const readF = try Helper.booleanOption(machine.stringPool, options, "read", false);
    const writeF = try Helper.booleanOption(machine.stringPool, options, "write", false);
    const appendF = try Helper.booleanOption(machine.stringPool, options, "append", false);
    const truncateF = try Helper.booleanOption(machine.stringPool, options, "truncate", false);
    const createF = try Helper.booleanOption(machine.stringPool, options, "create", false);

    if (createF) {
        const file = std.fs.cwd().createFile(path, .{ .read = readF, .truncate = truncateF, .exclusive = false }) catch |err| return Helper.raiseOsError(machine, "open", err);
        try machine.push(try machine.newFileValue(file));
    } else {
        const mode = if (readF and writeF) std.fs.File.OpenMode.read_write else if (readF) std.fs.File.OpenMode.read_only else std.fs.File.OpenMode.write_only;
        var file = std.fs.cwd().openFile(path, .{ .mode = mode }) catch |err| return Helper.raiseOsError(machine, "open", err);

        try machine.push(try machine.newFileValue(file));

        if (appendF) {
            file.seekFromEnd(0) catch |err| return Helper.raiseOsError(machine, "open", err);
        }
    }
}
