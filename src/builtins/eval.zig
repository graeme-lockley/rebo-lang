const std = @import("std");
const Helper = @import("./helper.zig");

pub fn eval(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression, args: []*Helper.Value) !void {
    const code = try Helper.getArgument(machine, calleeAST, argsAST, args, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});

    const stackSize = machine.memoryState.stack.items.len;
    _ = stackSize;

    try machine.memoryState.openScope();
    defer machine.memoryState.restoreScope();

    machine.execute("eval", code.v.StringKind.slice()) catch {
        const record = machine.topOfStack().?;
        try record.v.RecordKind.setU8(machine.memoryState.stringPool, "content", code);

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
