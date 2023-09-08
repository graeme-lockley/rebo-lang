const std = @import("std");

pub const Operator = enum {
    Plus,
    Minus,
    Times,
    Divide,
};

pub const Expression = union(enum) {
    binaryOp: BinaryOpExpression,
    literalBool: bool,
    literalInt: i32,
    literalList: []*Expression,
    literalVoid: void,
};

pub const BinaryOpExpression = struct {
    left: *Expression,
    op: Operator,
    right: *Expression,
};

pub fn destroy(allocator: std.mem.Allocator, expr: *Expression) void {
    switch (expr.*) {
        .binaryOp => {
            destroy(allocator, expr.*.binaryOp.left);
            destroy(allocator, expr.*.binaryOp.right);
        },
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
