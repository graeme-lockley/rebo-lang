const std = @import("std");

const AST = @import("./../ast.zig");
const Code = @import("./../bc-interpreter.zig").Code;
const Errors = @import("./../errors.zig");
const Op = @import("./ops.zig").Op;
const SP = @import("./../string_pool.zig");
const V = @import("./../value.zig");

pub const Compiler = struct {
    stringPool: *SP.StringPool,
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(stringPool: *SP.StringPool, allocator: std.mem.Allocator) Compiler {
        return .{
            .stringPool = stringPool,
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.buffer.deinit();
    }

    pub fn compile(self: *Compiler, ast: *AST.Expression) ![]u8 {
        self.buffer.clearRetainingCapacity();

        try self.compileExpr(ast);
        try self.buffer.append(@intFromEnum(Op.ret));

        return self.buffer.toOwnedSlice();
    }

    fn compileExprInScope(self: *Compiler, e: *AST.Expression) Errors.RuntimeErrors!void {
        if (e.kind == .exprs) {
            try self.buffer.append(@intFromEnum(Op.open_scope));
        }

        try self.compileExpr(e);

        if (e.kind == .exprs) {
            try self.buffer.append(@intFromEnum(Op.close_scope));
        }
    }

    fn compileExpr(self: *Compiler, e: *AST.Expression) Errors.RuntimeErrors!void {
        switch (e.kind) {
            .assignment => {
                switch (e.kind.assignment.lhs.kind) {
                    .dot => {
                        try self.compileExpr(e.kind.assignment.lhs.kind.dot.record);
                        try self.appendPushLiteralString(e.kind.assignment.lhs.kind.dot.field.slice());
                        try self.compileExpr(e.kind.assignment.rhs);
                        try self.buffer.append(@intFromEnum(Op.assign_dot));
                        try self.appendPosition(e.kind.assignment.lhs.kind.dot.record.position);
                        try self.appendPosition(e.position);
                    },
                    .identifier => {
                        try self.compileExpr(e.kind.assignment.rhs);
                        try self.buffer.append(@intFromEnum(Op.assign_identifier));
                        try self.appendSP(e.kind.assignment.lhs.kind.identifier);
                    },
                    .indexRange => {
                        if (e.kind.assignment.lhs.kind.indexRange.start == null) {
                            if (e.kind.assignment.lhs.kind.indexRange.end == null) {
                                try self.compileExpr(e.kind.assignment.lhs.kind.indexRange.expr);
                                try self.compileExpr(e.kind.assignment.rhs);
                                try self.buffer.append(@intFromEnum(Op.assign_range_all));
                                try self.appendPosition(e.kind.assignment.lhs.kind.indexRange.expr.position);
                                try self.appendPosition(e.kind.assignment.rhs.position);
                            } else {
                                try self.compileExpr(e.kind.assignment.lhs.kind.indexRange.expr);
                                try self.compileExpr(e.kind.assignment.lhs.kind.indexRange.end.?);
                                try self.compileExpr(e.kind.assignment.rhs);
                                try self.buffer.append(@intFromEnum(Op.assign_range_to));
                                try self.appendPosition(e.kind.assignment.lhs.kind.indexRange.expr.position);
                                try self.appendPosition(e.kind.assignment.lhs.kind.indexRange.end.?.position);
                                try self.appendPosition(e.kind.assignment.rhs.position);
                            }
                        } else if (e.kind.assignment.lhs.kind.indexRange.end == null) {
                            try self.compileExpr(e.kind.assignment.lhs.kind.indexRange.expr);
                            try self.compileExpr(e.kind.assignment.lhs.kind.indexRange.start.?);
                            try self.compileExpr(e.kind.assignment.rhs);
                            try self.buffer.append(@intFromEnum(Op.assign_range_from));
                            try self.appendPosition(e.kind.assignment.lhs.kind.indexRange.expr.position);
                            try self.appendPosition(e.kind.assignment.lhs.kind.indexRange.start.?.position);
                            try self.appendPosition(e.kind.assignment.rhs.position);
                        } else {
                            try self.compileExpr(e.kind.assignment.lhs.kind.indexRange.expr);
                            try self.compileExpr(e.kind.assignment.lhs.kind.indexRange.start.?);
                            try self.compileExpr(e.kind.assignment.lhs.kind.indexRange.end.?);
                            try self.compileExpr(e.kind.assignment.rhs);
                            try self.buffer.append(@intFromEnum(Op.assign_range));
                            try self.appendPosition(e.kind.assignment.lhs.kind.indexRange.expr.position);
                            try self.appendPosition(e.kind.assignment.lhs.kind.indexRange.start.?.position);
                            try self.appendPosition(e.kind.assignment.lhs.kind.indexRange.end.?.position);
                            try self.appendPosition(e.kind.assignment.rhs.position);
                        }
                    },
                    .indexValue => {
                        try self.compileExpr(e.kind.assignment.lhs.kind.indexValue.expr);
                        try self.compileExpr(e.kind.assignment.lhs.kind.indexValue.index);
                        try self.compileExpr(e.kind.assignment.rhs);
                        try self.buffer.append(@intFromEnum(Op.assign_index));
                        try self.appendPosition(e.kind.assignment.lhs.kind.indexValue.expr.position);
                        try self.appendPosition(e.kind.assignment.lhs.kind.indexValue.index.position);
                    },
                    else => {
                        try self.buffer.append(@intFromEnum(Op.push_record));
                        try self.appendPushLiteralString("kind");
                        try self.appendPushLiteralString("InvalidLHSError");
                        try self.buffer.append(@intFromEnum(Op.set_record_item_bang));
                        try self.appendPosition(e.position);

                        try self.buffer.append(@intFromEnum(Op.push_identifier));
                        try self.appendString("rebo");
                        try self.appendPosition(e.position);
                        try self.appendPushLiteralString("lang");
                        try self.buffer.append(@intFromEnum(Op.dot));
                        try self.appendPosition(e.position);
                        try self.appendPushLiteralString("stack.append.position!");
                        try self.buffer.append(@intFromEnum(Op.index));
                        try self.appendPosition(e.position);
                        try self.appendPosition(e.position);
                        try self.buffer.append(@intFromEnum(Op.push_int));
                        try self.appendInt(@intCast(e.position.start));
                        try self.buffer.append(@intFromEnum(Op.push_int));
                        try self.appendInt(@intCast(e.position.end));
                        try self.buffer.append(@intFromEnum(Op.call));
                        try self.appendInt(2);
                        try self.appendPosition(e.position);

                        try self.buffer.append(@intFromEnum(Op.discard));

                        try self.buffer.append(@intFromEnum(Op.raise));
                        try self.appendPosition(e.position);
                    },
                }
            },
            .binaryOp => {
                switch (e.kind.binaryOp.op) {
                    .Equal => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.equals));
                    },
                    .GreaterThan => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.greater_than));
                        try self.appendPosition(e.position);
                    },
                    .GreaterEqual => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.greater_equal));
                        try self.appendPosition(e.position);
                    },
                    .LessThan => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.less_than));
                        try self.appendPosition(e.position);
                    },
                    .LessEqual => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.less_equal));
                        try self.appendPosition(e.position);
                    },
                    .NotEqual => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.not_equals));
                    },
                    .And => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.buffer.append(@intFromEnum(Op.jmp_false));
                        const patch1 = self.buffer.items.len;
                        try self.appendInt(0);
                        try self.appendPosition(e.kind.binaryOp.lhs.position);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.jmp));
                        const patch2 = self.buffer.items.len;
                        try self.appendInt(0);
                        try self.appendIntAt(@intCast(self.buffer.items.len), patch1);
                        try self.buffer.append(@intFromEnum(Op.push_false));
                        try self.appendIntAt(@intCast(self.buffer.items.len), patch2);
                    },
                    .Or => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.buffer.append(@intFromEnum(Op.jmp_true));
                        const patch1 = self.buffer.items.len;
                        try self.appendInt(0);
                        try self.appendPosition(e.kind.binaryOp.lhs.position);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.jmp));
                        const patch2 = self.buffer.items.len;
                        try self.appendInt(0);
                        try self.appendIntAt(@intCast(self.buffer.items.len), patch1);
                        try self.buffer.append(@intFromEnum(Op.push_true));
                        try self.appendIntAt(@intCast(self.buffer.items.len), patch2);
                    },
                    .Plus => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.add));
                        try self.appendPosition(e.position);
                    },
                    .Minus => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.subtract));
                        try self.appendPosition(e.position);
                    },
                    .Times => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.multiply));
                        try self.appendPosition(e.position);
                    },
                    .Divide => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.divide));
                        try self.appendPosition(e.position);
                    },
                    .Modulo => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.modulo));
                        try self.appendPosition(e.position);
                    },
                    .Append => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.seq_append));
                        try self.appendPosition(e.position);
                    },
                    .AppendUpdate => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.seq_append_bang));
                        try self.appendPosition(e.position);
                    },
                    .Prepend => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.seq_prepend));
                        try self.appendPosition(e.position);
                    },
                    .PrependUpdate => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.buffer.append(@intFromEnum(Op.seq_prepend_bang));
                        try self.appendPosition(e.position);
                    },
                    .Hook => {
                        try self.compileExpr(e.kind.binaryOp.lhs);
                        try self.buffer.append(@intFromEnum(Op.duplicate));
                        try self.buffer.append(@intFromEnum(Op.push_unit));
                        try self.buffer.append(@intFromEnum(Op.equals));
                        try self.buffer.append(@intFromEnum(Op.jmp_false));
                        const patch = self.buffer.items.len;
                        try self.appendInt(0);
                        try self.appendPosition(e.kind.binaryOp.lhs.position);
                        try self.buffer.append(@intFromEnum(Op.discard));
                        try self.compileExpr(e.kind.binaryOp.rhs);
                        try self.appendIntAt(@intCast(self.buffer.items.len), patch);
                    },
                    else => {
                        std.debug.panic("Unhandled: {}", .{e.kind.binaryOp.op});
                        unreachable;
                    },
                }
            },
            .call => {
                try self.compileExpr(e.kind.call.callee);
                for (e.kind.call.args) |arg| {
                    try self.compileExpr(arg);
                }
                try self.buffer.append(@intFromEnum(Op.call));
                try self.appendInt(@intCast(e.kind.call.args.len));
                try self.appendPosition(Errors.Position{ .start = e.kind.call.callee.position.start, .end = e.position.end });
            },
            .catche => {
                var patches = std.ArrayList(usize).init(self.allocator);
                defer patches.deinit();

                var casePatches = std.ArrayList(usize).init(self.allocator);
                defer casePatches.deinit();

                try self.buffer.append(@intFromEnum(Op.catche));
                const noExceptionPatch = self.buffer.items.len;
                try self.appendInt(0);
                const exceptionPatch = self.buffer.items.len;
                try self.appendInt(0);
                try self.compileExpr(e.kind.catche.value);
                try self.buffer.append(@intFromEnum(Op.ret));
                try self.appendIntAt(@intCast(self.buffer.items.len), exceptionPatch);

                for (e.kind.catche.cases) |case| {
                    for (casePatches.items) |patch| {
                        try self.appendIntAt(@intCast(self.buffer.items.len), patch);
                    }

                    if (casePatches.items.len > 0) {
                        try self.buffer.append(@intFromEnum(Op.close_scope));
                    }
                    casePatches.clearRetainingCapacity();

                    try self.buffer.append(@intFromEnum(Op.open_scope));
                    try self.compilePattern(case.pattern, &casePatches);
                    try self.buffer.append(@intFromEnum(Op.discard));
                    try self.compileExpr(case.body);
                    try self.buffer.append(@intFromEnum(Op.close_scope));
                    try self.buffer.append(@intFromEnum(Op.jmp));
                    try patches.append(@intCast(self.buffer.items.len));
                    try self.appendInt(0);
                }

                for (casePatches.items) |patch| {
                    try self.appendIntAt(@intCast(self.buffer.items.len), patch);
                }

                if (casePatches.items.len > 0) {
                    try self.buffer.append(@intFromEnum(Op.close_scope));
                }

                try self.buffer.append(@intFromEnum(Op.raise));
                try self.appendPosition(e.position);

                for (patches.items) |patch| {
                    try self.appendIntAt(@intCast(self.buffer.items.len), patch);
                }

                try self.appendIntAt(@intCast(self.buffer.items.len), noExceptionPatch);
            },
            .dot => {
                try self.compileExpr(e.kind.dot.record);
                try self.appendPushLiteralString(e.kind.dot.field.slice());
                try self.buffer.append(@intFromEnum(Op.dot));
                try self.appendPosition(e.position);
            },
            .exprs => if (e.kind.exprs.len == 0) {
                try self.buffer.append(@intFromEnum(Op.push_unit));
            } else {
                for (e.kind.exprs, 0..) |expr, index| {
                    if (index > 0) {
                        try self.buffer.append(@intFromEnum(Op.discard));
                    }
                    try self.compileExprInScope(expr);
                }
            },
            .idDeclaration => {
                try self.compileExpr(e.kind.idDeclaration.value);
                try self.buffer.append(@intFromEnum(Op.bind_identifier));
                try self.appendString(e.kind.idDeclaration.name.slice());
            },
            .identifier => {
                try self.buffer.append(@intFromEnum(Op.push_identifier));
                try self.appendSP(e.kind.identifier);
                try self.appendPosition(e.position);
            },
            .ifte => {
                var done = false;
                var previousPatch: ?usize = null;
                var endPatches = std.ArrayList(usize).init(self.allocator);
                defer {
                    for (endPatches.items) |patch| {
                        self.appendIntAt(@intCast(self.buffer.items.len), patch) catch {};
                    }
                    endPatches.deinit();
                }

                for (e.kind.ifte) |case| {
                    if (previousPatch != null) {
                        try self.appendIntAt(@intCast(self.buffer.items.len), previousPatch.?);
                        previousPatch = null;
                    }

                    if (!done) {
                        if (case.condition == null) {
                            try self.compileExpr(case.then);
                            done = true;
                        } else {
                            try self.compileExpr(case.condition.?);
                            try self.buffer.append(@intFromEnum(Op.jmp_false));
                            previousPatch = self.buffer.items.len;
                            try self.appendInt(0);
                            try self.appendPosition(case.condition.?.position);

                            try self.compileExpr(case.then);
                            try self.buffer.append(@intFromEnum(Op.jmp));
                            try endPatches.append(self.buffer.items.len);
                            try self.appendInt(0);
                        }
                    }
                }

                if (previousPatch != null) {
                    try self.appendIntAt(@intCast(self.buffer.items.len), previousPatch.?);
                }
                if (!done) {
                    try self.buffer.append(@intFromEnum(Op.push_unit));
                }
            },
            .indexRange => {
                try self.compileExpr(e.kind.indexRange.expr);

                if (e.kind.indexRange.start == null) {
                    if (e.kind.indexRange.end == null) {} else {
                        try self.compileExpr(e.kind.indexRange.end.?);
                        try self.buffer.append(@intFromEnum(Op.rangeTo));
                        try self.appendPosition(e.kind.indexRange.expr.position);
                        try self.appendPosition(e.kind.indexRange.end.?.position);
                    }
                } else if (e.kind.indexRange.end == null) {
                    try self.compileExpr(e.kind.indexRange.start.?);
                    try self.buffer.append(@intFromEnum(Op.rangeFrom));
                    try self.appendPosition(e.kind.indexRange.expr.position);
                    try self.appendPosition(e.kind.indexRange.start.?.position);
                } else {
                    try self.compileExpr(e.kind.indexRange.start.?);
                    try self.compileExpr(e.kind.indexRange.end.?);
                    try self.buffer.append(@intFromEnum(Op.range));
                    try self.appendPosition(e.kind.indexRange.expr.position);
                    try self.appendPosition(e.kind.indexRange.start.?.position);
                    try self.appendPosition(e.kind.indexRange.end.?.position);
                }
            },
            .indexValue => {
                try self.compileExpr(e.kind.indexValue.expr);
                try self.compileExpr(e.kind.indexValue.index);
                try self.buffer.append(@intFromEnum(Op.index));
                try self.appendPosition(e.kind.indexValue.expr.position);
                try self.appendPosition(e.kind.indexValue.index.position);
            },
            .literalBool => try self.buffer.append(@intFromEnum(if (e.kind.literalBool) Op.push_true else Op.push_false)),
            .literalChar => {
                try self.buffer.append(@intFromEnum(Op.push_char));
                try self.buffer.append(e.kind.literalChar);
            },
            .literalFloat => {
                try self.buffer.append(@intFromEnum(Op.push_float));
                try self.appendFloat(e.kind.literalFloat);
            },
            .literalFunction => {
                try self.buffer.append(@intFromEnum(Op.push_function));
                try self.appendInt(@intCast(e.kind.literalFunction.params.len));
                for (e.kind.literalFunction.params) |param| {
                    try self.appendString(param.name.slice());
                    if (param.default) |d| {
                        try self.compileCodeBlock(d);
                    } else {
                        try self.appendInt(0);
                    }
                }
                if (e.kind.literalFunction.restOfParams) |rest| {
                    try self.appendString(rest.slice());
                } else {
                    try self.appendInt(0);
                }
                try self.compileCodeBlock(e.kind.literalFunction.body);
            },
            .literalInt => {
                try self.buffer.append(@intFromEnum(Op.push_int));
                try self.appendInt(e.kind.literalInt);
            },
            .literalRecord => {
                try self.buffer.append(@intFromEnum(Op.push_record));

                for (e.kind.literalRecord) |entry| {
                    switch (entry) {
                        .value => {
                            try self.appendPushLiteralString(entry.value.key.slice());
                            try self.compileExpr(entry.value.value);
                            try self.buffer.append(@intFromEnum(Op.set_record_item_bang));
                            try self.appendPosition(e.position);
                        },
                        .record => {
                            try self.compileExpr(entry.record);
                            try self.buffer.append(@intFromEnum(Op.set_record_items_bang));
                            try self.appendPosition(e.position);
                        },
                    }
                }
            },
            .literalSequence => {
                try self.buffer.append(@intFromEnum(Op.push_sequence));
                for (e.kind.literalSequence) |item| {
                    if (item == .value) {
                        try self.compileExpr(item.value);
                        try self.buffer.append(@intFromEnum(Op.append_sequence_item_bang));
                        try self.appendPosition(e.position);
                    } else {
                        try self.compileExpr(item.sequence);
                        try self.buffer.append(@intFromEnum(Op.append_sequence_items_bang));
                        try self.appendPosition(e.position);
                        try self.appendPosition(item.sequence.position);
                    }
                }
            },
            .literalString => try self.appendPushLiteralString(e.kind.literalString.slice()),
            .literalVoid => try self.buffer.append(@intFromEnum(Op.push_unit)),
            .match => {
                var patches = std.ArrayList(usize).init(self.allocator);
                defer patches.deinit();

                var casePatches = std.ArrayList(usize).init(self.allocator);
                defer casePatches.deinit();

                try self.compileExpr(e.kind.match.value);

                for (e.kind.match.cases) |case| {
                    for (casePatches.items) |patch| {
                        try self.appendIntAt(@intCast(self.buffer.items.len), patch);
                    }

                    if (casePatches.items.len > 0) {
                        try self.buffer.append(@intFromEnum(Op.close_scope));
                    }
                    casePatches.clearRetainingCapacity();

                    try self.buffer.append(@intFromEnum(Op.open_scope));
                    try self.compilePattern(case.pattern, &casePatches);
                    try self.buffer.append(@intFromEnum(Op.discard));
                    try self.compileExpr(case.body);
                    try self.buffer.append(@intFromEnum(Op.close_scope));
                    try self.buffer.append(@intFromEnum(Op.jmp));
                    try patches.append(@intCast(self.buffer.items.len));
                    try self.appendInt(0);
                }

                for (casePatches.items) |patch| {
                    try self.appendIntAt(@intCast(self.buffer.items.len), patch);
                }

                if (casePatches.items.len > 0) {
                    try self.buffer.append(@intFromEnum(Op.close_scope));
                }

                try self.buffer.append(@intFromEnum(Op.push_record));
                try self.appendPushLiteralString("kind");
                try self.appendPushLiteralString("MatchError");
                try self.buffer.append(@intFromEnum(Op.set_record_item_bang));
                try self.appendPosition(e.position);
                try self.buffer.append(@intFromEnum(Op.swap));
                try self.appendPushLiteralString("value");
                try self.buffer.append(@intFromEnum(Op.swap));
                try self.buffer.append(@intFromEnum(Op.set_record_item_bang));
                try self.appendPosition(e.position);

                try self.buffer.append(@intFromEnum(Op.push_identifier));
                try self.appendString("rebo");
                try self.appendPosition(e.position);
                try self.appendPushLiteralString("lang");
                try self.buffer.append(@intFromEnum(Op.dot));
                try self.appendPosition(e.position);
                try self.appendPushLiteralString("stack.append.position!");
                try self.buffer.append(@intFromEnum(Op.index));
                try self.appendPosition(e.position);
                try self.appendPosition(e.position);
                try self.buffer.append(@intFromEnum(Op.push_int));
                try self.appendInt(@intCast(e.position.start));
                try self.buffer.append(@intFromEnum(Op.push_int));
                try self.appendInt(@intCast(e.position.end));
                try self.buffer.append(@intFromEnum(Op.call));
                try self.appendInt(2);
                try self.appendPosition(e.position);

                try self.buffer.append(@intFromEnum(Op.discard));

                try self.buffer.append(@intFromEnum(Op.raise));
                try self.appendPosition(e.position);

                for (patches.items) |patch| {
                    try self.appendIntAt(@intCast(self.buffer.items.len), patch);
                }
            },
            .notOp => {
                try self.compileExpr(e.kind.notOp.value);
                try self.buffer.append(@intFromEnum(Op.not));
                try self.appendPosition(e.position);
            },
            .patternDeclaration => {
                var casePatches = std.ArrayList(usize).init(self.allocator);
                defer casePatches.deinit();

                try self.compileExpr(e.kind.patternDeclaration.value);
                try self.compilePattern(e.kind.patternDeclaration.pattern, &casePatches);
                try self.buffer.append(@intFromEnum(Op.jmp));
                const patch = self.buffer.items.len;
                try self.appendInt(0);

                for (casePatches.items) |ptch| {
                    try self.appendIntAt(@intCast(self.buffer.items.len), ptch);
                }

                try self.buffer.append(@intFromEnum(Op.push_record));
                try self.appendPushLiteralString("kind");
                try self.appendPushLiteralString("MatchError");
                try self.buffer.append(@intFromEnum(Op.set_record_item_bang));
                try self.appendPosition(e.position);
                try self.buffer.append(@intFromEnum(Op.swap));
                try self.appendPushLiteralString("value");
                try self.buffer.append(@intFromEnum(Op.swap));
                try self.buffer.append(@intFromEnum(Op.set_record_item_bang));
                try self.appendPosition(e.position);

                try self.buffer.append(@intFromEnum(Op.push_identifier));
                try self.appendString("rebo");
                try self.appendPosition(e.position);
                try self.appendPushLiteralString("lang");
                try self.buffer.append(@intFromEnum(Op.dot));
                try self.appendPosition(e.position);
                try self.appendPushLiteralString("stack.append.position!");
                try self.buffer.append(@intFromEnum(Op.index));
                try self.appendPosition(e.position);
                try self.appendPosition(e.position);
                try self.buffer.append(@intFromEnum(Op.push_int));
                try self.appendInt(@intCast(e.position.start));
                try self.buffer.append(@intFromEnum(Op.push_int));
                try self.appendInt(@intCast(e.position.end));
                try self.buffer.append(@intFromEnum(Op.call));
                try self.appendInt(2);
                try self.appendPosition(e.position);

                try self.buffer.append(@intFromEnum(Op.discard));

                try self.buffer.append(@intFromEnum(Op.raise));
                try self.appendPosition(e.position);

                try self.appendIntAt(@intCast(self.buffer.items.len), patch);
            },
            .raise => {
                try self.compileExpr(e.kind.raise.expr);
                try self.buffer.append(@intFromEnum(Op.raise));
                try self.appendPosition(e.position);
            },
            .whilee => {
                const start = self.buffer.items.len;
                try self.compileExpr(e.kind.whilee.condition);
                try self.buffer.append(@intFromEnum(Op.jmp_false));
                const patch = self.buffer.items.len;
                try self.appendInt(0);
                try self.appendPosition(e.kind.whilee.condition.position);
                try self.compileExpr(e.kind.whilee.body);
                try self.buffer.append(@intFromEnum(Op.discard));
                try self.buffer.append(@intFromEnum(Op.jmp));
                try self.appendInt(@intCast(start));
                try self.appendIntAt(@intCast(self.buffer.items.len), patch);
                try self.buffer.append(@intFromEnum(Op.push_unit));
            },
        }
    }

    fn compilePattern(self: *Compiler, pattern: *AST.Pattern, casePatches: *std.ArrayList(usize)) !void {
        switch (pattern.kind) {
            .identifier => {
                if (!std.mem.eql(u8, pattern.kind.identifier.slice(), "_")) {
                    try self.buffer.append(@intFromEnum(Op.duplicate));
                    try self.buffer.append(@intFromEnum(Op.bind_identifier_discard));
                    try self.appendSP(pattern.kind.identifier);
                }
            },
            .literalBool => {
                try self.buffer.append(@intFromEnum(Op.duplicate));
                try self.buffer.append(@intFromEnum(if (pattern.kind.literalBool) Op.push_true else Op.push_false));
                try self.buffer.append(@intFromEnum(Op.equals));

                try self.buffer.append(@intFromEnum(Op.jmp_false));
                try casePatches.append(self.buffer.items.len);
                try self.appendInt(0);
                try self.appendPosition(pattern.position);
            },
            .literalChar => {
                try self.buffer.append(@intFromEnum(Op.duplicate));
                try self.buffer.append(@intFromEnum(Op.push_char));
                try self.buffer.append(pattern.kind.literalChar);
                try self.buffer.append(@intFromEnum(Op.equals));

                try self.buffer.append(@intFromEnum(Op.jmp_false));
                try casePatches.append(self.buffer.items.len);
                try self.appendInt(0);
                try self.appendPosition(pattern.position);
            },
            .literalFloat => {
                try self.buffer.append(@intFromEnum(Op.duplicate));
                try self.buffer.append(@intFromEnum(Op.push_float));
                try self.appendFloat(pattern.kind.literalFloat);
                try self.buffer.append(@intFromEnum(Op.equals));

                try self.buffer.append(@intFromEnum(Op.jmp_false));
                try casePatches.append(self.buffer.items.len);
                try self.appendInt(0);
                try self.appendPosition(pattern.position);
            },
            .literalInt => {
                try self.buffer.append(@intFromEnum(Op.duplicate));
                try self.buffer.append(@intFromEnum(Op.push_int));
                try self.appendInt(pattern.kind.literalInt);
                try self.buffer.append(@intFromEnum(Op.equals));

                try self.buffer.append(@intFromEnum(Op.jmp_false));
                try casePatches.append(self.buffer.items.len);
                try self.appendInt(0);
                try self.appendPosition(pattern.position);
            },
            .literalString => {
                try self.buffer.append(@intFromEnum(Op.duplicate));
                try self.appendPushLiteralString(pattern.kind.literalString.slice());
                try self.buffer.append(@intFromEnum(Op.equals));

                try self.buffer.append(@intFromEnum(Op.jmp_false));
                try casePatches.append(self.buffer.items.len);
                try self.appendInt(0);
                try self.appendPosition(pattern.position);
            },
            .record => {
                var doubleNestedCasePatches = std.ArrayList(usize).init(self.allocator);
                defer doubleNestedCasePatches.deinit();

                try self.buffer.append(@intFromEnum(Op.duplicate));
                try self.buffer.append(@intFromEnum(Op.is_record));
                try self.buffer.append(@intFromEnum(Op.jmp_false));
                try casePatches.append(self.buffer.items.len);
                try self.appendInt(0);
                try self.appendPosition(pattern.position);

                for (pattern.kind.record.entries) |entry| {
                    try self.buffer.append(@intFromEnum(Op.duplicate));
                    try self.appendPushLiteralString(entry.key.slice());
                    try self.buffer.append(@intFromEnum(Op.dot));
                    try self.appendPosition(pattern.position);
                    try self.buffer.append(@intFromEnum(Op.duplicate));
                    try self.buffer.append(@intFromEnum(Op.push_unit));
                    try self.buffer.append(@intFromEnum(Op.equals));
                    try self.buffer.append(@intFromEnum(Op.jmp_true));
                    try doubleNestedCasePatches.append(self.buffer.items.len);
                    try self.appendInt(0);
                    try self.appendPosition(pattern.position);
                    if (entry.pattern) |p| {
                        try self.compilePattern(p, &doubleNestedCasePatches);
                        try self.buffer.append(@intFromEnum(Op.discard));
                    } else if (entry.id) |id| {
                        try self.buffer.append(@intFromEnum(Op.bind_identifier_discard));
                        try self.appendSP(id);
                    } else {
                        try self.buffer.append(@intFromEnum(Op.bind_identifier_discard));
                        try self.appendSP(entry.key);
                    }
                }
                if (pattern.kind.record.id != null) {
                    try self.buffer.append(@intFromEnum(Op.bind_identifier));
                    try self.appendSP(pattern.kind.record.id.?);
                }

                if (doubleNestedCasePatches.items.len > 0) {
                    try self.buffer.append(@intFromEnum(Op.jmp));
                    const patch = self.buffer.items.len;
                    try self.appendInt(0);

                    for (doubleNestedCasePatches.items) |p| {
                        try self.appendIntAt(@intCast(self.buffer.items.len), p);
                    }

                    try self.buffer.append(@intFromEnum(Op.discard));
                    try self.buffer.append(@intFromEnum(Op.jmp));
                    try casePatches.append(self.buffer.items.len);
                    try self.appendInt(0);

                    try self.appendIntAt(@intCast(self.buffer.items.len), patch);
                }
            },
            .sequence => {
                try self.buffer.append(@intFromEnum(Op.duplicate));
                try self.buffer.append(@intFromEnum(Op.seq_len));
                try self.buffer.append(@intFromEnum(Op.push_int));
                try self.appendInt(@intCast(pattern.kind.sequence.patterns.len));
                if (pattern.kind.sequence.restOfPatterns == null) {
                    try self.buffer.append(@intFromEnum(Op.equals));
                } else {
                    try self.buffer.append(@intFromEnum(Op.greater_equal));
                    try self.appendPosition(pattern.position);
                }
                try self.buffer.append(@intFromEnum(Op.jmp_false));
                try casePatches.append(self.buffer.items.len);
                try self.appendInt(0);
                try self.appendPosition(pattern.position);

                var nestedCasePatches = std.ArrayList(usize).init(self.allocator);
                defer nestedCasePatches.deinit();

                for (pattern.kind.sequence.patterns, 0..) |p, idx| {
                    if (p.kind != .identifier or !std.mem.eql(u8, p.kind.identifier.slice(), "_")) {
                        try self.buffer.append(@intFromEnum(Op.duplicate));
                        try self.buffer.append(@intFromEnum(Op.seq_at));
                        try self.appendInt(@intCast(idx));
                        try self.compilePattern(p, &nestedCasePatches);
                        try self.buffer.append(@intFromEnum(Op.discard));
                    }
                }

                if (pattern.kind.sequence.restOfPatterns != null and !std.mem.eql(u8, pattern.kind.sequence.restOfPatterns.?.slice(), "_")) {
                    try self.buffer.append(@intFromEnum(Op.duplicate));
                    try self.buffer.append(@intFromEnum(Op.push_int));
                    try self.appendInt(@intCast(pattern.kind.sequence.patterns.len));
                    try self.buffer.append(@intFromEnum(Op.rangeFrom));
                    try self.appendPosition(pattern.position);
                    try self.appendPosition(pattern.position);
                    try self.buffer.append(@intFromEnum(Op.bind_identifier_discard));
                    try self.appendSP(pattern.kind.sequence.restOfPatterns.?);
                }

                if (pattern.kind.sequence.id != null) {
                    try self.buffer.append(@intFromEnum(Op.bind_identifier));
                    try self.appendSP(pattern.kind.sequence.id.?);
                }

                if (nestedCasePatches.items.len > 0) {
                    try self.buffer.append(@intFromEnum(Op.jmp));
                    const patch = self.buffer.items.len;
                    try self.appendInt(0);

                    for (nestedCasePatches.items) |p| {
                        try self.appendIntAt(@intCast(self.buffer.items.len), p);
                    }

                    try self.buffer.append(@intFromEnum(Op.discard));
                    try self.buffer.append(@intFromEnum(Op.jmp));
                    try casePatches.append(self.buffer.items.len);
                    try self.appendInt(0);

                    try self.appendIntAt(@intCast(self.buffer.items.len), patch);
                }
            },
            .unit => {
                try self.buffer.append(@intFromEnum(Op.duplicate));
                try self.buffer.append(@intFromEnum(Op.push_unit));
                try self.buffer.append(@intFromEnum(Op.equals));

                try self.buffer.append(@intFromEnum(Op.jmp_false));
                try casePatches.append(self.buffer.items.len);
                try self.appendInt(0);
                try self.appendPosition(pattern.position);
            },
        }
    }

    fn compileCodeBlock(self: *Compiler, block: *AST.Expression) !void {
        // std.io.getStdOut().writer().print("Compiling code block: ip: {d}\n", .{self.buffer.items.len}) catch {};

        var compiler = Compiler.init(self.stringPool, self.allocator);
        defer compiler.deinit();

        const bytecode = try compiler.compile(block);
        errdefer self.allocator.free(bytecode);

        try self.appendCode(bytecode);
    }

    fn appendDebug(self: *Compiler, stackDepth: usize, msg: []const u8) !void {
        try self.buffer.append(@intFromEnum(Op.debug));
        try self.appendInt(@intCast(stackDepth));
        try self.appendString(msg);
    }

    fn appendCode(self: *Compiler, bytecode: []const u8) !void {
        const code = try self.allocator.create(Code);
        code.* = Code.init(bytecode);
        errdefer code.decRef(self.allocator);

        try self.appendInt(@as(V.IntType, @bitCast(@intFromPtr(code))));
    }

    fn appendFloat(self: *Compiler, v: V.FloatType) !void {
        try self.appendInt(@as(V.IntType, @bitCast(v)));
    }

    fn appendInt(self: *Compiler, v: V.IntType) !void {
        const v1: u8 = @intCast(v & 0xff);
        const v2: u8 = @intCast((@as(u64, @bitCast(v & 0xff00))) >> 8);
        const v3: u8 = @intCast((@as(u64, @bitCast(v & 0xff0000))) >> 16);
        const v4: u8 = @intCast((@as(u64, @bitCast(v & 0xff000000))) >> 24);
        const v5: u8 = @intCast((@as(u64, @bitCast(v & 0xff00000000))) >> 32);
        const v6: u8 = @intCast((@as(u64, @bitCast(v & 0xff0000000000))) >> 40);
        const v7: u8 = @intCast((@as(u64, @bitCast(v & 0xff000000000000))) >> 48);
        const v8: u8 = @intCast((@as(u64, @bitCast(v))) >> 56);

        try self.buffer.append(v1);
        try self.buffer.append(v2);
        try self.buffer.append(v3);
        try self.buffer.append(v4);
        try self.buffer.append(v5);
        try self.buffer.append(v6);
        try self.buffer.append(v7);
        try self.buffer.append(v8);
    }

    fn appendIntAt(self: *Compiler, v: V.IntType, offset: usize) !void {
        const v1: u8 = @intCast(v & 0xff);
        const v2: u8 = @intCast((@as(u64, @bitCast(v & 0xff00))) >> 8);
        const v3: u8 = @intCast((@as(u64, @bitCast(v & 0xff0000))) >> 16);
        const v4: u8 = @intCast((@as(u64, @bitCast(v & 0xff000000))) >> 24);
        const v5: u8 = @intCast((@as(u64, @bitCast(v & 0xff00000000))) >> 32);
        const v6: u8 = @intCast((@as(u64, @bitCast(v & 0xff0000000000))) >> 40);
        const v7: u8 = @intCast((@as(u64, @bitCast(v & 0xff000000000000))) >> 48);
        const v8: u8 = @intCast((@as(u64, @bitCast(v))) >> 56);

        self.buffer.items[offset] = v1;
        self.buffer.items[offset + 1] = v2;
        self.buffer.items[offset + 2] = v3;
        self.buffer.items[offset + 3] = v4;
        self.buffer.items[offset + 4] = v5;
        self.buffer.items[offset + 5] = v6;
        self.buffer.items[offset + 6] = v7;
        self.buffer.items[offset + 7] = v8;
    }

    fn appendPushLiteralString(self: *Compiler, s: []const u8) !void {
        try self.buffer.append(@intFromEnum(Op.push_string));
        try self.appendString(s);
    }

    fn appendSP(self: *Compiler, s: *SP.String) !void {
        try self.appendInt(@as(V.IntType, @bitCast(@intFromPtr(s))));
        s.incRef();
    }

    fn appendString(self: *Compiler, s: []const u8) !void {
        const string = try self.stringPool.intern(s);
        errdefer string.decRef();

        try self.appendInt(@as(V.IntType, @bitCast(@intFromPtr(string))));
    }

    fn appendPosition(self: *Compiler, position: Errors.Position) !void {
        try self.appendInt(@intCast(position.start));
        try self.appendInt(@intCast(position.end));
    }
};
