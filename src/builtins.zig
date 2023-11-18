const std = @import("std");

const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const M = @import("./machine.zig");
const Machine = M.Machine;
const MS = @import("./memory_state.zig");
const Main = @import("./main.zig");
const V = @import("./value.zig");

fn reportExpectedTypeError(machine: *Machine, position: Errors.Position, expected: []const V.ValueKind, v: V.ValueKind) !void {
    machine.replaceErr(try Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), position, expected, v));
    return Errors.err.InterpreterError;
}

pub fn close(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    const handle = machine.memoryState.getFromScope("handle") orelse machine.memoryState.unitValue;

    if (handle.?.v == V.ValueKind.FileKind) {
        handle.?.v.FileKind.close();
    } else if (handle.?.v == V.ValueKind.StreamKind) {
        handle.?.v.StreamKind.close();
    } else {
        const position = if (argsAST.len > 0) argsAST[0].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.FileKind}, handle.?.v);
    }
    try machine.memoryState.pushUnitValue();
}

pub fn cwd(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    const c = std.os.getcwd(&buf) catch {
        try machine.memoryState.pushStringValue("./");
        return;
    };

    try machine.memoryState.pushStringValue(c);
}

pub fn eval(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    const code = machine.memoryState.getFromScope("code") orelse machine.memoryState.unitValue;

    if (code.?.v != V.ValueKind.StringKind) {
        const position = if (argsAST.len > 0) argsAST[0].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.StringKind}, code.?.v);
    }

    const stackSize = machine.memoryState.stack.items.len;

    machine.execute("eval", code.?.v.StringKind) catch |e| {
        while (machine.memoryState.stack.items.len > stackSize) {
            _ = machine.memoryState.pop();
        }

        try machine.memoryState.pushEmptyMapValue();
        const record = machine.memoryState.peek(0);

        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "kind", try machine.memoryState.newStringValue("EvalError"));
        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "content", code.?);

        var err = machine.grabErr();

        if (err == null) {
            std.debug.print("Error: {}\n", .{e});
        } else {
            var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
            defer buffer.deinit();

            err.?.append(&buffer) catch {};

            try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "message", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try buffer.toOwnedSlice() }));

            err.?.deinit();
        }
    };
}

test "eval" {
    try Main.expectExprEqual("eval(\"\")", "()");

    try Main.expectExprEqual("eval(\"1\")", "1");
    try Main.expectExprEqual("eval(\"let x = 10; x + 1\")", "11");
    try Main.expectExprEqual("eval(\"let add(a, b) a + b; add\")(1, 2)", "3");
}

pub fn exit(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    const v = machine.memoryState.getFromScope("v") orelse machine.memoryState.unitValue;

    if (v.?.v == V.ValueKind.IntKind) {
        std.os.exit(@intCast(v.?.v.IntKind));
    } else {
        std.os.exit(0);
    }
    return;
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
    defer machine.memoryState.restoreScope();

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
        const __file = machine.memoryState.getFromScope("__FILE");
        if (__file != null) {
            try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "__FILE", __file.?);
        }

        var e = machine.grabErr();
        if (e == null) {
            std.debug.print("Error: {}\n", .{err});
        } else {
            e.?.print() catch {};
            e.?.deinit();
        }

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
        const __file = machine.memoryState.getFromScope("__FILE");
        if (__file != null) {
            try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "__FILE", __file.?);
        }

        var e = machine.grabErr();
        if (e == null) {
            std.debug.print("Error: {}\n", .{err});
        } else {
            e.?.print() catch {};
            e.?.deinit();
        }

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

pub fn int(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = calleeAST;
    const v = machine.memoryState.getFromScope("value") orelse machine.memoryState.unitValue;
    const d = machine.memoryState.getFromScope("default") orelse machine.memoryState.unitValue;
    const b = machine.memoryState.getFromScope("base") orelse machine.memoryState.unitValue;

    if (b != machine.memoryState.unitValue and b.?.v != V.ValueKind.IntKind) {
        try reportExpectedTypeError(machine, argsAST[2].position, &[_]V.ValueKind{V.ValueValue.IntKind}, b.?.v);
    }

    if (v.?.v == V.ValueKind.StringKind) {
        const literalInt = std.fmt.parseInt(i32, v.?.v.StringKind, @intCast(if (b == machine.memoryState.unitValue) 10 else b.?.v.IntKind)) catch {
            try machine.memoryState.push(d.?);
            return;
        };
        try machine.memoryState.pushIntValue(literalInt);
    } else if (v.?.v == V.ValueKind.CharKind) {
        try machine.memoryState.pushIntValue(@intCast(v.?.v.CharKind));
    } else {
        try reportExpectedTypeError(machine, argsAST[0].position, &[_]V.ValueKind{V.ValueValue.StringKind}, v.?.v);
    }
    return;
}

