const std = @import("std");

const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const Machine = @import("./machine.zig").Machine;

pub const IntType = i64;
pub const FloatType = f64;

pub const Colour = enum(u2) {
    Black = 0,
    White = 1,
};

pub const Value = struct {
    colour: Colour,
    next: ?*Value,

    v: ValueValue,

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.v) {
            .BoolKind, .BuiltinKind, .CharKind, .IntKind, .FloatKind, .VoidKind => {},
            .FileKind => self.v.FileKind.deinit(),
            .FunctionKind => {
                for (self.v.FunctionKind.arguments) |argument| {
                    allocator.free(argument.name);
                }
                if (self.v.FunctionKind.restOfArguments != null) {
                    allocator.free(self.v.FunctionKind.restOfArguments.?);
                }
                allocator.free(self.v.FunctionKind.arguments);

                // This is a problem - an AST is part of a value and therefore needs to be under control of the garbage collector.
                // At the moment, this is not possible as the AST is managed as general memory.
                // AST.destroy(allocator, self.v.FunctionKind.body);
            },
            .SequenceKind => self.v.SequenceKind.destroy(),
            .StreamKind => self.v.StreamKind.deinit(),
            .StringKind => allocator.free(self.v.StringKind),
            .RecordKind => {
                var iterator = self.v.RecordKind.keyIterator();
                while (iterator.next()) |keyPtr| {
                    allocator.free(keyPtr.*);
                }
                self.v.RecordKind.deinit();
            },
            .ScopeKind => {
                var iterator = self.v.ScopeKind.values.keyIterator();
                while (iterator.next()) |keyPtr| {
                    allocator.free(keyPtr.*);
                }
                self.v.ScopeKind.values.deinit();
            },
        }
    }

    pub fn appendValue(self: *const Value, buffer: *std.ArrayList(u8)) !void {
        // std.debug.print("appending {}\n", .{self});

        switch (self.v) {
            .BoolKind => try buffer.appendSlice(if (self.v.BoolKind) "true" else "false"),
            .BuiltinKind => {
                try buffer.appendSlice("bfn(");
                var i: usize = 0;
                for (self.v.BuiltinKind.arguments) |argument| {
                    if (i != 0) {
                        try buffer.appendSlice(", ");
                    }

                    try buffer.appendSlice(argument.name);
                    if (argument.default != null) {
                        try buffer.appendSlice(" = ");
                        try argument.default.?.appendValue(buffer);
                    }

                    i += 1;
                }
                if (self.v.BuiltinKind.restOfArguments != null) {
                    if (i != 0) {
                        try buffer.appendSlice(", ");
                    }

                    try buffer.appendSlice("...");
                    try buffer.appendSlice(self.v.BuiltinKind.restOfArguments.?);
                }
                try buffer.append(')');
            },
            .CharKind => {
                if (self.v.CharKind == 10) {
                    try buffer.appendSlice("'\\n'");
                } else if (self.v.CharKind == 39) {
                    try buffer.appendSlice("'\\''");
                } else if (self.v.CharKind == 92) {
                    try buffer.appendSlice("'\\\\'");
                } else if (self.v.CharKind < 32) {
                    try std.fmt.format(buffer.writer(), "'\\x{d}'", .{self.v.CharKind});
                } else {
                    try std.fmt.format(buffer.writer(), "'{c}'", .{self.v.CharKind});
                }
            },
            .FileKind => try std.fmt.format(buffer.writer(), "<file: {d} {s}>", .{ self.v.FileKind.file.handle, if (self.v.FileKind.isOpen) "open" else "closed" }),
            .FloatKind => try std.fmt.format(buffer.writer(), "{d}", .{self.v.FloatKind}),
            .FunctionKind => {
                try buffer.appendSlice("fn(");
                var i: usize = 0;
                for (self.v.FunctionKind.arguments) |argument| {
                    if (i != 0) {
                        try buffer.appendSlice(", ");
                    }

                    try buffer.appendSlice(argument.name);
                    if (argument.default != null) {
                        try buffer.appendSlice(" = ");
                        try argument.default.?.appendValue(buffer);
                    }

                    i += 1;
                }
                if (self.v.FunctionKind.restOfArguments != null) {
                    if (i != 0) {
                        try buffer.appendSlice(", ");
                    }

                    try buffer.appendSlice("...");
                    try buffer.appendSlice(self.v.FunctionKind.restOfArguments.?);
                }
                try buffer.append(')');
            },
            .IntKind => try std.fmt.format(buffer.writer(), "{d}", .{self.v.IntKind}),
            .RecordKind => {
                var first = true;

                try buffer.append('{');
                var iterator = self.v.RecordKind.iterator();
                while (iterator.next()) |entry| {
                    if (first) {
                        first = false;
                    } else {
                        try buffer.appendSlice(", ");
                    }

                    try buffer.appendSlice(entry.key_ptr.*);
                    try buffer.appendSlice(": ");
                    try entry.value_ptr.*.appendValue(buffer);
                }
                try buffer.append('}');
            },
            .StreamKind => try std.fmt.format(buffer.writer(), "<stream: {d} {s}>", .{ self.v.StreamKind.stream.handle, if (self.v.StreamKind.isOpen) "open" else "closed" }),
            .ScopeKind => {
                var first = true;
                var runner: ?*const Value = self;

                try buffer.append('<');
                while (true) {
                    if (first) {
                        first = false;
                    } else {
                        try buffer.append(' ');
                    }

                    try buffer.append('{');
                    var innerFirst = true;
                    var iterator = runner.?.v.ScopeKind.values.iterator();
                    while (iterator.next()) |entry| {
                        if (innerFirst) {
                            innerFirst = false;
                        } else {
                            try buffer.appendSlice(", ");
                        }
                        try buffer.appendSlice(entry.key_ptr.*);
                        try buffer.appendSlice(": ");
                        try entry.value_ptr.*.appendValue(buffer);
                    }
                    try buffer.append('}');

                    if (runner.?.v.ScopeKind.parent == null) {
                        break;
                    }

                    runner = runner.?.v.ScopeKind.parent;
                }
                try buffer.append('>');
            },
            .SequenceKind => {
                try buffer.append('[');
                for (self.v.SequenceKind.items(), 0..) |v, i| {
                    if (i != 0) {
                        try buffer.appendSlice(", ");
                    }

                    try v.appendValue(buffer);
                }
                try buffer.append(']');
            },
            .StringKind => {
                try buffer.append('"');
                for (self.v.StringKind) |c| {
                    if (c == 10) {
                        try buffer.appendSlice("\\n");
                    } else if (c == 34) {
                        try buffer.appendSlice("\\\"");
                    } else if (c == 92) {
                        try buffer.appendSlice("\\\\");
                    } else if (c < 32) {
                        try std.fmt.format(buffer.writer(), "\\x{d};", .{c});
                    } else {
                        try buffer.append(c);
                    }
                }
                try buffer.append('"');
            },
            .VoidKind => try buffer.appendSlice("()"),
        }
    }

    pub fn toString(self: *Value, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        try self.appendValue(&buffer);

        return buffer.toOwnedSlice();
    }
};

