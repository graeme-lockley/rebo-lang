const std = @import("std");
const Helper = @import("./helper.zig");

fn booleanOption(stringPool: *Helper.StringPool, options: *Helper.Value, name: []const u8, default: bool) !bool {
    if (options.v != Helper.ValueValue.RecordKind) {
        return default;
    }

    const option = try options.v.RecordKind.getU8(stringPool, name);

    if (option == null or option.?.v != Helper.ValueKind.BoolKind) {
        return default;
    }

    return option.?.v.BoolKind;
}

pub fn eval(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const code = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const scope = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});

    try machine.runtime.openScopeUsing(scope);
    defer machine.runtime.restoreScope();

    machine.execute("eval", code.v.StringKind.slice()) catch {
        const record = machine.topOfStack().?;
        if (record.v == Helper.ValueValue.RecordKind) {
            try record.v.RecordKind.setU8(machine.runtime.stringPool, "content", code);
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
