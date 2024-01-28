const std = @import("std");

const AST = @import("./ast.zig");
const ER = @import("./error-reporting.zig");
const Errors = @import("./errors.zig");
const SP = @import("./string_pool.zig");
const V = @import("./value.zig");

const MAINTAIN_FREE_CHAIN = true;
const INITIAL_HEAP_SIZE = 1;
const HEAP_GROW_THRESHOLD = 0.25;

pub const Runtime = struct {
    allocator: std.mem.Allocator,

    stringPool: *SP.StringPool,
    stack: std.ArrayList(*V.Value),
    colour: V.Colour,
    root: ?*V.Value,
    free: ?*V.Value,
    memory_size: u32,
    memory_capacity: u32,
    allocations: u64,
    scopes: std.ArrayList(*V.Value),
    unitValue: ?*V.Value,
    trueValue: ?*V.Value,
    falseValue: ?*V.Value,

    pub fn init(allocator: std.mem.Allocator) !Runtime {
        const stringPool = try allocator.create(SP.StringPool);
        stringPool.* = SP.StringPool.init(allocator);

        var state = Runtime{
            .allocator = allocator,
            .stringPool = stringPool,
            .stack = std.ArrayList(*V.Value).init(allocator),
            .colour = V.Colour.White,
            .root = null,
            .free = null,
            .memory_size = 0,
            .memory_capacity = INITIAL_HEAP_SIZE,
            .allocations = 0,
            .scopes = std.ArrayList(*V.Value).init(allocator),
            .unitValue = null,
            .trueValue = null,
            .falseValue = null,
        };

        state.unitValue = try state.newValue(V.ValueValue{ .UnitKind = void{} });
        state.trueValue = try state.newValue(V.ValueValue{ .BoolKind = true });
        state.falseValue = try state.newValue(V.ValueValue{ .BoolKind = false });

        try state.openScope();
        try setupRebo(&state);

        return state;
    }

    pub fn deinit(self: *Runtime) void {
        var count = self.stack.items.len;

        _ = force_gc(self);

        // var number_of_values: u32 = 0;
        // {
        //     var runner: ?*V.Value = self.root;1
        //     while (runner != null) {
        //         const next = runner.?.next;
        //         number_of_values += 1;
        //         runner = next;
        //     }
        // }
        // std.log.info("gc: memory state stack length: {d} vs {d}: values: {d} vs {d}", .{ self.stack.items.len, count, self.memory_size, number_of_values });
        // 361571 vs 272164
        std.log.info("gc: memory state stack length: {d} vs {d}, values: {d}, stringpool: {d}", .{ self.stack.items.len, count, self.memory_size, self.stringPool.count() });
        self.unitValue = null;
        self.trueValue = null;
        self.falseValue = null;
        self.scopes.deinit();
        self.scopes = std.ArrayList(*V.Value).init(self.allocator);
        self.stack.deinit();
        self.stack = std.ArrayList(*V.Value).init(self.allocator);
        _ = force_gc(self);

        if (MAINTAIN_FREE_CHAIN) {
            self.destroyFreeList();
        }

        self.stack.deinit();

        std.log.info("gc: memory state stack length: {d} vs {d}, values: {d}, stringpool: {d}", .{ self.stack.items.len, count, self.memory_size, self.stringPool.count() });

        self.stringPool.deinit();
        self.allocator.destroy(self.stringPool);
    }

    fn destroyFreeList(self: *Runtime) void {
        var runner: ?*V.Value = self.free;
        while (runner != null) {
            const next = runner.?.next;
            self.allocator.destroy(runner.?);
            runner = next;
        }
        self.free = null;
    }

    pub inline fn newValue(self: *Runtime, vv: V.ValueValue) !*V.Value {
        const v = if (self.free == null) try self.allocator.create(V.Value) else self.nextFreeValue();
        self.memory_size += 1;
        self.allocations += 1;

        v.colour = self.colour;
        v.v = vv;
        v.next = self.root;

        self.root = v;

        return v;
    }

    fn nextFreeValue(self: *Runtime) *V.Value {
        const v: *V.Value = self.free.?;
        self.free = v.next;

        return v;
    }

    pub inline fn appendSequenceItemBang(self: *Runtime, seqPosition: Errors.Position) !void {
        const seq = self.peek(1);
        const item = self.peek(0);

        if (!seq.isSequence()) {
            try ER.raiseExpectedTypeError(self, seqPosition, &[_]V.ValueKind{V.ValueValue.SequenceKind}, seq.v);
        }

        try seq.v.SequenceKind.appendItem(item);
        self.popn(1);
    }

    pub inline fn appendSequenceItemsBang(self: *Runtime, seqPosition: Errors.Position, itemPosition: Errors.Position) !void {
        const seq = self.peek(1);
        const item = self.peek(0);

        if (!seq.isSequence()) {
            try ER.raiseExpectedTypeError(self, seqPosition, &[_]V.ValueKind{V.ValueValue.SequenceKind}, seq.v);
        }

        if (!item.isSequence()) {
            try ER.raiseExpectedTypeError(self, itemPosition, &[_]V.ValueKind{V.ValueValue.SequenceKind}, item.v);
        }

        try seq.v.SequenceKind.appendSlice(item.v.SequenceKind.items());
        self.popn(1);
    }

    pub inline fn newBuiltinValue(self: *Runtime, body: V.BuiltinFunctionType) !*V.Value {
        return try self.newValue(V.ValueValue{ .BuiltinKind = .{ .body = body } });
    }

    pub inline fn newFileValue(self: *Runtime, file: std.fs.File) !*V.Value {
        return try self.newValue(V.ValueValue{ .FileKind = V.FileValue.init(file) });
    }

    pub inline fn newIntValue(self: *Runtime, v: V.IntType) !*V.Value {
        return try self.newValue(V.ValueValue{ .IntKind = v });
    }

    pub inline fn newRecordValue(self: *Runtime) !*V.Value {
        return try self.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(self.allocator) });
    }

    pub inline fn newScopeValue(self: *Runtime, parent: ?*V.Value) !*V.Value {
        return try self.newValue(V.ValueValue{ .ScopeKind = V.ScopeValue.init(self.allocator, parent) });
    }

    pub inline fn newEmptySequenceValue(self: *Runtime) !*V.Value {
        return try self.newValue(V.ValueValue{ .SequenceKind = try V.SequenceValue.init(self.allocator) });
    }

    pub inline fn newStreamValue(self: *Runtime, v: std.net.Stream) !*V.Value {
        return try self.newValue(V.ValueValue{ .StreamKind = V.StreamValue.init(v) });
    }

    pub inline fn newStringPoolValue(self: *Runtime, v: *SP.String) !*V.Value {
        return try self.newValue(V.ValueValue{ .StringKind = V.StringValue.initPool(v) });
    }

    pub inline fn newStringValue(self: *Runtime, v: []const u8) !*V.Value {
        return try self.newValue(V.ValueValue{ .StringKind = try V.StringValue.init(self.stringPool, v) });
    }

    pub inline fn newOwnedStringValue(self: *Runtime, v: []u8) !*V.Value {
        return try self.newValue(V.ValueValue{ .StringKind = try V.StringValue.initOwned(self.stringPool, v) });
    }

    pub inline fn pushValue(self: *Runtime, vv: V.ValueValue) !*V.Value {
        const v = try self.newValue(vv);

        try self.stack.append(v);

        gc(self);

        return v;
    }

    pub inline fn pushBoolValue(self: *Runtime, b: bool) !void {
        if (b and self.trueValue != null) {
            _ = try self.push(self.trueValue.?);
            return;
        } else if (!b and self.falseValue != null) {
            _ = try self.push(self.falseValue.?);
            return;
        } else {
            _ = try self.pushValue(V.ValueValue{ .BoolKind = b });
        }
    }

    pub inline fn pushEmptyRecordValue(self: *Runtime) !void {
        try self.push(try self.newRecordValue());
    }

    pub inline fn pushCharValue(self: *Runtime, v: u8) !void {
        _ = try self.pushValue(V.ValueValue{ .CharKind = v });
    }

    pub inline fn pushFloatValue(self: *Runtime, v: V.FloatType) !void {
        _ = try self.pushValue(V.ValueValue{ .FloatKind = v });
    }

    pub inline fn pushIntValue(self: *Runtime, v: V.IntType) !void {
        _ = try self.push(try self.newIntValue(v));
    }

    pub inline fn pushScopeValue(self: *Runtime, parent: ?*V.Value) !void {
        _ = try self.push(try self.newScopeValue(parent));
    }

    pub inline fn pushEmptySequenceValue(self: *Runtime) !void {
        _ = try self.push(try self.newEmptySequenceValue());
    }

    pub inline fn pushStringPoolValue(self: *Runtime, v: *SP.String) !void {
        _ = try self.push(try self.newStringPoolValue(v));
    }

    pub inline fn pushStringValue(self: *Runtime, v: []const u8) !void {
        _ = try self.push(try self.newStringValue(v));
    }

    pub inline fn pushOwnedStringValue(self: *Runtime, v: []u8) !void {
        _ = try self.push(try self.newOwnedStringValue(v));
    }

    pub inline fn pushUnitValue(self: *Runtime) !void {
        _ = try self.push(self.unitValue.?);
    }

    pub inline fn pop(self: *Runtime) *V.Value {
        return self.stack.pop();
    }

    pub inline fn popn(self: *Runtime, n: usize) void {
        self.stack.items.len -= n;
    }

    pub inline fn push(self: *Runtime, v: *V.Value) !void {
        try self.stack.append(v);
    }

    pub inline fn peek(self: *Runtime, n: usize) *V.Value {
        return self.stack.items[self.stack.items.len - n - 1];
    }

    pub fn topOfStack(self: *Runtime) ?*V.Value {
        if (self.stack.items.len == 0) {
            return null;
        } else {
            return self.peek(0);
        }
    }

    pub inline fn scope(self: *Runtime) ?*V.Value {
        if (self.scopes.items.len == 0) {
            return null;
        } else {
            return self.scopes.items[self.scopes.items.len - 1];
        }
    }

    pub inline fn topScope(self: *Runtime) *V.Value {
        return self.scopes.items[0];
    }

    pub inline fn openScope(self: *Runtime) !void {
        try self.scopes.append(try self.newValue(V.ValueValue{ .ScopeKind = V.ScopeValue.init(self.allocator, self.scope()) }));
    }

    pub inline fn openScopeFrom(self: *Runtime, outerScope: ?*V.Value) !void {
        if (outerScope != null and outerScope.?.v != V.ValueKind.ScopeKind) unreachable;

        try self.scopes.append(try self.newValue(V.ValueValue{ .ScopeKind = V.ScopeValue.init(self.allocator, outerScope) }));
    }

    pub inline fn openScopeUsing(self: *Runtime, outerScope: *V.Value) !void {
        if (outerScope.v != V.ValueKind.ScopeKind) unreachable;

        try self.scopes.append(outerScope);
    }

    pub inline fn restoreScope(self: *Runtime) void {
        _ = self.scopes.pop();
    }

    pub inline fn pushScope(self: *Runtime) !void {
        self.scopes.items[self.scopes.items.len - 1] = try self.newValue(V.ValueValue{ .ScopeKind = V.ScopeValue.init(self.allocator, self.scopes.items[self.scopes.items.len - 1]) });
    }

    pub inline fn popScope(self: *Runtime) void {
        self.scopes.items[self.scopes.items.len - 1] = self.scopes.items[self.scopes.items.len - 1].v.ScopeKind.parent.?;
    }

    pub inline fn addToScope(self: *Runtime, name: *SP.String, value: *V.Value) !void {
        try self.scope().?.v.ScopeKind.set(name, value);
    }

    pub inline fn addU8ToScope(self: *Runtime, name: []const u8, value: *V.Value) !void {
        const spName = try self.stringPool.intern(name);
        defer spName.decRef();

        try self.scope().?.v.ScopeKind.set(spName, value);
    }

    pub inline fn addArrayValueToScope(self: *Runtime, name: *SP.String, values: []*V.Value) !void {
        const value = try self.newValue(V.ValueValue{ .SequenceKind = try V.SequenceValue.init(self.allocator) });
        try value.v.SequenceKind.appendSlice(values);

        try self.scope().?.v.ScopeKind.set(name, value);
    }

    pub inline fn updateInScope(self: *Runtime, name: *SP.String, value: *V.Value) !bool {
        return try self.scope().?.v.ScopeKind.update(name, value);
    }

    pub inline fn getFromScope(self: *Runtime, name: *SP.String) ?*V.Value {
        return self.scope().?.v.ScopeKind.get(name);
    }

    pub inline fn getU8FromScope(self: *Runtime, name: []const u8) !?*V.Value {
        const spName = try self.stringPool.intern(name);
        defer spName.decRef();

        return self.scope().?.v.ScopeKind.get(spName);
    }

    pub fn reset(self: *Runtime) !void {
        while (self.scopes.items.len > 2) {
            self.restoreScope();
        }

        self.stack.deinit();
        self.stack = std.ArrayList(*V.Value).init(self.allocator);
    }

    pub inline fn equals(self: *Runtime) !void {
        const right = self.pop();
        const left = self.pop();

        try self.pushBoolValue(V.eq(left, right));
    }

    pub inline fn notEquals(self: *Runtime) !void {
        const right = self.pop();
        const left = self.pop();

        try self.pushBoolValue(!V.eq(left, right));
    }

    pub inline fn lessThan(self: *Runtime, position: Errors.Position) !void {
        const right = self.pop();
        const left = self.pop();

        switch (left.v) {
            V.ValueValue.IntKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushBoolValue(left.v.IntKind < right.v.IntKind);
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) < right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.FloatKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushBoolValue(left.v.FloatKind < @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushBoolValue(left.v.FloatKind < right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.StringKind => {
                if (right.isString()) {
                    try self.pushBoolValue(std.mem.lessThan(u8, left.v.StringKind.slice(), right.v.StringKind.slice()));
                    return;
                }
            },
            else => {},
        }
        try ER.raiseIncompatibleOperandTypesError(self, position, AST.Operator.LessThan, left.v, right.v);
    }

    pub inline fn lessEqual(self: *Runtime, position: Errors.Position) !void {
        const right = self.pop();
        const left = self.pop();

        switch (left.v) {
            V.ValueValue.IntKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushBoolValue(left.v.IntKind <= right.v.IntKind);
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) <= right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.FloatKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushBoolValue(left.v.FloatKind <= @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushBoolValue(left.v.FloatKind <= right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.StringKind => {
                if (right.isString()) {
                    try self.pushBoolValue(std.mem.lessThan(u8, left.v.StringKind.slice(), right.v.StringKind.slice()) or std.mem.eql(u8, left.v.StringKind.slice(), right.v.StringKind.slice()));
                    return;
                }
            },
            else => {},
        }
        try ER.raiseIncompatibleOperandTypesError(self, position, AST.Operator.LessEqual, left.v, right.v);
    }

    pub inline fn greaterThan(self: *Runtime, position: Errors.Position) !void {
        const right = self.pop();
        const left = self.pop();

        switch (left.v) {
            V.ValueValue.IntKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushBoolValue(left.v.IntKind > right.v.IntKind);
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) > right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.FloatKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushBoolValue(left.v.FloatKind > @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushBoolValue(left.v.FloatKind > right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.StringKind => {
                if (right.isString()) {
                    try self.pushBoolValue(std.mem.lessThan(u8, right.v.StringKind.slice(), left.v.StringKind.slice()));
                    return;
                }
            },
            else => {},
        }
        try ER.raiseIncompatibleOperandTypesError(self, position, AST.Operator.GreaterThan, left.v, right.v);
    }

    pub inline fn greaterEqual(self: *Runtime, position: Errors.Position) !void {
        const right = self.pop();
        const left = self.pop();

        switch (left.v) {
            V.ValueValue.IntKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushBoolValue(left.v.IntKind >= right.v.IntKind);
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushBoolValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) >= right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.FloatKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushBoolValue(left.v.FloatKind >= @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushBoolValue(left.v.FloatKind >= right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.StringKind => {
                if (right.isString()) {
                    try self.pushBoolValue(std.mem.lessThan(u8, right.v.StringKind.slice(), left.v.StringKind.slice()) or std.mem.eql(u8, right.v.StringKind.slice(), left.v.StringKind.slice()));
                    return;
                }
            },
            else => {},
        }
        try ER.raiseIncompatibleOperandTypesError(self, position, AST.Operator.GreaterEqual, left.v, right.v);
    }

    pub inline fn add(self: *Runtime, position: Errors.Position) !void {
        const right = self.peek(0);
        const left = self.peek(1);

        switch (left.v) {
            V.ValueValue.IntKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        self.popn(2);
                        try self.pushIntValue(left.v.IntKind + right.v.IntKind);
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        self.popn(2);
                        try self.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) + right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.FloatKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        self.popn(2);
                        try self.pushFloatValue(left.v.FloatKind + @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        self.popn(2);
                        try self.pushFloatValue(left.v.FloatKind + right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.SequenceKind => {
                switch (right.v) {
                    V.ValueValue.SequenceKind => {
                        try self.pushEmptySequenceValue();
                        const seq = self.peek(0);
                        try seq.v.SequenceKind.appendSlice(left.v.SequenceKind.items());
                        try seq.v.SequenceKind.appendSlice(right.v.SequenceKind.items());
                        self.popn(3);
                        try self.push(seq);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.StringKind => {
                switch (right.v) {
                    V.ValueValue.StringKind => {
                        self.popn(2);

                        const slices = [_][]const u8{ left.v.StringKind.slice(), right.v.StringKind.slice() };
                        try self.pushOwnedStringValue(try std.mem.concat(self.allocator, u8, &slices));
                        return;
                    },
                    else => {},
                }
            },
            else => {},
        }

        try ER.raiseIncompatibleOperandTypesError(self, position, AST.Operator.Plus, left.v, right.v);
    }

    pub inline fn subtract(self: *Runtime, position: Errors.Position) !void {
        const right = self.pop();
        const left = self.pop();

        switch (left.v) {
            V.ValueValue.IntKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushIntValue(left.v.IntKind - right.v.IntKind);
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) - right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.FloatKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushFloatValue(left.v.FloatKind - @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushFloatValue(left.v.FloatKind - right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            else => {},
        }
        try ER.raiseIncompatibleOperandTypesError(self, position, AST.Operator.Minus, left.v, right.v);
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
        .HttpClientKind => {},
        .HttpClientRequestKind => {},
        .ScopeKind => markScope(&v.v.ScopeKind, colour),
        .SequenceKind => for (v.v.SequenceKind.items()) |item| {
            markValue(item, colour);
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

fn sweep(state: *Runtime, colour: V.Colour) void {
    var runner: *?*V.Value = &state.root;
    while (runner.* != null) {
        if (runner.*.?.colour != colour) {
            // std.debug.print("sweep: freeing {}\n", .{runner.*.?.v});
            const next = runner.*.?.next;
            runner.*.?.deinit(state.allocator);

            if (MAINTAIN_FREE_CHAIN) {
                runner.*.?.next = state.free;
                state.free = runner.*.?;
            } else {
                state.allocator.destroy(runner.*.?);
            }

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

pub fn force_gc(state: *Runtime) GCResult {
    const start_time = std.time.milliTimestamp();
    const old_size = state.memory_size;

    const new_colour = if (state.colour == V.Colour.Black) V.Colour.White else V.Colour.Black;

    if (state.unitValue != null) {
        markValue(state.unitValue.?, new_colour);
    }
    if (state.trueValue != null) {
        markValue(state.trueValue.?, new_colour);
    }
    if (state.falseValue != null) {
        markValue(state.falseValue.?, new_colour);
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

inline fn gc(state: *Runtime) void {
    if (state.memory_size > state.memory_capacity) {
        // _ = force_gc(state);
        const gcResult = force_gc(state);
        std.log.info("gc: time={d}ms, nodes freed={d}, heap size: {d}", .{ gcResult.duration, gcResult.oldSize - gcResult.newSize, gcResult.newSize });

        if (@as(f32, @floatFromInt(state.memory_size)) / @as(f32, @floatFromInt(state.memory_capacity)) > HEAP_GROW_THRESHOLD) {
            state.memory_capacity *= 2;
            std.log.info("gc: double heap capacity to {}", .{state.memory_capacity});
        }
    }
}

fn setupRebo(state: *Runtime) !void {
    var args = try std.process.argsAlloc(state.allocator);
    defer std.process.argsFree(state.allocator, args);

    const value = try state.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(state.allocator) });
    try state.addU8ToScope("rebo", value);

    const reboArgs = try state.newValue(V.ValueValue{ .SequenceKind = try V.SequenceValue.init(state.allocator) });
    try value.v.RecordKind.setU8(state.stringPool, "args", reboArgs);

    for (args) |arg| {
        try reboArgs.v.SequenceKind.appendItem(try state.newStringValue(arg));
    }

    var env = try std.process.getEnvMap(state.allocator);
    defer env.deinit();
    const reboEnv = try state.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(state.allocator) });
    try value.v.RecordKind.setU8(state.stringPool, "env", reboEnv);

    var iterator = env.iterator();
    while (iterator.next()) |entry| {
        try reboEnv.v.RecordKind.setU8(state.stringPool, entry.key_ptr.*, try state.newStringValue(entry.value_ptr.*));
    }

    const exePath = std.fs.selfExePathAlloc(state.allocator) catch return;
    defer state.allocator.free(exePath);
    try value.v.RecordKind.setU8(state.stringPool, "exe", try state.newStringValue(exePath));

    const reboLang = try state.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(state.allocator) });
    try value.v.RecordKind.setU8(state.stringPool, "lang", reboLang);
    try reboLang.v.RecordKind.setU8(state.stringPool, "eval", try state.newBuiltinValue(@import("builtins/eval.zig").eval));
    try reboLang.v.RecordKind.setU8(state.stringPool, "gc", try state.newBuiltinValue(@import("builtins/gc.zig").gc));
    try reboLang.v.RecordKind.setU8(state.stringPool, "int", try state.newBuiltinValue(@import("builtins/int.zig").int));
    try reboLang.v.RecordKind.setU8(state.stringPool, "float", try state.newBuiltinValue(@import("builtins/float.zig").float));
    try reboLang.v.RecordKind.setU8(state.stringPool, "keys", try state.newBuiltinValue(@import("builtins/keys.zig").keys));
    try reboLang.v.RecordKind.setU8(state.stringPool, "len", try state.newBuiltinValue(@import("builtins/len.zig").len));
    try reboLang.v.RecordKind.setU8(state.stringPool, "scope", try state.newBuiltinValue(@import("builtins/scope.zig").scope));
    try reboLang.v.RecordKind.setU8(state.stringPool, "scope.bind!", try state.newBuiltinValue(@import("builtins/scope.zig").bind));
    try reboLang.v.RecordKind.setU8(state.stringPool, "scope.delete!", try state.newBuiltinValue(@import("builtins/scope.zig").delete));
    try reboLang.v.RecordKind.setU8(state.stringPool, "scope.open", try state.newBuiltinValue(@import("builtins/scope.zig").open));
    try reboLang.v.RecordKind.setU8(state.stringPool, "scope.super", try state.newBuiltinValue(@import("builtins/scope.zig").super));
    try reboLang.v.RecordKind.setU8(state.stringPool, "scope.super.assign!", try state.newBuiltinValue(@import("builtins/scope.zig").assign));
    try reboLang.v.RecordKind.setU8(state.stringPool, "str", try state.newBuiltinValue(@import("builtins/str.zig").str));
    try reboLang.v.RecordKind.setU8(state.stringPool, "typeof", try state.newBuiltinValue(@import("builtins/typeof.zig").typeof));

    const reboOS = try state.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(state.allocator) });
    try value.v.RecordKind.setU8(state.stringPool, "os", reboOS);

    try reboOS.v.RecordKind.setU8(state.stringPool, "close", try state.newBuiltinValue(@import("builtins/close.zig").close));
    try reboOS.v.RecordKind.setU8(state.stringPool, "cwd", try state.newBuiltinValue(@import("builtins/cwd.zig").cwd));
    try reboOS.v.RecordKind.setU8(state.stringPool, "exit", try state.newBuiltinValue(@import("builtins/exit.zig").exit));
    try reboOS.v.RecordKind.setU8(state.stringPool, "fexists", try state.newBuiltinValue(@import("builtins/import.zig").exists));

    var client = try state.allocator.create(std.http.Client);
    client.* = std.http.Client{ .allocator = state.allocator };
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client", try state.newValue(V.ValueValue{ .HttpClientKind = V.HttpClientValue.init(client) }));
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client.start", try state.newBuiltinValue(@import("builtins/httpRequest.zig").httpStart));
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client.status", try state.newBuiltinValue(@import("builtins/httpRequest.zig").httpStatus));
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client.request", try state.newBuiltinValue(@import("builtins/httpRequest.zig").httpRequest));
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client.response", try state.newBuiltinValue(@import("builtins/httpRequest.zig").httpResponse));
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client.wait", try state.newBuiltinValue(@import("builtins/httpRequest.zig").httpWait));
    try reboOS.v.RecordKind.setU8(state.stringPool, "http.client.finish", try state.newBuiltinValue(@import("builtins/httpRequest.zig").httpFinish));
    try reboOS.v.RecordKind.setU8(state.stringPool, "listen", try state.newBuiltinValue(@import("builtins/listen.zig").listen));
    try reboOS.v.RecordKind.setU8(state.stringPool, "ls", try state.newBuiltinValue(@import("builtins/ls.zig").ls));
    try reboOS.v.RecordKind.setU8(state.stringPool, "milliTimestamp", try state.newBuiltinValue(@import("builtins/milliTimestamp.zig").milliTimestamp));
    try reboOS.v.RecordKind.setU8(state.stringPool, "open", try state.newBuiltinValue(@import("builtins/open.zig").open));
    try reboOS.v.RecordKind.setU8(state.stringPool, "path.absolute", try state.newBuiltinValue(@import("builtins/import.zig").absolute));
    try reboOS.v.RecordKind.setU8(state.stringPool, "print", try state.newBuiltinValue(@import("builtins/print.zig").print));
    try reboOS.v.RecordKind.setU8(state.stringPool, "println", try state.newBuiltinValue(@import("builtins/print.zig").println));
    try reboOS.v.RecordKind.setU8(state.stringPool, "read", try state.newBuiltinValue(@import("builtins/read.zig").read));
    try reboOS.v.RecordKind.setU8(state.stringPool, "socket", try state.newBuiltinValue(@import("builtins/socket.zig").socket));
    try reboOS.v.RecordKind.setU8(state.stringPool, "write", try state.newBuiltinValue(@import("builtins/write.zig").write));

    const reboImports = try state.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(state.allocator) });
    try value.v.RecordKind.setU8(state.stringPool, "imports", reboImports);
}
