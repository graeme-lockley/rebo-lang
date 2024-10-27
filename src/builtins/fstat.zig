const std = @import("std");
const Helper = @import("./helper.zig");

pub fn fstat(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const fileName = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});

    const file = std.fs.cwd().openFile(fileName.v.StringKind.slice(), .{}) catch |err| return Helper.raiseOsError(machine, "fstat", err);
    defer file.close();

    const stat = file.stat() catch |err| return Helper.raiseOsError(machine, "fstat", err);

    try machine.pushEmptyRecordValue();

    const record = machine.peek(0);

    try record.v.RecordKind.setU8(machine.stringPool, "size", try machine.newIntValue(@intCast(stat.size)));
    try record.v.RecordKind.setU8(machine.stringPool, "ctime", try machine.newIntValue(@intCast(stat.ctime)));
    try record.v.RecordKind.setU8(machine.stringPool, "mtime", try machine.newIntValue(@intCast(stat.mtime)));
    try record.v.RecordKind.setU8(machine.stringPool, "atime", try machine.newIntValue(@intCast(stat.atime)));

    const kind = switch (stat.kind) {
        .block_device => "block_device",
        .character_device => "character_device",
        .directory => "directory",
        .door => "door",
        .event_port => "event_port",
        .file => "file",
        .named_pipe => "named_pipe",
        .sym_link => "sym_link",
        .unix_domain_socket => "unix_domain_socket",
        .unknown => "unknown",
        .whiteout => "whiteout",
    };
    try record.v.RecordKind.setU8(machine.stringPool, "kind", try machine.newStringValue(kind));
}
