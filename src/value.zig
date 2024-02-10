const std = @import("std");

const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const ASTInterpreter = @import("./ast-interpreter.zig").ASTInterpreter;
const SP = @import("./string_pool.zig");

pub const IntType = i64;
pub const FloatType = f64;
pub const BuiltinFunctionType = *const fn (ASTInterpreter: *ASTInterpreter, numberOfArguments: usize) Errors.RuntimeErrors!void;

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
            .ASTFunctionKind => self.v.ASTFunctionKind.deinit(allocator),
            .BCFunctionKind => self.v.BCFunctionKind.deinit(allocator),
            .BoolKind, .BuiltinFunctionKind, .CharKind, .IntKind, .FloatKind, .UnitKind => {},
            .FileKind => self.v.FileKind.deinit(),
            .HttpClientKind => self.v.HttpClientKind.deinit(allocator),
            .HttpClientRequestKind => self.v.HttpClientRequestKind.deinit(allocator),
            .SequenceKind => self.v.SequenceKind.deinit(),
            .StreamKind => self.v.StreamKind.deinit(),
            .StringKind => self.v.StringKind.deinit(),
            .RecordKind => self.v.RecordKind.deinit(),
            .ScopeKind => self.v.ScopeKind.deinit(),
        }
    }

    pub fn isBool(self: *Value) bool {
        return self.v == .BoolKind;
    }

    pub fn isInt(self: *Value) bool {
        return self.v == .IntKind;
    }

    pub fn isRecord(self: *Value) bool {
        return self.v == .RecordKind;
    }

    pub fn isSequence(self: *Value) bool {
        return self.v == .SequenceKind;
    }

    pub fn isString(self: *Value) bool {
        return self.v == .StringKind;
    }

    pub fn isUnit(self: *Value) bool {
        return self.v == .UnitKind;
    }

    pub fn appendValue(self: *const Value, buffer: *std.ArrayList(u8), style: Style) !void {
        switch (self.v) {
            .ASTFunctionKind => {
                try buffer.appendSlice("fn(");
                for (self.v.ASTFunctionKind.arguments, 0..) |argument, i| {
                    if (i != 0) {
                        try buffer.appendSlice(", ");
                    }

                    try buffer.appendSlice(argument.name.slice());
                    if (argument.default) |default| {
                        try buffer.appendSlice(" = ");
                        try default.appendValue(buffer, style);
                    }
                }
                if (self.v.ASTFunctionKind.restOfArguments != null) {
                    if (self.v.ASTFunctionKind.arguments.len > 0) {
                        try buffer.appendSlice(", ");
                    }

                    try buffer.appendSlice("...");
                    try buffer.appendSlice(self.v.ASTFunctionKind.restOfArguments.?.slice());
                }
                try buffer.append(')');
            },
            .BCFunctionKind => {
                try buffer.appendSlice("fn(");
                for (self.v.BCFunctionKind.arguments, 0..) |argument, i| {
                    if (i != 0) {
                        try buffer.appendSlice(", ");
                    }

                    try buffer.appendSlice(argument.name.slice());
                    if (argument.default) |default| {
                        try buffer.appendSlice(" = ");
                        try default.appendValue(buffer, style);
                    }
                }
                if (self.v.BCFunctionKind.restOfArguments != null) {
                    if (self.v.BCFunctionKind.arguments.len > 0) {
                        try buffer.appendSlice(", ");
                    }

                    try buffer.appendSlice("...");
                    try buffer.appendSlice(self.v.BCFunctionKind.restOfArguments.?.slice());
                }
                try buffer.append(')');
            },
            .BoolKind => try buffer.appendSlice(if (self.v.BoolKind) "true" else "false"),
            .BuiltinFunctionKind => try buffer.appendSlice("fn(...)"),
            .CharKind => {
                switch (style) {
                    Style.Pretty => switch (self.v.CharKind) {
                        10 => try buffer.appendSlice("'\\n'"),
                        39 => try buffer.appendSlice("'\\''"),
                        92 => try buffer.appendSlice("'\\\\'"),
                        0...9, 11...31 => try std.fmt.format(buffer.writer(), "'\\x{d}'", .{self.v.CharKind}),
                        else => try std.fmt.format(buffer.writer(), "'{c}'", .{self.v.CharKind}),
                    },
                    Style.Raw => try buffer.append(self.v.CharKind),
                }
            },
            .FileKind => try std.fmt.format(buffer.writer(), "<file: {d} {s}>", .{ self.v.FileKind.file.handle, if (self.v.FileKind.isOpen) "open" else "closed" }),
            .FloatKind => try std.fmt.format(buffer.writer(), "{d}", .{self.v.FloatKind}),
            .HttpClientKind => try buffer.appendSlice("<http client>"),
            .HttpClientRequestKind => try std.fmt.format(buffer.writer(), "<http client response {s}>", .{@tagName(self.v.HttpClientRequestKind.state)}),
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

                    try buffer.appendSlice(entry.key_ptr.*.slice());
                    try buffer.appendSlice(": ");
                    try entry.value_ptr.*.appendValue(buffer, style);
                }
                try buffer.append('}');
            },
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
                        try buffer.appendSlice(entry.key_ptr.*.slice());
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
            .SequenceKind => switch (style) {
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
            },
            .StreamKind => try std.fmt.format(buffer.writer(), "<stream: {d} {s}>", .{ self.v.StreamKind.stream.handle, if (self.v.StreamKind.isOpen) "open" else "closed" }),
            .StringKind => switch (style) {
                Style.Pretty => {
                    try buffer.append('"');
                    for (self.v.StringKind.slice()) |c| {
                        switch (c) {
                            10 => try buffer.appendSlice("\\n"),
                            34 => try buffer.appendSlice("\\\""),
                            92 => try buffer.appendSlice("\\\\"),
                            0...9, 11...31 => try std.fmt.format(buffer.writer(), "\\x{d};", .{c}),
                            else => try buffer.append(c),
                        }
                    }
                    try buffer.append('"');
                },
                Style.Raw => try buffer.appendSlice(self.v.StringKind.slice()),
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
    ASTFunctionKind,
    BCFunctionKind,
    BoolKind,
    BuiltinFunctionKind,
    CharKind,
    FileKind,
    FloatKind,
    HttpClientKind,
    HttpClientRequestKind,
    IntKind,
    RecordKind,
    SequenceKind,
    StreamKind,
    StringKind,
    ScopeKind,
    UnitKind,

    pub fn toString(self: ValueKind) []const u8 {
        return switch (self) {
            ValueKind.BoolKind => "Bool",
            ValueKind.BCFunctionKind => "Function",
            ValueKind.BuiltinFunctionKind => "Function",
            ValueKind.CharKind => "Char",
            ValueKind.FileKind => "File",
            ValueKind.ASTFunctionKind => "Function",
            ValueKind.FloatKind => "Float",
            ValueKind.HttpClientKind => "HttpClient",
            ValueKind.HttpClientRequestKind => "HttpClientRequest",
            ValueKind.IntKind => "Int",
            ValueKind.SequenceKind => "Sequence",
            ValueKind.StreamKind => "Stream",
            ValueKind.StringKind => "String",
            ValueKind.RecordKind => "Record",
            ValueKind.ScopeKind => "Scope",
            ValueKind.UnitKind => "Unit",
        };
    }
};

