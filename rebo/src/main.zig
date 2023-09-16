const std = @import("std");
const Machine = @import("./machine.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const err = gpa.deinit();
        if (err == std.heap.Check.leak) {
            std.log.err("Failed to deinit allocator\n", .{});
            std.process.exit(1);
        }
    }

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 3 and std.mem.eql(u8, args[1], "run")) {
        const buffer: []u8 = try loadBinary(allocator, args[2]);
        defer allocator.free(buffer);

        var machine = Machine.Machine.init(allocator);
        defer machine.deinit();

        execute(&machine, args[2], buffer);
        try printResult(allocator, machine.topOfStack());
    } else if (args.len == 2 and std.mem.eql(u8, args[1], "repl")) {
        var buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(buffer);

        var machine = Machine.Machine.init(allocator);
        defer machine.deinit();

        const stdin = std.io.getStdIn().reader();

        while (true) {
            std.debug.print("> ", .{});

            if (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |line| {
                if (line.len == 0) {
                    break;
                }
                execute(&machine, "console", line);
                try printResult(allocator, machine.topOfStack());
                machine.reset();
            } else {
                break;
            }
        }
    } else {
        std.debug.print("Usage: {s} [repl|run <filename>]\n", .{args[0]});
    }
}

fn printResult(allocator: std.mem.Allocator, v: ?*Machine.Value) !void {
    if (v != null) {
        const result = try v.?.toString(allocator);
        std.debug.print("Result: {s}\n", .{result});
        allocator.free(result);
    }
}

fn errorHandler(err: anyerror, machine: *Machine.Machine) void {
    const e = machine.grabErr();
    if (e == null) {
        std.debug.print("Error: {}\n", .{err});
    } else {
        e.?.print() catch {};
        e.?.deinit();
    }
}

fn execute(machine: *Machine.Machine, name: []const u8, buffer: []const u8) void {
    machine.execute(name, buffer) catch |err| errorHandler(err, machine);
}

fn loadBinary(allocator: std.mem.Allocator, fileName: [:0]const u8) ![]u8 {
    var file = std.fs.cwd().openFile(fileName, .{}) catch {
        std.debug.print("Unable to open file: {s}\n", .{fileName});
        std.os.exit(1);
    };
    defer file.close();

    const fileSize = try file.getEndPos();
    const buffer: []u8 = try file.readToEndAlloc(allocator, fileSize);

    return buffer;
}

fn expectExecEqual(input: []const u8, expected: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var machine = Machine.Machine.init(allocator);
        defer machine.deinit();

        execute(&machine, "console", input);
        const v = machine.topOfStack();

        if (v == null) {
            std.log.err("Expected a value on the stack\n", .{});
            return error.TestingError;
        }

        const result = try v.?.toString(allocator);
        defer allocator.free(result);

        if (!std.mem.eql(u8, result, expected)) {
            std.log.err("Expected: '{s}', got: '{s}'\n", .{ expected, result });
            return error.TestingError;
        }
    }

    const err = gpa.deinit();
    if (err == std.heap.Check.leak) {
        std.log.err("Failed to deinit allocator\n", .{});
        return error.TestingError;
    }
}

fn expectError(input: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var machine = Machine.Machine.init(allocator);
        defer machine.deinit();

        const result = machine.execute("console", input);

        if (result != error.InterpreterError) {
            const v = machine.topOfStack();

            const str = try v.?.toString(allocator);
            defer allocator.free(str);

            std.log.err("Expected error: got: '{s}'\n", .{str});
            return error.TestingError;
        }
    }

    const err = gpa.deinit();
    if (err == std.heap.Check.leak) {
        std.log.err("Failed to deinit allocator\n", .{});
        return error.TestingError;
    }
}

const expectEqual = std.testing.expectEqual;

test "call expression" {
    try expectExecEqual("(fn() = 1)()", "1");
    try expectExecEqual("(fn() = 1)(1, 2, 3)", "1");
    try expectExecEqual("(fn(n) = n + 1)(10, 20, 30)", "11");

    try expectExecEqual("(fn(n = 0, m = 1) = n + m)()", "1");
    try expectExecEqual("(fn(n = 0, m = 1) = n + m)(10)", "11");
    try expectExecEqual("(fn(n = 0, m = 1) = n + m)(10, 20)", "30");
    try expectExecEqual("(fn(n = 0, m = 1) = n + m)(10, 20, 40)", "30");
}

test "literal bool" {
    try expectExecEqual("true", "true");
    try expectExecEqual("false", "false");
}

test "literal function" {
    try expectExecEqual("fn() = 1", "fn()");
    try expectExecEqual("fn(a) = a + 1", "fn(a)");
    try expectExecEqual("fn(a = 1, b = 2, c = 3) = a + b + c", "fn(a = 1, b = 2, c = 3)");

    try expectError("fn(a = 1, b = 2, c = 3) = ");
}

test "literal int" {
    try expectExecEqual("0", "0");
    try expectExecEqual("-0", "0");
    try expectExecEqual("123", "123");
    try expectExecEqual("-123", "-123");
}

test "literal record" {
    try expectExecEqual("{}", "{}");
    try expectExecEqual("{name: 10}", "{name: 10}");

    // the following is a brittle test but it is good enough for now
    try expectExecEqual("{a: 1, b: 2, c: 3}", "{b: 2, a: 1, c: 3}");
    try expectExecEqual("{a: 1, a: 2, a: 3}", "{a: 3}");

    try expectError("{a:1,");
}

test "literal sequence" {
    try expectExecEqual("[]", "[]");
    try expectExecEqual("[1]", "[1]");
    try expectExecEqual("[1, 2, 3]", "[1, 2, 3]");
    try expectExecEqual("[1, [true, false], 3]", "[1, [true, false], 3]");

    try expectError("[1, 2,");
    try expectError("[1, 2, 3");
}

test "literal unit" {
    try expectExecEqual("()", "()");
}

test "additive op" {
    try expectExecEqual("1 + 1", "2");
    try expectExecEqual("1 + 2 + 3 + 4 + 5", "15");

    try expectExecEqual("1 - 1", "0");
    try expectExecEqual("1 - 2 + 3 - 4 + 5", "3");

    try expectError("1 + true");
    try expectError("1 - true");
}

test "multiplicative op" {
    try expectExecEqual("1 * 1", "1");
    try expectExecEqual("1 * 2 * 3 * 4 * 5", "120");

    try expectExecEqual("100 / 2", "50");
    try expectExecEqual("100 / 10 / 2", "5");
    try expectExecEqual("100 / (10 / 2)", "20");

    try expectError("1 * true");
    try expectError("1 / true");
    try expectError("100 / (10 / 0)");
}

test "parenthesis" {
    try expectExecEqual("(1)", "1");
    try expectExecEqual("(((1)))", "1");

    try expectError("(");
    try expectError("(1");
}
