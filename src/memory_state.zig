const std = @import("std");

pub const AST = @import("./ast.zig");
pub const SP = @import("./string_pool.zig");
pub const V = @import("./value.zig");

pub const MemoryState = struct {
    allocator: std.mem.Allocator,

    stringPool: *SP.StringPool,
    stack: std.ArrayList(*V.Value),
    colour: V.Colour,
    root: ?*V.Value,
    memory_size: u32,
    memory_capacity: u32,
    scopes: std.ArrayList(*V.Value),
    imports: Imports,
    unitValue: ?*V.Value,

    pub fn init(allocator: std.mem.Allocator) !MemoryState {
        const stringPool = try allocator.create(SP.StringPool);
        stringPool.* = SP.StringPool.init(allocator);

        var state = MemoryState{
            .allocator = allocator,
            .stringPool = stringPool,
            .stack = std.ArrayList(*V.Value).init(allocator),
            .colour = V.Colour.White,
            .root = null,
            .memory_size = 0,
            .memory_capacity = 1024 * 64,
            .scopes = std.ArrayList(*V.Value).init(allocator),
            .imports = Imports.init(allocator),
            .unitValue = null,
        };

        state.unitValue = try state.newValue(V.ValueValue{ .UnitKind = void{} });

        return state;
    }

    pub fn deinit(self: *MemoryState) void {
        // Leave this code in - helpful to use when debugging memory leaks.
        // The code following this comment block just nukes the allocated
        // memory without consideration what is still in use.

        var count: u32 = 0;
        for (self.stack.items) |v| {
            count += 1;
            _ = v;
        }

        _ = force_gc(self);

        var number_of_values: u32 = 0;
        {
            var runner: ?*V.Value = self.root;
            while (runner != null) {
                const next = runner.?.next;
                number_of_values += 1;
                runner = next;
            }
        }
        std.log.info("gc: memory state stack length: {d} vs {d}: values: {d} vs {d}", .{ self.stack.items.len, count, self.memory_size, number_of_values });
        self.unitValue = null;
        self.scopes.deinit();
        self.scopes = std.ArrayList(*V.Value).init(self.allocator);
        self.stack.deinit();
        self.stack = std.ArrayList(*V.Value).init(self.allocator);
        self.imports.deinit();
        self.imports = Imports.init(self.allocator);
        _ = force_gc(self);

        self.stack.deinit();
        self.imports.deinit();

        std.log.info("gc: memory state stack length: {d} vs {d}: values: {d} vs {d}", .{ self.stack.items.len, count, self.memory_size, number_of_values });

        self.stringPool.deinit();
        self.allocator.destroy(self.stringPool);

        // self.stack.deinit();
        // var runner: ?*V.Value = self.root;
        // while (runner != null) {
        //     const next = runner.?.next;
        //     runner.?.deinit(self.allocator);
        //     self.allocator.destroy(runner.?);
        //     runner = next;
        // }
    }

    pub inline fn newValue(self: *MemoryState, vv: V.ValueValue) !*V.Value {
        const v = try self.allocator.create(V.Value);
        self.memory_size += 1;

        v.colour = self.colour;
        v.v = vv;
        v.next = self.root;

        self.root = v;

        return v;
    }

    pub inline fn pushValue(self: *MemoryState, vv: V.ValueValue) !*V.Value {
        const v = try self.newValue(vv);

        try self.stack.append(v);

        gc(self);

        return v;
    }

    pub inline fn pushBoolValue(self: *MemoryState, b: bool) !void {
        _ = try self.pushValue(V.ValueValue{ .BoolKind = b });
    }

    pub inline fn newMapValue(self: *MemoryState) !*V.Value {
        return try self.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(self.allocator) });
    }

    pub inline fn pushEmptyMapValue(self: *MemoryState) !void {
        try self.push(try self.newMapValue());
    }

    pub inline fn pushCharValue(self: *MemoryState, v: u8) !void {
        _ = try self.pushValue(V.ValueValue{ .CharKind = v });
    }

    pub inline fn newFileValue(self: *MemoryState, file: std.fs.File) !*V.Value {
        return try self.newValue(V.ValueValue{ .FileKind = V.FileValue.init(file) });
    }

    pub inline fn pushFloatValue(self: *MemoryState, v: V.FloatType) !void {
        _ = try self.pushValue(V.ValueValue{ .FloatKind = v });
    }

    pub inline fn newIntValue(self: *MemoryState, v: V.IntType) !*V.Value {
        return try self.newValue(V.ValueValue{ .IntKind = v });
    }

    pub inline fn pushIntValue(self: *MemoryState, v: V.IntType) !void {
        _ = try self.push(try self.newIntValue(v));
    }

    pub inline fn pushEmptySequenceValue(self: *MemoryState) !void {
        _ = try self.pushValue(V.ValueValue{ .SequenceKind = try V.SequenceValue.init(self.allocator) });
    }

    pub inline fn newStreamValue(self: *MemoryState, v: std.net.Stream) !*V.Value {
        return try self.newValue(V.ValueValue{ .StreamKind = V.StreamValue.init(v) });
    }

    pub inline fn newStringValue(self: *MemoryState, v: []const u8) !*V.Value {
        return try self.newValue(V.ValueValue{ .StringKind = try V.StringValue.init(self.stringPool, v) });
    }

    pub inline fn newOwnedStringValue(self: *MemoryState, v: []u8) !*V.Value {
        return try self.newValue(V.ValueValue{ .StringKind = try V.StringValue.initOwned(self.stringPool, v) });
    }

    pub inline fn pushStringPoolValue(self: *MemoryState, v: *SP.String) !void {
        _ = try self.push(try self.newValue(V.ValueValue{ .StringKind = V.StringValue.initPool(v) }));
    }

    pub inline fn pushStringValue(self: *MemoryState, v: []const u8) !void {
        _ = try self.push(try self.newStringValue(v));
    }

    pub inline fn pushOwnedStringValue(self: *MemoryState, v: []u8) !void {
        _ = try self.push(try self.newOwnedStringValue(v));
    }

    pub inline fn pushUnitValue(self: *MemoryState) !void {
        _ = try self.push(self.unitValue.?);
    }

    pub inline fn pop(self: *MemoryState) *V.Value {
        return self.stack.pop();
    }

    pub inline fn popn(self: *MemoryState, n: u32) void {
        self.stack.items.len -= n;
    }

    pub inline fn push(self: *MemoryState, v: *V.Value) !void {
        try self.stack.append(v);
    }

    pub inline fn peek(self: *MemoryState, n: u32) *V.Value {
        return self.stack.items[self.stack.items.len - n - 1];
    }

    pub fn topOfStack(self: *MemoryState) ?*V.Value {
        if (self.stack.items.len == 0) {
            return null;
        } else {
            return self.peek(0);
        }
    }

    pub fn scope(self: *MemoryState) ?*V.Value {
        if (self.scopes.items.len == 0) {
            return null;
        } else {
            return self.scopes.items[self.scopes.items.len - 1];
        }
    }

    pub fn topScope(self: *MemoryState) *V.Value {
        return self.scopes.items[0];
    }

    pub fn openScope(self: *MemoryState) !void {
        try self.scopes.append(try self.newValue(V.ValueValue{ .ScopeKind = V.ScopeValue.init(self.allocator, self.scope()) }));
    }

    pub fn openScopeFrom(self: *MemoryState, outerScope: ?*V.Value) !void {
        try self.scopes.append(try self.newValue(V.ValueValue{ .ScopeKind = V.ScopeValue.init(self.allocator, outerScope) }));
    }

    pub fn restoreScope(self: *MemoryState) void {
        _ = self.scopes.pop();
    }

    pub inline fn addToScope(self: *MemoryState, name: *SP.String, value: *V.Value) !void {
        try self.scope().?.v.ScopeKind.set(self.allocator, name.slice(), value);
    }

    pub inline fn addU8ToScope(self: *MemoryState, name: []const u8, value: *V.Value) !void {
        try self.scope().?.v.ScopeKind.set(self.allocator, name, value);
    }

    pub inline fn addArrayValueToScope(self: *MemoryState, name: *SP.String, values: []*V.Value) !void {
        const value = try self.newValue(V.ValueValue{ .SequenceKind = try V.SequenceValue.init(self.allocator) });
        try value.v.SequenceKind.appendSlice(values);

        try self.scope().?.v.ScopeKind.set(self.allocator, name.slice(), value);
    }

    pub inline fn updateInScope(self: *MemoryState, name: *SP.String, value: *V.Value) !bool {
        return try self.scope().?.v.ScopeKind.update(name.slice(), value);
    }

    pub inline fn getFromScope(self: *MemoryState, name: *SP.String) ?*V.Value {
        return self.scope().?.v.ScopeKind.get(name.slice());
    }

    pub inline fn getU8FromScope(self: *MemoryState, name: []const u8) !?*V.Value {
        return self.scope().?.v.ScopeKind.get(name);
    }

    pub fn reset(self: *MemoryState) !void {
        while (self.scopes.items.len > 2) {
            self.restoreScope();
        }

        self.stack.deinit();
        self.stack = std.ArrayList(*V.Value).init(self.allocator);
    }
};

