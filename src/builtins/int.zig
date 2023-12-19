const std = @import("std");
const Helper = @import("./helper.zig");

pub fn int(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    const v = try Helper.getArgument(machine, calleeAST, argsAST, "value", 0, &[_]Helper.ValueKind{ Helper.ValueValue.CharKind, Helper.ValueKind.StringKind });
    const d = machine.memoryState.getFromScope("default") orelse machine.memoryState.unitValue.?;
    const b = try Helper.getArgument(machine, calleeAST, argsAST, "base", 2, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueKind.UnitKind });

    switch (v.v) {
        Helper.ValueValue.CharKind => try machine.memoryState.pushIntValue(@intCast(v.v.CharKind)),
        Helper.ValueKind.StringKind => {
            const literalInt = std.fmt.parseInt(Helper.IntType, v.v.StringKind, @intCast(if (b == machine.memoryState.unitValue) 10 else b.v.IntKind)) catch {
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

    try Main.expectExprEqual("int(\"\")", "()");
    try Main.expectExprEqual("int(\"123\")", "123");
    try Main.expectExprEqual("int(\"123\", 0, 8)", "83");

    try Main.expectExprEqual("int(\"xxx\", 0, 8)", "0");

    try Main.expectExprEqual("int('1')", "49");
    try Main.expectExprEqual("int('\\n')", "10");
    try Main.expectExprEqual("int('\\\\')", "92");
    try Main.expectExprEqual("int('\\'')", "39");
    try Main.expectExprEqual("int('\\x13')", "13");
}