test "int" {
    try Main.expectExprEqual("int(\"\")", "()");
    try Main.expectExprEqual("int(\"123\")", "123");
    try Main.expectExprEqual("int(\"123\", 0, 8)", "83");

    try Main.expectExprEqual("int(\"xxx\", 0, 8)", "0");

    try Main.expectExprEqual("int('1')", "49");
    try Main.expectExprEqual("int('\\n')", "10");
    try Main.expectExprEqual("int('\\\\')", "92");
    try Main.expectExprEqual("int('\\'')", "39");
    try Main.expectExprEqual("int('\\x13')", "13");
}

pub fn listen(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    const host = machine.memoryState.getFromScope("host") orelse machine.memoryState.unitValue;
    const port = machine.memoryState.getFromScope("port") orelse machine.memoryState.unitValue;
    const cb = machine.memoryState.getFromScope("cb") orelse machine.memoryState.unitValue;

    if (host.?.v != V.ValueKind.StringKind) {
        const position = if (argsAST.len > 0) argsAST[0].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.StringKind}, host.?.v);
    }
    if (port.?.v != V.ValueKind.IntKind) {
        const position = if (argsAST.len > 1) argsAST[1].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.IntKind}, port.?.v);
    }
    if (cb.?.v != V.ValueKind.FunctionKind) {
        const position = if (argsAST.len > 2) argsAST[2].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.FunctionKind}, cb.?.v);
    }

    var server = std.net.StreamServer.init(.{});
    server.reuse_address = true;
    defer server.deinit();

    server.listen(std.net.Address.parseIp(host.?.v.StringKind, @intCast(port.?.v.IntKind)) catch |err| return osError(machine, "listen", err)) catch |err| {
        osError(machine, "listen", err) catch {};
        return;
    };

    while (true) {
        var conn = server.accept() catch |err| {
            osError(machine, "accept", err) catch {};
            return;
        };
        const stream = conn.stream;

        machine.memoryState.openScopeFrom(cb.?.v.FunctionKind.scope) catch |err| {
            osError(machine, "openScope", err) catch {};
            return;
        };

        errdefer machine.memoryState.restoreScope();

        if (cb.?.v.FunctionKind.arguments.len > 0) {
            try machine.memoryState.addToScope(cb.?.v.FunctionKind.arguments[0].name, try machine.memoryState.newStreamValue(stream));
        }
        var lp: u8 = 1;
        while (lp < cb.?.v.FunctionKind.arguments.len) {
            machine.memoryState.addToScope(cb.?.v.FunctionKind.arguments[lp].name, machine.memoryState.unitValue.?) catch |err| return osError(machine, "addToScope", err);
            lp += 1;
        }

        if (M.evalExpr(machine, cb.?.v.FunctionKind.body)) {
            std.debug.print("leaving...\n", .{});
            machine.memoryState.restoreScope();
            return;
        } else {
            _ = machine.pop();
            machine.memoryState.restoreScope();
        }
    }
}

pub fn len(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    const v = machine.memoryState.getFromScope("v") orelse machine.memoryState.unitValue;

    switch (v.?.v) {
        V.ValueValue.RecordKind => try machine.memoryState.pushIntValue(@intCast(v.?.v.RecordKind.count())),
        V.ValueValue.SequenceKind => try machine.memoryState.pushIntValue(@intCast(v.?.v.SequenceKind.len())),
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

pub fn ls(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    const v = machine.memoryState.getFromScope("path") orelse machine.memoryState.unitValue;

    const path = if (v.?.v == V.ValueKind.StringKind) v.?.v.StringKind else "./";
    try machine.memoryState.pushEmptySequenceValue();

    var dir = std.fs.cwd().openIterableDir(path, .{}) catch return;
    defer dir.close();

    const result = machine.memoryState.peek(0);

    var it = dir.iterate();
    while (it.next() catch return) |entry| {
        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) {
            continue;
        }

        const record = try machine.memoryState.newMapValue();
        try result.v.SequenceKind.append(record);

        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "name", try machine.memoryState.newStringValue(entry.name));

        const kind = switch (entry.kind) {
            std.fs.IterableDir.Entry.Kind.block_device => "block_device",
            std.fs.IterableDir.Entry.Kind.character_device => "character_device",
            std.fs.IterableDir.Entry.Kind.directory => "directory",
            std.fs.IterableDir.Entry.Kind.door => "door",
            std.fs.IterableDir.Entry.Kind.event_port => "event_port",
            std.fs.IterableDir.Entry.Kind.file => "file",
            std.fs.IterableDir.Entry.Kind.named_pipe => "named_pipe",
            std.fs.IterableDir.Entry.Kind.sym_link => "sym_link",
            std.fs.IterableDir.Entry.Kind.unix_domain_socket => "unix_domain_socket",
            std.fs.IterableDir.Entry.Kind.unknown => "unknown",
            std.fs.IterableDir.Entry.Kind.whiteout => "whiteout",
        };
        try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "kind", try machine.memoryState.newStringValue(kind));
    }
}

