const std = @import("std");

const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const Lexer = @import("./lexer.zig");
const Op = @import("./bc-interpreter/ops.zig").Op;
const Runtime = @import("./runtime.zig").Runtime;
const Parser = @import("./parser.zig");
const SP = @import("./string_pool.zig");
const V = @import("./value.zig");

const ER = @import("error-reporting.zig");

pub const Compiler = @import("./bc-interpreter/compiler.zig").Compiler;
const Interpreter = @import("./bc-interpreter/interpreter.zig");

pub fn compile(allocator: std.mem.Allocator, ast: *AST.Expression) !*Code {
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    const bytecode = try compiler.compile(ast);
    errdefer free(bytecode, allocator);

    const result = try allocator.create(Code);
    result.* = Code.init(bytecode);

    return result;
}

pub fn eval(runtime: *Runtime, bytecode: []const u8) !void {
    try Interpreter.eval(runtime, bytecode);
}

pub fn script(runtime: *Runtime, name: []const u8, input: []const u8) !void {
    const ast = try parse(runtime, name, input);
    defer ast.destroy(runtime.allocator);

    var code = try compile(runtime.allocator, ast);
    defer code.decRef(runtime.allocator);

    try code.eval(runtime);
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

pub const Code = struct {
    code: []const u8,
    count: u32,

    pub fn init(code: []const u8) Code {
        return Code{
            .code = code,
            .count = 1,
        };
    }

    pub fn deinit(this: *Code, allocator: std.mem.Allocator) void {
        free(this.code, allocator);
    }

    pub fn incRef(this: *Code) void {
        if (this.count == std.math.maxInt(u32)) {
            this.count = 0;
        } else if (this.count > 0) {
            this.count += 1;
        }
    }

    pub fn incRefR(this: *Code) *Code {
        this.incRef();
        return this;
    }

    pub fn decRef(this: *Code, allocator: std.mem.Allocator) void {
        if (this.count == 1) {
            this.deinit(allocator);
            allocator.destroy(this);

            return;
        } else if (this.count != 0) {
            this.count -= 1;
        }
    }

    pub fn eval(this: *Code, runtime: *Runtime) !void {
        try Interpreter.eval(runtime, this.code);
    }
};

pub fn execute(self: *Runtime, name: []const u8, buffer: []const u8) !void {
    const ast = try parse(self, name, buffer);
    defer ast.destroy(self.allocator);

    const bytecode = try compile(self.allocator, ast);
    defer self.allocator.free(bytecode);

    try Interpreter.eval(self, bytecode);
}

fn free(bytecode: []const u8, allocator: std.mem.Allocator) void {
    freeBlock(bytecode, 0, bytecode.len, allocator);

    allocator.free(bytecode);
}

fn freeBlock(bytecode: []const u8, startIp: usize, upper: usize, allocator: std.mem.Allocator) void {
    var ip: usize = startIp;
    while (ip < upper) {
        // std.io.getStdOut().writer().print("ip: {d}: {d}\n", .{ ip, bytecode[ip] }) catch {};
        switch (@as(Op, @enumFromInt(bytecode[ip]))) {
            .ret => ip += 1,
            .push_char => ip += 2,
            .push_false => ip += 1,
            .push_float => ip += 1 + Interpreter.FloatTypeSize,
            .push_identifier => {
                const len: usize = @intCast(Interpreter.readInt(bytecode, ip + 1));
                ip += 1 + Interpreter.IntTypeSize + len + Interpreter.PositionTypeSize;
            },
            .push_int => ip += 1 + Interpreter.IntTypeSize,
            .push_function => ip = freeFunction(bytecode, ip, allocator),
            .push_record => ip += 1,
            .push_sequence => ip += 1,
            .push_string => {
                const len: usize = @intCast(Interpreter.readInt(bytecode, ip + 1));
                ip += 1 + Interpreter.IntTypeSize + len;
            },
            .push_true => ip += 1,
            .push_unit => ip += 1,
            .jmp => ip += Interpreter.IntTypeSize,
            .jmp_true => ip += 1 + Interpreter.IntTypeSize + Interpreter.PositionTypeSize,
            .jmp_false => ip += 1 + Interpreter.IntTypeSize + Interpreter.PositionTypeSize,
            .raise => ip += 1 + Interpreter.PositionTypeSize,
            .catche => ip += 1 + Interpreter.IntTypeSize + Interpreter.IntTypeSize,
            .is_record => ip += 1,
            .seq_len => ip += 1,
            .seq_at => ip += 1 + Interpreter.IntTypeSize,
            .open_scope => ip += 1,
            .close_scope => ip += 1,
            .call => ip += 1 + Interpreter.IntTypeSize + Interpreter.PositionTypeSize,
            .bind => ip += 1,
            .assign_dot => ip += 1 + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize,
            .assign_identifier => ip += 1,
            .assign_index => ip += 1 + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize,
            .assign_range => ip += 1 + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize,
            .assign_range_all => ip += 1 + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize,
            .assign_range_from => ip += 1 + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize,
            .assign_range_to => ip += 1 + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize,
            .duplicate => ip += 1,
            .discard => ip += 1,
            .swap => ip += 1,
            .append_sequence_item_bang => ip += 1 + Interpreter.PositionTypeSize,
            .append_sequence_items_bang => ip += 1 + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize,
            .set_record_item_bang => ip += 1 + Interpreter.PositionTypeSize,
            .set_record_items_bang => ip += 1 + Interpreter.PositionTypeSize,
            .equals => ip += 1,
            .not_equals => ip += 1,
            .less_than => ip += 1 + Interpreter.PositionTypeSize,
            .less_equal => ip += 1 + Interpreter.PositionTypeSize,
            .greater_than => ip += 1 + Interpreter.PositionTypeSize,
            .greater_equal => ip += 1 + Interpreter.PositionTypeSize,
            .add => ip += 1 + Interpreter.PositionTypeSize,
            .subtract => ip += 1 + Interpreter.PositionTypeSize,
            .multiply => ip += 1 + Interpreter.PositionTypeSize,
            .divide => ip += 1 + Interpreter.PositionTypeSize,
            .modulo => ip += 1 + Interpreter.PositionTypeSize,
            .seq_append => ip += 1 + Interpreter.PositionTypeSize,
            .seq_append_bang => ip += 1 + Interpreter.PositionTypeSize,
            .seq_prepend => ip += 1 + Interpreter.PositionTypeSize,
            .seq_prepend_bang => ip += 1 + Interpreter.PositionTypeSize,
            .dot => ip += 1 + Interpreter.PositionTypeSize,
            .index => ip += 1 + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize,
            .range => ip += 1 + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize,
            .rangeFrom => ip += 1 + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize,
            .rangeTo => ip += 1 + Interpreter.PositionTypeSize + Interpreter.PositionTypeSize,
            .not => ip += 1 + Interpreter.PositionTypeSize,
            .debug => {
                const len: usize = @intCast(Interpreter.readInt(bytecode, ip + 1 + Interpreter.IntTypeSize));
                ip += 1 + Interpreter.IntTypeSize + Interpreter.IntTypeSize + len;
            },

            // else => unreachable,
        }
    }
}

fn freeFunction(bytecode: []const u8, startIp: usize, allocator: std.mem.Allocator) usize {
    var ip = startIp;

    const numberOfParameters: usize = @intCast(Interpreter.readInt(bytecode, ip + 1));
    ip += 1 + Interpreter.IntTypeSize;

    for (0..numberOfParameters) |_| {
        const nameLen: usize = @intCast(Interpreter.readInt(bytecode, ip));
        ip += Interpreter.IntTypeSize + nameLen;

        const codePtr = @as(?*Code, @ptrFromInt(@as(usize, @bitCast(Interpreter.readInt(bytecode, ip)))));
        ip += Interpreter.IntTypeSize;

        if (codePtr) |code| {
            code.decRef(allocator);
        }
    }

    const restNameLen: usize = @intCast(Interpreter.readInt(bytecode, ip));
    ip += Interpreter.IntTypeSize + restNameLen;

    const code = @as(*Code, @ptrFromInt(@as(usize, @bitCast(Interpreter.readInt(bytecode, ip)))));
    ip += Interpreter.IntTypeSize;

    code.decRef(allocator);

    return ip;
}