fn markValue(possible_value: ?*V.Value, colour: V.Colour) void {
    if (possible_value == null) {
        return;
    }

    const v = possible_value.?;

    if (v.colour == colour) {
        return;
    }

    v.colour = colour;

    switch (v.v) {
        .BoolKind, .BuiltinKind, .CharKind, .IntKind, .FileKind, .FloatKind, .StreamKind, .StringKind, .UnitKind => {},
        .FunctionKind => {
            markValue(v.v.FunctionKind.scope, colour);
            for (v.v.FunctionKind.arguments) |argument| {
                if (argument.default != null) {
                    markValue(argument.default.?, colour);
                }
            }
        },
        .ScopeKind => {
            markScope(&v.v.ScopeKind, colour);
        },
        .SequenceKind => {
            for (v.v.SequenceKind.items()) |item| {
                markValue(item, colour);
            }
        },
        .RecordKind => {
            var iterator = v.v.RecordKind.iterator();
            while (iterator.next()) |entry| {
                markValue(entry.value_ptr.*, colour);
            }
        },
    }
}

fn markScope(scope: ?*V.ScopeValue, colour: V.Colour) void {
    if (scope == null) {
        return;
    }

    var iterator = scope.?.values.valueIterator();
    while (iterator.next()) |entry| {
        markValue(entry.*, colour);
    }

    markValue(scope.?.parent, colour);
}