pub fn milliTimestamp(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    try machine.memoryState.pushIntValue(@intCast(std.time.milliTimestamp()));
}

fn osError(machine: *Machine, operation: []const u8, err: anyerror) !void {
    try machine.memoryState.pushEmptyMapValue();

    const record = machine.memoryState.peek(0);
    try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "error", try machine.memoryState.newStringValue("SystemError"));
    try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "operation", try machine.memoryState.newStringValue(operation));

    var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{err});

    try V.recordSet(machine.memoryState.allocator, &record.v.RecordKind, "kind", try machine.memoryState.newValue(V.ValueValue{ .StringKind = try buffer.toOwnedSlice() }));
}

fn booleanOption(options: *V.Value, name: []const u8, default: bool) bool {
    const option = V.recordGet(&options.v.RecordKind, name);

    if (option == null or option.?.v != V.ValueKind.BoolKind) {
        return default;
    }

    return option.?.v.BoolKind;
}

pub fn open(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    const path = machine.memoryState.getFromScope("path") orelse machine.memoryState.unitValue;
    const options = machine.memoryState.getFromScope("options") orelse machine.memoryState.unitValue;

    if (path.?.v != V.ValueKind.StringKind) {
        const position = if (argsAST.len > 0) argsAST[0].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.StringKind}, path.?.v);
    }
    if (options.?.v != V.ValueKind.RecordKind and options.?.v != V.ValueKind.VoidKind) {
        const position = if (argsAST.len > 1) argsAST[1].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.RecordKind}, options.?.v);
    }

    if (options.?.v == V.ValueKind.VoidKind) {
        try machine.memoryState.push(try machine.memoryState.newFileValue(std.fs.cwd().openFile(path.?.v.StringKind, .{}) catch |err| return osError(machine, "open", err)));
        return;
    }

    const readF = booleanOption(options.?, "read", false);
    const writeF = booleanOption(options.?, "write", false);
    const appendF = booleanOption(options.?, "append", false);
    const truncateF = booleanOption(options.?, "truncate", false);
    const createF = booleanOption(options.?, "create", false);

    if (createF) {
        try machine.memoryState.push(try machine.memoryState.newFileValue(std.fs.cwd().createFile(path.?.v.StringKind, .{ .read = readF, .truncate = truncateF, .exclusive = true }) catch |err| return osError(machine, "open", err)));
    } else {
        const mode = if (readF and writeF) std.fs.File.OpenMode.read_write else if (readF) std.fs.File.OpenMode.read_only else std.fs.File.OpenMode.write_only;
        var file = std.fs.cwd().openFile(path.?.v.StringKind, .{ .mode = mode }) catch |err| return osError(machine, "open", err);

        try machine.memoryState.push(try machine.memoryState.newFileValue(file));

        if (appendF) {
            file.seekFromEnd(0) catch |err| return osError(machine, "open", err);
        }
    }
}

