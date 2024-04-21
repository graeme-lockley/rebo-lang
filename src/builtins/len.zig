const Helper = @import("./helper.zig");

pub fn len(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{ Helper.ValueValue.CodeKind, Helper.ValueValue.RecordKind, Helper.ValueValue.ScopeKind, Helper.ValueValue.SequenceKind, Helper.ValueValue.StringKind, Helper.ValueValue.UnitKind });

    switch (v.v) {
        Helper.ValueValue.CodeKind => try machine.pushIntValue(@intCast(v.v.CodeKind.code.len)),
        Helper.ValueValue.RecordKind => try machine.pushIntValue(@intCast(v.v.RecordKind.count())),
        Helper.ValueValue.ScopeKind => try machine.pushIntValue(@intCast(v.v.ScopeKind.count())),
        Helper.ValueValue.SequenceKind => try machine.pushIntValue(@intCast(v.v.SequenceKind.len())),
        Helper.ValueValue.StringKind => try machine.pushIntValue(@intCast(v.v.StringKind.len())),
        Helper.ValueValue.UnitKind => try machine.pushIntValue(0),
        else => unreachable,
    }
}

test "len" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("rebo.lang.len({})", "0");
    try Main.expectExprEqual("rebo.lang.len({a: 1})", "1");
    try Main.expectExprEqual("rebo.lang.len({a: 1, b: 2, c: 3})", "3");

    try Main.expectExprEqual("rebo.lang.len(rebo.lang.scope())", "0");
    try Main.expectExprEqual("let x = 10 ; rebo.lang.len(rebo.lang.scope())", "1");

    try Main.expectExprEqual("rebo.lang.len([])", "0");
    try Main.expectExprEqual("rebo.lang.len([1])", "1");
    try Main.expectExprEqual("rebo.lang.len([1, 2, 3])", "3");

    try Main.expectExprEqual("rebo.lang.len(\"\")", "0");
    try Main.expectExprEqual("rebo.lang.len(\"x\")", "1");
    try Main.expectExprEqual("rebo.lang.len(\"hello\")", "5");
}
