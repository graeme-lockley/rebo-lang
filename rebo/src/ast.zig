const std = @import("std");

pub const Expression = union(enum) {
    literalBool: bool,
    literalInt: i32,
    literalVoid: void,
};

pub fn destroy(allocator: std.mem.Allocator, expr: *Expression) void {
    switch (expr.*) {
        .literalBool, .literalInt, .literalVoid => {},
    }

    allocator.destroy(expr);
}
