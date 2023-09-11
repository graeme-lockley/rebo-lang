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
    literalFunction: Function,
    literalInt: i32,
    literalSequence: []*Expression,
    literalRecord: []RecordEntry,
    literalVoid: void,
};

pub const Function = struct {
    params: []FunctionParam,
    body: *Expression,

    pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
        for (self.params) |*param| {
            param.deinit(allocator);
        }
        allocator.free(self.params);
        destroy(allocator, self.body);
    }
};

pub const FunctionParam = struct {
    name: []u8,
    default: ?*Expression,

    pub fn deinit(self: *FunctionParam, allocator: std.mem.Allocator) void {
        allocator.free(self.name);

        if (self.default != null) {
            destroy(allocator, self.default.?);
        }
    }
};

pub const RecordEntry = struct {
    key: []u8,
    value: *Expression,
};

pub const BinaryOpExpression = struct {
    left: *Expression,
    op: Operator,
    right: *Expression,
};

pub fn destroy(allocator: std.mem.Allocator, expr: *Expression) void {
    switch (expr.kind) {
        .binaryOp => {
            destroy(allocator, expr.kind.binaryOp.left);
            destroy(allocator, expr.kind.binaryOp.right);
        },
        .literalBool, .literalInt, .literalVoid => {},
        .literalFunction => expr.kind.literalFunction.deinit(allocator),
        .literalSequence => {
            for (expr.kind.literalSequence) |v| {
                destroy(allocator, v);
            }
            allocator.free(expr.kind.literalSequence);
        },
        .literalRecord => {
            for (expr.kind.literalRecord) |v| {
                allocator.free(v.key);
                destroy(allocator, v.value);
            }
            allocator.free(expr.kind.literalRecord);
        },
    }

    allocator.destroy(expr);
}
