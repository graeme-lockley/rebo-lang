const std = @import("std");

pub const Expr = union(enum) {
    literalBool: bool,
    literalVoid: void,
};

pub fn destroy(allocator: std.mem.Allocator, expr: *Expr) void {
    allocator.destroy(expr);
}
