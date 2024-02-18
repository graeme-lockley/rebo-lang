const std = @import("std");

const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const Lexer = @import("./lexer.zig");
const Runtime = @import("./runtime.zig").Runtime;
const Parser = @import("./parser.zig");
const V = @import("./value.zig");

const ER = @import("error-reporting.zig");

pub const Compiler = @import("./bc-interpreter/compiler.zig").Compiler;
const Interpreter = @import("./bc-interpreter/interpreter.zig");

pub fn compile(allocator: std.mem.Allocator, ast: *AST.Expression) ![]u8 {
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    return try compiler.compile(ast);
}

pub fn eval(runtime: *Runtime, bytecode: []const u8) !void {
    try Interpreter.eval(runtime, bytecode);
}

pub fn script(runtime: *Runtime, input: []const u8) !void {
    const ast = try parse(runtime, input);
    defer ast.destroy(runtime.allocator);

    const bytecode = try compile(runtime.allocator, ast);
    defer runtime.allocator.free(bytecode);

    try Interpreter.eval(runtime, bytecode);
}

pub fn parse(runtime: *Runtime, input: []const u8) !*AST.Expression {
    var l = Lexer.Lexer.init(runtime.allocator);

    l.initBuffer("test", input) catch |err| {
        var e = l.grabErr().?;
        defer e.deinit();

        try ER.parserErrorHandler(runtime, err, e);
        return Errors.RuntimeErrors.InterpreterError;
    };

    var p = Parser.Parser.init(runtime.stringPool, l);

    const ast = p.module() catch |err| {
        var e = p.grabErr().?;
        defer e.deinit();

        try ER.parserErrorHandler(runtime, err, e);
        return Errors.RuntimeErrors.InterpreterError;
    };
    errdefer AST.destroy(runtime.allocator, ast);

    return ast;
}

