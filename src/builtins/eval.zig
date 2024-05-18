const std = @import("std");
const Helper = @import("./helper.zig");

pub fn eval(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const code = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const scope = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});

    try machine.openScopeUsing(scope);
    defer machine.restoreScope();

    Helper.M.execute(machine, "eval", code.v.StringKind.slice()) catch {
        const record = machine.topOfStack().?;
        if (record.v == Helper.ValueValue.RecordKind) {
            try record.v.RecordKind.setU8(machine.stringPool, "content", code);
        }

        return Helper.Errors.RuntimeErrors.InterpreterError;
    };
}

test "eval" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("rebo.lang.eval(\"\", rebo.lang.scope())", "()");

    try Main.expectExprEqual("rebo.lang.eval(\"1\", rebo.lang.scope())", "1");
    try Main.expectExprEqual("rebo.lang.eval(\"let x = 10; x + 1\", rebo.lang.scope())", "11");
    try Main.expectExprEqual("rebo.lang.eval(\"let add(a, b) a + b; add\", rebo.lang.scope())(1, 2)", "3");
}
