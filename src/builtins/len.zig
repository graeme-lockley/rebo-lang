const Helper = @import("./helper.zig");

pub fn len(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{ Helper.ValueValue.RecordKind, Helper.ValueValue.SequenceKind, Helper.ValueValue.StringKind });

    switch (v.v) {
        Helper.ValueValue.RecordKind => try machine.memoryState.pushIntValue(@intCast(v.v.RecordKind.count())),
        Helper.ValueValue.SequenceKind => try machine.memoryState.pushIntValue(@intCast(v.v.SequenceKind.len())),
        Helper.ValueValue.StringKind => try machine.memoryState.pushIntValue(@intCast(v.v.StringKind.len())),
        else => unreachable,
    }
}

test "len" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("len({})", "0");
    try Main.expectExprEqual("len({a: 1})", "1");
    try Main.expectExprEqual("len({a: 1, b: 2, c: 3})", "3");

    try Main.expectExprEqual("len([])", "0");
    try Main.expectExprEqual("len([1])", "1");
    try Main.expectExprEqual("len([1, 2, 3])", "3");

    try Main.expectExprEqual("len(\"\")", "0");
    try Main.expectExprEqual("len(\"x\")", "1");
    try Main.expectExprEqual("len(\"hello\")", "5");
}
