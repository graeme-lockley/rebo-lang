const Helper = @import("./helper.zig");

pub fn typeof(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const v = if (numberOfArgs > 0) machine.memoryState.peek(numberOfArgs - 1) else machine.memoryState.unitValue.?;

    const tt: Helper.ValueKind = v.v;

    try machine.memoryState.pushStringValue(tt.toString());
}

test "typeof" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("typeof(true)", "\"Bool\"");
    try Main.expectExprEqual("typeof(len)", "\"Function\"");
    try Main.expectExprEqual("typeof('x')", "\"Char\"");
    try Main.expectExprEqual("typeof(fn() = ())", "\"Function\"");
    try Main.expectExprEqual("typeof(1.0)", "\"Float\"");
    try Main.expectExprEqual("typeof(1)", "\"Int\"");
    try Main.expectExprEqual("typeof([])", "\"Sequence\"");
    try Main.expectExprEqual("typeof({})", "\"Record\"");
    try Main.expectExprEqual("typeof(())", "\"Unit\"");
    try Main.expectExprEqual("typeof()", "\"Unit\"");
}
