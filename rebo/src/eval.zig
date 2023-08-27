const std = @import("std");

pub const Value = union(enum) {
    bool: bool,
};

pub const Expr = union(enum) {
    literalBool: bool,
};

fn evalExpr(allocator: *const std.mem.Allocator, e: *Expr) !*Value {
    switch (e.*) {
        .literalBool => {
            const v = try allocator.create(Value);
            v.bool = e.literalBool;

            return v;
        },
    }
}

pub const Machine = struct {
    allocator: *const std.mem.Allocator,

    pub fn init(allocator: *const std.mem.Allocator) Machine {
        return Machine{
            .allocator = allocator,
        };
    }

    pub fn eval(self: Machine, e: *Expr) !*Value {
        return evalExpr(self.allocator, e);
    }
};
