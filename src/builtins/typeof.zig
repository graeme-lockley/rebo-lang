const Helper = @import("./helper.zig");

pub fn typeof(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression, args: []*Helper.Value) !void {
    _ = argsAST;
    _ = calleeAST;

    const v = if (args.len > 0) args[0] else machine.memoryState.unitValue.?;

    const typeName = switch (v.v) {
        Helper.ValueKind.BoolKind => "Bool",
        Helper.ValueKind.BuiltinKind => "Function",
        Helper.ValueKind.CharKind => "Char",
        Helper.ValueKind.FileKind => "File",
        Helper.ValueKind.FunctionKind => "Function",
        Helper.ValueKind.FloatKind => "Float",
        Helper.ValueKind.IntKind => "Int",
        Helper.ValueKind.SequenceKind => "Sequence",
        Helper.ValueKind.StreamKind => "Stream",
        Helper.ValueKind.StringKind => "String",
        Helper.ValueKind.RecordKind => "Record",
        Helper.ValueKind.ScopeKind => "Scope",
        Helper.ValueKind.UnitKind => "Unit",
    };
    try machine.memoryState.pushStringValue(typeName);
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
