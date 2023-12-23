const Helper = @import("./helper.zig");

pub fn imports(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression, args: []*Helper.Value) !void {
    _ = args;
    _ = argsAST;
    _ = calleeAST;
    try machine.memoryState.pushEmptyMapValue();

    const result = machine.memoryState.peek(0);

    var iterator = machine.memoryState.imports.items.iterator();
    while (iterator.next()) |entry| {
        const items: *Helper.Value = if (entry.value_ptr.*.items == null) machine.memoryState.unitValue.? else entry.value_ptr.*.items.?;

        // unitValues are not stored in a record set so the repl lines will not be included in the result.
        // if you would like to see them then comment out the statement below.
        // const items: *V.Value = if (entry.value_ptr.*.items == null) try machine.memoryState.newValue(V.ValueValue{ .RecordKind = std.StringHashMap(*V.Value).init(machine.memoryState.allocator) }) else entry.value_ptr.*.items.?;

        try result.v.RecordKind.set(machine.memoryState.allocator, entry.key_ptr.*, items);
    }
}
