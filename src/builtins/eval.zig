const std = @import("std");
const Helper = @import("./helper.zig");

pub fn eval(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const code = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});

    try machine.memoryState.openScope();
    defer machine.memoryState.restoreScope();

    machine.execute("eval", code.v.StringKind.slice()) catch {
        const record = machine.topOfStack().?;
        try record.v.RecordKind.setU8(machine.memoryState.stringPool, "content", code);

        return Helper.Errors.RuntimeErrors.InterpreterError;
    };
}

test "eval" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("eval(\"\")", "()");

    try Main.expectExprEqual("eval(\"1\")", "1");
    try Main.expectExprEqual("eval(\"let x = 10; x + 1\")", "11");
    try Main.expectExprEqual("eval(\"let add(a, b) a + b; add\")(1, 2)", "3");
}
