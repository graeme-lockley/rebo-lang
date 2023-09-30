const std = @import("std");

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

fn ffn(allocator: std.mem.Allocator, fromSourceName: ?[]const u8, fileName: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(fileName)) {
        return try allocator.dupe(u8, fileName);
    }

    if (fromSourceName == null) {
        return std.fs.path.join(allocator, &[_][]const u8{ ".", fileName });
    }

    const dirname = std.fs.path.dirname(fromSourceName.?).?;
    return std.fs.path.join(allocator, &[_][]const u8{ dirname, fileName });
}

test "ffn" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const expectEqual = std.testing.expectEqual;
    _ = expectEqual;

    try std.testing.expectEqualSlices(u8, "/hello.txt", try ffn(allocator, null, "/hello.txt"));
}

fn fullFileName(machine: *Machine, fileName: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(fileName)) {
        return try machine.memoryState.allocator.dupe(u8, fileName);
    }

    const fromSourceName = machine.memoryState.getFromScope("__FILE");

    if (fromSourceName == null) {
        return std.fs.path.join(machine.memoryState.allocator, &[_][]const u8{ ".", fileName });
    }

    const dirname = std.fs.path.dirname(fromSourceName.?.v.StringKind).?;
    return std.fs.path.join(machine.memoryState.allocator, &[_][]const u8{ dirname, fileName });
}

test "fullFileName" {}

fn importFile(machine: *Machine, fileName: []const u8) !void {
    const name = try fullFileName(machine, fileName);
    defer machine.memoryState.allocator.free(name);

    const content = loadBinary(machine.memoryState.allocator, name) catch |err| {
        try machine.memoryState.pushEmptyMapValue();

        const record = machine.memoryState.peek(0);
        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "error", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try machine.memoryState.allocator.dupe(u8, "FileError") }));

        var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
        defer buffer.deinit();

        try std.fmt.format(buffer.writer(), "{}", .{err});

        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "kind", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try buffer.toOwnedSlice() }));
        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "name", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try machine.memoryState.allocator.dupe(u8, name) }));

        return;
    };
    defer machine.memoryState.allocator.free(content);

    try machine.memoryState.openScopeFrom(machine.memoryState.topScope());
    try machine.memoryState.addToScope("__FILE", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try machine.memoryState.allocator.dupe(u8, name) }));

    const ast = machine.parse(fileName, content) catch |err| {
        try machine.memoryState.pushEmptyMapValue();

        const record = machine.memoryState.peek(0);
        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "error", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try machine.memoryState.allocator.dupe(u8, "ExecuteError") }));

        var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
        defer buffer.deinit();

        try std.fmt.format(buffer.writer(), "{}", .{err});

        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "kind", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try buffer.toOwnedSlice() }));
        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "name", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try machine.memoryState.allocator.dupe(u8, name) }));

        return;
    };
    errdefer AST.destroy(machine.memoryState.allocator, ast);

    machine.eval(ast) catch |err| {
        try machine.memoryState.pushEmptyMapValue();

        const record = machine.memoryState.peek(0);
        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "error", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try machine.memoryState.allocator.dupe(u8, "ExecuteError") }));

        var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
        defer buffer.deinit();

        try std.fmt.format(buffer.writer(), "{}", .{err});

        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "kind", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try buffer.toOwnedSlice() }));
        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "name", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try machine.memoryState.allocator.dupe(u8, name) }));

        return;
    };
    _ = machine.memoryState.pop();

    try machine.memoryState.pushEmptyMapValue();

    const result = machine.memoryState.peek(0);

    var iterator = machine.memoryState.scope().?.v.ScopeKind.values.iterator();
    while (iterator.next()) |entry| {
        try V.recordSet(machine.memoryState.allocator, &result.v.RecordKind, entry.key_ptr.*, entry.value_ptr.*);
    }

    defer machine.memoryState.restoreScope();

    try machine.memoryState.imports.addImport(name, result, ast);
}

pub fn import(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    const v = machine.memoryState.getFromScope("file") orelse machine.memoryState.unitValue;

    switch (v.?.v) {
        V.ValueValue.StringKind => try importFile(machine, v.?.v.StringKind),
        else => try reportExpectedTypeError(machine, if (argsAST.len > 0) argsAST[0].position else calleeAST.position, &[_]V.ValueKind{V.ValueValue.StringKind}, v.?.v),
    }
}

test "import" {
    try Main.expectExprEqual("import(\"./test/simple.rebo\").x", "10");
}

pub fn loadBinary(allocator: std.mem.Allocator, fileName: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    const fileSize = try file.getEndPos();
    const buffer: []u8 = try file.readToEndAlloc(allocator, fileSize);

    return buffer;
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
