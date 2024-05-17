const std = @import("std");
const Helper = @import("./helper.zig");

pub fn exec(machine: *Helper.Runtime, numberOfArgs: usize) Helper.Errors.RuntimeErrors!void {
    const command = (try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.SequenceKind})).v.SequenceKind;

    var buffer = std.ArrayList([]u8).init(machine.allocator);
    defer {
        for (buffer.items) |item| {
            machine.allocator.free(item);
        }
        buffer.deinit();
    }

    for (command.values.items) |cmd| {
        try buffer.append(try cmd.toString(machine.allocator, .Raw));
    }

    const proc = std.ChildProcess.run(.{
        .allocator = machine.allocator,
        .argv = buffer.items,
    }) catch |err| return Helper.raiseOsError(machine, "exec", err);
    defer machine.allocator.free(proc.stdout);
    defer machine.allocator.free(proc.stderr);

    try machine.pushEmptyRecordValue();

    const record = machine.peek(0);

    try record.v.RecordKind.setU8(machine.stringPool, "stdout", try machine.newStringValue(proc.stdout));
    try record.v.RecordKind.setU8(machine.stringPool, "stderr", try machine.newStringValue(proc.stderr));
    try record.v.RecordKind.setU8(machine.stringPool, "code", try machine.newIntValue(@intFromEnum(proc.term)));
}
