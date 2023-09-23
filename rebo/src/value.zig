const std = @import("std");

const AST = @import("./ast.zig");

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
            .BoolKind, .CharKind, .IntKind, .FloatKind, .VoidKind => {},
            .FunctionKind => {
                for (self.v.FunctionKind.arguments) |argument| {
                    allocator.free(argument.name);
                }
                allocator.free(self.v.FunctionKind.arguments);

                // This is a problem - an AST is part of a value and therefore needs to be under control of the garbage collector.
                // At the moment, this is not possible as the AST is managed as general memory.
                // AST.destroy(allocator, self.v.FunctionKind.body);
            },
            .SequenceKind => allocator.free(self.v.SequenceKind),
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

    fn appendValue(self: *Value, buffer: *std.ArrayList(u8)) !void {
        // std.debug.print("appending {}\n", .{self});

        switch (self.v) {
            .BoolKind => try buffer.appendSlice(if (self.v.BoolKind) "true" else "false"),
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
            .ScopeKind => {
                var first = true;
                var runner: ?*Value = self;

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
                var i: usize = 0;
                for (self.v.SequenceKind) |v| {
                    if (i != 0) {
                        try buffer.appendSlice(", ");
                    }

                    try v.appendValue(buffer);

                    i += 1;
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
    CharKind,
    FunctionKind,
    IntKind,
    FloatKind,
    SequenceKind,
    StringKind,
    RecordKind,
    ScopeKind,
    VoidKind,

    pub fn toString(self: ValueKind) []const u8 {
        return switch (self) {
            ValueKind.BoolKind => "Bool",
            ValueKind.CharKind => "Chal",
            ValueKind.FunctionKind => "Function",
            ValueKind.FloatKind => "Float",
            ValueKind.IntKind => "Int",
            ValueKind.SequenceKind => "Sequence",
            ValueKind.StringKind => "String",
            ValueKind.RecordKind => "Record",
            ValueKind.ScopeKind => "Scope",
            ValueKind.VoidKind => "()",
        };
    }
};

pub const ValueValue = union(ValueKind) {
    BoolKind: bool,
    CharKind: u8,
    FunctionKind: FunctionValue,
    IntKind: IntType,
    FloatKind: FloatType,
    SequenceKind: []*Value,
    StringKind: []u8,
    RecordKind: std.StringHashMap(*Value),
    ScopeKind: ScopeValue,
    VoidKind: void,
};

pub const FunctionValue = struct {
    scope: ?*Value,
    arguments: []FunctionArgument,
    body: *AST.Expression,
};

pub const FunctionArgument = struct {
    name: []u8,
    default: ?*Value,
};

pub const ScopeValue = struct {
    parent: ?*Value,
    values: std.StringHashMap(*Value),
};
