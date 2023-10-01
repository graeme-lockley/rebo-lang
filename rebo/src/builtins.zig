const std = @import("std");

const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const Machine = @import("./machine.zig").Machine;
const MS = @import("./memory_state.zig");
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

pub fn gc(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    const result = MS.force_gc(&machine.memoryState);

    try machine.memoryState.pushEmptyMapValue();

    const record = machine.memoryState.peek(0);
    try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "capacity", try machine.memoryState.newValue(V.ValueValue{ .IntKind = result.capacity }));
    try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "before", try machine.memoryState.newValue(V.ValueValue{ .IntKind = result.oldSize }));
    try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "after", try machine.memoryState.newValue(V.ValueValue{ .IntKind = result.newSize }));
    try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "duration", try machine.memoryState.newValue(V.ValueValue{ .IntKind = @intCast(result.duration) }));
}

fn ffn(allocator: std.mem.Allocator, fromSourceName: ?[]const u8, fileName: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(fileName)) {
        return try allocator.dupe(u8, fileName);
    }

    if (fromSourceName == null) {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        return try std.fs.cwd().realpathAlloc(allocator, fileName);
    }

    const dirname = std.fs.path.dirname(fromSourceName.?).?;
    const dir = try std.fs.openDirAbsolute(dirname, std.fs.Dir.OpenDirOptions{ .access_sub_paths = false, .no_follow = false });

    return try dir.realpathAlloc(allocator, fileName);
}

test "ffn" {
    // This test is commented out because it requires tinkering to work and therefore serves as an exploratory test.

    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    // try std.testing.expectEqualSlices(u8, "/hello.txt", try ffn(allocator, null, "/hello.txt"));
    // try std.testing.expectEqualSlices(u8, "test/simple.rebo", try ffn(allocator, null, "test/simple.rebo"));
    // try std.testing.expectEqualSlices(u8, "test/simple.rebo", try ffn(allocator, "/Users/graemelockley/Projects/rebo-lang/rebo/test/simple.rebo", "../src/ast.zig"));
}

fn fullFileName(machine: *Machine, fileName: []const u8) ![]u8 {
    const fromSourceName = machine.memoryState.getFromScope("__FILE");
    return try ffn(machine.memoryState.allocator, if (fromSourceName == null) null else fromSourceName.?.v.StringKind, fileName);
}

test "fullFileName" {}

pub fn importFile(machine: *Machine, fileName: []const u8) !void {
    const name = fullFileName(machine, fileName) catch |err| {
        try machine.memoryState.pushEmptyMapValue();

        const record = machine.memoryState.peek(0);
        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "error", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try machine.memoryState.allocator.dupe(u8, "FileError") }));

        var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
        defer buffer.deinit();

        try std.fmt.format(buffer.writer(), "{}", .{err});

        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "kind", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try buffer.toOwnedSlice() }));
        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "name", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try machine.memoryState.allocator.dupe(u8, fileName) }));

        return;
    };
    defer machine.memoryState.allocator.free(name);

    const loadedImport = machine.memoryState.imports.find(name);
    if (loadedImport != null) {
        if (loadedImport.?.items == null) {
            std.log.err("Fatal Error: Cyclic Import: {s}", .{name});
            std.os.exit(1);
            return;
        }

        try machine.memoryState.push(loadedImport.?.items.?);
        return;
    }

    std.log.info("loading import {s}...", .{name});

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

    try machine.memoryState.imports.addImport(name, null, ast);

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
        const entryName = entry.key_ptr.*;

        if (entryName.len > 0 and entryName[0] == '_') {
            continue;
        }
        try V.recordSet(machine.memoryState.allocator, &result.v.RecordKind, entryName, entry.value_ptr.*);
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

pub fn imports(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    try machine.memoryState.pushEmptyMapValue();

    const result = machine.memoryState.peek(0);

    var iterator = machine.memoryState.imports.items.iterator();
    while (iterator.next()) |entry| {
        const items: *V.Value = if (entry.value_ptr.*.items == null) machine.memoryState.unitValue.? else entry.value_ptr.*.items.?;

        // unitValues are not stored in a record set so the repl lines will not be included in the result.
        // if you would like to see them then comment out the statement below.
        // const items: *V.Value = if (entry.value_ptr.*.items == null) try machine.memoryState.newValue(V.ValueValue{ .RecordKind = std.StringHashMap(*V.Value).init(machine.memoryState.allocator) }) else entry.value_ptr.*.items.?;

        try V.recordSet(machine.memoryState.allocator, &result.v.RecordKind, entry.key_ptr.*, items);
    }
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
