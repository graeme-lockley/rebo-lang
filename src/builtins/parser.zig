const std = @import("std");

const AST = @import("./../ast.zig");
const Helper = @import("./helper.zig");
const Parser = @import("./../ast-interpreter.zig");

pub fn parse(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const options = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.RecordKind, Helper.ValueValue.UnitKind });

    const ast = try Parser.parse(machine, "input", v.v.StringKind.slice());
    defer ast.destroy(machine.allocator);

    const position = try Helper.booleanOption(machine.stringPool, options, "position", false);

    try emit(machine, ast, position);
}
const pos = Helper.Errors.Position{ .start = 0, .end = 0 };

fn emit(machine: *Helper.Runtime, ast: *AST.Expression, position: bool) !void {
    switch (ast.kind) {
        .binaryOp => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("binaryOp");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("op");
            try machine.pushStringValue(ast.kind.binaryOp.op.toString());
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("lhs");
            try emit(machine, ast.kind.binaryOp.left, position);
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("rhs");
            try emit(machine, ast.kind.binaryOp.right, position);
            try machine.setRecordItemBang(pos);
        },
        .exprs => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("exprs");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("value");
            try machine.pushEmptySequenceValue();
            for (ast.kind.exprs) |expr| {
                try emit(machine, expr, position);
                try machine.appendSequenceItemBang(pos);
            }
            try machine.setRecordItemBang(pos);
        },
        .literalInt => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("literalInt");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("value");
            try machine.pushIntValue(ast.kind.literalInt);
            try machine.setRecordItemBang(pos);
        },
        else => {
            std.io.getStdErr().writer().print("unreachable: {}\n", .{ast.kind}) catch {};
            unreachable;
        },
    }

    if (position) {
        try machine.pushStringValue("position");
        try machine.pushEmptySequenceValue();
        try machine.pushIntValue(@intCast(ast.position.start));
        try machine.appendSequenceItemBang(pos);
        try machine.pushIntValue(@intCast(ast.position.end));
        try machine.appendSequenceItemBang(pos);
        try machine.setRecordItemBang(pos);
    }
}