pub const ValueKind = enum {
    BoolKind,
    BuiltinKind,
    CharKind,
    FileKind,
    FunctionKind,
    IntKind,
    FloatKind,
    SequenceKind,
    StreamKind,
    StringKind,
    RecordKind,
    ScopeKind,
    VoidKind,

    pub fn toString(self: ValueKind) []const u8 {
        return switch (self) {
            ValueKind.BoolKind => "Bool",
            ValueKind.BuiltinKind => "Function",
            ValueKind.CharKind => "Char",
            ValueKind.FileKind => "File",
            ValueKind.FunctionKind => "Function",
            ValueKind.FloatKind => "Float",
            ValueKind.IntKind => "Int",
            ValueKind.SequenceKind => "Sequence",
            ValueKind.StreamKind => "Stream",
            ValueKind.StringKind => "String",
            ValueKind.RecordKind => "Record",
            ValueKind.ScopeKind => "Scope",
            ValueKind.VoidKind => "()",
        };
    }
};

pub const ValueValue = union(ValueKind) {
    BoolKind: bool,
    BuiltinKind: BuiltinValue,
    CharKind: u8,
    FileKind: FileValue,
    FunctionKind: FunctionValue,
    IntKind: IntType,
    FloatKind: FloatType,
    SequenceKind: SequenceValue,
    StreamKind: StreamValue,
    StringKind: []u8,
    RecordKind: std.StringHashMap(*Value),
    ScopeKind: ScopeValue,
    VoidKind: void,
};

pub const BuiltinValue = struct {
    arguments: []const FunctionArgument,
    restOfArguments: ?[]const u8,
    body: *const fn (machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) Errors.err!void,
};

pub fn recordGet(record: *const std.StringHashMap(*Value), key: []const u8) ?*Value {
    return record.get(key);
}

pub fn recordSet(allocator: std.mem.Allocator, record: *std.StringHashMap(*Value), key: []const u8, value: *Value) !void {
    if (value.v == ValueKind.VoidKind) {
        const old = record.fetchRemove(key);

        if (old != null) {
            allocator.free(old.?.key);
        }
    } else {
        const oldKey = record.getKey(key);

        if (oldKey == null) {
            try record.put(try allocator.dupe(u8, key), value);
        } else {
            try record.put(oldKey.?, value);
        }
    }
}

pub const FileValue = struct {
    isOpen: bool,
    file: std.fs.File,

    pub fn init(file: std.fs.File) FileValue {
        return FileValue{
            .isOpen = true,
            .file = file,
        };
    }

    pub fn deinit(self: *FileValue) void {
        self.close();
    }

    pub fn close(self: *FileValue) void {
        if (self.isOpen) {
            self.file.close();
            self.isOpen = false;
        }
    }
};

pub const FunctionValue = struct {
    scope: ?*Value,
    arguments: []FunctionArgument,
    restOfArguments: ?[]u8,
    body: *AST.Expression,
};

pub const FunctionArgument = struct {
    name: []const u8,
    default: ?*Value,
};

