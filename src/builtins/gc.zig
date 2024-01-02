const Helper = @import("./helper.zig");

pub fn gc(machine: *Helper.Machine, numberOfArgs: usize) !void {
    _ = numberOfArgs;
    const result = Helper.MemoryState.force_gc(&machine.memoryState);

    try machine.memoryState.pushEmptyRecordValue();

    const record = machine.memoryState.peek(0);

    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "allocations", try machine.memoryState.newIntValue(@intCast((machine.memoryState.allocations))));
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "stringpool", try machine.memoryState.newIntValue(@intCast((machine.memoryState.stringPool.count()))));
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "capacity", try machine.memoryState.newIntValue(result.capacity));
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "before", try machine.memoryState.newIntValue(result.oldSize));
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "after", try machine.memoryState.newIntValue(result.newSize));
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "duration", try machine.memoryState.newIntValue(@intCast(result.duration)));
}