fn sweep(state: *MemoryState, colour: V.Colour) void {
    var runner: *?*V.Value = &state.root;
    while (runner.* != null) {
        if (runner.*.?.colour != colour) {
            // std.debug.print("sweep: freeing {}\n", .{runner.*.?.v});
            const next = runner.*.?.next;
            runner.*.?.deinit(state.allocator);
            state.allocator.destroy(runner.*.?);
            state.memory_size -= 1;
            runner.* = next;
        } else {
            runner = &(runner.*.?.next);
        }
    }
}

pub const GCResult = struct {
    capacity: u32,
    oldSize: u32,
    newSize: u32,
    duration: i64,
};

pub fn force_gc(state: *MemoryState) GCResult {
    const start_time = std.time.milliTimestamp();
    const old_size = state.memory_size;

    const new_colour = if (state.colour == V.Colour.Black) V.Colour.White else V.Colour.Black;

    state.imports.mark(new_colour);
    if (state.unitValue != null) {
        markValue(state.unitValue.?, new_colour);
    }

    for (state.scopes.items) |value| {
        markValue(value, new_colour);
    }
    for (state.stack.items) |value| {
        markValue(value, new_colour);
    }

    sweep(state, new_colour);
    const end_time = std.time.milliTimestamp();

    state.colour = new_colour;

    return GCResult{ .capacity = state.memory_capacity, .oldSize = old_size, .newSize = state.memory_size, .duration = end_time - start_time };
}

fn gc(state: *MemoryState) void {
    const threshold_rate = 0.25;

    if (state.memory_size > state.memory_capacity) {
        // _ = force_gc(state);
        const gcResult = force_gc(state);
        std.log.info("gc: time={d}ms, nodes freed={d}, heap size: {d}", .{ gcResult.duration, gcResult.oldSize - gcResult.newSize, gcResult.newSize });

        if (@as(f32, @floatFromInt(state.memory_size)) / @as(f32, @floatFromInt(state.memory_capacity)) > threshold_rate) {
            state.memory_capacity *= 2;
            std.log.info("gc: double heap capacity to {}", .{state.memory_capacity});
        }
    }
}

pub const Imports = struct {
    items: std.StringHashMap(Import),
    allocator: std.mem.Allocator,
    annie: u32,

    pub fn init(allocator: std.mem.Allocator) Imports {
        return Imports{ .items = std.StringHashMap(Import).init(allocator), .allocator = allocator, .annie = 0 };
    }

    pub fn deinit(self: *Imports) void {
        var iterator = self.items.iterator();

        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.ast.destroy(self.allocator);
        }
        self.items.deinit();
    }

    pub fn mark(self: *Imports, colour: V.Colour) void {
        var iterator = self.items.iterator();

        while (iterator.next()) |entry| {
            entry.value_ptr.*.mark(colour);
        }
    }

    pub fn addImport(self: *Imports, name: []const u8, items: ?*V.Value, e: *AST.Expression) !void {
        const oldName = self.items.getKey(name);

        if (oldName == null) {
            try self.items.put(try self.allocator.dupe(u8, name), Import{ .items = items, .ast = e });
        } else {
            try self.items.put(oldName.?, Import{ .items = items, .ast = e });
        }

        // try self.items.put(try self.allocator.dupe(u8, name), Import{ .items = items, .ast = e });
        // self.dump();
    }

    pub fn addAnnie(self: *Imports, e: *AST.Expression) !void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try std.fmt.format(buffer.writer(), "repl-{d}", .{self.annie});
        self.annie += 1;

        try self.items.put(try buffer.toOwnedSlice(), Import{ .items = null, .ast = e });
        // self.dump();
    }

    pub fn find(self: *Imports, name: []const u8) ?Import {
        return self.items.get(name);
    }

    fn dump(self: *Imports) void {
        var iterator = self.items.iterator();
        while (iterator.next()) |entry| {
            std.log.info("- {s}: {?}", .{ entry.key_ptr.*, entry.value_ptr.*.items });
        }
    }
};

pub const Import = struct {
    items: ?*V.Value,
    ast: *AST.Expression,

    pub fn mark(this: *Import, colour: V.Colour) void {
        if (this.items != null) {
            markValue(this.items.?, colour);
        }
    }
};
