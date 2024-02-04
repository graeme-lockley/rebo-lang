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

    return try compiler.compile(ast);
}

pub fn script(runtime: *Runtime, input: []const u8) !void {
    const ast = try parse(runtime, input);
    defer ast.destroy(runtime.allocator);

    const bytecode = try compile(runtime.allocator, ast);
    defer runtime.allocator.free(bytecode);

    try Interpreter.eval(runtime, bytecode);
}

fn parse(runtime: *Runtime, input: []const u8) !*AST.Expression {
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

    // try expectError("1 + true");
    // try expectError("1 - true");
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

test "hook op" {
    try expectExprEqual("123 ? 0", "123");
    try expectExprEqual("() ? 0", "0");
    try expectExprEqual("0 ? 1", "0");
}

test "list append/prepend" {
    try expectExprEqual("[1, 2] << 3", "[1, 2, 3]");
    try expectExprEqual("[1, 2] <! 3", "[1, 2, 3]");

    // try expectExprEqual("let x = [1, 2]; x << 3; x", "[1, 2]");
    // try expectExprEqual("let x = [1, 2]; x <! 3; x", "[1, 2, 3]");

    try expectExprEqual("1 >> [2, 3]", "[1, 2, 3]");
    try expectExprEqual("1 >! [2, 3]", "[1, 2, 3]");

    // try expectExprEqual("let x = [2, 3]; 1 >> x; x", "[2, 3]");
    // try expectExprEqual("let x = [2, 3]; 1 >! x 3; x", "[1, 2, 3]");
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

test "literal int" {
    try expectExprEqual("0", "0");
    try expectExprEqual("-0", "0");
    try expectExprEqual("123", "123");
    try expectExprEqual("-123", "-123");
}

test "literal record" {
    try expectExprEqual("{}", "{}");
    try expectExprEqual("{name: 10}", "{name: 10}");

    // try expectExprEqual("{a: 1, a: 2, a: 3}", "{a: 3}");
    // try expectExprEqual("{a: 10, b: ()}", "{a: 10}");
    // try expectExprEqual("{a: 10, b: 20, a: ()}", "{b: 20}");

    // try expectExprEqual("rebo.lang.len({a: 10, ...{b: 20}})", "2");
    // try expectExprEqual("{a: 10, ...{b: 20}}.a", "10");
    // try expectExprEqual("{a: 10, ...{b: 20}}.b", "20");

    // try expectError("{a:1,");
}

test "literal sequence" {
    try expectExprEqual("[]", "[]");
    try expectExprEqual("[1]", "[1]");
    try expectExprEqual("[1, 2, 3]", "[1, 2, 3]");
    try expectExprEqual("[1, [true, false], 3]", "[1, [true, false], 3]");

    try expectExprEqual("[1, ...[], 3]", "[1, 3]");
    try expectExprEqual("[1, ...[true], 3]", "[1, true, 3]");
    try expectExprEqual("[1, ...[true, false], 3]", "[1, true, false, 3]");
    try expectExprEqual("[...[true, false], 1, ...[true, false], 3, ...[true, false]]", "[true, false, 1, true, false, 3, true, false]");

    // try expectExprEqual("let x = [true, false]; [...x, 1, ...x, 3, ...x]", "[true, false, 1, true, false, 3, true, false]");
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

    // try expectError("1 * true");
    // try expectError("1 / true");
    // try expectError("100 / (10 / 0)");
    // try expectError("100 / (10 / 0.0)");
    // try expectError("100 / (10.0 / 0)");
    // try expectError("100 / (10.0 / 0.0)");
}
