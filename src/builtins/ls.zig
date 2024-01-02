const std = @import("std");
const Helper = @import("./helper.zig");

pub fn ls(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{ Helper.ValueValue.StringKind, Helper.ValueValue.UnitKind });

    const path = if (v.v == Helper.ValueKind.StringKind) v.v.StringKind.slice() else "./";
    try machine.memoryState.pushEmptySequenceValue();

    var dir = std.fs.cwd().openIterableDir(path, .{}) catch |err| return Helper.raiseOsError(machine, "ls", err);
    defer dir.close();

    const result = machine.memoryState.peek(0);

    var it = dir.iterate();
    while (it.next() catch |err| return Helper.raiseOsError(machine, "listen", err)) |entry| {
        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) {
            continue;
        }

        const record = try machine.memoryState.newRecordValue();
        try result.v.SequenceKind.appendItem(record);

        try record.v.RecordKind.setU8(machine.memoryState.stringPool, "name", try machine.memoryState.newStringValue(entry.name));

        const kind = switch (entry.kind) {
            std.fs.IterableDir.Entry.Kind.block_device => "block_device",
            std.fs.IterableDir.Entry.Kind.character_device => "character_device",
            std.fs.IterableDir.Entry.Kind.directory => "directory",
            std.fs.IterableDir.Entry.Kind.door => "door",
            std.fs.IterableDir.Entry.Kind.event_port => "event_port",
            std.fs.IterableDir.Entry.Kind.file => "file",
            std.fs.IterableDir.Entry.Kind.named_pipe => "named_pipe",
            std.fs.IterableDir.Entry.Kind.sym_link => "sym_link",
            std.fs.IterableDir.Entry.Kind.unix_domain_socket => "unix_domain_socket",
            std.fs.IterableDir.Entry.Kind.unknown => "unknown",
            std.fs.IterableDir.Entry.Kind.whiteout => "whiteout",
        };
        try record.v.RecordKind.setU8(machine.memoryState.stringPool, "kind", try machine.memoryState.newStringValue(kind));
    }
}
