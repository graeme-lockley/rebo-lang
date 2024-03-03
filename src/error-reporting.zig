const AST = @import("ast.zig");
const Errors = @import("errors.zig");
const Runtime = @import("runtime.zig");
const V = @import("value.zig");
pub const appendErrorPosition = @import("./builtins/errors.zig").appendErrorPosition;
const appendErrorStackItem = @import("./builtins/errors.zig").appendErrorStackItem;

pub fn parserErrorHandler(runtime: *Runtime.Runtime, err: Errors.ParserErrors, e: Errors.Error) !void {
    switch (err) {
        Errors.ParserErrors.FunctionValueExpectedError => {
            _ = try pushNamedUserError(runtime, "FunctionValueExpectedError", null);
            try appendErrorStackItem(runtime, e.stackItem);
        },
        Errors.ParserErrors.LiteralIntError => _ = try raiseNamedUserErrorFromError(runtime, "LiteralIntOverflowError", "value", e.detail.LiteralIntOverflowKind.lexeme, e),
        Errors.ParserErrors.LiteralFloatError => _ = try raiseNamedUserErrorFromError(runtime, "LiteralFloatOverflowError", "value", e.detail.LiteralFloatOverflowKind.lexeme, e),
        Errors.ParserErrors.SyntaxError => {
            const rec = try raiseNamedUserErrorFromError(runtime, "SyntaxError", "found", e.detail.ParserKind.lexeme, e);

            const expected = try runtime.newEmptySequenceValue();
            try rec.v.RecordKind.setU8(runtime.stringPool, "expected", expected);

            for (e.detail.ParserKind.expected) |vk| {
                try expected.v.SequenceKind.appendItem(try runtime.newStringValue(vk.toString()));
            }
        },
        Errors.ParserErrors.LexicalError => _ = try raiseNamedUserErrorFromError(runtime, "LexicalError", "found", e.detail.LexicalKind.lexeme, e),
        else => unreachable,
    }
}

fn raiseNamedUserErrorFromError(runtime: *Runtime.Runtime, kind: []const u8, name: []const u8, value: []const u8, e: Errors.Error) !*V.Value {
    const rec = try pushNamedUserError(runtime, kind, null);

    try rec.v.RecordKind.setU8(runtime.stringPool, name, try runtime.newStringValue(value));
    try rec.v.RecordKind.setU8(runtime.stringPool, "stack", try runtime.newEmptySequenceValue());
    try appendErrorStackItem(runtime, e.stackItem);

    return rec;
}

pub fn pushNamedUserError(runtime: *Runtime.Runtime, name: []const u8, position: ?Errors.Position) !*V.Value {
    try runtime.pushEmptyRecordValue();
    const record = runtime.peek(0);

    try record.v.RecordKind.setU8(runtime.stringPool, "kind", try runtime.newStringValue(name));
    try appendErrorPosition(runtime, position);

    return record;
}

pub fn raiseNamedUserError(runtime: *Runtime.Runtime, name: []const u8, position: ?Errors.Position) !void {
    _ = try pushNamedUserError(runtime, name, position);
    return Errors.RuntimeErrors.InterpreterError;
}

pub fn raiseExpectedTypeError(runtime: *Runtime.Runtime, position: ?Errors.Position, expected: []const V.ValueKind, found: V.ValueKind) !void {
    const rec = try pushNamedUserError(runtime, "ExpectedTypeError", position);

    try rec.v.RecordKind.setU8(runtime.stringPool, "found", try runtime.newStringValue(found.toString()));
    const expectedSeq = try runtime.newEmptySequenceValue();
    try rec.v.RecordKind.setU8(runtime.stringPool, "expected", expectedSeq);

    for (expected) |vk| {
        try expectedSeq.v.SequenceKind.appendItem(try runtime.newStringValue(vk.toString()));
    }

    return Errors.RuntimeErrors.InterpreterError;
}

pub fn raiseIncompatibleOperandTypesError(runtime: *Runtime.Runtime, position: Errors.Position, op: AST.Operator, left: V.ValueKind, right: V.ValueKind) !void {
    const rec = try pushNamedUserError(runtime, "IncompatibleOperandTypesError", position);

    try rec.v.RecordKind.setU8(runtime.stringPool, "op", try runtime.newStringValue(op.toString()));
    try rec.v.RecordKind.setU8(runtime.stringPool, "left", try runtime.newStringValue(left.toString()));
    try rec.v.RecordKind.setU8(runtime.stringPool, "right", try runtime.newStringValue(right.toString()));

    return Errors.RuntimeErrors.InterpreterError;
}

pub fn raiseIndexOutOfRangeError(runtime: *Runtime.Runtime, position: Errors.Position, index: V.IntType, len: V.IntType) !void {
    const rec = try pushNamedUserError(runtime, "IndexOutOfRangeError", position);

    try rec.v.RecordKind.setU8(runtime.stringPool, "index", try runtime.newIntValue(index));
    try rec.v.RecordKind.setU8(runtime.stringPool, "lower", try runtime.newIntValue(0));
    try rec.v.RecordKind.setU8(runtime.stringPool, "upper", try runtime.newIntValue(len));

    return Errors.RuntimeErrors.InterpreterError;
}

pub fn raiseMatchError(runtime: *Runtime.Runtime, position: Errors.Position, value: *V.Value) !void {
    const rec = try pushNamedUserError(runtime, "MatchError", position);

    try rec.v.RecordKind.setU8(runtime.stringPool, "value", value);

    return Errors.RuntimeErrors.InterpreterError;
}
