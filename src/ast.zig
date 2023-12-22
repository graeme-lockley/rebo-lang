const std = @import("std");

const Errors = @import("./errors.zig");
const SP = @import("./string_pool.zig");
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
    Append,
    AppendUpdate,
    Prepend,
    PrependUpdate,
    Hook,

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
            Operator.Append => "<<",
            Operator.AppendUpdate => "<!",
            Operator.Prepend => ">>",
            Operator.PrependUpdate => ">!",
            Operator.Hook => "?",
        };
    }
};

pub const Expression = struct {
    kind: ExpressionKind,
    position: Errors.Position,

    pub fn destroy(self: *Expression, allocator: std.mem.Allocator) void {
        destroyExpr(allocator, self);
    }
};

pub const ExpressionKind = union(enum) {
    assignment: AssignmentExpression,
    binaryOp: BinaryOpExpression,
    call: CallExpression,
    catche: CatchExpression,
    dot: DotExpression,
    exprs: []*Expression,
    idDeclaration: IdDeclarationExpression,
    identifier: *SP.String,
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
    match: MatchExpression,
    notOp: NotOpExpression,
    patternDeclaration: PatternDeclarationExpression,
    raise: RaiseExpression,
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

pub const IdDeclarationExpression = struct {
    name: []u8,
    value: *Expression,

    pub fn deinit(self: *IdDeclarationExpression, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        destroyExpr(allocator, self.value);
    }
};

pub const CatchExpression = struct {
    value: *Expression,
    cases: []MatchCase,
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
        destroyExpr(allocator, self.body);
    }
};

