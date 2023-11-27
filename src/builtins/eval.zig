const std = @import("std");
const Helper = @import("./helper.zig");

pub fn eval(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    const code = machine.memoryState.getFromScope("code") orelse machine.memoryState.unitValue;

    if (code.?.v != Helper.ValueKind.StringKind) {
        try Helper.reportPositionExpectedTypeError(machine, 0, argsAST, calleeAST.position, &[_]Helper.ValueKind{Helper.ValueValue.StringKind}, code.?.v);
    }

    const stackSize = machine.memoryState.stack.items.len;

    machine.execute("eval", code.?.v.StringKind) catch |e| {
        while (machine.memoryState.stack.items.len > stackSize) {
            _ = machine.memoryState.pop();
        }

        try machine.memoryState.pushEmptyMapValue();
        const record = machine.memoryState.peek(0);

        try record.v.RecordKind.set(machine.memoryState.allocator, "kind", try machine.memoryState.newStringValue("EvalError"));
        try record.v.RecordKind.set(machine.memoryState.allocator, "content", code.?);

        var err = machine.grabErr();

        if (err == null) {
            std.debug.print("Error: {}\n", .{e});
        } else {
            var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
            defer buffer.deinit();

            err.?.append(&buffer) catch {};

            try record.v.RecordKind.set(machine.memoryState.allocator, "message", try machine.memoryState.newOwnedStringValue(&buffer));

            err.?.deinit();
        }
    };
}

test "eval" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("eval(\"\")", "()");

    try Main.expectExprEqual("eval(\"1\")", "1");
    try Main.expectExprEqual("eval(\"let x = 10; x + 1\")", "11");
    try Main.expectExprEqual("eval(\"let add(a, b) a + b; add\")(1, 2)", "3");
}
