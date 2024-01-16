const std = @import("std");
const Helper = @import("./helper.zig");

pub fn int(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{ Helper.ValueValue.CharKind, Helper.ValueKind.StringKind });
    const d = if (numberOfArgs > 1) machine.memoryState.peek(numberOfArgs - 2) else machine.memoryState.unitValue.?;
    const b = try Helper.getArgument(machine, numberOfArgs, 2, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueKind.UnitKind });

    switch (v.v) {
        Helper.ValueValue.CharKind => try machine.memoryState.pushIntValue(@intCast(v.v.CharKind)),
        Helper.ValueKind.StringKind => {
            const literalInt = std.fmt.parseInt(Helper.IntType, v.v.StringKind.slice(), @intCast(if (b == machine.memoryState.unitValue) 10 else b.v.IntKind)) catch {
                try machine.memoryState.push(d);
                return;
            };
            try machine.memoryState.pushIntValue(literalInt);
        },
        else => unreachable,
    }
}

test "int" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("rebo.lang.int(\"\")", "()");
    try Main.expectExprEqual("rebo.lang.int(\"123\")", "123");
    try Main.expectExprEqual("rebo.lang.int(\"123\", 0, 8)", "83");

    try Main.expectExprEqual("rebo.lang.int(\"xxx\", 0, 8)", "0");

    try Main.expectExprEqual("rebo.lang.int('1')", "49");
    try Main.expectExprEqual("rebo.lang.int('\\n')", "10");
    try Main.expectExprEqual("rebo.lang.int('\\\\')", "92");
    try Main.expectExprEqual("rebo.lang.int('\\'')", "39");
    try Main.expectExprEqual("rebo.lang.int('\\x13')", "13");
}
