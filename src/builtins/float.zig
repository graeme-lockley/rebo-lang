const std = @import("std");
const Helper = @import("./helper.zig");

pub fn float(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueKind.StringKind});
    const d = if (numberOfArgs > 1) machine.memoryState.peek(numberOfArgs - 2) else machine.memoryState.unitValue.?;

    switch (v.v) {
        Helper.ValueValue.CharKind => try machine.memoryState.pushIntValue(@intCast(v.v.CharKind)),
        Helper.ValueKind.StringKind => {
            const literalFloat = std.fmt.parseFloat(Helper.FloatType, v.v.StringKind.slice()) catch {
                try machine.memoryState.push(d);
                return;
            };
            try machine.memoryState.pushFloatValue(literalFloat);
        },
        else => unreachable,
    }
}

test "float" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("float(\"\")", "()");
    try Main.expectExprEqual("float(\"1.23\")", "1.23");
    try Main.expectExprEqual("float(\"1.23\", 0)", "1.23");

    try Main.expectExprEqual("float(\"xxx\", 0)", "0");
}
