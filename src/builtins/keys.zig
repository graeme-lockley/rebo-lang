const std = @import("std");
const Helper = @import("./helper.zig");

pub fn keys(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{ Helper.ValueValue.RecordKind, Helper.ValueValue.ScopeKind });

    try machine.memoryState.pushEmptySequenceValue();

    const seq = machine.memoryState.peek(0);

    switch (v.v) {
        Helper.ValueValue.RecordKind => {
            var iterator = v.v.RecordKind.keyIterator();
            while (iterator.next()) |item| {
                try seq.v.SequenceKind.appendItem(try machine.memoryState.newStringPoolValue(item.*));
            }
        },
        Helper.ValueValue.ScopeKind => {
            var iterator = v.v.ScopeKind.keyIterator();
            while (iterator.next()) |item| {
                try seq.v.SequenceKind.appendItem(try machine.memoryState.newStringPoolValue(item.*));
            }
        },
        else => unreachable,
    }
}

test "int" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("keys({})", "[]");
    try Main.expectExprEqual("keys({a: 1})", "[\"a\"]");
    try Main.expectExprEqual("len(keys({a: 1, b: 2}))", "2");

    try Main.expectExprEqual("keys(scope())", "[]");
    try Main.expectExprEqual("let x = 10 ; keys(scope())", "[\"x\"]");
}
