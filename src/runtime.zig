const std = @import("std");

const AST = @import("./ast.zig");
const ER = @import("./error-reporting.zig");
const Errors = @import("./errors.zig");
const SP = @import("./string_pool.zig");
const V = @import("./value.zig");

const evalAST = @import("./ast-interpreter.zig").evalExpr;
const evalBC = @import("./bc-interpreter.zig").eval;

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

    pub fn newValue(self: *Runtime, vv: V.ValueValue) !*V.Value {
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

    pub fn appendSequenceItem(self: *Runtime, seqPosition: Errors.Position) !void {
        const seq = self.peek(1);
        const item = self.peek(0);

        if (!seq.isSequence()) {
            try ER.raiseExpectedTypeError(self, seqPosition, &[_]V.ValueKind{V.ValueValue.SequenceKind}, seq.v);
        }

        try self.pushEmptySequenceValue();
        const result = self.peek(0);

        try result.v.SequenceKind.appendSlice(seq.v.SequenceKind.items());
        try result.v.SequenceKind.appendItem(item);

        self.popn(3);
        try self.push(result);
    }

    pub fn appendSequenceItemBang(self: *Runtime, seqPosition: Errors.Position) !void {
        const seq = self.peek(1);
        const item = self.peek(0);

        if (!seq.isSequence()) {
            try ER.raiseExpectedTypeError(self, seqPosition, &[_]V.ValueKind{V.ValueValue.SequenceKind}, seq.v);
        }

        try seq.v.SequenceKind.appendItem(item);
        self.popn(1);
    }

    pub fn prependSequenceItem(self: *Runtime, seqPosition: Errors.Position) !void {
        const item = self.peek(1);
        const seq = self.peek(0);

        if (!seq.isSequence()) {
            try ER.raiseExpectedTypeError(self, seqPosition, &[_]V.ValueKind{V.ValueValue.SequenceKind}, seq.v);
        }

        try self.pushEmptySequenceValue();
        const result = self.peek(0);

        try result.v.SequenceKind.appendItem(item);
        try result.v.SequenceKind.appendSlice(seq.v.SequenceKind.items());

        self.popn(3);
        try self.push(result);
    }

    pub fn prependSequenceItemBang(self: *Runtime, seqPosition: Errors.Position) !void {
        const item = self.peek(1);
        const seq = self.peek(0);

        if (!seq.isSequence()) {
            try ER.raiseExpectedTypeError(self, seqPosition, &[_]V.ValueKind{V.ValueValue.SequenceKind}, seq.v);
        }

        try seq.v.SequenceKind.prependItem(item);

        self.popn(2);
        try self.push(seq);
    }

    pub fn appendSequenceItemsBang(self: *Runtime, seqPosition: Errors.Position, itemPosition: Errors.Position) !void {
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

    pub fn setRecordItemBang(self: *Runtime, position: Errors.Position) !void {
        const record = self.peek(2);
        const key = self.peek(1);
        const value = self.peek(0);

        if (!record.isRecord()) {
            try ER.raiseExpectedTypeError(self, position, &[_]V.ValueKind{V.ValueValue.RecordKind}, record.v);
        }
        if (!key.isString()) {
            try ER.raiseExpectedTypeError(self, position, &[_]V.ValueKind{V.ValueValue.StringKind}, key.v);
        }

        try record.v.RecordKind.set(key.v.StringKind.value, value);

        self.popn(2);
    }

    pub fn setRecordItemsBang(self: *Runtime, position: Errors.Position) !void {
        const record = self.peek(1);
        const value = self.peek(0);

        if (!record.isRecord()) {
            try ER.raiseExpectedTypeError(self, position, &[_]V.ValueKind{V.ValueValue.RecordKind}, record.v);
        }
        if (!value.isRecord()) {
            try ER.raiseExpectedTypeError(self, position, &[_]V.ValueKind{V.ValueValue.StringKind}, value.v);
        }

        var iterator = value.v.RecordKind.iterator();
        while (iterator.next()) |rv| {
            try record.v.RecordKind.set(rv.key_ptr.*, rv.value_ptr.*);
        }

        self.popn(1);
    }

    pub fn newBuiltinValue(self: *Runtime, body: V.BuiltinFunctionType) !*V.Value {
        return try self.newValue(V.ValueValue{ .BuiltinFunctionKind = .{ .body = body } });
    }

    pub fn newFileValue(self: *Runtime, file: std.fs.File) !*V.Value {
        return try self.newValue(V.ValueValue{ .FileKind = V.FileValue.init(file) });
    }

    pub fn newIntValue(self: *Runtime, v: V.IntType) !*V.Value {
        return try self.newValue(V.ValueValue{ .IntKind = v });
    }

    pub fn newRecordValue(self: *Runtime) !*V.Value {
        return try self.newValue(V.ValueValue{ .RecordKind = V.RecordValue.init(self.allocator) });
    }

    pub fn newScopeValue(self: *Runtime, parent: ?*V.Value) !*V.Value {
        return try self.newValue(V.ValueValue{ .ScopeKind = V.ScopeValue.init(self.allocator, parent) });
    }

    pub fn newEmptySequenceValue(self: *Runtime) !*V.Value {
        return try self.newValue(V.ValueValue{ .SequenceKind = try V.SequenceValue.init(self.allocator) });
    }

    pub fn newStreamValue(self: *Runtime, v: std.net.Stream) !*V.Value {
        return try self.newValue(V.ValueValue{ .StreamKind = V.StreamValue.init(v) });
    }

    pub fn newStringPoolValue(self: *Runtime, v: *SP.String) !*V.Value {
        return try self.newValue(V.ValueValue{ .StringKind = V.StringValue.initPool(v) });
    }

    pub fn newStringValue(self: *Runtime, v: []const u8) !*V.Value {
        return try self.newValue(V.ValueValue{ .StringKind = try V.StringValue.init(self.stringPool, v) });
    }

    pub fn newOwnedStringValue(self: *Runtime, v: []u8) !*V.Value {
        return try self.newValue(V.ValueValue{ .StringKind = try V.StringValue.initOwned(self.stringPool, v) });
    }

    pub fn pushValue(self: *Runtime, vv: V.ValueValue) !*V.Value {
        const v = try self.newValue(vv);

        try self.stack.append(v);

        gc(self);

        return v;
    }

    pub fn pushBoolValue(self: *Runtime, b: bool) !void {
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

    pub fn pushEmptyRecordValue(self: *Runtime) !void {
        try self.push(try self.newRecordValue());
    }

    pub fn pushCharValue(self: *Runtime, v: u8) !void {
        _ = try self.pushValue(V.ValueValue{ .CharKind = v });
    }

    pub fn pushFloatValue(self: *Runtime, v: V.FloatType) !void {
        _ = try self.pushValue(V.ValueValue{ .FloatKind = v });
    }

    pub fn pushIntValue(self: *Runtime, v: V.IntType) !void {
        _ = try self.push(try self.newIntValue(v));
    }

    pub fn pushScopeValue(self: *Runtime, parent: ?*V.Value) !void {
        _ = try self.push(try self.newScopeValue(parent));
    }

    pub fn pushEmptySequenceValue(self: *Runtime) !void {
        _ = try self.push(try self.newEmptySequenceValue());
    }

    pub fn pushStringPoolValue(self: *Runtime, v: *SP.String) !void {
        _ = try self.push(try self.newStringPoolValue(v));
    }

    pub fn pushStringValue(self: *Runtime, v: []const u8) !void {
        _ = try self.push(try self.newStringValue(v));
    }

    pub fn pushOwnedStringValue(self: *Runtime, v: []u8) !void {
        _ = try self.push(try self.newOwnedStringValue(v));
    }

    pub fn pushUnitValue(self: *Runtime) !void {
        _ = try self.push(self.unitValue.?);
    }

    pub fn pop(self: *Runtime) *V.Value {
        return self.stack.pop();
    }

    pub fn popn(self: *Runtime, n: usize) void {
        self.stack.items.len -= n;
    }

    pub fn push(self: *Runtime, v: *V.Value) !void {
        try self.stack.append(v);
    }

    pub fn peek(self: *Runtime, n: usize) *V.Value {
        return self.stack.items[self.stack.items.len - n - 1];
    }

    pub fn topOfStack(self: *Runtime) ?*V.Value {
        if (self.stack.items.len == 0) {
            return null;
        } else {
            return self.peek(0);
        }
    }

    pub fn scope(self: *Runtime) ?*V.Value {
        if (self.scopes.items.len == 0) {
            return null;
        } else {
            return self.scopes.items[self.scopes.items.len - 1];
        }
    }

    pub fn topScope(self: *Runtime) *V.Value {
        return self.scopes.items[0];
    }

    pub fn openScope(self: *Runtime) !void {
        try self.scopes.append(try self.newValue(V.ValueValue{ .ScopeKind = V.ScopeValue.init(self.allocator, self.scope()) }));
    }

    pub fn openScopeFrom(self: *Runtime, outerScope: ?*V.Value) !void {
        if (outerScope != null and outerScope.?.v != V.ValueKind.ScopeKind) unreachable;

        try self.scopes.append(try self.newValue(V.ValueValue{ .ScopeKind = V.ScopeValue.init(self.allocator, outerScope) }));
    }

    pub fn openScopeUsing(self: *Runtime, outerScope: *V.Value) !void {
        if (outerScope.v != V.ValueKind.ScopeKind) unreachable;

        try self.scopes.append(outerScope);
    }

    pub fn restoreScope(self: *Runtime) void {
        _ = self.scopes.pop();
    }

    pub fn pushScope(self: *Runtime) !void {
        self.scopes.items[self.scopes.items.len - 1] = try self.newValue(V.ValueValue{ .ScopeKind = V.ScopeValue.init(self.allocator, self.scopes.items[self.scopes.items.len - 1]) });
    }

    pub fn popScope(self: *Runtime) void {
        self.scopes.items[self.scopes.items.len - 1] = self.scopes.items[self.scopes.items.len - 1].v.ScopeKind.parent.?;
    }

    pub fn addToScope(self: *Runtime, name: *SP.String, value: *V.Value) !void {
        try self.scope().?.v.ScopeKind.set(name, value);
    }

    pub fn addU8ToScope(self: *Runtime, name: []const u8, value: *V.Value) !void {
        const spName = try self.stringPool.intern(name);
        defer spName.decRef();

        try self.scope().?.v.ScopeKind.set(spName, value);
    }

    pub fn addArrayValueToScope(self: *Runtime, name: *SP.String, values: []*V.Value) !void {
        const value = try self.newValue(V.ValueValue{ .SequenceKind = try V.SequenceValue.init(self.allocator) });
        try value.v.SequenceKind.appendSlice(values);

        try self.scope().?.v.ScopeKind.set(name, value);
    }

    pub fn updateInScope(self: *Runtime, name: *SP.String, value: *V.Value) !bool {
        return try self.scope().?.v.ScopeKind.update(name, value);
    }

    pub fn getFromScope(self: *Runtime, name: *SP.String) ?*V.Value {
        return self.scope().?.v.ScopeKind.get(name);
    }

    pub fn getU8FromScope(self: *Runtime, name: []const u8) !?*V.Value {
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

    pub fn equals(self: *Runtime) !void {
        const right = self.pop();
        const left = self.pop();

        try self.pushBoolValue(V.eq(left, right));
    }

    pub fn notEquals(self: *Runtime) !void {
        const right = self.pop();
        const left = self.pop();

        try self.pushBoolValue(!V.eq(left, right));
    }

    pub fn lessThan(self: *Runtime, position: Errors.Position) !void {
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

    pub fn lessEqual(self: *Runtime, position: Errors.Position) !void {
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

    pub fn greaterThan(self: *Runtime, position: Errors.Position) !void {
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

    pub fn greaterEqual(self: *Runtime, position: Errors.Position) !void {
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

    pub fn add(self: *Runtime, position: Errors.Position) !void {
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

    pub fn subtract(self: *Runtime, position: Errors.Position) !void {
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

    pub fn multiply(self: *Runtime, position: Errors.Position) !void {
        const right = self.pop();
        const left = self.pop();

        switch (left.v) {
            V.ValueValue.IntKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushIntValue(left.v.IntKind * right.v.IntKind);
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) * right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.FloatKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushFloatValue(left.v.FloatKind * @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushFloatValue(left.v.FloatKind * right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.StringKind => {
                if (right.v == V.ValueValue.IntKind) {
                    const mem = try self.allocator.alloc(u8, left.v.StringKind.len() * @as(usize, @intCast(right.v.IntKind)));

                    for (0..@intCast(right.v.IntKind)) |index| {
                        std.mem.copyForwards(u8, mem[index * left.v.StringKind.len() ..], left.v.StringKind.slice());
                    }

                    try self.pushOwnedStringValue(mem);
                    return;
                }
            },
            else => {},
        }
        try ER.raiseIncompatibleOperandTypesError(self, position, AST.Operator.Times, left.v, right.v);
    }

    pub fn divide(self: *Runtime, position: Errors.Position) !void {
        const right = self.pop();
        const left = self.pop();

        switch (left.v) {
            V.ValueValue.IntKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        if (right.v.IntKind == 0) {
                            try ER.raiseNamedUserError(self, "DivideByZeroError", position);
                        }
                        try self.pushIntValue(@divTrunc(left.v.IntKind, right.v.IntKind));
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        if (right.v.FloatKind == 0.0) {
                            try ER.raiseNamedUserError(self, "DivideByZeroError", position);
                        }
                        try self.pushFloatValue(@as(V.FloatType, @floatFromInt(left.v.IntKind)) / right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.FloatKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        if (right.v.IntKind == 0) {
                            try ER.raiseNamedUserError(self, "DivideByZeroError", position);
                        }
                        try self.pushFloatValue(left.v.FloatKind / @as(V.FloatType, @floatFromInt(right.v.IntKind)));
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        if (right.v.FloatKind == 0.0) {
                            try ER.raiseNamedUserError(self, "DivideByZeroError", position);
                        }
                        try self.pushFloatValue(left.v.FloatKind / right.v.FloatKind);
                        return;
                    },
                    else => {},
                }
            },
            else => {},
        }
        try ER.raiseIncompatibleOperandTypesError(self, position, AST.Operator.Divide, left.v, right.v);
    }

    pub fn power(self: *Runtime, position: Errors.Position) !void {
        const right = self.pop();
        const left = self.pop();

        switch (left.v) {
            V.ValueValue.IntKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushIntValue(std.math.pow(V.IntType, left.v.IntKind, right.v.IntKind));
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushFloatValue(std.math.pow(V.FloatType, @as(V.FloatType, @floatFromInt(left.v.IntKind)), right.v.FloatKind));
                        return;
                    },
                    else => {},
                }
            },
            V.ValueValue.FloatKind => {
                switch (right.v) {
                    V.ValueValue.IntKind => {
                        try self.pushFloatValue(std.math.pow(V.FloatType, left.v.FloatKind, @as(V.FloatType, @floatFromInt(right.v.IntKind))));
                        return;
                    },
                    V.ValueValue.FloatKind => {
                        try self.pushFloatValue(std.math.pow(V.FloatType, left.v.FloatKind, right.v.FloatKind));
                        return;
                    },
                    else => {},
                }
            },
            else => {},
        }
        try ER.raiseIncompatibleOperandTypesError(self, position, AST.Operator.Power, left.v, right.v);
    }

    pub fn modulo(self: *Runtime, position: Errors.Position) !void {
        const right = self.pop();
        const left = self.pop();

        if (!left.isInt() or !right.isInt()) {
            try ER.raiseIncompatibleOperandTypesError(self, position, AST.Operator.Modulo, left.v, right.v);
        }
        if (right.v.IntKind == 0) {
            try ER.raiseNamedUserError(self, "DivideByZeroError", position);
        }

        try self.pushIntValue(@mod(left.v.IntKind, right.v.IntKind));
    }

    pub fn dot(self: *Runtime, position: Errors.Position) !void {
        const field = self.pop();
        const record = self.pop();

        if (!record.isRecord()) {
            try ER.raiseExpectedTypeError(self, position, &[_]V.ValueKind{V.ValueValue.RecordKind}, record.v);
        }
        if (!field.isString()) {
            try ER.raiseExpectedTypeError(self, position, &[_]V.ValueKind{V.ValueValue.StringKind}, field.v);
        }

        if (record.v.RecordKind.get(field.v.StringKind.value)) |value| {
            try self.push(value);
        } else {
            try self.pushUnitValue();
        }
    }

    pub fn indexRange(self: *Runtime, exprPosition: Errors.Position, indexStartPosition: Errors.Position, indexEndPosition: Errors.Position) !void {
        const expr = self.peek(2);
        const indexStart = self.peek(1);
        const indexEnd = self.peek(0);

        switch (expr.v) {
            V.ValueValue.SequenceKind => {
                const seq = expr.v.SequenceKind;

                const start: V.IntType = try self.indexPoint(indexStart, indexStartPosition, 0, @intCast(seq.len()));
                const end: V.IntType = try self.indexPoint(indexEnd, indexEndPosition, start, @intCast(seq.len()));

                try self.pushEmptySequenceValue();
                try self.peek(0).v.SequenceKind.appendSlice(seq.items()[@intCast(start)..@intCast(end)]);
            },
            V.ValueValue.StringKind => {
                const str = expr.v.StringKind.slice();

                const start: V.IntType = try self.indexPoint(indexStart, indexStartPosition, 0, @intCast(str.len));
                const end: V.IntType = try self.indexPoint(indexEnd, indexEndPosition, start, @intCast(str.len));

                try self.pushStringValue(str[@intCast(start)..@intCast(end)]);
            },
            else => {
                try ER.raiseExpectedTypeError(self, exprPosition, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v);
            },
        }

        const result = self.pop();
        self.popn(3);
        try self.push(result);
    }

    pub fn indexRangeTo(self: *Runtime, exprPosition: Errors.Position, indexEndPosition: Errors.Position) !void {
        const expr = self.peek(1);
        const indexEnd = self.peek(0);

        switch (expr.v) {
            V.ValueValue.SequenceKind => {
                const seq = expr.v.SequenceKind;

                const end: V.IntType = try self.indexPoint(indexEnd, indexEndPosition, 0, @intCast(seq.len()));

                try self.pushEmptySequenceValue();
                try self.peek(0).v.SequenceKind.appendSlice(seq.items()[0..@intCast(end)]);
            },
            V.ValueValue.StringKind => {
                const str = expr.v.StringKind.slice();

                const end: V.IntType = try self.indexPoint(indexEnd, indexEndPosition, 0, @intCast(str.len));

                try self.pushStringValue(str[0..@intCast(end)]);
            },
            else => {
                try ER.raiseExpectedTypeError(self, exprPosition, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v);
            },
        }

        const result = self.pop();
        self.popn(2);
        try self.push(result);
    }

    pub fn indexRangeFrom(self: *Runtime, exprPosition: Errors.Position, indexStartPosition: Errors.Position) !void {
        const expr = self.peek(1);
        const indexStart = self.peek(0);

        switch (expr.v) {
            V.ValueValue.SequenceKind => {
                const seq = expr.v.SequenceKind;
                const seqLen: usize = @intCast(seq.len());

                const start: V.IntType = try self.indexPoint(indexStart, indexStartPosition, 0, @intCast(seqLen));

                try self.pushEmptySequenceValue();
                try self.peek(0).v.SequenceKind.appendSlice(seq.items()[@intCast(start)..seqLen]);
            },
            V.ValueValue.StringKind => {
                const str = expr.v.StringKind.slice();
                const strLen: usize = str.len;

                const start: V.IntType = try self.indexPoint(indexStart, indexStartPosition, 0, @intCast(strLen));

                try self.pushStringValue(str[@intCast(start)..strLen]);
            },
            else => {
                try ER.raiseExpectedTypeError(self, exprPosition, &[_]V.ValueKind{ V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v);
            },
        }

        const result = self.pop();
        self.popn(2);
        try self.push(result);
    }

    fn indexPoint(self: *Runtime, v: *V.Value, position: Errors.Position, min: V.IntType, max: V.IntType) !V.IntType {
        if (v.isInt()) {
            if (v.v.IntKind < min) return min;
            if (v.v.IntKind > max) return max;
            return v.v.IntKind;
        } else {
            try ER.raiseExpectedTypeError(self, position, &[_]V.ValueKind{V.ValueValue.IntKind}, v.v);
            return 0;
        }
    }

    pub fn indexValue(self: *Runtime, exprPosition: Errors.Position, indexPosition: Errors.Position) !void {
        const expr = self.peek(1);
        const index = self.peek(0);

        switch (expr.v) {
            V.ValueValue.RecordKind => {
                if (index.v != V.ValueValue.StringKind) {
                    try ER.raiseExpectedTypeError(self, indexPosition, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
                }

                self.popn(2);

                const value = expr.v.RecordKind.get(index.v.StringKind.value);

                if (value == null) {
                    try self.pushUnitValue();
                } else {
                    try self.push(value.?);
                }
            },
            V.ValueValue.ScopeKind => {
                if (index.v != V.ValueValue.StringKind) {
                    try ER.raiseExpectedTypeError(self, indexPosition, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
                }

                self.popn(2);

                const value = expr.v.ScopeKind.get(index.v.StringKind.value);

                if (value == null) {
                    try self.pushUnitValue();
                } else {
                    try self.push(value.?);
                }
            },
            V.ValueValue.SequenceKind => {
                if (index.v != V.ValueValue.IntKind) {
                    try ER.raiseExpectedTypeError(self, indexPosition, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
                }

                self.popn(2);

                const seq = expr.v.SequenceKind;
                const idx = index.v.IntKind;

                if (idx < 0 or idx >= seq.len()) {
                    try self.pushUnitValue();
                } else {
                    try self.push(seq.at(@intCast(idx)));
                }
            },
            V.ValueValue.StringKind => {
                if (index.v != V.ValueValue.IntKind) {
                    try ER.raiseExpectedTypeError(self, indexPosition, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
                }

                self.popn(2);

                const str = expr.v.StringKind.slice();
                const idx = index.v.IntKind;

                if (idx < 0 or idx >= str.len) {
                    try self.pushUnitValue();
                } else {
                    try self.pushCharValue(str[@intCast(idx)]);
                }
            },
            else => {
                self.popn(2);
                try ER.raiseExpectedTypeError(self, exprPosition, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.SequenceKind, V.ValueValue.StringKind }, expr.v);
            },
        }
    }

    pub fn not(self: *Runtime, position: Errors.Position) !void {
        const v = self.pop();
        if (!v.isBool()) {
            try ER.raiseExpectedTypeError(self, position, &[_]V.ValueKind{V.ValueValue.BoolKind}, v.v);
        }

        try self.pushBoolValue(!v.v.BoolKind);
    }

    pub fn duplicate(self: *Runtime) !void {
        const value = self.peek(0);
        try self.push(value);
    }

    pub fn callFn(self: *Runtime, numberOfArgs: usize) Errors.RuntimeErrors!void {
        const callee = self.peek(@intCast(numberOfArgs));

        switch (callee.v) {
            V.ValueValue.ASTFunctionKind => try callASTFn(self, numberOfArgs),
            V.ValueValue.BCFunctionKind => try callBCFn(self, numberOfArgs),
            V.ValueValue.BuiltinFunctionKind => try callBuiltinFn(self, numberOfArgs),
            else => try ER.raiseExpectedTypeError(self, null, &[_]V.ValueKind{V.ValueValue.ASTFunctionKind}, callee.v),
        }

        const result = self.pop();
        self.popn(@intCast(numberOfArgs + 1));
        try self.push(result);
    }

    fn callASTFn(self: *Runtime, numberOfArgs: usize) !void {
        const enclosingScope = self.scope().?;

        const callee = self.peek(@intCast(numberOfArgs));

        try self.openScopeFrom(callee.v.ASTFunctionKind.scope);
        defer self.restoreScope();

        try self.addU8ToScope("__caller_scope__", enclosingScope);

        var lp: usize = 0;
        const maxArgs = @min(numberOfArgs, callee.v.ASTFunctionKind.arguments.len);
        const sp = self.stack.items.len - numberOfArgs;
        while (lp < maxArgs) {
            try self.addToScope(callee.v.ASTFunctionKind.arguments[lp].name, self.stack.items[sp + lp]);
            lp += 1;
        }
        while (lp < callee.v.ASTFunctionKind.arguments.len) {
            const value = callee.v.ASTFunctionKind.arguments[lp].default orelse self.unitValue.?;

            try self.addToScope(callee.v.ASTFunctionKind.arguments[lp].name, value);
            lp += 1;
        }

        if (callee.v.ASTFunctionKind.restOfArguments != null) {
            if (numberOfArgs > callee.v.ASTFunctionKind.arguments.len) {
                const rest = self.stack.items[sp + callee.v.ASTFunctionKind.arguments.len ..];
                try self.addArrayValueToScope(callee.v.ASTFunctionKind.restOfArguments.?, rest);
            } else {
                try self.addToScope(callee.v.ASTFunctionKind.restOfArguments.?, try self.newEmptySequenceValue());
            }
        }

        try evalAST(self, callee.v.ASTFunctionKind.body);
    }

    fn callBCFn(self: *Runtime, numberOfArgs: usize) !void {
        const enclosingScope = self.scope().?;

        const callee = self.peek(@intCast(numberOfArgs));

        try self.openScopeFrom(callee.v.BCFunctionKind.scope);
        defer self.restoreScope();

        try self.addU8ToScope("__caller_scope__", enclosingScope);

        var lp: usize = 0;
        const maxArgs = @min(numberOfArgs, callee.v.BCFunctionKind.arguments.len);
        const sp = self.stack.items.len - numberOfArgs;
        while (lp < maxArgs) {
            try self.addToScope(callee.v.BCFunctionKind.arguments[lp].name, self.stack.items[sp + lp]);
            lp += 1;
        }
        while (lp < callee.v.BCFunctionKind.arguments.len) {
            const value = callee.v.BCFunctionKind.arguments[lp].default orelse self.unitValue.?;

            try self.addToScope(callee.v.BCFunctionKind.arguments[lp].name, value);
            lp += 1;
        }

        if (callee.v.BCFunctionKind.restOfArguments != null) {
            if (numberOfArgs > callee.v.BCFunctionKind.arguments.len) {
                const rest = self.stack.items[sp + callee.v.BCFunctionKind.arguments.len ..];
                try self.addArrayValueToScope(callee.v.BCFunctionKind.restOfArguments.?, rest);
            } else {
                try self.addToScope(callee.v.BCFunctionKind.restOfArguments.?, try self.newEmptySequenceValue());
            }
        }

        try evalBC(self, callee.v.BCFunctionKind.body);
    }

    fn callBuiltinFn(self: *Runtime, numberOfArgs: usize) !void {
        const callee = self.peek(@intCast(numberOfArgs));

        try callee.v.BuiltinFunctionKind.body(self, numberOfArgs);
    }

    pub fn bind(self: *Runtime) !void {
        const v = self.peek(1);
        const n = self.peek(0);

        if (n.isString()) {
            try self.addToScope(n.v.StringKind.value, v);
            self.popn(1);
        } else {
            try ER.raiseExpectedTypeError(self, null, &[_]V.ValueKind{V.ValueValue.StringKind}, n.v);
        }
    }

    pub fn assignIdentifier(self: *Runtime) !void {
        const n = self.peek(1);
        const v = self.peek(0);

        if (!n.isString()) {
            try ER.raiseExpectedTypeError(self, null, &[_]V.ValueKind{V.ValueValue.StringKind}, n.v);
        } else if (!(try self.updateInScope(n.v.StringKind.value, v))) {
            const rec = try ER.pushNamedUserError(self, "UnknownIdentifierError", null);
            try rec.v.RecordKind.setU8(self.stringPool, "identifier", n);
            return Errors.RuntimeErrors.InterpreterError;
        } else {
            self.popn(2);
            try self.push(v);
        }
    }

    pub fn assignIndex(self: *Runtime, exprPosition: Errors.Position, indexPosition: Errors.Position) !void {
        const expr = self.peek(2);
        const index = self.peek(1);
        const value = self.peek(0);

        switch (expr.v) {
            V.ValueValue.ScopeKind => {
                if (!index.isString()) {
                    try ER.raiseExpectedTypeError(self, indexPosition, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
                }

                if (!(try expr.v.ScopeKind.update(index.v.StringKind.value, value))) {
                    const rec = try ER.pushNamedUserError(self, "UnknownIdentifierError", indexPosition);
                    try rec.v.RecordKind.setU8(self.stringPool, "identifier", index);
                    return Errors.RuntimeErrors.InterpreterError;
                }
            },
            V.ValueValue.SequenceKind => {
                if (!index.isInt()) {
                    try ER.raiseExpectedTypeError(self, indexPosition, &[_]V.ValueKind{V.ValueValue.IntKind}, index.v);
                }

                const seq = expr.v.SequenceKind;
                const idx = index.v.IntKind;

                if (idx < 0 or idx >= seq.len()) {
                    try ER.raiseIndexOutOfRangeError(self, indexPosition, idx, @intCast(seq.len()));
                } else {
                    seq.set(@intCast(idx), value);
                }
            },
            V.ValueValue.RecordKind => {
                if (!index.isString()) {
                    try ER.raiseExpectedTypeError(self, indexPosition, &[_]V.ValueKind{V.ValueValue.StringKind}, index.v);
                }

                try expr.v.RecordKind.set(index.v.StringKind.value, value);
            },
            else => {
                self.popn(1);
                try ER.raiseExpectedTypeError(self, exprPosition, &[_]V.ValueKind{ V.ValueValue.RecordKind, V.ValueValue.ScopeKind, V.ValueValue.SequenceKind }, expr.v);
            },
        }

        self.popn(3);
        try self.push(value);
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
        .ASTFunctionKind => {
            markValue(v.v.ASTFunctionKind.scope, colour);
            for (v.v.ASTFunctionKind.arguments) |argument| {
                if (argument.default != null) {
                    markValue(argument.default.?, colour);
                }
            }
        },
        .BCFunctionKind => {
            markValue(v.v.BCFunctionKind.scope, colour);
            for (v.v.BCFunctionKind.arguments) |argument| {
                if (argument.default != null) {
                    markValue(argument.default.?, colour);
                }
            }
        },
        .BoolKind, .BuiltinFunctionKind, .CharKind, .IntKind, .FileKind, .FloatKind, .StreamKind, .StringKind, .UnitKind => {},
        .HttpClientKind => {},
        .HttpClientRequestKind => {},
        .RecordKind => {
            var iterator = v.v.RecordKind.iterator();
            while (iterator.next()) |entry| {
                markValue(entry.value_ptr.*, colour);
            }
        },
        .ScopeKind => markScope(&v.v.ScopeKind, colour),
        .SequenceKind => for (v.v.SequenceKind.items()) |item| {
            markValue(item, colour);
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

fn gc(state: *Runtime) void {
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

    try reboOS.v.RecordKind.setU8(state.stringPool, "bc.compile", try state.newBuiltinValue(@import("builtins/bytecode.zig").compile));
    try reboOS.v.RecordKind.setU8(state.stringPool, "bc.eval", try state.newBuiltinValue(@import("builtins/bytecode.zig").eval));
    try reboOS.v.RecordKind.setU8(state.stringPool, "bc.readFloat", try state.newBuiltinValue(@import("builtins/bytecode.zig").readFloat));
    try reboOS.v.RecordKind.setU8(state.stringPool, "bc.readInt", try state.newBuiltinValue(@import("builtins/bytecode.zig").readInt));
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
