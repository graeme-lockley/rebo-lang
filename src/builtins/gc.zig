const Helper = @import("./helper.zig");

pub fn gc(runtime: *Helper.Runtime, numberOfArgs: usize) !void {
    _ = numberOfArgs;
    const result = Helper.MemoryState.force_gc(runtime);

    try runtime.pushEmptyRecordValue();

    const record = runtime.peek(0);

    try record.v.RecordKind.setU8(runtime.stringPool, "allocations", try runtime.newIntValue(@intCast((runtime.allocations))));
    try record.v.RecordKind.setU8(runtime.stringPool, "stringpool", try runtime.newIntValue(@intCast((runtime.stringPool.count()))));
    try record.v.RecordKind.setU8(runtime.stringPool, "capacity", try runtime.newIntValue(result.capacity));
    try record.v.RecordKind.setU8(runtime.stringPool, "before", try runtime.newIntValue(result.oldSize));
    try record.v.RecordKind.setU8(runtime.stringPool, "after", try runtime.newIntValue(result.newSize));
    try record.v.RecordKind.setU8(runtime.stringPool, "duration", try runtime.newIntValue(@intCast(result.duration)));
}
