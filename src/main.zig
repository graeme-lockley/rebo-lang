const std = @import("std");

const API = @import("./api.zig").API;
const Errors = @import("./errors.zig");
const V = @import("./value.zig");

const Editor = @import("zigline/main.zig").Editor;

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const err = gpa.deinit();
        if (err == std.heap.Check.leak) {
            stdout.print("Failed to deinit allocator\n", .{}) catch {};
            std.process.exit(1);
        }
    }

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2 and std.mem.eql(u8, args[1], "help")) {
        try stdout.print("Usage: {s} [file ...args | repl | help]\n", .{args[0]});
        std.process.exit(1);
    } else if (args.len == 1 or args.len == 2 and std.mem.eql(u8, args[1], "repl")) {
        var editor = Editor.init(gpa.allocator(), .{});
        defer editor.deinit();

        var rebo = try API.init(allocator);
        defer rebo.deinit();

        var historyFile = try historyFileName(&rebo);
        defer allocator.free(historyFile);

        try editor.loadHistory(historyFile);
        defer editor.saveHistory(historyFile) catch unreachable;

        while (true) {
            const line: []const u8 = editor.getLine("> ") catch |err| switch (err) {
                error.Eof => break,
                else => return err,
            };
            defer gpa.allocator().free(line);

            if (line.len == 0) {
                continue;
            }
            if (std.mem.eql(u8, line, "quit")) {
                break;
            }

            try editor.addToHistory(line);
            rebo.script(line) catch |err| {
                try errorHandler(err, &rebo);
                continue;
            };

            try printResult(&rebo);
            try rebo.reset();
        }
    } else {
        const startTime = std.time.milliTimestamp();

        var rebo = try API.init(allocator);
        defer rebo.deinit();

        rebo.import(args[1]) catch |e| {
            try errorHandler(e, &rebo);
        };

        const executeTime = std.time.milliTimestamp();
        std.log.info("time: {d}ms", .{executeTime - startTime});
    }
}

fn historyFileName(rebo: *API) ![]u8 {
    try rebo.script("(rebo.env.HOME ? \".\") + \"/.rebo.repl.history\"");
    if (rebo.topOfStack()) |v| {
        const result = try rebo.allocator().dupe(u8, v.v.StringKind.slice());
        rebo.pop();
        return result;
    } else {
        return rebo.allocator().dupe(u8, ".rebo.repl.history");
    }
}

fn printResult(rebo: *API) !void {
    if (rebo.topOfStack()) |_| {
        try rebo.script("import(import(\"sys\").binHome() + \"/src/repl-util.rebo\").printResult");
        try rebo.swap();
        try rebo.call(1);
    } else {
        try stdout.print("Unexpected Error: no result to print\n", .{});
    }
}

fn errorHandler(err: anyerror, rebo: *API) !void {
    if (err == Errors.RuntimeErrors.InterpreterError) {
        try rebo.script("import(import(\"sys\").binHome() + \"/src/repl-util.rebo\").printError");
        try rebo.swap();
        try rebo.call(1);
    } else {
        err catch {};
        try stdout.print("Unknown Error:\n", .{});
    }
}

fn nike(input: []const u8) !void {
    var lp: usize = 1;

    while (lp < input.len) {
        const s = input[0..lp];

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        {
            var rebo = try API.init(allocator);
            defer rebo.deinit();

            _ = rebo.script(s) catch {};
        }

        const err = gpa.deinit();
        if (err == std.heap.Check.leak) {
            std.log.err("Failed to deinit allocator: {s}\n", .{s});
            return error.TestingError;
        }

        lp += 1;
    }
}

pub fn expectExprEqual(input: []const u8, expected: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var rebo = try API.init(allocator);
        defer rebo.deinit();

        rebo.script(input) catch |err| {
            std.log.err("Error: {}: {s}\n", .{ err, input });
            return error.TestingError;
        };

        if (rebo.topOfStack()) |v| {
            const result = try v.toString(allocator, V.Style.Pretty);
            defer allocator.free(result);

            if (!std.mem.eql(u8, result, expected)) {
                std.log.err("Expected: '{s}', got: '{s}'\n", .{ expected, result });
                return error.TestingError;
            }
            if (rebo.stackDepth() != 1) {
                std.log.err("Expected 1 value on the stack, got: {d}\n", .{rebo.stackDepth()});
                return error.TestingError;
            }
        } else {
            std.log.err("Expected a value on the stack\n", .{});
            return error.TestingError;
        }
    }

    const err = gpa.deinit();
    if (err == std.heap.Check.leak) {
        std.log.err("Failed to deinit allocator\n", .{});
        return error.TestingError;
    }

    // try nike(input);
}

fn expectError(input: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var rebo = try API.init(allocator);
        defer rebo.deinit();

        rebo.script(input) catch {
            return;
        };

        if (rebo.topOfStack()) |v| {
            const result = try v.toString(allocator, V.Style.Pretty);
            defer allocator.free(result);

            std.log.err("Expected error: got: '{s}'\n", .{result});
        } else {
            std.log.err("Expected error: got: empty stack\n", .{});
        }
        return error.TestingError;
    }

    var err = gpa.deinit();
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

    try expectExprEqual("{a: 1, a: 2, a: 3}", "{a: 3}");
    try expectExprEqual("{a: 10, b: ()}", "{a: 10}");
    try expectExprEqual("{a: 10, b: 20, a: ()}", "{b: 20}");

    try expectExprEqual("len({a: 10, ...{b: 20}})", "2");
    try expectExprEqual("{a: 10, ...{b: 20}}.a", "10");
    try expectExprEqual("{a: 10, ...{b: 20}}.b", "20");

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

test "list append/prepend" {
    try expectExprEqual("[1, 2] << 3", "[1, 2, 3]");
    try expectExprEqual("[1, 2] <! 3", "[1, 2, 3]");

    try expectExprEqual("let x = [1, 2]; x << 3; x", "[1, 2]");
    try expectExprEqual("let x = [1, 2]; x <! 3; x", "[1, 2, 3]");

    try expectExprEqual("1 >> [2, 3]", "[1, 2, 3]");
    try expectExprEqual("1 >! [2, 3]", "[1, 2, 3]");

    try expectExprEqual("let x = [2, 3]; 1 >> x; x", "[2, 3]");
    try expectExprEqual("let x = [2, 3]; 1 >! x 3; x", "[1, 2, 3]");
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

test "not" {
    try expectExprEqual("!true", "false");
    try expectExprEqual("!false", "true");

    try expectError("!()");
}

test "catch-raise" {
    try expectExprEqual("0 catch \"Hello\" -> 1 | _ -> 2", "0");
    try expectExprEqual("{ raise \"Hello\" } catch \"Hello\" -> 1 | _ -> 2", "1");
    try expectExprEqual("{ raise \"Bye\" } catch \"Hello\" -> 1 | _ -> 2", "2");
    try expectExprEqual("{{ raise \"Bye\" } catch \"Hello\" -> 1} catch \"Bye\" -> 2", "2");
}
