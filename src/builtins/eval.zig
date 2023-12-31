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

pub fn eval(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const code = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const options = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.RecordKind, Helper.ValueValue.UnitKind });

    const persistent = try booleanOption(machine.memoryState.stringPool, options, "persistent", false);

    if (!persistent) {
        try machine.memoryState.openScope();
    }
    defer if (!persistent) {
        machine.memoryState.restoreScope();
    };

    machine.execute("eval", code.v.StringKind.slice()) catch {
        const record = machine.topOfStack().?;
        if (record.v == Helper.ValueValue.RecordKind) {
            try record.v.RecordKind.setU8(machine.memoryState.stringPool, "content", code);
        }

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
