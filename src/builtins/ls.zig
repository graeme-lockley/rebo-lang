const std = @import("std");
const Helper = @import("./helper.zig");

pub fn ls(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{ Helper.ValueValue.StringKind, Helper.ValueValue.UnitKind });

    const path = if (v.v == Helper.ValueKind.StringKind) v.v.StringKind.slice() else "./";
    try machine.pushEmptySequenceValue();

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| return Helper.raiseOsError(machine, "ls", err);
    defer dir.close();

    const result = machine.peek(0);

    var it = dir.iterate();
    while (it.next() catch |err| return Helper.raiseOsError(machine, "ls", err)) |entry| {
        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) {
            continue;
        }

        const record = try machine.newRecordValue();
        try result.v.SequenceKind.appendItem(record);

        try record.v.RecordKind.setU8(machine.stringPool, "name", try machine.newStringValue(entry.name));

        const kind = switch (entry.kind) {
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
}