pub const SequenceValue = struct {
    values: std.ArrayList(*Value),

    pub fn init(allocator: std.mem.Allocator) !SequenceValue {
        var result = SequenceValue{
            .values = std.ArrayList(*Value).init(allocator),
        };

        return result;
    }

    pub fn destroy(self: *SequenceValue) void {
        self.values.deinit();
    }

    pub fn append(self: *SequenceValue, value: *Value) !void {
        try self.values.append(value);
    }

    pub fn prepend(self: *SequenceValue, value: *Value) !void {
        try self.values.insert(0, value);
    }

    pub fn appendSlice(self: *SequenceValue, values: []const *Value) !void {
        try self.values.appendSlice(values);
    }

    pub fn replaceSlice(self: *SequenceValue, values: []*Value) !void {
        self.values.clearAndFree();
        try self.values.appendSlice(values);
    }

    pub fn replaceRange(self: *SequenceValue, start: usize, end: usize, values: []*Value) !void {
        try self.values.replaceRange(start, end - start, values);
    }

    pub fn len(self: *const SequenceValue) usize {
        return self.values.items.len;
    }

    pub fn items(self: *const SequenceValue) []*Value {
        return self.values.items;
    }

    pub fn at(self: *const SequenceValue, i: usize) *Value {
        return self.values.items[i];
    }

    pub fn set(self: *const SequenceValue, i: usize, v: *Value) void {
        self.values.items[i] = v;
    }
};

pub const StreamValue = struct {
    isOpen: bool,
    stream: std.net.Stream,

    pub fn init(stream: std.net.Stream) StreamValue {
        return StreamValue{
            .isOpen = true,
            .stream = stream,
        };
    }

    pub fn deinit(self: *StreamValue) void {
        self.close();
    }

    pub fn close(self: *StreamValue) void {
        if (self.isOpen) {
            self.stream.close();
            self.isOpen = false;
        }
    }
};

pub const ScopeValue = struct {
    parent: ?*Value,
    values: std.StringHashMap(*Value),
};

pub fn eq(a: *Value, b: *Value) bool {
    if (@intFromPtr(a) == @intFromPtr(b)) return true;
    if (@intFromEnum(a.v) != @intFromEnum(b.v)) {
        switch (a.v) {
            .IntKind => {
                switch (b.v) {
                    .IntKind => return a.v.IntKind == b.v.IntKind,
                    .FloatKind => return @as(FloatType, @floatFromInt(a.v.IntKind)) == b.v.FloatKind,
                    else => {
                        return false;
                    },
                }
            },
            .FloatKind => {
                switch (b.v) {
                    .IntKind => return a.v.FloatKind == @as(FloatType, @floatFromInt(b.v.IntKind)),
                    .FloatKind => return a.v.FloatKind == b.v.FloatKind,
                    else => {
                        return false;
                    },
                }
            },
            else => {
                return false;
            },
        }
    }

    switch (a.v) {
        .BoolKind => return a.v.BoolKind == b.v.BoolKind,
        .BuiltinKind => return @intFromPtr(a) == @intFromPtr(b),
        .CharKind => return a.v.CharKind == b.v.CharKind,
        .FileKind => return a.v.FileKind.file.handle == b.v.FileKind.file.handle,
        .FunctionKind => return @intFromPtr(a) == @intFromPtr(b),
        .IntKind => return a.v.IntKind == b.v.IntKind,
        .FloatKind => return a.v.FloatKind == b.v.FloatKind,
        .SequenceKind => {
            if (a.v.SequenceKind.len() != b.v.SequenceKind.len()) return false;

            for (a.v.SequenceKind.items(), 0..) |v, i| {
                if (!eq(v, b.v.SequenceKind.at(i))) return false;
            }

            return true;
        },
        .StreamKind => return a.v.StreamKind.stream.handle == b.v.StreamKind.stream.handle,
        .StringKind => {
            if (a.v.StringKind.len != b.v.StringKind.len) return false;

            for (a.v.StringKind, 0..) |c, i| {
                if (c != b.v.StringKind[i]) return false;
            }

            return true;
        },
        .RecordKind => {
            if (a.v.RecordKind.count() != b.v.RecordKind.count()) return false;

            var iterator = a.v.RecordKind.iterator();
            while (iterator.next()) |entry| {
                var value = b.v.RecordKind.get(entry.key_ptr.*);
                if (value == null) return false;

                if (!eq(entry.value_ptr.*, value.?)) return false;
            }

            return true;
        },
        .ScopeKind => {
            if (a.v.ScopeKind.values.count() != b.v.ScopeKind.values.count()) return false;

            var iterator = a.v.ScopeKind.values.iterator();
            while (iterator.next()) |entry| {
                var value = b.v.ScopeKind.values.get(entry.key_ptr.*);
                if (value == null) return false;

                if (!eq(entry.value_ptr.*, value.?)) return false;
            }

            return true;
        },
        .VoidKind => return true,
    }
}

pub fn clamp(value: IntType, min: IntType, max: IntType) IntType {
    if (value < min) {
        return min;
    } else if (value > max) {
        return max;
    } else {
        return value;
    }
}