fn expectExprEqual(input: []const u8, expected: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var runtime = try Runtime.init(allocator);
        defer runtime.deinit();

        try runtime.openScope();

        script(&runtime, input) catch |err| {
            std.log.err("Error: {}: {s}\n", .{ err, input });
            return error.TestingError;
        };

        if (runtime.topOfStack()) |v| {
            const result = try v.toString(allocator, V.Style.Pretty);
            defer allocator.free(result);

            if (!std.mem.eql(u8, result, expected)) {
                std.log.err("Expected: '{s}', got: '{s}'\n", .{ expected, result });
                return error.TestingError;
            }
            if (runtime.stack.items.len != 1) {
                std.log.err("Expected 1 value on the stack, got: {d}\n", .{runtime.stack.items.len});
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
}

fn expectError(input: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var runtime = try Runtime.init(allocator);
        defer runtime.deinit();

        try runtime.openScope();

        script(&runtime, input) catch {
            return;
        };

        if (runtime.topOfStack()) |v| {
            const result = try v.toString(allocator, V.Style.Pretty);
            defer allocator.free(result);

            std.log.err("Expected error: got: '{s}'\n", .{result});
        } else {
            std.log.err("Expected error: got: empty stack\n", .{});
        }
        return error.TestingError;
    }

    const err = gpa.deinit();
    if (err == std.heap.Check.leak) {
        std.log.err("Failed to deinit allocator\n", .{});
        return error.TestingError;
    }
}

test "assignment expression" {
    // try expectExprEqual("let x = 10; x := x + 1", "11");
    // try expectExprEqual("let x = 10; x := x + 1", "11");
    // try expectExprEqual("let x = 10; x := x + 1; x", "11");
    // try expectExprEqual("(fn (x = 0) = { x := x + 1 })(10)", "11");
    // try expectExprEqual("let count = 0; let inc() = count := count + 1; inc(); inc(); inc()", "3");

    // try expectExprEqual("let count = 0; rebo.lang.scope()[\"count\"] := 10", "10");
    // try expectError("let count = 0; rebo.lang.scope()[\"counting\"] := 10");

    // try expectExprEqual("let x = {a: 10, b: 20}; x.a := x.a + 1", "11");
    // try expectExprEqual("let x = {a: 10, b: 20}; x.a := x.a + 1; [x.a, x.b]", "[11, 20]");
    // try expectExprEqual("let x = {a: 10, b: 20}; let getX() = x; getX().a := getX().a + 1; [getX().a, x.a, x.b]", "[11, 11, 20]");
    // try expectExprEqual("let x = {a: 10, b: 20}; x.a := (); x", "{b: 20}");
    // try expectExprEqual("let x = {b: 20}; x.a := (); x", "{b: 20}");

    // try expectExprEqual("let v = {a: 10}; v[\"a\"] := 11", "11");
    // try expectExprEqual("let v = {a: 10}; v[\"a\"] := 11; v", "{a: 11}");
    // try expectExprEqual("let v = {}; v[\"b\"] := 11", "11");
    // try expectExprEqual("let v = {}; v[\"b\"] := 11; v", "{b: 11}");
    // try expectExprEqual("let x = {a: 10, b: 20}; x[\"a\"] := (); x", "{b: 20}");
    // try expectExprEqual("let x = {b: 20}; x[\"a\"] := (); x", "{b: 20}");

    // try expectExprEqual("let v = [1, 2, 3, 4]; v[1] := 11", "11");
    // try expectExprEqual("let v = [1, 2, 3, 4]; v[1] := 11; v", "[1, 11, 3, 4]");

    // try expectExprEqual("let v = [1, 2, 3, 4]; v[1:2] := [11, 12, 13]; v", "[1, 11, 12, 13, 3, 4]");
    // try expectExprEqual("let v = [1, 2, 3, 4]; v[:2] := [11, 12, 13]; v", "[11, 12, 13, 3, 4]");
    // try expectExprEqual("let v = [1, 2, 3, 4]; v[1:] := [11, 12, 13]; v", "[1, 11, 12, 13]");
    // try expectExprEqual("let v = [1, 2, 3, 4]; v[:] := [11, 12, 13]; v", "[11, 12, 13]");
    // try expectExprEqual("let v = [1, 2, 3, 4]; v[:] := [11, 12, 13]", "[11, 12, 13]");

    // try expectError("let v = [1, 2, 3, 4]; v[4] := 11");
    // try expectError("let v = [1, 2, 3, 4]; v[-1] := 11");
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

    try expectExprEqual("let x = 10 ; rebo.lang.scope()[\"x\"]", "10");
    try expectExprEqual("let x = 10 ; rebo.lang.scope()[\"y\"]", "()");

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

    // try expectExprEqual("rebo.lang.len({a: 10, ...{b: 20}})", "2");
    // try expectExprEqual("{a: 10, ...{b: 20}}.a", "10");
    // try expectExprEqual("{a: 10, ...{b: 20}}.b", "20");

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
    // try expectExprEqual("true && true", "true");
    // try expectExprEqual("false && true", "false");
    // try expectExprEqual("true && false", "false");
    // try expectExprEqual("false && false", "false");

    // try expectExprEqual("true && true && true", "true");

    // try expectExprEqual("false && (1/0)", "false");

    // try expectExprEqual("true || true", "true");
    // try expectExprEqual("false || true", "true");
    // try expectExprEqual("true || false", "true");
    // try expectExprEqual("false || false", "false");

    // try expectExprEqual("false || false || true", "true");

    // try expectExprEqual("true || (1/0)", "true");
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

test "hook op" {
    try expectExprEqual("123 ? 0", "123");
    try expectExprEqual("() ? 0", "0");
    try expectExprEqual("0 ? 1", "0");
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
    try expectExprEqual("let a = 1; a", "1");

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
    // try expectExprEqual("!true", "false");
    // try expectExprEqual("!false", "true");

    // try expectError("!()");
}

test "catch-raise" {
    // try expectExprEqual("0 catch \"Hello\" -> 1 | _ -> 2", "0");
    // try expectExprEqual("{ raise \"Hello\" } catch \"Hello\" -> 1 | _ -> 2", "1");
    // try expectExprEqual("{ raise \"Bye\" } catch \"Hello\" -> 1 | _ -> 2", "2");
    // try expectExprEqual("{{ raise \"Bye\" } catch \"Hello\" -> 1} catch \"Bye\" -> 2", "2");
}