fn printValue(stdout: std.fs.File.Writer, v: *const V.Value) !void {
    switch (v.v) {
        .BoolKind => try stdout.print("{s}", .{if (v.v.BoolKind) "true" else "false"}),
        .BuiltinKind => {
            try stdout.print("fn(", .{});
            for (v.v.BuiltinKind.arguments, 0..) |argument, i| {
                if (i != 0) {
                    try stdout.print(", ", .{});
                }

                try stdout.print("{s}", .{argument.name});
                if (argument.default != null) {
                    try stdout.print(" = ", .{});
                    try printValue(stdout, argument.default.?);
                }
            }
            if (v.v.BuiltinKind.restOfArguments != null) {
                if (v.v.BuiltinKind.arguments.len > 0) {
                    try stdout.print(", ", .{});
                }

                try stdout.print("...{s}", .{v.v.BuiltinKind.restOfArguments.?});
            }
            try stdout.print(")", .{});
        },
        .CharKind => try stdout.print("{c}", .{v.v.CharKind}),
        .FileKind => try stdout.print("file: {d}", .{v.v.FileKind.file.handle}),
        .FloatKind => try stdout.print("{d}", .{v.v.FloatKind}),
        .FunctionKind => {
            try stdout.print("fn(", .{});
            for (v.v.FunctionKind.arguments, 0..) |argument, i| {
                if (i != 0) {
                    try stdout.print(", ", .{});
                }

                try stdout.print("{s}", .{argument.name});
                if (argument.default != null) {
                    try stdout.print(" = ", .{});
                    try printValue(stdout, argument.default.?);
                }
            }
            if (v.v.FunctionKind.restOfArguments != null) {
                if (v.v.BuiltinKind.arguments.len > 0) {
                    try stdout.print(", ", .{});
                }

                try stdout.print("...{s}", .{v.v.BuiltinKind.restOfArguments.?});
            }
            try stdout.print(")", .{});
        },
        .IntKind => try stdout.print("{d}", .{v.v.IntKind}),
        .RecordKind => {
            var first = true;

            try stdout.print("{s}", .{"{"});
            var iterator = v.v.RecordKind.iterator();
            while (iterator.next()) |entry| {
                if (first) {
                    first = false;
                } else {
                    try stdout.print(", ", .{});
                }

                try stdout.print("{s}: ", .{entry.key_ptr.*});
                try printValue(stdout, entry.value_ptr.*);
            }
            try stdout.print("{s}", .{"}"});
        },
        .ScopeKind => {
            var first = true;
            var runner: ?*const V.Value = v;

            try stdout.print("<", .{});
            while (true) {
                if (first) {
                    first = false;
                } else {
                    try stdout.print(" ", .{});
                }

                try stdout.print("{s}", .{"{"});
                var innerFirst = true;
                var iterator = runner.?.v.ScopeKind.values.iterator();
                while (iterator.next()) |entry| {
                    if (innerFirst) {
                        innerFirst = false;
                    } else {
                        try stdout.print(", ", .{});
                    }
                    try stdout.print("{s}: ", .{entry.key_ptr.*});
                    try printValue(stdout, entry.value_ptr.*);
                }
                try stdout.print("{s}", .{"}"});

                if (runner.?.v.ScopeKind.parent == null) {
                    break;
                }

                runner = runner.?.v.ScopeKind.parent;
            }
            try stdout.print(">", .{});
        },
        .SequenceKind => {
            try stdout.print("[", .{});
            for (v.v.SequenceKind.items(), 0..) |item, i| {
                if (i != 0) {
                    try stdout.print(", ", .{});
                }

                try printValue(stdout, item);
            }
            try stdout.print("]", .{});
        },
        .StreamKind => try stdout.print("stream: {d}", .{v.v.StreamKind.stream.handle}),
        .StringKind => try stdout.print("{s}", .{v.v.StringKind}),
        .VoidKind => try stdout.print("()", .{}),
    }
}

fn printSequence(stdout: std.fs.File.Writer, vs: *V.Value) !void {
    switch (vs.v) {
        V.ValueKind.SequenceKind => {
            for (vs.v.SequenceKind.items()) |v| {
                try printValue(stdout, v);
            }
        },
        else => try printValue(stdout, vs),
    }
}

pub fn print(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    const stdout = std.io.getStdOut().writer();
    const vs = machine.memoryState.getFromScope("vs") orelse machine.memoryState.unitValue;

    printSequence(stdout, vs.?) catch {};

    try machine.memoryState.pushUnitValue();
}

pub fn println(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    const stdout = std.io.getStdOut().writer();
    const vs = machine.memoryState.getFromScope("vs") orelse machine.memoryState.unitValue;

    printSequence(stdout, vs.?) catch {};
    stdout.print("\n", .{}) catch {};

    try machine.memoryState.pushUnitValue();
}

