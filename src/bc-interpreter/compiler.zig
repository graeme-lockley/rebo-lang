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

    fn compileExpr(self: *Compiler, e: *AST.Expression) Errors.RuntimeErrors!void {
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
                    .Plus => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.add));
                        try self.appendPosition(e.position);
                    },
                    .Minus => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.subtract));
                        try self.appendPosition(e.position);
                    },
                    .Times => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.multiply));
                        try self.appendPosition(e.position);
                    },
                    .Divide => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.divide));
                        try self.appendPosition(e.position);
                    },
                    .Modulo => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.modulo));
                        try self.appendPosition(e.position);
                    },
                    .Append => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.seq_append));
                        try self.appendPosition(e.position);
                    },
                    .AppendUpdate => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.seq_append_bang));
                        try self.appendPosition(e.position);
                    },
                    .Prepend => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.seq_prepend));
                        try self.appendPosition(e.position);
                    },
                    .PrependUpdate => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.compileExpr(e.kind.binaryOp.right);
                        try self.buffer.append(@intFromEnum(Op.seq_prepend_bang));
                        try self.appendPosition(e.position);
                    },
                    .Hook => {
                        try self.compileExpr(e.kind.binaryOp.left);
                        try self.buffer.append(@intFromEnum(Op.duplicate));
                        try self.buffer.append(@intFromEnum(Op.push_unit));
                        try self.buffer.append(@intFromEnum(Op.equals));
                        try self.buffer.append(@intFromEnum(Op.jmp_false));
                        const patch = self.buffer.items.len;
                        try self.appendInt(0);
                        try self.appendPosition(e.kind.binaryOp.left.position);
                        try self.buffer.append(@intFromEnum(Op.discard));
                        try self.compileExpr(e.kind.binaryOp.right);
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
                try self.appendPosition(e.position);
            },
            .exprs => for (e.kind.exprs, 0..) |expr, index| {
                if (index > 0) {
                    try self.buffer.append(@intFromEnum(Op.discard));
                }
                try self.compileExpr(expr);
            },
            .idDeclaration => {
                try self.compileExpr(e.kind.idDeclaration.value);
                try self.appendPushLiteralString(e.kind.idDeclaration.name.slice());
                try self.buffer.append(@intFromEnum(Op.bind));
            },
            .identifier => {
                try self.buffer.append(@intFromEnum(Op.push_identifier));
                try self.appendString(e.kind.identifier.slice());
                try self.appendPosition(e.position);
            },
            .ifte => {
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

                    if (case.condition == null) {
                        try self.compileExpr(case.then);
                        try self.buffer.append(@intFromEnum(Op.jmp));
                        try endPatches.append(self.buffer.items.len);
                        try self.appendInt(0);
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

                if (previousPatch != null) {
                    try self.appendIntAt(@intCast(self.buffer.items.len), previousPatch.?);
                }
                try self.buffer.append(@intFromEnum(Op.push_unit));
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
            else => {
                std.debug.panic("Unhandled: {}", .{e.kind});
                unreachable;
            },
        }
    }

    fn compileCodeBlock(self: *Compiler, block: *AST.Expression) !void {
        // std.io.getStdOut().writer().print("Compiling code block: ip: {d}\n", .{self.buffer.items.len}) catch {};

        var compiler = Compiler.init(self.allocator);
        defer compiler.deinit();

        const bc = try compiler.compile(block);
        defer self.allocator.free(bc);

        try self.appendInt(@intCast(bc.len));
        try self.buffer.appendSlice(bc);
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

    fn appendString(self: *Compiler, s: []const u8) !void {
        try self.appendInt(@intCast(s.len));
        try self.buffer.appendSlice(s);
    }

    fn appendPosition(self: *Compiler, position: Errors.Position) !void {
        try self.appendInt(@intCast(position.start));
        try self.appendInt(@intCast(position.end));
    }
};
