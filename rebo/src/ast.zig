const std = @import("std");

const Errors = @import("./errors.zig");

pub const Operator = enum {
    Plus,
    Minus,
    Times,
    Divide,

    pub fn toString(self: Operator) []const u8 {
        return switch (self) {
            Operator.Plus => "+",
            Operator.Minus => "-",
            Operator.Times => "-",
            Operator.Divide => "/",
        };
    }
};

pub const Expression = struct {
    kind: ExpressionKind,
    position: Errors.Position,
};

pub const ExpressionKind = union(enum) {
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
    switch (expr.*.kind) {
        .binaryOp => {
            destroy(allocator, expr.*.kind.binaryOp.left);
            destroy(allocator, expr.*.kind.binaryOp.right);
        },
        .literalBool, .literalInt, .literalVoid => {},
        .literalList => {
            for (expr.*.kind.literalList) |v| {
                destroy(allocator, v);
            }
            allocator.free(expr.*.kind.literalList);
        },
    }

    allocator.destroy(expr);
}
