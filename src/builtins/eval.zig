const std = @import("std");
const Helper = @import("./helper.zig");

pub fn eval(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression, args: []*Helper.Value) !void {
    const code = try Helper.getArgument(machine, calleeAST, argsAST, args, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});

    const stackSize = machine.memoryState.stack.items.len;

    try machine.memoryState.openScope();
    defer machine.memoryState.restoreScope();

    machine.execute("eval", code.v.StringKind.slice()) catch |e| {
        if (machine.err == null or machine.err.?.detail != Helper.Errors.ErrorKind.UserKind) {
            while (machine.memoryState.stack.items.len > stackSize) {
                _ = machine.memoryState.pop();
            }

            try machine.memoryState.pushEmptyMapValue();
            const record = machine.memoryState.peek(0);

            try record.v.RecordKind.setU8(machine.memoryState.stringPool, "kind", try machine.memoryState.newStringValue("EvalError"));

            var err = machine.grabErr();
            if (err == null) {
                std.debug.print("Error: {}\n", .{e});
            } else {
                var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
                defer buffer.deinit();

                err.?.append(&buffer) catch {};

                try record.v.RecordKind.setU8(machine.memoryState.stringPool, "message", try machine.memoryState.newOwnedStringValue(try buffer.toOwnedSlice()));

                err.?.deinit();
            }
        } else {
            const record = machine.topOfStack().?;
            try record.v.RecordKind.setU8(machine.memoryState.stringPool, "content", code);
        }

        return Helper.Errors.err.InterpreterError;
    };
}

test "eval" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("eval(\"\")", "()");

    try Main.expectExprEqual("eval(\"1\")", "1");
    try Main.expectExprEqual("eval(\"let x = 10; x + 1\")", "11");
    try Main.expectExprEqual("eval(\"let add(a, b) a + b; add\")(1, 2)", "3");
}
