const std = @import("std");

const Errors = @import("./errors.zig");
const Value = @import("./value.zig");

pub const Operator = enum {
    Plus,
    Minus,
    Times,
    Divide,
    Modulo,
    Equal,
    NotEqual,
    LessThan,
    LessEqual,
    GreaterThan,
    GreaterEqual,
    And,
    Or,

    pub fn toString(self: Operator) []const u8 {
        return switch (self) {
            Operator.Plus => "+",
            Operator.Minus => "-",
            Operator.Times => "*",
            Operator.Divide => "/",
            Operator.Modulo => "%",
            Operator.Equal => "==",
            Operator.NotEqual => "!=",
            Operator.LessThan => "<",
            Operator.LessEqual => "<=",
            Operator.GreaterThan => ">",
            Operator.GreaterEqual => ">=",
            Operator.And => "&&",
            Operator.Or => "||",
        };
    }
};

pub const Expression = struct {
    kind: ExpressionKind,
    position: Errors.Position,
};

pub const ExpressionKind = union(enum) {
    assignment: AssignmentExpression,
    binaryOp: BinaryOpExpression,
    call: CallExpression,
    declaration: DeclarationExpression,
    dot: DotExpression,
    exprs: []*Expression,
    identifier: []u8,
    ifte: []IfCouple,
    indexRange: IndexRangeExpression,
    indexValue: IndexValueExpression,
    literalBool: bool,
    literalChar: u8,
    literalFunction: Function,
    literalInt: Value.IntType,
    literalFloat: Value.FloatType,
    literalRecord: []RecordEntry,
    literalSequence: []LiteralSequenceValue,
    literalString: []u8,
    literalVoid: void,
    notOp: NotOpExpression,
    whilee: WhileExpression,
};

pub const AssignmentExpression = struct {
    lhs: *Expression,
    value: *Expression,
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
    restOfParams: ?[]u8,
    body: *Expression,

    pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
        for (self.params) |*param| {
            param.deinit(allocator);
        }
        allocator.free(self.params);
        if (self.restOfParams != null) {
            allocator.free(self.restOfParams.?);
        }
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

pub const IndexRangeExpression = struct {
    expr: *Expression,
    start: ?*Expression,
    end: ?*Expression,
};

pub const IndexValueExpression = struct {
    expr: *Expression,
    index: *Expression,
};

pub const LiteralSequenceValue = union(enum) {
    value: *Expression,
    sequence: *Expression,
};

pub const NotOpExpression = struct {
    value: *Expression,
};

pub const RecordEntry = union(enum) {
    value: struct {
        key: []u8,
        value: *Expression,
    },
    record: *Expression,
};

pub const WhileExpression = struct {
    condition: *Expression,
    body: *Expression,
};

pub fn destroy(allocator: std.mem.Allocator, expr: *Expression) void {
    switch (expr.kind) {
        .assignment => {
            destroy(allocator, expr.kind.assignment.lhs);
            destroy(allocator, expr.kind.assignment.value);
        },
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
        .indexRange => {
            destroy(allocator, expr.kind.indexRange.expr);
            if (expr.kind.indexRange.start != null) {
                destroy(allocator, expr.kind.indexRange.start.?);
            }
            if (expr.kind.indexRange.end != null) {
                destroy(allocator, expr.kind.indexRange.end.?);
            }
        },
        .indexValue => {
            destroy(allocator, expr.kind.indexValue.expr);
            destroy(allocator, expr.kind.indexValue.index);
        },
        .literalBool, .literalChar, .literalFloat, .literalInt, .literalVoid => {},
        .literalFunction => expr.kind.literalFunction.deinit(allocator),
        .literalRecord => {
            for (expr.kind.literalRecord) |v| {
                switch (v) {
                    .value => {
                        allocator.free(v.value.key);
                        destroy(allocator, v.value.value);
                    },
                    .record => destroy(allocator, v.record),
                }
            }
            allocator.free(expr.kind.literalRecord);
        },
        .literalSequence => {
            for (expr.kind.literalSequence) |v| {
                switch (v) {
                    .value => destroy(allocator, v.value),
                    .sequence => destroy(allocator, v.sequence),
                }
            }
            allocator.free(expr.kind.literalSequence);
        },
        .literalString => allocator.free(expr.kind.literalString),
        .notOp => destroy(allocator, expr.kind.notOp.value),
        .whilee => {
            destroy(allocator, expr.kind.whilee.condition);
            destroy(allocator, expr.kind.whilee.body);
        },
    }

    allocator.destroy(expr);
}
