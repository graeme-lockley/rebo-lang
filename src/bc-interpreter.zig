const std = @import("std");

const AST = @import("./ast.zig");
const Builtins = @import("./builtins.zig");
const Errors = @import("./errors.zig");
const Lexer = @import("./lexer.zig");
const MS = @import("./runtime.zig");
const Parser = @import("./parser.zig");
const SP = @import("./string_pool.zig");
const V = @import("./value.zig");

const ER = @import("error-reporting.zig");

const Op = enum(u8) {
    ret,
    push_char,
    push_int,
    push_false,
    push_float,
    push_string,
    push_true,
    push_unit,
};

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Compiler {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.buffer.deinit();
    }

    fn compile(self: *Compiler, ast: *AST.Expression) ![]u8 {
        self.buffer.clearRetainingCapacity();

        try self.compileExpr(ast);
        try self.buffer.append(@intFromEnum(Op.ret));

        return self.buffer.toOwnedSlice();
    }

    fn compileExpr(self: *Compiler, e: *AST.Expression) !void {
        switch (e.kind) {
            .exprs => for (e.kind.exprs) |expr| {
                try self.compileExpr(expr);
            },
            .literalBool => try self.buffer.append(@intFromEnum(if (e.kind.literalBool) Op.push_true else Op.push_false)),
            .literalChar => {
                try self.buffer.append(@intFromEnum(Op.push_char));
                try self.buffer.append(e.kind.literalChar);
            },
            .literalFloat => {
                try self.buffer.append(@intFromEnum(Op.push_float));
                try self.appendFloat(e.kind.literalFloat);
            },
            .literalInt => {
                try self.buffer.append(@intFromEnum(Op.push_int));
                try self.appendInt(e.kind.literalInt);
            },
            .literalString => {
                try self.buffer.append(@intFromEnum(Op.push_string));
                const s = e.kind.literalString.slice();
                try self.appendInt(@intCast(s.len));
                try self.buffer.appendSlice(s);
            },
            .literalVoid => try self.buffer.append(@intFromEnum(Op.push_unit)),
            else => {
                std.debug.panic("Unhandled: {}", .{e.kind});
                unreachable;
            },
        }
    }

    fn appendFloat(self: *Compiler, v: V.FloatType) !void {
        try self.appendInt(@as(V.IntType, @bitCast(v)));
    }

    fn appendInt(self: *Compiler, v: V.IntType) !void {
        const v1: u8 = @intCast(v & 0xff);
        const v2: u8 = @intCast((@as(u64, @bitCast(v & 0xff00))) >> 8);
        const v3: u8 = @intCast((@as(u64, @bitCast(v & 0xff0000))) >> 16);
        const v4: u8 = @intCast((@as(u64, @bitCast(v & 0xff000000))) >> 24);
        const v5: u8 = @intCast((@as(u64, @bitCast(v & 0xff00000000))) >> 32);
        const v6: u8 = @intCast((@as(u64, @bitCast(v & 0xff0000000000))) >> 40);
        const v7: u8 = @intCast((@as(u64, @bitCast(v & 0xff000000000000))) >> 48);
        const v8: u8 = @intCast((@as(u64, @bitCast(v))) >> 56);

        try self.buffer.append(v1);
        try self.buffer.append(v2);
        try self.buffer.append(v3);
        try self.buffer.append(v4);
        try self.buffer.append(v5);
        try self.buffer.append(v6);
        try self.buffer.append(v7);
        try self.buffer.append(v8);
    }
};

pub fn compile(allocator: std.mem.Allocator, ast: *AST.Expression) ![]u8 {
    var compiler = Compiler.init(allocator);

    return try compiler.compile(ast);
}

pub fn script(runtime: *MS.Runtime, input: []const u8) !void {
    const ast = try parse(runtime, input);
    defer ast.destroy(runtime.allocator);

    const bytecode = try compile(runtime.allocator, ast);
    defer runtime.allocator.free(bytecode);

    try eval(runtime, bytecode);
}

fn eval(runtime: *MS.Runtime, bytecode: []const u8) !void {
    var ip: usize = 0;
    while (true) {
        switch (@as(Op, @enumFromInt(bytecode[ip]))) {
            Op.ret => return,
            Op.push_char => {
                try runtime.pushCharValue(bytecode[ip + 1]);
                ip += 2;
            },
            Op.push_false => {
                try runtime.pushBoolValue(false);
                ip += 1;
            },
            Op.push_float => {
                try runtime.pushFloatValue(readFloat(bytecode, ip + 1));
                ip += 9;
            },
            Op.push_int => {
                try runtime.pushIntValue(readInt(bytecode, ip + 1));
                ip += 9;
            },
            Op.push_string => {
                const len: usize = @intCast(readInt(bytecode, ip + 1));
                const str = bytecode[ip + 9 .. ip + 9 + len];
                try runtime.pushStringValue(str);
                ip += 9 + len;
            },
            Op.push_true => {
                try runtime.pushBoolValue(true);
                ip += 1;
            },
            Op.push_unit => {
                try runtime.pushUnitValue();
                ip += 1;
            },
            // else => unreachable,
        }
    }
}

fn readFloat(bytecode: []const u8, ip: usize) V.FloatType {
    return @as(V.FloatType, @bitCast(readInt(bytecode, ip)));
}

fn readInt(bytecode: []const u8, ip: usize) V.IntType {
    const v: V.IntType = @bitCast(@as(u64, (bytecode[ip])) |
        (@as(u64, bytecode[ip + 1]) << 8) |
        (@as(u64, bytecode[ip + 2]) << 16) |
        (@as(u64, bytecode[ip + 3]) << 24) |
        (@as(u64, bytecode[ip + 4]) << 32) |
        (@as(u64, bytecode[ip + 5]) << 40) |
        (@as(u64, bytecode[ip + 6]) << 48) |
        (@as(u64, bytecode[ip + 7]) << 56));

    return v;
}

fn parse(runtime: *MS.Runtime, input: []const u8) !*AST.Expression {
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
        var runtime = try MS.Runtime.init(allocator);
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

test "literal string" {
    try expectExprEqual("\"\"", "\"\"");
    try expectExprEqual("\"hello world\"", "\"hello world\"");
    try expectExprEqual("\"\\n \\\\ \\\"\"", "\"\\n \\\\ \\\"\"");
    try expectExprEqual("\"\\x32;\"", "\" \"");
}

test "literal unit" {
    try expectExprEqual("()", "()");
}
