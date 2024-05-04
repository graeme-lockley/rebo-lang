const std = @import("std");
const Helper = @import("./helper.zig");

pub fn char(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueKind.IntKind});

    const value = v.v.IntKind;

    if (value < 0 or value > 255) {
        try machine.pushUnitValue();
    } else {
        try machine.pushCharValue(@intCast(value));
    }
}

test "char" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("rebo.lang.char(32)", "' '");
    try Main.expectExprEqual("rebo.lang.char(300)", "()");
}
