const std = @import("std");

const Errors = @import("./errors.zig");
const Value = @import("./value.zig");

pub const Operator = enum {
    Plus,
    Minus,
    Times,
    Divide,
    Modulo,
    Equals,
    NotEquals,

    pub fn toString(self: Operator) []const u8 {
        return switch (self) {
            Operator.Plus => "+",
            Operator.Minus => "-",
            Operator.Times => "-",
            Operator.Divide => "/",
            Operator.Modulo => "%",
            Operator.Equals => "==",
            Operator.NotEquals => "!=",
        };
    }
};

pub const Expression = struct {
    kind: ExpressionKind,
    position: Errors.Position,
};

pub const ExpressionKind = union(enum) {
    binaryOp: BinaryOpExpression,
    call: CallExpression,
    declaration: DeclarationExpression,
    dot: DotExpression,
    exprs: []*Expression,
    identifier: []u8,
    ifte: []IfCouple,
    literalBool: bool,
    literalChar: u8,
    literalFunction: Function,
    literalInt: Value.IntType,
    literalFloat: Value.FloatType,
    literalRecord: []RecordEntry,
    literalSequence: []*Expression,
    literalString: []u8,
    literalVoid: void,
};

pub const BinaryOpExpression = struct {
    left: *Expression,
    op: Operator,
    right: *Expression,
};

pub const CallExpression = struct {
    callee: *Expression,
    args: []*Expression,
};

pub const DeclarationExpression = struct {
    name: []u8,
    value: *Expression,

    pub fn deinit(self: *DeclarationExpression, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        destroy(allocator, self.value);
    }
};

pub const DotExpression = struct {
    record: *Expression,
    field: []u8,
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

pub const IfCouple = struct {
    condition: ?*Expression,
    then: *Expression,
};

pub const RecordEntry = struct {
    key: []u8,
    value: *Expression,
};

pub fn destroy(allocator: std.mem.Allocator, expr: *Expression) void {
    switch (expr.kind) {
        .binaryOp => {
            destroy(allocator, expr.kind.binaryOp.left);
            destroy(allocator, expr.kind.binaryOp.right);
        },
        .call => {
            destroy(allocator, expr.kind.call.callee);
            for (expr.kind.call.args) |arg| {
                destroy(allocator, arg);
            }
            allocator.free(expr.kind.call.args);
        },
        .declaration => expr.kind.declaration.deinit(allocator),
        .dot => {
            destroy(allocator, expr.kind.dot.record);
            allocator.free(expr.kind.dot.field);
        },
        .exprs => {
            for (expr.kind.exprs) |v| {
                destroy(allocator, v);
            }
            allocator.free(expr.kind.exprs);
        },
        .identifier => allocator.free(expr.kind.identifier),
        .ifte => {
            for (expr.kind.ifte) |v| {
                if (v.condition != null) {
                    destroy(allocator, v.condition.?);
                }
                destroy(allocator, v.then);
            }
            allocator.free(expr.kind.ifte);
        },
        .literalBool, .literalChar, .literalFloat, .literalInt, .literalVoid => {},
        .literalFunction => expr.kind.literalFunction.deinit(allocator),
        .literalRecord => {
            for (expr.kind.literalRecord) |v| {
                allocator.free(v.key);
                destroy(allocator, v.value);
            }
            allocator.free(expr.kind.literalRecord);
        },
        .literalSequence => {
            for (expr.kind.literalSequence) |v| {
                destroy(allocator, v);
            }
            allocator.free(expr.kind.literalSequence);
        },
        .literalString => allocator.free(expr.kind.literalString),
    }

    allocator.destroy(expr);
}
