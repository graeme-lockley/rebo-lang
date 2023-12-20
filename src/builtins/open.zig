const std = @import("std");
const Helper = @import("./helper.zig");

fn booleanOption(options: *Helper.Value, name: []const u8, default: bool) bool {
    const option = options.v.RecordKind.get(name);

    if (option == null or option.?.v != Helper.ValueKind.BoolKind) {
        return default;
    }

    return option.?.v.BoolKind;
}

pub fn open(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    const path = (try Helper.getArgument(machine, calleeAST, argsAST, "path", 0, &[_]Helper.ValueKind{Helper.ValueValue.OldStringKind})).v.OldStringKind;
    const options = try Helper.getArgument(machine, calleeAST, argsAST, "options", 1, &[_]Helper.ValueKind{ Helper.ValueValue.RecordKind, Helper.ValueValue.UnitKind });

    if (options.v == Helper.ValueKind.UnitKind) {
        try machine.memoryState.push(try machine.memoryState.newFileValue(std.fs.cwd().openFile(path, .{}) catch |err| return Helper.osError(machine, "open", err)));
        return;
    }

    const readF = booleanOption(options, "read", false);
    const writeF = booleanOption(options, "write", false);
    const appendF = booleanOption(options, "append", false);
    const truncateF = booleanOption(options, "truncate", false);
    const createF = booleanOption(options, "create", false);

    if (createF) {
        try machine.memoryState.push(try machine.memoryState.newFileValue(std.fs.cwd().createFile(path, .{ .read = readF, .truncate = truncateF, .exclusive = true }) catch |err| return Helper.osError(machine, "open", err)));
    } else {
        const mode = if (readF and writeF) std.fs.File.OpenMode.read_write else if (readF) std.fs.File.OpenMode.read_only else std.fs.File.OpenMode.write_only;
        var file = std.fs.cwd().openFile(path, .{ .mode = mode }) catch |err| return Helper.osError(machine, "open", err);

        try machine.memoryState.push(try machine.memoryState.newFileValue(file));

        if (appendF) {
            file.seekFromEnd(0) catch |err| return Helper.osError(machine, "open", err);
        }
    }
}