pub const FunctionParam = struct {
    name: []u8,
    default: ?*Expression,

    pub fn deinit(self: *FunctionParam, allocator: std.mem.Allocator) void {
        allocator.free(self.name);

        if (self.default != null) {
            destroyExpr(allocator, self.default.?);
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

pub const MatchExpression = struct {
    value: *Expression,
    cases: []MatchCase,
    elseCase: ?*Expression,
};

pub const MatchCase = struct {
    pattern: *Pattern,
    body: *Expression,

    pub fn deinit(self: *MatchCase, allocator: std.mem.Allocator) void {
        destroyPattern(allocator, self.pattern);
        destroyExpr(allocator, self.body);
    }
};

pub const NotOpExpression = struct {
    value: *Expression,
};

pub const RaiseExpression = struct {
    expr: *Expression,
};

pub const RecordEntry = union(enum) {
    value: struct {
        key: []u8,
        value: *Expression,
    },
    record: *Expression,
};

pub const PatternDeclarationExpression = struct {
    pattern: *Pattern,
    value: *Expression,

    pub fn deinit(self: *PatternDeclarationExpression, allocator: std.mem.Allocator) void {
        destroyPattern(allocator, self.pattern);
        destroyExpr(allocator, self.value);
    }
};

pub const WhileExpression = struct {
    condition: *Expression,
    body: *Expression,
};

fn destroyExpr(allocator: std.mem.Allocator, expr: *Expression) void {
    switch (expr.kind) {
        .assignment => {
            destroyExpr(allocator, expr.kind.assignment.lhs);
            destroyExpr(allocator, expr.kind.assignment.value);
        },
        .binaryOp => {
            destroyExpr(allocator, expr.kind.binaryOp.left);
            destroyExpr(allocator, expr.kind.binaryOp.right);
        },
        .call => {
            destroyExpr(allocator, expr.kind.call.callee);
            for (expr.kind.call.args) |arg| {
                destroyExpr(allocator, arg);
            }
            allocator.free(expr.kind.call.args);
        },
        .catche => {
            destroyExpr(allocator, expr.kind.catche.value);
            for (expr.kind.catche.cases) |*c| {
                c.deinit(allocator);
            }
            allocator.free(expr.kind.catche.cases);
        },
        .dot => {
            destroyExpr(allocator, expr.kind.dot.record);
            allocator.free(expr.kind.dot.field);
        },
        .exprs => {
            for (expr.kind.exprs) |v| {
                destroyExpr(allocator, v);
            }
            allocator.free(expr.kind.exprs);
        },
        .idDeclaration => expr.kind.idDeclaration.deinit(allocator),
        .identifier => expr.kind.identifier.decRef(),
        .ifte => {
            for (expr.kind.ifte) |v| {
                if (v.condition != null) {
                    destroyExpr(allocator, v.condition.?);
                }
                destroyExpr(allocator, v.then);
            }
            allocator.free(expr.kind.ifte);
        },
        .indexRange => {
            destroyExpr(allocator, expr.kind.indexRange.expr);
            if (expr.kind.indexRange.start != null) {
                destroyExpr(allocator, expr.kind.indexRange.start.?);
            }
            if (expr.kind.indexRange.end != null) {
                destroyExpr(allocator, expr.kind.indexRange.end.?);
            }
        },
        .indexValue => {
            destroyExpr(allocator, expr.kind.indexValue.expr);
            destroyExpr(allocator, expr.kind.indexValue.index);
        },
        .literalBool, .literalChar, .literalFloat, .literalInt, .literalVoid => {},
        .literalFunction => expr.kind.literalFunction.deinit(allocator),
        .literalRecord => {
            for (expr.kind.literalRecord) |v| {
                switch (v) {
                    .value => {
                        allocator.free(v.value.key);
                        destroyExpr(allocator, v.value.value);
                    },
                    .record => destroyExpr(allocator, v.record),
                }
            }
            allocator.free(expr.kind.literalRecord);
        },
        .literalSequence => {
            for (expr.kind.literalSequence) |v| {
                switch (v) {
                    .value => destroyExpr(allocator, v.value),
                    .sequence => destroyExpr(allocator, v.sequence),
                }
            }
            allocator.free(expr.kind.literalSequence);
        },
        .literalString => allocator.free(expr.kind.literalString),
        .match => {
            destroyExpr(allocator, expr.kind.match.value);
            for (expr.kind.match.cases) |*c| {
                c.deinit(allocator);
            }
            allocator.free(expr.kind.match.cases);
            if (expr.kind.match.elseCase != null) {
                destroyExpr(allocator, expr.kind.match.elseCase.?);
            }
        },
        .notOp => destroyExpr(allocator, expr.kind.notOp.value),
        .patternDeclaration => expr.kind.patternDeclaration.deinit(allocator),
        .raise => destroyExpr(allocator, expr.kind.raise.expr),
        .whilee => {
            destroyExpr(allocator, expr.kind.whilee.condition);
            destroyExpr(allocator, expr.kind.whilee.body);
        },
    }

    allocator.destroy(expr);
}

pub const Pattern = struct {
    kind: PatternKind,
    position: Errors.Position,

    pub fn destroy(self: *Pattern, allocator: std.mem.Allocator) void {
        destroyPattern(allocator, self);
    }
};

pub const PatternKind = union(enum) {
    identifier: []u8,
    literalChar: u8,
    literalBool: bool,
    literalFloat: Value.FloatType,
    literalInt: Value.IntType,
    literalString: []u8,
    record: RecordPattern,
    sequence: SequencePattern,
    void: void,
};

pub const SequencePattern = struct {
    patterns: []*Pattern,
    restOfPatterns: ?[]u8,
    id: ?[]u8,
};

pub const RecordPattern = struct {
    entries: []RecordPatternEntry,
    id: ?[]u8,

    pub fn deinit(self: *RecordPattern, allocator: std.mem.Allocator) void {
        for (self.items) |*item| {
            item.deinit(allocator);
        }
        self.items.deinit();

        if (self.id != null) {
            allocator.free(self.id.?);
        }
    }
};

pub const RecordPatternEntry = struct {
    key: []u8,
    pattern: ?*Pattern,
    id: ?[]u8,

    pub fn deinit(self: *RecordPatternEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        if (self.pattern != null) {
            destroyPattern(allocator, self.pattern.?);
        }
        if (self.id != null) {
            allocator.free(self.id.?);
        }
    }
};

fn destroyPattern(allocator: std.mem.Allocator, pattern: *Pattern) void {
    switch (pattern.kind) {
        .identifier => allocator.free(pattern.kind.identifier),
        .literalChar, .literalFloat, .literalInt, .literalBool, .void => {},
        .literalString => allocator.free(pattern.kind.literalString),
        .record => {
            for (pattern.kind.record.entries) |e| {
                allocator.free(e.key);
                if (e.pattern != null) {
                    destroyPattern(allocator, e.pattern.?);
                }
                if (e.id != null) {
                    allocator.free(e.id.?);
                }
            }
            allocator.free(pattern.kind.record.entries);
            if (pattern.kind.record.id != null) {
                allocator.free(pattern.kind.record.id.?);
            }
        },
        .sequence => {
            for (pattern.kind.sequence.patterns) |p| {
                destroyPattern(allocator, p);
            }
            allocator.free(pattern.kind.sequence.patterns);
            if (pattern.kind.sequence.restOfPatterns != null) {
                allocator.free(pattern.kind.sequence.restOfPatterns.?);
            }
            if (pattern.kind.sequence.id != null) {
                allocator.free(pattern.kind.sequence.id.?);
            }
        },
    }

    allocator.destroy(pattern);
}
