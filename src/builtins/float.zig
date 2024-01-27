const std = @import("std");
const Helper = @import("./helper.zig");

pub fn float(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueKind.StringKind});
    const d = if (numberOfArgs > 1) machine.runtime.peek(numberOfArgs - 2) else machine.runtime.unitValue.?;

    const literalFloat = std.fmt.parseFloat(Helper.FloatType, v.v.StringKind.slice()) catch {
        try machine.runtime.push(d);
        return;
    };
    try machine.runtime.pushFloatValue(literalFloat);
}

test "float" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("rebo.lang.float(\"\")", "()");
    try Main.expectExprEqual("rebo.lang.float(\"1.23\")", "1.23");
    try Main.expectExprEqual("rebo.lang.float(\"1.23\", 0)", "1.23");

    try Main.expectExprEqual("rebo.lang.float(\"xxx\", 0)", "0");
}
