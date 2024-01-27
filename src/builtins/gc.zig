const Helper = @import("./helper.zig");

pub fn gc(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    _ = numberOfArgs;
    const result = Helper.MemoryState.force_gc(&machine.runtime);

    try machine.runtime.pushEmptyRecordValue();

    const record = machine.runtime.peek(0);

    try record.v.RecordKind.setU8(machine.runtime.stringPool, "allocations", try machine.runtime.newIntValue(@intCast((machine.runtime.allocations))));
    try record.v.RecordKind.setU8(machine.runtime.stringPool, "stringpool", try machine.runtime.newIntValue(@intCast((machine.runtime.stringPool.count()))));
    try record.v.RecordKind.setU8(machine.runtime.stringPool, "capacity", try machine.runtime.newIntValue(result.capacity));
    try record.v.RecordKind.setU8(machine.runtime.stringPool, "before", try machine.runtime.newIntValue(result.oldSize));
    try record.v.RecordKind.setU8(machine.runtime.stringPool, "after", try machine.runtime.newIntValue(result.newSize));
    try record.v.RecordKind.setU8(machine.runtime.stringPool, "duration", try machine.runtime.newIntValue(@intCast(result.duration)));
}
