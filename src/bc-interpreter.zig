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

pub fn script(runtime: *Runtime, name: []const u8, input: []const u8) !void {
    const ast = try parse(runtime, name, input);
    defer ast.destroy(runtime.allocator);

    const bytecode = try compile(runtime.allocator, ast);
    defer runtime.allocator.free(bytecode);

    try Interpreter.eval(runtime, bytecode);
}

pub fn parse(runtime: *Runtime, name: []const u8, input: []const u8) !*AST.Expression {
    var l = Lexer.Lexer.init(runtime.allocator);

    l.initBuffer(name, input) catch |err| {
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

pub fn execute(self: *Runtime, name: []const u8, buffer: []const u8) !void {
    const ast = try parse(self, name, buffer);
    defer ast.destroy(self.allocator);

    const bytecode = try compile(self.allocator, ast);
    defer self.allocator.free(bytecode);

    try Interpreter.eval(self, bytecode);
}
