const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const Machine = @import("./machine.zig").Machine;
const Main = @import("./main.zig");
const V = @import("./value.zig");

fn reportExpectedTypeError(machine: *Machine, position: Errors.Position, expected: []const V.ValueKind, v: V.ValueKind) !void {
    {
        var exp = try machine.memoryState.allocator.alloc(V.ValueKind, expected.len);
        errdefer machine.memoryState.allocator.free(exp);

        for (expected, 0..) |vk, i| {
            exp[i] = vk;
        }

        machine.replaceErr(Errors.expectedTypeError(machine.memoryState.allocator, position, exp, v));
    }
    return Errors.err.InterpreterError;
}

pub fn len(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    const v = machine.memoryState.getFromScope("v") orelse machine.memoryState.unitValue;

    switch (v.?.v) {
        V.ValueValue.RecordKind => try machine.memoryState.pushIntValue(@intCast(v.?.v.RecordKind.count())),
        V.ValueValue.SequenceKind => try machine.memoryState.pushIntValue(@intCast(v.?.v.SequenceKind.len)),
        V.ValueValue.StringKind => try machine.memoryState.pushIntValue(@intCast(v.?.v.StringKind.len)),
        else => try reportExpectedTypeError(machine, if (argsAST.len > 0) argsAST[0].position else calleeAST.position, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.SequenceKind, V.ValueValue.StringKind }, v.?.v),
    }
}

test "len" {
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
