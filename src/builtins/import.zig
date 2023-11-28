const std = @import("std");
const Helper = @import("./helper.zig");

const loadBinary = @import("../builtins.zig").loadBinary;

fn ffn(allocator: std.mem.Allocator, fromSourceName: ?[]const u8, fileName: []const u8) ![]u8 {
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

fn fullFileName(machine: *Helper.Machine, fileName: []const u8) ![]u8 {
    const fromSourceName = machine.memoryState.getFromScope("__FILE");
    return try ffn(machine.memoryState.allocator, if (fromSourceName == null) null else fromSourceName.?.v.StringKind, fileName);
}

test "fullFileName" {}

fn processError(machine: *Helper.Machine, err: anyerror, nature: []const u8, name: []const u8) !void {
    try machine.memoryState.pushEmptyMapValue();

    const record = machine.memoryState.peek(0);
    try record.v.RecordKind.set(machine.memoryState.allocator, "error", try machine.memoryState.newStringValue(nature));

    var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{err});

    try record.v.RecordKind.set(machine.memoryState.allocator, "kind", try machine.memoryState.newOwnedStringValue(&buffer));
    try record.v.RecordKind.set(machine.memoryState.allocator, "name", try machine.memoryState.newStringValue(name));
}

pub fn importFile(machine: *Helper.Machine, fileName: []const u8) !void {
    const name = fullFileName(machine, fileName) catch |err| return processError(machine, err, "FileError", fileName);
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

    const content = loadBinary(machine.memoryState.allocator, name) catch |err| return processError(machine, err, "FileError", fileName);
    defer machine.memoryState.allocator.free(content);

    try machine.memoryState.openScopeFrom(machine.memoryState.topScope());
    defer machine.memoryState.restoreScope();

    try machine.memoryState.addToScope("__FILE", try machine.memoryState.newStringValue(name));

    const ast = machine.parse(fileName, content) catch |err| return processError(machine, err, "ExecuteError", fileName);
    errdefer ast.destroy(machine.memoryState.allocator);

    try machine.memoryState.imports.addImport(name, null, ast);

    machine.eval(ast) catch |err| return processError(machine, err, "ExecuteError", fileName);
    _ = machine.memoryState.pop();

    try machine.memoryState.pushEmptyMapValue();

    const result = machine.memoryState.peek(0);

    var iterator = machine.memoryState.scope().?.v.ScopeKind.values.iterator();
    while (iterator.next()) |entry| {
        const entryName = entry.key_ptr.*;

        if (entryName.len > 0 and entryName[0] == '_') {
            continue;
        }
        try result.v.RecordKind.set(machine.memoryState.allocator, entryName, entry.value_ptr.*);
    }

    try machine.memoryState.imports.addImport(name, result, ast);
}

fn indexOfLastLinear(comptime T: type, haystack: []const T, needle: T) ?usize {
    var i: usize = haystack.len - 1;
    while (true) : (i -= 1) {
        if (haystack[i] == needle) return i;
        if (i == 0) return null;
    }
}

fn fexists(name: []const u8) bool {
    std.fs.Dir.access(std.fs.cwd(), name, .{}) catch return false;
    return true;
}

pub fn import(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    const v = (try Helper.getArgument(machine, calleeAST, argsAST, "file", 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind})).v.StringKind;

    const indexOfDot = indexOfLastLinear(u8, v, '.');
    const indexOfSlash = indexOfLastLinear(u8, v, '/');
    if (indexOfDot != null or indexOfSlash != null) {
        try importFile(machine, v);
        return;
    }

    const exePath = std.fs.selfExePathAlloc(machine.memoryState.allocator) catch return;
    defer machine.memoryState.allocator.free(exePath);

    const exeDir = std.fs.path.dirname(exePath).?;

    var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{s}/../lib/{s}.rebo", .{ exeDir, v });
    if (fexists(buffer.items)) {
        try importFile(machine, buffer.items);
    } else {
        buffer.clearAndFree();
        try std.fmt.format(buffer.writer(), "{s}/../../lib/{s}.rebo", .{ exeDir, v });
        try importFile(machine, buffer.items);
    }
}

test "import" {
    const Main = @import("./../main.zig");

    try Main.expectExprEqual("import(\"./test/simple.rebo\").x", "10");
}