pub const ValueValue = union(ValueKind) {
    ASTFunctionKind: ASTFunctionValue,
    BCFunctionKind: BCFunctionValue,
    BoolKind: bool,
    BuiltinFunctionKind: BuiltinFunctionValue,
    CharKind: u8,
    FileKind: FileValue,
    FloatKind: FloatType,
    IntKind: IntType,
    HttpClientKind: HttpClientValue,
    HttpClientRequestKind: HttpClientRequestValue,
    RecordKind: RecordValue,
    ScopeKind: ScopeValue,
    SequenceKind: SequenceValue,
    StreamKind: StreamValue,
    StringKind: StringValue,
    UnitKind: void,
};

pub const ASTFunctionValue = struct {
    scope: ?*Value,
    arguments: []FunctionArgument,
    restOfArguments: ?*SP.String,
    body: *AST.Expression,

    pub fn deinit(self: *ASTFunctionValue, allocator: std.mem.Allocator) void {
        for (self.arguments) |*argument| {
            argument.deinit();
        }
        if (self.restOfArguments != null) {
            self.restOfArguments.?.decRef();
        }
        allocator.free(self.arguments);
        self.body.destroy(allocator);
    }
};

pub const FunctionArgument = struct {
    name: *SP.String,
    default: ?*Value,

    pub fn deinit(self: *FunctionArgument) void {
        self.name.decRef();
    }
};

pub const BCFunctionValue = struct {
    scope: ?*Value,
    arguments: []FunctionArgument,
    restOfArguments: ?*SP.String,
    body: []u8,

    pub fn deinit(self: *BCFunctionValue, allocator: std.mem.Allocator) void {
        for (self.arguments) |*argument| {
            argument.deinit();
        }
        if (self.restOfArguments != null) {
            self.restOfArguments.?.decRef();
        }
        allocator.free(self.arguments);
        allocator.free(self.body);
    }
};

