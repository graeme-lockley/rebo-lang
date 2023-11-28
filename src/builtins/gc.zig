const Helper = @import("./helper.zig");

pub fn gc(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    const result = Helper.MemoryState.force_gc(&machine.memoryState);

    try machine.memoryState.pushEmptyMapValue();

    const record = machine.memoryState.peek(0);
    try record.v.RecordKind.set(machine.memoryState.allocator, "capacity", try machine.memoryState.newIntValue(result.capacity));
    try record.v.RecordKind.set(machine.memoryState.allocator, "before", try machine.memoryState.newIntValue(result.oldSize));
    try record.v.RecordKind.set(machine.memoryState.allocator, "after", try machine.memoryState.newIntValue(result.newSize));
    try record.v.RecordKind.set(machine.memoryState.allocator, "duration", try machine.memoryState.newIntValue(@intCast(result.duration)));
}
