const Errors = @import("errors.zig");
const Runtime = @import("runtime.zig");
const V = @import("value.zig");

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

fn raiseNamedUserError(runtime: *Runtime.Runtime, name: []const u8, position: ?Errors.Position) !void {
    _ = try pushNamedUserError(runtime, name, position);
    return Errors.RuntimeErrors.InterpreterError;
}

inline fn appendErrorPosition(runtime: *Runtime.Runtime, position: ?Errors.Position) !void {
    if (position != null) {
        try appendErrorStackItem(runtime, Errors.StackItem{ .src = try src(runtime), .position = position.? });
    }
}

fn appendErrorStackItem(runtime: *Runtime.Runtime, stackItem: Errors.StackItem) !void {
    const stack = try getErrorStack(runtime);

    if (stack != null) {
        const frameRecord = try runtime.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(runtime.allocator) });
        try stack.?.v.SequenceKind.appendItem(frameRecord);

        try frameRecord.v.RecordKind.setU8(runtime.stringPool, "file", try runtime.newStringValue(stackItem.src));
        const fromRecord = try runtime.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(runtime.allocator) });
        try frameRecord.v.RecordKind.setU8(runtime.stringPool, "from", fromRecord);

        try fromRecord.v.RecordKind.setU8(runtime.stringPool, "offset", try runtime.newValue(V.ValueValue{ .IntKind = @intCast(stackItem.position.start) }));

        const toRecord = try runtime.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(runtime.allocator) });
        try frameRecord.v.RecordKind.setU8(runtime.stringPool, "to", toRecord);

        try toRecord.v.RecordKind.setU8(runtime.stringPool, "offset", try runtime.newValue(V.ValueValue{ .IntKind = @intCast(stackItem.position.end) }));

        const position = try stackItem.location(runtime.allocator);
        if (position != null) {
            try fromRecord.v.RecordKind.setU8(runtime.stringPool, "line", try runtime.newValue(V.ValueValue{ .IntKind = @intCast(position.?.from.line) }));
            try fromRecord.v.RecordKind.setU8(runtime.stringPool, "column", try runtime.newValue(V.ValueValue{ .IntKind = @intCast(position.?.from.column) }));
            try toRecord.v.RecordKind.setU8(runtime.stringPool, "line", try runtime.newValue(V.ValueValue{ .IntKind = @intCast(position.?.to.line) }));
            try toRecord.v.RecordKind.setU8(runtime.stringPool, "column", try runtime.newValue(V.ValueValue{ .IntKind = @intCast(position.?.to.column) }));
        }
    }
}

fn getErrorStack(runtime: *Runtime.Runtime) !?*V.Value {
    const v = runtime.peek(0);

    if (v.v == V.ValueValue.RecordKind) {
        var record = v.v.RecordKind;

        var stack = try record.getU8(runtime.stringPool, "stack");
        if (stack == null) {
            stack = try runtime.newEmptySequenceValue();
            try record.setU8(runtime.stringPool, "stack", stack.?);
        }
        if (stack.?.v != V.ValueValue.SequenceKind) {
            return null;
        }

        return stack;
    } else {
        return null;
    }
}

fn src(runtime: *Runtime.Runtime) ![]const u8 {
    const result = try runtime.getU8FromScope("__FILE");

    return if (result == null) Errors.STREAM_SRC else if (result.?.v == V.ValueValue.StringKind) result.?.v.StringKind.slice() else Errors.STREAM_SRC;
}
