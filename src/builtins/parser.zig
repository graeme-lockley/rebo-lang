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
        .ifte => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("ifThenElse");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("cases");
            try machine.pushEmptySequenceValue();
            for (ast.kind.ifte) |value| {
                try machine.pushEmptyRecordValue();
                if (value.condition != null) {
                    try machine.pushStringValue("condition");
                    try emit(machine, value.condition.?, position);
                    try machine.setRecordItemBang(pos);
                }
                try machine.pushStringValue("then");
                try emit(machine, value.then, position);
                try machine.setRecordItemBang(pos);

                try machine.appendSequenceItemBang(pos);
            }
            try machine.setRecordItemBang(pos);
        },
        .indexRange => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("indexRange");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("expr");
            try emit(machine, ast.kind.indexRange.expr, position);
            try machine.setRecordItemBang(pos);

            if (ast.kind.indexRange.start != null) {
                try machine.pushStringValue("start");
                try emit(machine, ast.kind.indexRange.start.?, position);
                try machine.setRecordItemBang(pos);
            }
            if (ast.kind.indexRange.end != null) {
                try machine.pushStringValue("end");
                try emit(machine, ast.kind.indexRange.end.?, position);
                try machine.setRecordItemBang(pos);
            }
        },
        .indexValue => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("indexValue");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("expr");
            try emit(machine, ast.kind.indexValue.expr, position);
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("index");
            try emit(machine, ast.kind.indexValue.index, position);
            try machine.setRecordItemBang(pos);
        },
        .literalBool => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("literalBool");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("value");
            try machine.pushBoolValue(ast.kind.literalBool);
            try machine.setRecordItemBang(pos);
        },
        .literalChar => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("literalChar");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("value");
            try machine.pushCharValue(ast.kind.literalChar);
            try machine.setRecordItemBang(pos);
        },
        .literalFunction => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("literalFunction");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("params");
            try machine.pushEmptySequenceValue();
            for (ast.kind.literalFunction.params) |param| {
                try machine.pushEmptyRecordValue();
                try machine.pushStringValue("name");
                try machine.pushStringValue(param.name.slice());
                try machine.setRecordItemBang(pos);

                if (param.default != null) {
                    try machine.pushStringValue("default");
                    try emit(machine, param.default.?, position);
                    try machine.setRecordItemBang(pos);
                }

                try machine.appendSequenceItemBang(pos);
            }
            try machine.setRecordItemBang(pos);

            if (ast.kind.literalFunction.restOfParams != null) {
                try machine.pushStringValue("restOfParams");
                try machine.pushStringValue(ast.kind.literalFunction.restOfParams.?.slice());
                try machine.setRecordItemBang(pos);
            }

            try machine.pushStringValue("body");
            try emit(machine, ast.kind.literalFunction.body, position);
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
        .literalFloat => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("literalFloat");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("value");
            try machine.pushFloatValue(ast.kind.literalFloat);
            try machine.setRecordItemBang(pos);
        },
        .literalRecord => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("literalRecord");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("fields");
            try machine.pushEmptySequenceValue();
            for (ast.kind.literalRecord) |field| {
                try machine.pushEmptyRecordValue();

                if (field == .value) {
                    try machine.pushStringValue("kind");
                    try machine.pushStringValue("value");
                    try machine.setRecordItemBang(pos);

                    try machine.pushStringValue("key");
                    try machine.pushStringValue(field.value.key.slice());
                    try machine.setRecordItemBang(pos);

                    try machine.pushStringValue("value");
                    try emit(machine, field.value.value, position);
                    try machine.setRecordItemBang(pos);
                } else {
                    try machine.pushStringValue("kind");
                    try machine.pushStringValue("record");
                    try machine.setRecordItemBang(pos);

                    try machine.pushStringValue("value");
                    try emit(machine, field.record, position);
                    try machine.setRecordItemBang(pos);
                }

                try machine.appendSequenceItemBang(pos);
            }
            try machine.setRecordItemBang(pos);
        },
        .literalSequence => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("literalSequence");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("values");
            try machine.pushEmptySequenceValue();
            for (ast.kind.literalSequence) |value| {
                try machine.pushEmptyRecordValue();

                if (value == .value) {
                    try machine.pushStringValue("kind");
                    try machine.pushStringValue("value");
                    try machine.setRecordItemBang(pos);

                    try machine.pushStringValue("value");
                    try emit(machine, value.value, position);
                    try machine.setRecordItemBang(pos);
                } else {
                    try machine.pushStringValue("kind");
                    try machine.pushStringValue("sequence");
                    try machine.setRecordItemBang(pos);

                    try machine.pushStringValue("value");
                    try emit(machine, value.sequence, position);
                    try machine.setRecordItemBang(pos);
                }
                try machine.appendSequenceItemBang(pos);
            }
            try machine.setRecordItemBang(pos);
        },
        .literalString => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("literalString");
            try machine.setRecordItemBang(pos);

            try machine.pushStringValue("value");
            try machine.pushStringValue(ast.kind.literalString.slice());
            try machine.setRecordItemBang(pos);
        },
        .literalVoid => {
            try machine.pushEmptyRecordValue();

            try machine.pushStringValue("kind");
            try machine.pushStringValue("literalUnit");
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
