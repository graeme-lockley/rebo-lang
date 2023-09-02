const std = @import("std");

const Errors = @import("./errors.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

pub const Value = union(enum) {
    void: void,
    bool: bool,
};

pub const Expr = union(enum) {
    literalBool: bool,
    literalVoid: void,
};

fn evalExpr(machine: *Machine, e: *Expr) !*Value {
    switch (e.*) {
        .literalBool => {
            return try machine.createBoolValue(e.literalBool);
        },
        .literalVoid => {
            return try machine.createVoidValue();
        },
    }
}

pub const Machine = struct {
    allocator: std.mem.Allocator,
    err: ?*Errors.Error,

    pub fn init(allocator: std.mem.Allocator) Machine {
        return Machine{
            .allocator = allocator,
            .err = null,
        };
    }

    pub fn createVoidValue(self: *Machine) !*Value {
        const v = try self.allocator.create(Value);
        v.* = Value{ .void = void{} };
        return v;
    }

    pub fn createBoolValue(self: *Machine, v: bool) !*Value {
        const r = try self.allocator.create(Value);
        r.* = Value{ .bool = v };
        return r;
    }

    pub fn eval(self: *Machine, e: *Expr) !*Value {
        return evalExpr(self, e);
    }

    pub fn execute(self: *Machine, name: []const u8, buffer: []u8) !*Value {
        var l = lexer.Lexer.init(self.allocator);

        l.initBuffer(name, buffer) catch |err| {
            self.err = l.grabErr();
            return err;
        };

        var p = parser.Parser.init(self.allocator, l);

        const ast = p.expr() catch |err| {
            self.err = p.grabErr();
            return err;
        };

        return self.eval(ast);
    }

    pub fn grabErr(self: *Machine) ?*Errors.Error {
        const err = self.err;
        self.err = null;

        return err;
    }
};
