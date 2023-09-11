const std = @import("std");

const AST = @import("./ast.zig");

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
            .BoolKind, .IntKind, .VoidKind => {},
            .FunctionKind => {
                for (self.v.FunctionKind.arguments) |argument| {
                    allocator.free(argument.name);
                }
                allocator.free(self.v.FunctionKind.arguments);

                // This is a problem - an AST is part of a value and therefore needs to be under control of the garbage collector.
                // At the moment, this is not possible as the AST is managed as general memory.
                // AST.destroy(allocator, self.v.FunctionKind.body);
            },
            .SequenceKind => {
                allocator.free(self.v.SequenceKind);
            },
            .RecordKind => {
                var iterator = self.v.RecordKind.keyIterator();
                while (iterator.next()) |keyPtr| {
                    allocator.free(keyPtr.*);
                }
                self.v.RecordKind.deinit();
            },
        }
    }

    fn appendValue(self: *Value, buffer: *std.ArrayList(u8)) !void {
        switch (self.v) {
            .BoolKind => try buffer.appendSlice(if (self.v.BoolKind) "true" else "false"),
            .FunctionKind => {
                try buffer.appendSlice("fn(");
                for (self.v.FunctionKind.arguments) |argument, i| {
                    if (i != 0) {
                        try buffer.appendSlice(", ");
                    }

                    try buffer.appendSlice(argument.name);
                    if (argument.default != null) {
                        try buffer.appendSlice(" = ");
                        try argument.default.?.appendValue(buffer);
                    }
                }
                try buffer.append(')');
            },
            .IntKind => try std.fmt.format(buffer.writer(), "{d}", .{self.v.IntKind}),
            .SequenceKind => {
                try buffer.append('[');
                for (self.v.SequenceKind) |v, i| {
                    if (i != 0) {
                        try buffer.appendSlice(", ");
                    }

                    try v.appendValue(buffer);
                }
                try buffer.append(']');
            },
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
    FunctionKind,
    IntKind,
    SequenceKind,
    RecordKind,
    VoidKind,

    pub fn toString(self: ValueKind) []const u8 {
        return switch (self) {
            ValueKind.BoolKind => "Bool",
            ValueKind.FunctionKind => "Function",
            ValueKind.IntKind => "Int",
            ValueKind.SequenceKind => "Sequence",
            ValueKind.RecordKind => "Record",
            ValueKind.VoidKind => "()",
        };
    }
};

pub const ValueValue = union(ValueKind) {
    BoolKind: bool,
    FunctionKind: FunctionValue,
    IntKind: i32,
    SequenceKind: []*Value,
    RecordKind: std.StringHashMap(*Value),
    VoidKind: void,
};

pub const FunctionValue = struct {
    arguments: []FunctionArgument,
    body: *AST.Expression,
};

pub const FunctionArgument = struct {
    name: []u8,
    default: ?*Value,
};
