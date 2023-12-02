const Helper = @import("./helper.zig");

pub fn str(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    _ = calleeAST;
    _ = argsAST;
    const v = machine.memoryState.getFromScope("value") orelse machine.memoryState.unitValue.?;

    try machine.memoryState.pushOwnedStringValue(try v.toString(machine.memoryState.allocator));

    return;
}

test "str" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("str(1)", "\"1\"");
}
