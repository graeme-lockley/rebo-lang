const std = @import("std");

pub const Expression = union(enum) {
    literalBool: bool,
    literalInt: i32,
    literalList: []*Expression,
    literalVoid: void,
    minus: MinusExpression,
    plus: PlusExpression,
};

pub const MinusExpression = struct {
    left: *Expression,
    right: *Expression,
};

pub const PlusExpression = struct {
    left: *Expression,
    right: *Expression,
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
        .minus => {
            destroy(allocator, expr.*.minus.left);
            destroy(allocator, expr.*.minus.right);
        },
        .plus => {
            destroy(allocator, expr.*.plus.left);
            destroy(allocator, expr.*.plus.right);
        },
    }

    allocator.destroy(expr);
}
