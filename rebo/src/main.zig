const std = @import("std");
const Machine = @import("./machine.zig");
const V = @import("./value.zig");

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
        const startTime = std.time.milliTimestamp();

        const buffer: []u8 = try loadBinary(allocator, args[2]);
        defer allocator.free(buffer);

        const loadBinaryTime = std.time.milliTimestamp();
        var machine = try Machine.Machine.init(allocator);
        defer machine.deinit();

        execute(&machine, args[2], buffer);
        const executeTime = std.time.milliTimestamp();
        try printResult(allocator, machine.topOfStack());
        std.log.info("time: load: {d}ms, execute: {d}ms", .{ loadBinaryTime - startTime, executeTime - loadBinaryTime });
    } else if (args.len == 2 and std.mem.eql(u8, args[1], "repl")) {
        var buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(buffer);

        var machine = try Machine.Machine.init(allocator);
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
                try machine.reset();
            } else {
                break;
            }
        }
    } else {
        std.debug.print("Usage: {s} [repl|run <filename>]\n", .{args[0]});
    }
}

fn printResult(allocator: std.mem.Allocator, v: ?*V.Value) !void {
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

fn expectExprEqual(input: []const u8, expected: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var machine = try Machine.Machine.init(allocator);
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
        if (machine.memoryState.stack.items.len != 1) {
            std.log.err("Expected 1 value on the stack, got: {d}\n", .{machine.memoryState.stack.items.len});
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
        var machine = try Machine.Machine.init(allocator);
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

test "assignment expression" {
    try expectExprEqual("let x = 10; x := x + 1", "11");
    try expectExprEqual("let x = 10; x := x + 1; x", "11");
    try expectExprEqual("(fn (x = 0) = { x := x + 1 })(10)", "11");
    try expectExprEqual("let count = 0; let inc() = count := count + 1; inc(); inc(); inc()", "3");

    try expectExprEqual("let x = {a: 10, b: 20}; x.a := x.a + 1", "11");
    try expectExprEqual("let x = {a: 10, b: 20}; x.a := x.a + 1; [x.a, x.b]", "[11, 20]");
    try expectExprEqual("let x = {a: 10, b: 20}; let getX() = x; getX().a := getX().a + 1; [getX().a, x.a, x.b]", "[11, 11, 20]");
    try expectExprEqual("let x = {a: 10, b: 20}; x.a := (); x", "{b: 20}");
    try expectExprEqual("let x = {b: 20}; x.a := (); x", "{b: 20}");

    try expectExprEqual("let v = {a: 10}; v[\"a\"] := 11", "11");
    try expectExprEqual("let v = {a: 10}; v[\"a\"] := 11; v", "{a: 11}");
    try expectExprEqual("let v = {}; v[\"b\"] := 11", "11");
    try expectExprEqual("let v = {}; v[\"b\"] := 11; v", "{b: 11}");
    try expectExprEqual("let x = {a: 10, b: 20}; x[\"a\"] := (); x", "{b: 20}");
    try expectExprEqual("let x = {b: 20}; x[\"a\"] := (); x", "{b: 20}");

    try expectExprEqual("let v = [1, 2, 3, 4]; v[1] := 11", "11");
    try expectExprEqual("let v = [1, 2, 3, 4]; v[1] := 11; v", "[1, 11, 3, 4]");

    try expectExprEqual("let v = [1, 2, 3, 4]; v[1:2] := [11, 12, 13]; v", "[1, 11, 12, 13, 3, 4]");
    try expectExprEqual("let v = [1, 2, 3, 4]; v[:2] := [11, 12, 13]; v", "[11, 12, 13, 3, 4]");
    try expectExprEqual("let v = [1, 2, 3, 4]; v[1:] := [11, 12, 13]; v", "[1, 11, 12, 13]");
    try expectExprEqual("let v = [1, 2, 3, 4]; v[:] := [11, 12, 13]; v", "[11, 12, 13]");
    try expectExprEqual("let v = [1, 2, 3, 4]; v[:] := [11, 12, 13]", "[11, 12, 13]");

    try expectError("let v = [1, 2, 3, 4]; v[4] := 11");
    try expectError("let v = [1, 2, 3, 4]; v[-1] := 11");
}

test "call expression" {
    try expectExprEqual("(fn() = 1)()", "1");
    try expectExprEqual("(fn() = 1)(1, 2, 3)", "1");
    try expectExprEqual("(fn(n) = n + 1)(10, 20, 30)", "11");

    try expectExprEqual("(fn(n = 0, m = 1) = n + m)()", "1");
    try expectExprEqual("(fn(n = 0, m = 1) = n + m)(10)", "11");
    try expectExprEqual("(fn(n = 0, m = 1) = n + m)(10, 20)", "30");
    try expectExprEqual("(fn(n = 0, m = 1) = n + m)(10, 20, 40)", "30");

    try expectExprEqual("(fn(f, g) = (fn(n) = f(g(n))))(fn(n) = n * n, fn(n) = n + n)(3)", "36");
    try expectExprEqual("(fn(f) = (fn (g) = (fn(n=1) = f(g(n)))))(fn(n) = n * n)(fn(n) = n + n)()", "4");
    try expectExprEqual("(fn(f) = (fn (g) = (fn(n=1) = f(g(n)))))(fn(n) = n * n)(fn(n) = n + n)(3)", "36");

    try expectError("20(10)");
    try expectError("(fn(f) = (fn (g) = (fn(n) = f(g(n)))))(fn(n) = n * n)(fn(n) = n + n)()");
}

test "dot expression" {
    try expectExprEqual("{}.a", "()");
    try expectExprEqual("{a: 10}.a", "10");
    try expectExprEqual("{a: 10, b: 20, c: 30, a: 40}.a", "40");
    try expectExprEqual("{a: {x: 1, y: 2}}.a.x", "1");

    try expectError("{a: 10}.20");
}

test "index range" {
    try expectExprEqual("[1, 2, 3, 4, 5, 6][0:1]", "[1]");
    try expectExprEqual("[1, 2, 3, 4, 5, 6][0:2]", "[1, 2]");
    try expectExprEqual("[1, 2, 3, 4, 5, 6][:2]", "[1, 2]");
    try expectExprEqual("[1, 2, 3, 4, 5, 6][-110:2]", "[1, 2]");
    try expectExprEqual("[1, 2, 3, 4, 5, 6][3:]", "[4, 5, 6]");
    try expectExprEqual("[1, 2, 3, 4, 5, 6][:3]", "[1, 2, 3]");
    try expectExprEqual("[1, 2, 3, 4, 5, 6][:]", "[1, 2, 3, 4, 5, 6]");

    try expectExprEqual("\"hellos\"[0:1]", "\"h\"");
    try expectExprEqual("\"hellos\"[0:2]", "\"he\"");
    try expectExprEqual("\"hellos\"[:2]", "\"he\"");
    try expectExprEqual("\"hellos\"[-110:2]", "\"he\"");
    try expectExprEqual("\"hellos\"[3:]", "\"los\"");
    try expectExprEqual("\"hellos\"[:3]", "\"hel\"");
    try expectExprEqual("\"hellos\"[:]", "\"hellos\"");
}

test "index value" {
    try expectExprEqual("{a: 10, b: 20}[\"a\"]", "10");
    try expectExprEqual("{a: 10, b: 20}[\"b\"]", "20");
    try expectExprEqual("{a: 10, b: 20}[\"c\"]", "()");

    try expectExprEqual("[1, 2, 3][0]", "1");
    try expectExprEqual("[1, 2, 3][2]", "3");
    try expectExprEqual("[1, 2, 3][3]", "()");
    try expectExprEqual("[1, 2, 3][-1]", "()");

    try expectExprEqual("\"hello\"[0]", "'h'");
    try expectExprEqual("\"hello\"[4]", "'o'");
    try expectExprEqual("\"hello\"[5]", "()");
    try expectExprEqual("\"hello\"[-1]", "()");
}

test "literal bool" {
    try expectExprEqual("true", "true");
    try expectExprEqual("false", "false");
}

test "literal char" {
    try expectExprEqual("'x'", "'x'");
    try expectExprEqual("'\\n'", "'\\n'");
    try expectExprEqual("'\\''", "'\\''");
    try expectExprEqual("'\\\\'", "'\\\\'");
    try expectExprEqual("'\\x32'", "' '");
    try expectExprEqual("'\\x10'", "'\\n'");
    try expectExprEqual("'\\x5'", "'\\x5'");
}

test "literal float" {
    try expectExprEqual("1.0", "1");
    try expectExprEqual("1.23", "1.23");

    try expectExprEqual("1.0e5", "100000");
    try expectExprEqual("1.0e-5", "0.00001");
}

test "literal function" {
    try expectExprEqual("fn() = 1", "fn()");
    try expectExprEqual("fn(a) = a + 1", "fn(a)");
    try expectExprEqual("fn(a = 1, b = 2, c = 3) = a + b + c", "fn(a = 1, b = 2, c = 3)");

    try expectExprEqual("(fn(n) = (fn (m) = n + m))(1)(2)", "3");

    try expectExprEqual("(fn(a = 1, b = 2, ...c) = [a, b] + c)()", "[1, 2]");
    try expectExprEqual("(fn(a = 1, b = 2, ...c) = [a, b] + c)(10)", "[10, 2]");
    try expectExprEqual("(fn(a = 1, b = 2, ...c) = [a, b] + c)(10, 20)", "[10, 20]");
    try expectExprEqual("(fn(a = 1, b = 2, ...c) = [a, b] + c)(10, 20, 30)", "[10, 20, 30]");
    try expectExprEqual("(fn(a = 1, b = 2, ...c) = [a, b] + c)(10, 20, 30, 40)", "[10, 20, 30, 40]");
    try expectExprEqual("(fn(...x) = x)()", "[]");
    try expectExprEqual("(fn(...x) = x)(1)", "[1]");
    try expectExprEqual("(fn(...x) = x)(1, 2, 3)", "[1, 2, 3]");

    try expectError("fn(a = 1, b = 2, c = 3) = ");
}

test "literal int" {
    try expectExprEqual("0", "0");
    try expectExprEqual("-0", "0");
    try expectExprEqual("123", "123");
    try expectExprEqual("-123", "-123");
}

test "literal record" {
    try expectExprEqual("{}", "{}");
    try expectExprEqual("{name: 10}", "{name: 10}");

    // the following is a brittle test but it is good enough for now
    try expectExprEqual("{a: 1, b: 2, c: 3}", "{b: 2, a: 1, c: 3}");
    try expectExprEqual("{a: 1, a: 2, a: 3}", "{a: 3}");
    try expectExprEqual("{a: 10, b: ()}", "{a: 10}");
    try expectExprEqual("{a: 10, b: 20, a: ()}", "{b: 20}");

    try expectExprEqual("{a: 10, ...{b: 20}}", "{b: 20, a: 10}");

    try expectError("{a:1,");
}

test "literal sequence" {
    try expectExprEqual("[]", "[]");
    try expectExprEqual("[1]", "[1]");
    try expectExprEqual("[1, 2, 3]", "[1, 2, 3]");
    try expectExprEqual("[1, [true, false], 3]", "[1, [true, false], 3]");

    try expectExprEqual("[1, ...[], 3]", "[1, 3]");
    try expectExprEqual("[1, ...[true], 3]", "[1, true, 3]");
    try expectExprEqual("[1, ...[true, false], 3]", "[1, true, false, 3]");
    try expectExprEqual("let x = [true, false]; [...x, 1, ...x, 3, ...x]", "[true, false, 1, true, false, 3, true, false]");

    try expectError("[1, 2,");
    try expectError("[1, 2, 3");
}

test "literal string" {
    try expectExprEqual("\"\"", "\"\"");
    try expectExprEqual("\"hello world\"", "\"hello world\"");
    try expectExprEqual("\"\\n \\\\ \\\"\"", "\"\\n \\\\ \\\"\"");
    try expectExprEqual("\"\\x32;\"", "\" \"");
}

test "literal unit" {
    try expectExprEqual("()", "()");
}

test "boolean op" {
    try expectExprEqual("true && true", "true");
    try expectExprEqual("false && true", "false");
    try expectExprEqual("true && false", "false");
    try expectExprEqual("false && false", "false");

    try expectExprEqual("true && true && true", "true");

    try expectExprEqual("false && (1/0)", "false");

    try expectExprEqual("true || true", "true");
    try expectExprEqual("false || true", "true");
    try expectExprEqual("true || false", "true");
    try expectExprEqual("false || false", "false");

    try expectExprEqual("false || false || true", "true");

    try expectExprEqual("true || (1/0)", "true");
}

test "equality op" {
    try expectExprEqual("1 == 1", "true");
    try expectExprEqual("0 == 1", "false");

    try expectExprEqual("1 != 1", "false");
    try expectExprEqual("0 != 1", "true");

    try expectExprEqual("0 < 1", "true");
    try expectExprEqual("0 < 1.0", "true");
    try expectExprEqual("0.0 < 1", "true");
    try expectExprEqual("0.0 < 1.0", "true");
    try expectExprEqual("0 < 0", "false");
    try expectExprEqual("0 < 0.0", "false");
    try expectExprEqual("0.0 < 0", "false");
    try expectExprEqual("0.0 < 0.0", "false");
    try expectExprEqual("1 < 0", "false");
    try expectExprEqual("1 < 0.0", "false");
    try expectExprEqual("1.0 < 0", "false");
    try expectExprEqual("1.0 < 0.0", "false");

    try expectExprEqual("0 <= 1", "true");
    try expectExprEqual("0 <= 1.0", "true");
    try expectExprEqual("0.0 <= 1", "true");
    try expectExprEqual("0.0 <= 1.0", "true");
    try expectExprEqual("0 <= 0", "true");
    try expectExprEqual("0 <= 0.0", "true");
    try expectExprEqual("0.0 <= 0", "true");
    try expectExprEqual("0.0 <= 0.0", "true");
    try expectExprEqual("1 <= 0", "false");
    try expectExprEqual("1 <= 0.0", "false");
    try expectExprEqual("1.0 <= 0", "false");
    try expectExprEqual("1.0 <= 0.0", "false");

    try expectExprEqual("0 > 1", "false");
    try expectExprEqual("0 > 1.0", "false");
    try expectExprEqual("0.0 > 1", "false");
    try expectExprEqual("0.0 > 1.0", "false");
    try expectExprEqual("0 > 0", "false");
    try expectExprEqual("0 > 0.0", "false");
    try expectExprEqual("0.0 > 0", "false");
    try expectExprEqual("0.0 > 0.0", "false");
    try expectExprEqual("1 > 0", "true");
    try expectExprEqual("1 > 0.0", "true");
    try expectExprEqual("1.0 > 0", "true");
    try expectExprEqual("1.0 > 0.0", "true");

    try expectExprEqual("0 >= 1", "false");
    try expectExprEqual("0 >= 1.0", "false");
    try expectExprEqual("0.0 >= 1", "false");
    try expectExprEqual("0.0 >= 1.0", "false");
    try expectExprEqual("0 >= 0", "true");
    try expectExprEqual("0 >= 0.0", "true");
    try expectExprEqual("0.0 >= 0", "true");
    try expectExprEqual("0.0 >= 0.0", "true");
    try expectExprEqual("1 >= 0", "true");
    try expectExprEqual("1 >= 0.0", "true");
    try expectExprEqual("1.0 >= 0", "true");
    try expectExprEqual("1.0 >= 0.0", "true");
}

test "additive op" {
    try expectExprEqual("1 + 1", "2");
    try expectExprEqual("1 + 1.1", "2.1");
    try expectExprEqual("1.1 + 1", "2.1");
    try expectExprEqual("1.1 + 1.1", "2.2");
    try expectExprEqual("1 + 2 + 3 + 4 + 5", "15");

    try expectExprEqual("1 - 1", "0");
    try expectExprEqual("1 - 1.0", "0");
    try expectExprEqual("1.0 - 1", "0");
    try expectExprEqual("1 - 1.0", "0");
    try expectExprEqual("1 - 2 + 3 - 4 + 5", "3");

    try expectExprEqual("\"hello\" + \" \" + \"world\"", "\"hello world\"");
    try expectExprEqual("[1, 2, 3] + [] + [4, 5] + [6]", "[1, 2, 3, 4, 5, 6]");

    try expectError("1 + true");
    try expectError("1 - true");
}

test "multiplicative op" {
    try expectExprEqual("1 * 1", "1");
    try expectExprEqual("1 * 1.1", "1.1");
    try expectExprEqual("1.1 * 1", "1.1");
    try expectExprEqual("1.1 * 1.1", "1.2100000000000002");
    try expectExprEqual("1 * 2 * 3 * 4 * 5", "120");

    try expectExprEqual("3 / 2", "1");
    try expectExprEqual("3.0 / 2", "1.5");
    try expectExprEqual("3 / 2.0", "1.5");
    try expectExprEqual("3.0 / 2.0", "1.5");
    try expectExprEqual("100 / 2", "50");
    try expectExprEqual("100 / 10 / 2", "5");
    try expectExprEqual("100 / (10 / 2)", "20");

    try expectExprEqual("3 % 2", "1");
    try expectExprEqual("5 % 3", "2");

    try expectError("1 * true");
    try expectError("1 / true");
    try expectError("100 / (10 / 0)");
    try expectError("100 / (10 / 0.0)");
    try expectError("100 / (10.0 / 0)");
    try expectError("100 / (10.0 / 0.0)");
}

test "parenthesis" {
    try expectExprEqual("(1)", "1");
    try expectExprEqual("(((1)))", "1");

    try expectError("(");
    try expectError("(1");
}

test "let declaration" {
    try expectExprEqual("1; 2; 3; 1;", "1");
    try expectExprEqual("let a = 1; a;", "1");

    try expectExprEqual("let add(a = 0, b = 0) = a + b; add();", "0");
    try expectExprEqual("let add(a = 0, b = 0) = a + b; add(1);", "1");
    try expectExprEqual("let add(a = 0, b = 0) = a + b; add(1, 2);", "3");
    try expectExprEqual("let add(a = 0, b = 0) = a + b; add(1, 2, 3);", "3");
    try expectExprEqual("let add(a = 0, b = 0) = a + b; add;", "fn(a = 0, b = 0)");

    try expectExprEqual("let args(...x) = x; args;", "fn(...x)");
    try expectExprEqual("let args(...x) = x; args();", "[]");
    try expectExprEqual("let args(...x) = x; args(1, 2, 3);", "[1, 2, 3]");

    try expectExprEqual("let add(a = 0, b = 0) = a + b; let fun(x = add(1, 2)) = x * x; fun();", "9");
}

test "if" {
    try expectExprEqual("if true -> 1 | 0", "1");
    try expectExprEqual("if false -> 1 | 0", "0");
    try expectExprEqual("if false -> 1", "()");
    try expectExprEqual("if false -> 1 | false -> 2 | 3", "3");
}
