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
        .assignment => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("assignment");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("lhs");
            try emit(machine, ast.kind.assignment.lhs, position);
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("rhs");
            try emit(machine, ast.kind.assignment.rhs, position);
            try machine.setRecordItemBang(pos);
        },
        .binaryOp => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("binaryOp");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("op");
            try machine.pushStringValue(ast.kind.binaryOp.op.toString());
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("lhs");
            try emit(machine, ast.kind.binaryOp.lhs, position);
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("rhs");
            try emit(machine, ast.kind.binaryOp.rhs, position);
            try machine.setRecordItemBang(pos);
        },
        .call => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("call");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("callee");
            try emit(machine, ast.kind.call.callee, position);
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("args");
            try machine.pushEmptySequenceValue();
            for (ast.kind.call.args) |arg| {
                try emit(machine, arg, position);
                try machine.appendSequenceItemBang(pos);
            }
            try machine.setRecordItemBang(pos);
        },
        .catche => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("catche");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("value");
            try emit(machine, ast.kind.catche.value, position);
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("cases");
            try machine.pushEmptySequenceValue();
            for (ast.kind.catche.cases) |case| {
                try machine.pushEmptyRecordValue();

                try machine.pushStringValue("pattern");
                try emitPattern(machine, case.pattern, position);
                try machine.setRecordItemBang(pos);

                try machine.pushStringValue("body");
                try emit(machine, case.body, position);
                try machine.setRecordItemBang(pos);

                try machine.appendSequenceItemBang(pos);
            }
            try machine.setRecordItemBang(pos);
        },
        .dot => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("dot");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("record");
            try emit(machine, ast.kind.dot.record, position);
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("field");
            try machine.pushStringValue(ast.kind.dot.field.slice());
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
        .idDeclaration => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("idDeclaration");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("id");
            try machine.pushStringValue(ast.kind.idDeclaration.name.slice());
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("value");
            try emit(machine, ast.kind.idDeclaration.value, position);
            try machine.setRecordItemBang(pos);
        },
        .identifier => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("identifier");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("value");
            try machine.pushStringValue(ast.kind.identifier.slice());
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

fn emitPattern(machine: *Helper.Runtime, ast: *AST.Pattern, position: bool) !void {
    switch (ast.kind) {
        .identifier => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("identifier");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("value");
            try machine.pushStringValue(ast.kind.identifier.slice());
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