pub const BuiltinFunctionValue = struct {
    body: BuiltinFunctionType,
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

pub const HttpClientValue = struct {
    client: *std.http.Client,

    pub fn init(client: *std.http.Client) HttpClientValue {
        return HttpClientValue{ .client = client };
    }

    pub fn deinit(self: *HttpClientValue, allocator: std.mem.Allocator) void {
        self.client.deinit();
        allocator.destroy(self.client);
    }
};

pub const HttpClientRequestState = enum {
    Created,
    Started,
    Finished,
    Waiting,
    Done,
};

pub const HttpClientRequestValue = struct {
    state: HttpClientRequestState,
    headers: std.http.Headers,
    request: *std.http.Client.Request,

    pub fn init(headers: std.http.Headers, request: *std.http.Client.Request) HttpClientRequestValue {
        return HttpClientRequestValue{ .state = .Created, .headers = headers, .request = request };
    }

    pub fn deinit(self: *HttpClientRequestValue, allocator: std.mem.Allocator) void {
        self.headers.deinit();
        self.request.deinit();
        allocator.destroy(self.request);
    }

    pub fn start(self: *HttpClientRequestValue) !void {
        if (self.state == .Created) {
            try self.request.start();
            self.state = .Started;
        } else {
            return error.IllegalState;
        }
    }

    pub fn write(self: *HttpClientRequestValue, buffer: []const u8) !usize {
        if (self.state != .Started) {
            return error.IllegalState;
        }

        return try self.request.write(buffer);
    }

    pub fn finish(self: *HttpClientRequestValue) !void {
        if (self.state == .Finished) {
            return;
        } else if (self.state == .Started) {
            try self.request.finish();
            self.state = .Finished;
        } else {
            return error.IllegalState;
        }
    }

    pub fn wait(self: *HttpClientRequestValue) !void {
        if (self.state == .Started or self.state == .Finished) {
            try self.request.wait();
            self.state = .Waiting;
        } else {
            return error.IllegalState;
        }
    }

    pub fn read(self: *HttpClientRequestValue, buffer: []u8) !usize {
        if (self.state == .Done) {
            return 0;
        }

        if (self.state != .Waiting) {
            return error.IllegalState;
        }

        const bytesRead = try self.request.read(buffer);

        if (bytesRead == 0) {
            self.state = .Done;
        }

        return bytesRead;
    }
};

pub const RecordValue = struct {
    items: std.AutoHashMap(*SP.String, *Value),

    pub fn init(allocator: std.mem.Allocator) RecordValue {
        return RecordValue{ .items = std.AutoHashMap(*SP.String, *Value).init(allocator) };
    }

    pub fn deinit(self: *RecordValue) void {
        var itrtr = self.keyIterator();
        while (itrtr.next()) |keyPtr| {
            keyPtr.*.decRef();
        }
        self.items.deinit();
    }

    pub fn set(self: *RecordValue, key: *SP.String, value: *Value) !void {
        if (value.v == ValueKind.UnitKind) {
            const old = self.items.fetchRemove(key);

            if (old != null) {
                old.?.key.decRef();
            }
        } else if (self.items.getKey(key)) |oldKey| {
            try self.items.put(oldKey, value);
        } else {
            try self.items.put(key.incRefR(), value);
        }
    }

    pub fn setU8(self: *RecordValue, stringPool: *SP.StringPool, key: []const u8, value: *Value) !void {
        const spKey = try stringPool.intern(key);
        defer spKey.decRef();

        return self.set(spKey, value);
    }

    pub fn get(self: *const RecordValue, key: *SP.String) ?*Value {
        return self.items.get(key);
    }

    pub fn getU8(self: *const RecordValue, stringPool: *SP.StringPool, key: []const u8) !?*Value {
        const spKey = try stringPool.intern(key);
        defer spKey.decRef();

        return self.items.get(spKey);
    }

    pub fn count(self: *const RecordValue) usize {
        return self.items.count();
    }

    pub fn iterator(self: *const RecordValue) std.AutoHashMap(*SP.String, *Value).Iterator {
        return self.items.iterator();
    }

    pub fn keyIterator(self: *const RecordValue) std.AutoHashMap(*SP.String, *Value).KeyIterator {
        return self.items.keyIterator();
    }
};

pub const ScopeValue = struct {
    parent: ?*Value,
    values: std.AutoHashMap(*SP.String, *Value),

    pub fn init(allocator: std.mem.Allocator, parent: ?*Value) ScopeValue {
        return ScopeValue{
            .parent = parent,
            .values = std.AutoHashMap(*SP.String, *Value).init(allocator),
        };
    }

    pub fn deinit(self: *ScopeValue) void {
        var iterator = self.values.keyIterator();
        while (iterator.next()) |keyPtr| {
            keyPtr.*.decRef();
        }

        self.values.deinit();
    }

    pub fn set(self: *ScopeValue, key: *SP.String, value: *Value) !void {
        if (self.values.getKey(key)) |oldKey| {
            try self.values.put(oldKey, value);
        } else {
            try self.values.put(key.incRefR(), value);
        }
    }

    pub fn update(self: *ScopeValue, key: *SP.String, value: *Value) !bool {
        var runner: ?*ScopeValue = self;

        while (true) {
            const oldKey = runner.?.values.getKey(key);

            if (oldKey == null) {
                if (runner.?.parent == null) {
                    return false;
                } else {
                    runner = &runner.?.parent.?.v.ScopeKind;
                }
            } else {
                try runner.?.values.put(oldKey.?, value);

                return true;
            }
        }
    }

    pub fn get(self: *const ScopeValue, key: *SP.String) ?*Value {
        var runner: ?*const ScopeValue = self;

        while (true) {
            const value = runner.?.values.get(key);

            if (value != null) {
                return value;
            } else if (runner.?.parent == null) {
                return null;
            } else {
                runner = &runner.?.parent.?.v.ScopeKind;
            }
        }
    }

    pub fn count(self: *const ScopeValue) usize {
        return self.values.count();
    }

    pub fn keyIterator(self: *const ScopeValue) std.AutoHashMap(*SP.String, *Value).KeyIterator {
        return self.values.keyIterator();
    }

    pub fn delete(self: *ScopeValue, key: *SP.String) !?*Value {
        const value = self.values.get(key);

        if (self.values.getKey(key)) |oldKey| {
            _ = self.values.remove(oldKey);
            oldKey.decRef();
        }

        return value;
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
    value: *SP.String,

    pub fn init(sp: *SP.StringPool, value: []const u8) !StringValue {
        return StringValue{ .value = try sp.intern(value) };
    }

    pub fn initOwned(sp: *SP.StringPool, value: []u8) !StringValue {
        return StringValue{ .value = try sp.internOwned(value) };
    }

    pub fn initPool(value: *SP.String) StringValue {
        return StringValue{ .value = value.incRefR() };
    }

    pub fn deinit(self: *StringValue) void {
        self.value.decRef();
    }

    pub fn slice(self: *const StringValue) []const u8 {
        return self.value.slice();
    }

    pub fn len(self: *const StringValue) usize {
        return self.value.len();
    }
};

pub fn eq(a: *Value, b: *Value) bool {
    if (@intFromPtr(a) == @intFromPtr(b)) return true;
    if (@intFromEnum(a.v) != @intFromEnum(b.v)) {
        switch (a.v) {
            .IntKind => return b.v == .FloatKind and @as(FloatType, @floatFromInt(a.v.IntKind)) == b.v.FloatKind,
            .FloatKind => return b.v == .IntKind and a.v.FloatKind == @as(FloatType, @floatFromInt(b.v.IntKind)),
            else => {
                return false;
            },
        }
    }

    switch (a.v) {
        .ASTFunctionKind => return @intFromPtr(a) == @intFromPtr(b),
        .BCFunctionKind => return @intFromPtr(a) == @intFromPtr(b),
        .BoolKind => return a.v.BoolKind == b.v.BoolKind,
        .BuiltinFunctionKind => return @intFromPtr(a) == @intFromPtr(b),
        .CharKind => return a.v.CharKind == b.v.CharKind,
        .FileKind => return a.v.FileKind.file.handle == b.v.FileKind.file.handle,
        .IntKind => return a.v.IntKind == b.v.IntKind,
        .FloatKind => return a.v.FloatKind == b.v.FloatKind,
        .HttpClientKind => unreachable,
        .HttpClientRequestKind => unreachable,
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
        .SequenceKind => {
            if (a.v.SequenceKind.len() != b.v.SequenceKind.len()) return false;

            for (a.v.SequenceKind.items(), 0..) |v, i| {
                if (!eq(v, b.v.SequenceKind.at(i))) return false;
            }

            return true;
        },
        .StreamKind => return a.v.StreamKind.stream.handle == b.v.StreamKind.stream.handle,
        .StringKind => return a.v.StringKind.value == b.v.StringKind.value,
        .UnitKind => return true,
    }
}
