const std = @import("std");

pub const Expr = union(enum) {
    literalBool: bool,
    literalInt: i32,
    literalVoid: void,
};

pub fn destroy(allocator: std.mem.Allocator, expr: *Expr) void {
    switch (expr.*) {
        .literalBool, .literalInt, .literalVoid => {},
    }

    allocator.destroy(expr);
}