pub fn read(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    const handle = machine.memoryState.getFromScope("handle") orelse machine.memoryState.unitValue;
    const bytes = machine.memoryState.getFromScope("bytes") orelse machine.memoryState.unitValue;

    if (handle.?.v != V.ValueKind.FileKind and handle.?.v != V.ValueKind.StreamKind) {
        const position = if (argsAST.len > 0) argsAST[0].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{ V.ValueValue.FileKind, V.ValueValue.StreamKind }, handle.?.v);
    }

    if (bytes.?.v == V.ValueKind.IntKind) {
        const buffer = try machine.memoryState.allocator.alloc(u8, @intCast(bytes.?.v.IntKind));
        defer machine.memoryState.allocator.free(buffer);

        var bytesRead: usize = 0;

        if (handle.?.v == V.ValueKind.FileKind) {
            bytesRead = handle.?.v.FileKind.file.read(buffer) catch |err| return osError(machine, "read", err);
        } else {
            bytesRead = handle.?.v.StreamKind.stream.read(buffer) catch |err| return osError(machine, "read", err);
        }
        // bytesRead = handle.?.v.FileKind.file.read(buffer) catch |err| return osError(machine, "read", err);

        try machine.memoryState.push(try machine.memoryState.newStringValue(buffer[0..bytesRead]));
    } else if (bytes.?.v == V.ValueKind.VoidKind) {
        const buffer = try machine.memoryState.allocator.alloc(u8, 4096);
        defer machine.memoryState.allocator.free(buffer);

        var bytesRead: usize = 0;

        if (handle.?.v == V.ValueKind.FileKind) {
            bytesRead = handle.?.v.FileKind.file.read(buffer) catch |err| return osError(machine, "read", err);
        } else {
            bytesRead = handle.?.v.StreamKind.stream.read(buffer) catch |err| return osError(machine, "read", err);
        }
        // bytesRead= handle.?.v.FileKind.file.read(buffer) catch |err| return osError(machine, "read", err);

        try machine.memoryState.push(try machine.memoryState.newStringValue(buffer[0..bytesRead]));
    } else {
        const position = if (argsAST.len > 1) argsAST[1].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.IntKind}, handle.?.v);
    }
}

pub fn socket(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    const name = machine.memoryState.getFromScope("name") orelse machine.memoryState.unitValue;
    const port = machine.memoryState.getFromScope("port") orelse machine.memoryState.unitValue;

    if (name.?.v != V.ValueKind.StringKind) {
        const position = if (argsAST.len > 0) argsAST[0].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.StringKind}, name.?.v);
    }
    if (port.?.v != V.ValueKind.IntKind) {
        const position = if (argsAST.len > 1) argsAST[1].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.IntKind}, port.?.v);
    }

    const stream = std.net.tcpConnectToHost(machine.memoryState.allocator, name.?.v.StringKind, @intCast(port.?.v.IntKind)) catch |err| return osError(machine, "socket", err);
    try machine.memoryState.push(try machine.memoryState.newStreamValue(stream));
}

pub fn str(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = calleeAST;
    _ = argsAST;
    const v = machine.memoryState.getFromScope("value") orelse machine.memoryState.unitValue;

    try machine.memoryState.pushOwnedStringValue(try v.?.toString(machine.memoryState.allocator));

    return;
}

test "str" {
    try Main.expectExprEqual("str(1)", "\"1\"");
}

pub fn typeof(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = argsAST;
    _ = calleeAST;

    const v = machine.memoryState.getFromScope("v") orelse machine.memoryState.unitValue;

    const typeName = switch (v.?.v) {
        V.ValueKind.BoolKind => "Bool",
        V.ValueKind.BuiltinKind => "Function",
        V.ValueKind.CharKind => "Char",
        V.ValueKind.FileKind => "File",
        V.ValueKind.FunctionKind => "Function",
        V.ValueKind.FloatKind => "Float",
        V.ValueKind.IntKind => "Int",
        V.ValueKind.SequenceKind => "Sequence",
        V.ValueKind.StreamKind => "Stream",
        V.ValueKind.StringKind => "String",
        V.ValueKind.RecordKind => "Record",
        V.ValueKind.ScopeKind => "Scope",
        V.ValueKind.VoidKind => "Unit",
    };
    try machine.memoryState.pushStringValue(typeName);
}

test "typeof" {
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

pub fn write(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    const handle = machine.memoryState.getFromScope("handle") orelse machine.memoryState.unitValue;
    const bytes = machine.memoryState.getFromScope("bytes") orelse machine.memoryState.unitValue;

    if (handle.?.v != V.ValueKind.FileKind and handle.?.v != V.ValueKind.StreamKind) {
        const position = if (argsAST.len > 0) argsAST[0].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{ V.ValueValue.FileKind, V.ValueValue.StreamKind }, handle.?.v);
    }

    if (bytes.?.v != V.ValueKind.StringKind) {
        const position = if (argsAST.len > 1) argsAST[1].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.StringKind}, bytes.?.v);
    }
    var bytesWritten: usize = 0;

    if (handle.?.v == V.ValueKind.FileKind) {
        bytesWritten = handle.?.v.FileKind.file.write(bytes.?.v.StringKind) catch |err| return osError(machine, "write", err);
    } else {
        bytesWritten = handle.?.v.StreamKind.stream.write(bytes.?.v.StringKind) catch |err| return osError(machine, "read", err);
    }
    try machine.memoryState.pushIntValue(@intCast(bytesWritten));
}
