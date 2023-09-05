const std = @import("std");

pub const Expression = union(enum) {
    literalBool: bool,
    literalInt: i32,
    literalList: []*Expression,
    literalVoid: void,
};

pub fn destroy(allocator: std.mem.Allocator, expr: *Expression) void {
    switch (expr.*) {
        .literalBool, .literalInt, .literalVoid => {},
        .literalList => {
            for (expr.literalList) |v| {
                destroy(allocator, v);
            }
            allocator.free(expr.*.literalList);
        },
    }

    allocator.destroy(expr);
}
