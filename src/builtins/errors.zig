const std = @import("std");
const Helper = @import("./helper.zig");

// const Debug = @import("../debug.zig");

pub fn appendPosition(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    // Debug.showStack(machine, 4, "appendPosition: before") catch {};

    const v1 = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueKind.UnitKind });
    const v2 = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueKind.UnitKind });

    if (v1.isInt()) {
        if (v2.isInt()) {
            const position = Helper.Errors.Position{ .start = @intCast(v1.v.IntKind), .end = @intCast(v2.v.IntKind) };
            try appendErrorStackItemToStack(machine, try errorStackItem(machine, position), try getErrorStack(machine, 3));
            try machine.push(machine.peek(3));
        } else {
            const position = Helper.Errors.Position{ .start = @intCast(v1.v.IntKind), .end = @intCast(v1.v.IntKind) };
            try appendErrorStackItemToStack(machine, try errorStackItem(machine, position), try getErrorStack(machine, 2));
            try machine.push(machine.peek(2));
        }
    } else {
        try machine.push(machine.peek(1));
    }

    // Debug.showStack(machine, 4, "appendPosition: after") catch {};
}

pub fn appendErrorPosition(runtime: *Helper.Runtime, position: ?Helper.Errors.Position) !void {
    if (position != null) {
        try appendErrorStackItem(runtime, try errorStackItem(runtime, position));
    }
}

fn errorStackItem(runtime: *Helper.Runtime, position: ?Helper.Errors.Position) !Helper.Errors.StackItem {
    return Helper.Errors.StackItem{ .src = try src(runtime), .position = position.? };
}

pub fn appendErrorStackItem(runtime: *Helper.Runtime, stackItem: Helper.Errors.StackItem) !void {
    const stack = try getErrorStack(runtime, 0);

    try appendErrorStackItemToStack(runtime, stackItem, stack);
}

pub fn appendErrorStackItemToStack(runtime: *Helper.Runtime, stackItem: Helper.Errors.StackItem, stack: ?*Helper.V.Value) !void {
    if (stack != null) {
        const frameRecord = try runtime.newValue(Helper.ValueValue{ .RecordKind = Helper.V.RecordValue.init(runtime.allocator) });
        try stack.?.v.SequenceKind.appendItem(frameRecord);

        try frameRecord.v.RecordKind.setU8(runtime.stringPool, "file", try runtime.newStringValue(stackItem.src));
        const fromRecord = try runtime.newValue(Helper.ValueValue{ .RecordKind = Helper.V.RecordValue.init(runtime.allocator) });
        try frameRecord.v.RecordKind.setU8(runtime.stringPool, "from", fromRecord);

        try fromRecord.v.RecordKind.setU8(runtime.stringPool, "offset", try runtime.newValue(Helper.ValueValue{ .IntKind = @intCast(stackItem.position.start) }));

        const toRecord = try runtime.newValue(Helper.ValueValue{ .RecordKind = Helper.V.RecordValue.init(runtime.allocator) });
        try frameRecord.v.RecordKind.setU8(runtime.stringPool, "to", toRecord);

        try toRecord.v.RecordKind.setU8(runtime.stringPool, "offset", try runtime.newValue(Helper.ValueValue{ .IntKind = @intCast(stackItem.position.end) }));

        const position = try stackItem.location(runtime.allocator);
        if (position != null) {
            try fromRecord.v.RecordKind.setU8(runtime.stringPool, "line", try runtime.newValue(Helper.ValueValue{ .IntKind = @intCast(position.?.from.line) }));
            try fromRecord.v.RecordKind.setU8(runtime.stringPool, "column", try runtime.newValue(Helper.ValueValue{ .IntKind = @intCast(position.?.from.column) }));
            try toRecord.v.RecordKind.setU8(runtime.stringPool, "line", try runtime.newValue(Helper.ValueValue{ .IntKind = @intCast(position.?.to.line) }));
            try toRecord.v.RecordKind.setU8(runtime.stringPool, "column", try runtime.newValue(Helper.ValueValue{ .IntKind = @intCast(position.?.to.column) }));
        }
    }
}

fn getErrorStack(runtime: *Helper.Runtime, offset: usize) !?*Helper.Value {
    const v = runtime.peek(offset);

    if (v.v == Helper.ValueValue.RecordKind) {
        var record = v.v.RecordKind;

        var stack = try record.getU8(runtime.stringPool, "stack");
        if (stack == null) {
            stack = try runtime.newEmptySequenceValue();
            try record.setU8(runtime.stringPool, "stack", stack.?);
        }
        if (stack.?.v != Helper.ValueValue.SequenceKind) {
            return null;
        }

        return stack;
    } else {
        return null;
    }
}

fn src(runtime: *Helper.Runtime) ![]const u8 {
    const result = try runtime.getU8FromScope("__FILE");

    return if (result == null) Helper.Errors.STREAM_SRC else if (result.?.v == Helper.ValueValue.StringKind) result.?.v.StringKind.slice() else Helper.Errors.STREAM_SRC;
}
