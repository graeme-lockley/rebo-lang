const std = @import("std");

const AST = @import("./../ast.zig");
const Errors = @import("./../errors.zig");
const Op = @import("./ops.zig").Op;
const V = @import("./../value.zig");

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Compiler {
        return .{
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

    fn compileExpr(self: *Compiler, e: *AST.Expression) !void {
        switch (e.kind) {
            .binaryOp => {
                switch (e.kind.binaryOp.op) {
                    .Equal => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.equals));
                    },
                    .GreaterThan => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.greater_than));
                        try self.appendPosition(e.position);
                    },
                    .GreaterEqual => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.greater_equal));
                        try self.appendPosition(e.position);
                    },
                    .LessThan => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.less_than));
                        try self.appendPosition(e.position);
                    },
                    .LessEqual => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.less_equal));
                        try self.appendPosition(e.position);
                    },
                    .NotEqual => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.not_equals));
                    },
                    else => {
                        std.debug.panic("Unhandled: {}", .{e.kind.binaryOp.op});
                        unreachable;
                    },
                }
            },
            .exprs => for (e.kind.exprs) |expr| {
                try self.compileExpr(expr);
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
            .literalInt => {
                try self.buffer.append(@intFromEnum(Op.push_int));
                try self.appendInt(e.kind.literalInt);
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
            .literalString => {
                try self.buffer.append(@intFromEnum(Op.push_string));
                const s = e.kind.literalString.slice();
                try self.appendInt(@intCast(s.len));
                try self.buffer.appendSlice(s);
            },
            .literalVoid => try self.buffer.append(@intFromEnum(Op.push_unit)),
            else => {
                std.debug.panic("Unhandled: {}", .{e.kind});
                unreachable;
            },
        }
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

    fn appendPosition(self: *Compiler, position: Errors.Position) !void {
        try self.appendInt(@intCast(position.start));
        try self.appendInt(@intCast(position.end));
    }
};
