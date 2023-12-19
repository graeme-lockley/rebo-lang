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

pub const Style = enum(u2) {
    Pretty = 0,
    Raw = 1,
};

pub const Value = struct {
    colour: Colour,
    next: ?*Value,

    v: ValueValue,

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.v) {
            .BoolKind, .BuiltinKind, .CharKind, .IntKind, .FloatKind, .UnitKind => {},
            .FileKind => self.v.FileKind.deinit(),
            .FunctionKind => self.v.FunctionKind.deinit(allocator),
            .SequenceKind => self.v.SequenceKind.deinit(),
            .StreamKind => self.v.StreamKind.deinit(),
            .StringKind => StringValue.deinit(self.v.StringKind, allocator),
            .RecordKind => self.v.RecordKind.deinit(allocator),
            .ScopeKind => self.v.ScopeKind.deinit(allocator),
        }
    }

    pub fn appendValue(self: *const Value, buffer: *std.ArrayList(u8), style: Style) !void {
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
                        try argument.default.?.appendValue(buffer, style);
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
                switch (style) {
                    Style.Pretty => if (self.v.CharKind == 10) {
                        try buffer.appendSlice("'\\n'");
                    } else if (self.v.CharKind == 39) {
                        try buffer.appendSlice("'\\''");
                    } else if (self.v.CharKind == 92) {
                        try buffer.appendSlice("'\\\\'");
                    } else if (self.v.CharKind < 32) {
                        try std.fmt.format(buffer.writer(), "'\\x{d}'", .{self.v.CharKind});
                    } else {
                        try std.fmt.format(buffer.writer(), "'{c}'", .{self.v.CharKind});
                    },
                    Style.Raw => try buffer.append(self.v.CharKind),
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
                        try argument.default.?.appendValue(buffer, style);
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
                    try entry.value_ptr.*.appendValue(buffer, style);
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
                        try entry.value_ptr.*.appendValue(buffer, style);
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
                switch (style) {
                    Style.Pretty => {
                        try buffer.append('[');
                        for (self.v.SequenceKind.items(), 0..) |v, i| {
                            if (i != 0) {
                                try buffer.appendSlice(", ");
                            }

                            try v.appendValue(buffer, style);
                        }
                        try buffer.append(']');
                    },
                    Style.Raw => for (self.v.SequenceKind.items()) |v| {
                        try v.appendValue(buffer, style);
                    },
                }
            },
            .StringKind => {
                switch (style) {
                    Style.Pretty => {
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
                    Style.Raw => try buffer.appendSlice(self.v.StringKind),
                }
            },
            .UnitKind => try buffer.appendSlice("()"),
        }
    }

    pub fn toString(self: *Value, allocator: std.mem.Allocator, style: Style) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        try self.appendValue(&buffer, style);

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
    UnitKind,

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
            ValueKind.UnitKind => "()",
        };
    }
};

pub const ValueValue = union(ValueKind) {
    BoolKind: bool,
    BuiltinKind: BuiltinValue,
    CharKind: u8,
    FileKind: FileValue,
    FloatKind: FloatType,
    FunctionKind: FunctionValue,
    IntKind: IntType,
    RecordKind: RecordValue,
    ScopeKind: ScopeValue,
    SequenceKind: SequenceValue,
    StreamKind: StreamValue,
    StringKind: []u8,
    UnitKind: void,
};

pub const BuiltinValue = struct {
    arguments: []const FunctionArgument,
    restOfArguments: ?[]const u8,
    body: *const fn (machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) Errors.err!void,
};

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

    pub fn deinit(self: *FunctionValue, allocator: std.mem.Allocator) void {
        for (self.arguments) |argument| {
            allocator.free(argument.name);
        }
        if (self.restOfArguments != null) {
            allocator.free(self.restOfArguments.?);
        }
        allocator.free(self.arguments);

        // This is a problem - an AST is part of a value and therefore needs to be under control of the garbage collector.
        // At the moment, this is not possible as the AST is managed as general memory.
        // AST.destroy(allocator, self.v.FunctionKind.body);
    }
};

pub const FunctionArgument = struct {
    name: []const u8,
    default: ?*Value,
};

pub const RecordValue = struct {
    items: std.StringHashMap(*Value),

    pub fn init(allocator: std.mem.Allocator) RecordValue {
        return RecordValue{ .items = std.StringHashMap(*Value).init(allocator) };
    }

    pub fn deinit(self: *RecordValue, allocator: std.mem.Allocator) void {
        var itrtr = self.keyIterator();
        while (itrtr.next()) |keyPtr| {
            allocator.free(keyPtr.*);
        }
        self.items.deinit();
    }

    pub fn set(self: *RecordValue, allocator: std.mem.Allocator, key: []const u8, value: *Value) !void {
        if (value.v == ValueKind.UnitKind) {
            const old = self.items.fetchRemove(key);

            if (old != null) {
                allocator.free(old.?.key);
            }
        } else {
            const oldKey = self.items.getKey(key);

            if (oldKey == null) {
                try self.items.put(try allocator.dupe(u8, key), value);
            } else {
                try self.items.put(oldKey.?, value);
            }
        }
    }

    pub fn get(self: *const RecordValue, key: []const u8) ?*Value {
        return self.items.get(key);
    }

    pub fn count(self: *const RecordValue) usize {
        return self.items.count();
    }

    pub fn iterator(self: *const RecordValue) std.StringHashMap(*Value).Iterator {
        return self.items.iterator();
    }

    pub fn keyIterator(self: *const RecordValue) std.StringHashMap(*Value).KeyIterator {
        return self.items.keyIterator();
    }
};

pub const SequenceValue = struct {
    values: std.ArrayList(*Value),

    pub fn init(allocator: std.mem.Allocator) !SequenceValue {
        var result = SequenceValue{
            .values = std.ArrayList(*Value).init(allocator),
        };

        return result;
    }

    pub fn deinit(self: *SequenceValue) void {
        self.values.deinit();
    }

    pub fn appendItem(self: *SequenceValue, value: *Value) !void {
        try self.values.append(value);
    }

    pub fn prependItem(self: *SequenceValue, value: *Value) !void {
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

    pub fn removeRange(self: *SequenceValue, start: usize, end: usize) !void {
        const values = &[_]*Value{};

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

pub const StringValue = struct {
    pub fn init(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
        return try allocator.dupe(u8, value);
    }

    pub fn deinit(self: []u8, allocator: std.mem.Allocator) void {
        allocator.free(self);
    }
};

pub const ScopeValue = struct {
    parent: ?*Value,
    values: std.StringHashMap(*Value),

    pub fn deinit(self: *ScopeValue, allocator: std.mem.Allocator) void {
        var iterator = self.values.keyIterator();
        while (iterator.next()) |keyPtr| {
            allocator.free(keyPtr.*);
        }

        self.values.deinit();
    }
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
        .UnitKind => return true,
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
