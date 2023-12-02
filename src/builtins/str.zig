const std = @import("std");
const Helper = @import("./helper.zig");

pub fn str(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    const v = machine.memoryState.getFromScope("value") orelse machine.memoryState.unitValue.?;
    const s = try Helper.getArgument(machine, calleeAST, argsAST, "literal", 1, &[_]Helper.ValueKind{ Helper.ValueValue.BoolKind, Helper.ValueValue.VoidKind });

    const style = if (s.v == Helper.ValueValue.VoidKind or s.v.BoolKind) Helper.Style.Pretty else Helper.Style.Raw;

    const strValue = try v.toString(machine.memoryState.allocator, style);

    try machine.memoryState.pushOwnedStringValue(strValue);

    return;
}

test "str" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("str(1)", "\"1\"");
    try Main.expectExprEqual("str(1, true)", "\"1\"");
    try Main.expectExprEqual("str(1, false)", "\"1\"");

    try Main.expectExprEqual("str('a')", "\"'a'\"");
    try Main.expectExprEqual("str('a', true)", "\"'a'\"");
    try Main.expectExprEqual("str('a', false)", "\"a\"");
}
