const Helper = @import("./helper.zig");

pub fn typeof(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const v = if (numberOfArgs > 0) machine.memoryState.peek(numberOfArgs - 1) else machine.memoryState.unitValue.?;

    const tt: Helper.ValueKind = v.v;

    try machine.memoryState.pushStringValue(tt.toString());
}

test "typeof" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("rebo.lang.typeof(true)", "\"Bool\"");
    try Main.expectExprEqual("rebo.lang.typeof(rebo.lang.len)", "\"Function\"");
    try Main.expectExprEqual("rebo.lang.typeof('x')", "\"Char\"");
    try Main.expectExprEqual("rebo.lang.typeof(fn() = ())", "\"Function\"");
    try Main.expectExprEqual("rebo.lang.typeof(1.0)", "\"Float\"");
    try Main.expectExprEqual("rebo.lang.typeof(1)", "\"Int\"");
    try Main.expectExprEqual("rebo.lang.typeof([])", "\"Sequence\"");
    try Main.expectExprEqual("rebo.lang.typeof({})", "\"Record\"");
    try Main.expectExprEqual("rebo.lang.typeof(())", "\"Unit\"");
    try Main.expectExprEqual("rebo.lang.typeof()", "\"Unit\"");
}
