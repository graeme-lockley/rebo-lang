const std = @import("std");

pub const V = @import("./value.zig");

pub const MemoryState = struct {
    allocator: std.mem.Allocator,
    stack: std.ArrayList(*V.Value),
    colour: V.Colour,
    root: ?*V.Value,
    memory_size: u32,
    memory_capacity: u32,
    scopes: std.ArrayList(*V.Value),

    fn newValue(self: *MemoryState, vv: V.ValueValue) !*V.Value {
        const v = try self.allocator.create(V.Value);
        self.memory_size += 1;

        v.colour = self.colour;
        v.v = vv;
        v.next = self.root;

        self.root = v;

        return v;
    }

    pub fn pushValue(self: *MemoryState, vv: V.ValueValue) !*V.Value {
        const v = try self.newValue(vv);

        try self.stack.append(v);

        gc(self);

        return v;
    }

    pub fn pushBoolValue(self: *MemoryState, b: bool) !void {
        _ = try self.pushValue(V.ValueValue{ .BoolKind = b });
    }

    pub fn pushEmptyMapValue(self: *MemoryState) !void {
        _ = try self.pushValue(V.ValueValue{ .RecordKind = std.StringHashMap(*V.Value).init(self.allocator) });
    }

    pub fn pushCharValue(self: *MemoryState, v: u8) !void {
        _ = try self.pushValue(V.ValueValue{ .CharKind = v });
    }

    pub fn pushFloatValue(self: *MemoryState, v: V.FloatType) !void {
        _ = try self.pushValue(V.ValueValue{ .FloatKind = v });
    }

    pub fn pushIntValue(self: *MemoryState, v: V.IntType) !void {
        _ = try self.pushValue(V.ValueValue{ .IntKind = v });
    }

    pub fn pushSequenceValue(self: *MemoryState, size: usize) !void {
        var items = try self.allocator.alloc(*V.Value, size);

        if (size > 0) {
            var tos: usize = size - 1;
            while (true) {
                items[tos] = self.stack.pop();
                if (tos == 0) {
                    break;
                }
                tos -= 1;
            }
        }

        _ = try self.pushValue(V.ValueValue{ .SequenceKind = items });
    }

    pub fn pushOwnedSequenceValue(self: *MemoryState, v: []*V.Value) !void {
        _ = try self.pushValue(V.ValueValue{ .SequenceKind = v });
    }

    pub fn pushStringValue(self: *MemoryState, v: []const u8) !void {
        _ = try self.pushValue(V.ValueValue{ .StringKind = try self.allocator.dupe(u8, v) });
    }

    pub fn pushOwnedStringValue(self: *MemoryState, v: []u8) !void {
        _ = try self.pushValue(V.ValueValue{ .StringKind = v });
    }

    pub fn pushUnitValue(self: *MemoryState) !void {
        _ = try self.pushValue(V.ValueValue{ .VoidKind = void{} });
    }

    pub fn pop(self: *MemoryState) *V.Value {
        return self.stack.pop();
    }

    pub fn popn(self: *MemoryState, n: u32) void {
        self.stack.items.len -= n;
    }

    pub fn push(self: *MemoryState, v: *V.Value) !void {
        try self.stack.append(v);
    }

    pub fn peek(self: *MemoryState, n: u32) *V.Value {
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

    pub fn openScope(self: *MemoryState) !void {
        try self.scopes.append(try self.newValue(V.ValueValue{ .ScopeKind = V.ScopeValue{ .parent = self.scope(), .values = std.StringHashMap(*V.Value).init(self.allocator) } }));
    }

    pub fn openScopeFrom(self: *MemoryState, outerScope: ?*V.Value) !void {
        try self.scopes.append(try self.newValue(V.ValueValue{ .ScopeKind = V.ScopeValue{ .parent = outerScope, .values = std.StringHashMap(*V.Value).init(self.allocator) } }));
    }

    pub fn restoreScope(self: *MemoryState) void {
        _ = self.scopes.pop();
    }

    pub fn addToScope(self: *MemoryState, name: []const u8, value: *V.Value) !void {
        const s = self.scope().?;

        const oldKey = s.v.ScopeKind.values.getKey(name);

        if (oldKey == null) {
            try s.v.ScopeKind.values.put(try self.allocator.dupe(u8, name), value);
        } else {
            try s.v.ScopeKind.values.put(oldKey.?, value);
        }
    }

    pub fn updateInScope(self: *MemoryState, name: []const u8, value: *V.Value) !bool {
        var runner = self.scope();

        while (runner != null) {
            const oldKey = runner.?.v.ScopeKind.values.getKey(name);

            if (oldKey == null) {
                runner = runner.?.v.ScopeKind.parent;
            } else {
                try runner.?.v.ScopeKind.values.put(oldKey.?, value);

                return true;
            }
        }
        return false;
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

        force_gc(self);
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
        self.scopes.deinit();
        self.scopes = std.ArrayList(*V.Value).init(self.allocator);
        self.stack.deinit();
        self.stack = std.ArrayList(*V.Value).init(self.allocator);
        force_gc(self);
        self.stack.deinit();

        // self.stack.deinit();
        // var runner: ?*V.Value = self.root;
        // while (runner != null) {
        //     const next = runner.?.next;
        //     runner.?.deinit(self.allocator);
        //     self.allocator.destroy(runner.?);
        //     runner = next;
        // }
    }
};

fn mark(state: *MemoryState, possible_value: ?*V.Value, colour: V.Colour) void {
    if (possible_value == null) {
        return;
    }

    const v = possible_value.?;

    if (v.colour == colour) {
        return;
    }

    v.colour = colour;

    switch (v.v) {
        .BoolKind, .CharKind, .IntKind, .FloatKind, .StringKind, .VoidKind => {},
        .FunctionKind => {
            mark(state, v.v.FunctionKind.scope, colour);
            for (v.v.FunctionKind.arguments) |argument| {
                if (argument.default != null) {
                    mark(state, argument.default.?, colour);
                }
            }
        },
        .ScopeKind => {
            markScope(state, &v.v.ScopeKind, colour);
        },
        .SequenceKind => {
            for (v.v.SequenceKind) |item| {
                mark(state, item, colour);
            }
        },
        .RecordKind => {
            var iterator = v.v.RecordKind.iterator();
            while (iterator.next()) |entry| {
                mark(state, entry.value_ptr.*, colour);
            }
        },
    }
}

fn markScope(state: *MemoryState, scope: ?*V.ScopeValue, colour: V.Colour) void {
    if (scope == null) {
        return;
    }

    var iterator = scope.?.values.valueIterator();
    while (iterator.next()) |entry| {
        mark(state, entry.*, colour);
    }

    mark(state, scope.?.parent, colour);
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

fn force_gc(state: *MemoryState) void {
    const new_colour = if (state.colour == V.Colour.Black) V.Colour.White else V.Colour.Black;

    for (state.scopes.items) |value| {
        mark(state, value, new_colour);
    }
    for (state.stack.items) |value| {
        mark(state, value, new_colour);
    }

    sweep(state, new_colour);

    state.colour = new_colour;
}

fn gc(state: *MemoryState) void {
    const threshold_rate = 0.75;

    if (state.memory_size > state.memory_capacity) {
        const old_size = state.memory_size;
        const start_time = std.time.milliTimestamp();
        force_gc(state);
        const end_time = std.time.milliTimestamp();
        std.log.info("gc: time={d}ms, nodes freed={d}, heap size: {d}", .{ end_time - start_time, old_size - state.memory_size, state.memory_size });

        if (@as(f32, @floatFromInt(state.memory_size)) / @as(f32, @floatFromInt(state.memory_capacity)) > threshold_rate) {
            state.memory_capacity *= 2;
            std.log.info("gc: double heap capacity to {}", .{state.memory_capacity});
        }
    }
}
