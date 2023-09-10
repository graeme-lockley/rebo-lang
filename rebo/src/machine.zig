const std = @import("std");

const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const Lexer = @import("./lexer.zig");
const Parser = @import("./parser.zig");

pub const Value = @import("./value.zig").Value;
const ValueValue = @import("./value.zig").ValueValue;
const Colour = @import("./value.zig").Colour;

pub const MemoryState = struct {
    allocator: std.mem.Allocator,
    stack: std.ArrayList(*Value),
    colour: Colour,
    root: ?*Value,
    memory_size: u32,
    memory_capacity: u32,

    fn pushValue(self: *MemoryState, vv: ValueValue) !*Value {
        const v = try self.allocator.create(Value);
        self.memory_size += 1;

        v.colour = self.colour;
        v.v = vv;
        v.next = self.root;

        self.root = v;

        try self.stack.append(v);

        gc(self);

        return v;
    }

    pub fn pushBoolValue(self: *MemoryState, b: bool) !void {
        _ = try self.pushValue(ValueValue{ .BoolKind = b });
    }

    pub fn pushEmptyMapValue(self: *MemoryState) !void {
        _ = try self.pushValue(ValueValue{ .RecordKind = std.StringHashMap(*Value).init(self.allocator) });
    }

    pub fn pushIntValue(self: *MemoryState, v: i32) !void {
        _ = try self.pushValue(ValueValue{ .IntKind = v });
    }

    pub fn pushListValue(self: *MemoryState, size: usize) !void {
        var items = try self.allocator.alloc(*Value, size);

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

        _ = try self.pushValue(ValueValue{ .SequenceKind = items });
    }

    pub fn pushUnitValue(self: *MemoryState) !void {
        _ = try self.pushValue(ValueValue{ .VoidKind = void{} });
    }

    pub fn pop(self: *MemoryState) *Value {
        return self.stack.pop();
    }

    pub fn push(self: *MemoryState, v: *Value) !void {
        try self.stack.append(v);
    }

    pub fn peek(self: *MemoryState, n: u32) *Value {
        return self.stack.items[self.stack.items.len - n - 1];
    }

    pub fn topOfStack(self: *MemoryState) ?*Value {
        if (self.stack.items.len == 0) {
            return null;
        } else {
            return self.peek(0);
        }
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
            var runner: ?*Value = self.root;
            while (runner != null) {
                const next = runner.?.next;
                number_of_values += 1;
                runner = next;
            }
        }
        std.log.info("gc: memory state stack length: {d} vs {d}: values: {d} vs {d}", .{ self.stack.items.len, count, self.memory_size, number_of_values });
        self.stack.deinit();
        self.stack = std.ArrayList(*Value).init(self.allocator);
        force_gc(self);
        self.stack.deinit();

        // self.stack.deinit();
        // var runner: ?*Value = self.root;
        // while (runner != null) {
        //     const next = runner.?.next;
        //     runner.?.deinit(self.allocator);
        //     self.allocator.destroy(runner.?);
        //     runner = next;
        // }
    }
};

fn mark(state: *MemoryState, possible_value: ?*Value, colour: Colour) void {
    if (possible_value == null) {
        return;
    }

    const v = possible_value.?;

    if (v.colour == colour) {
        return;
    }

    v.colour = colour;

    switch (v.v) {
        .BoolKind, .IntKind, .VoidKind => {},
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

fn sweep(state: *MemoryState, colour: Colour) void {
    var runner: *?*Value = &state.root;
    while (runner.* != null) {
        if (runner.*.?.colour != colour) {
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
    const new_colour = if (state.colour == Colour.Black) Colour.White else Colour.Black;

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

        if (@intToFloat(f32, state.memory_size) / @intToFloat(f32, state.memory_capacity) > threshold_rate) {
            state.memory_capacity *= 2;
            std.log.info("gc: double heap capacity to {}", .{state.memory_capacity});
        }
    }
}

fn evalExpr(machine: *Machine, e: *AST.Expression) bool {
    switch (e.*.kind) {
        .binaryOp => {
            if (evalExpr(machine, e.kind.binaryOp.left)) return true;
            if (evalExpr(machine, e.*.kind.binaryOp.right)) return true;

            const right = machine.pop();
            const left = machine.pop();

            if (left.v != ValueValue.IntKind or right.v != ValueValue.IntKind) {
                machine.replaceErr(Errors.incompatibleOperandTypesError(machine.memoryState.allocator, e.*.position, e.*.kind.binaryOp.op, left.v, right.v));

                return true;
            }

            const result = switch (e.*.kind.binaryOp.op) {
                AST.Operator.Plus => left.v.IntKind + right.v.IntKind,
                AST.Operator.Minus => left.v.IntKind - right.v.IntKind,
                AST.Operator.Times => left.v.IntKind * right.v.IntKind,
                AST.Operator.Divide => div: {
                    if (right.v.IntKind == 0) {
                        machine.replaceErr(Errors.divideByZeroError(machine.memoryState.allocator, e.*.position));

                        return true;
                    }

                    break :div @divTrunc(left.v.IntKind, right.v.IntKind);
                },
            };

            machine.createIntValue(result) catch return true;
        },
        .literalBool => {
            machine.createBoolValue(e.kind.literalBool) catch return true;
        },
        .literalInt => {
            machine.createIntValue(e.kind.literalInt) catch return true;
        },
        .literalSequence => {
            for (e.*.kind.literalSequence) |v| {
                if (evalExpr(machine, v)) return true;
            }

            machine.createListValue(e.*.kind.literalSequence.len) catch return true;
        },
        .literalRecord => {
            machine.memoryState.pushEmptyMapValue() catch return true;
            var map = machine.topOfStack().?;

            for (e.*.kind.literalRecord) |entry| {
                if (evalExpr(machine, entry.value)) return true;

                const value = machine.pop();
                const oldKey = map.v.RecordKind.getKey(entry.key);

                if (oldKey == null) {
                    map.v.RecordKind.put(machine.memoryState.allocator.dupe(u8, entry.key) catch return true, value) catch return true;
                } else {
                    map.v.RecordKind.put(oldKey.?, value) catch return true;
                }
            }
        },
        .literalVoid => {
            machine.createVoidValue() catch return true;
        },
    }

    return false;
}

fn initMemoryState(allocator: std.mem.Allocator) !MemoryState {
    const default_colour = Colour.White;

    return MemoryState{
        .allocator = allocator,
        .stack = std.ArrayList(*Value).init(allocator),
        .colour = default_colour,
        .root = null,
        .memory_size = 0,
        .memory_capacity = 2,
    };
}
pub const Machine = struct {
    memoryState: MemoryState,
    err: ?Errors.Error,

    pub fn init(allocator: std.mem.Allocator) Machine {
        return Machine{
            .memoryState = try initMemoryState(allocator),
            .err = null,
        };
    }

    pub fn deinit(self: *Machine) void {
        self.eraseErr();
        self.memoryState.deinit();
    }

    pub fn createVoidValue(self: *Machine) !void {
        try self.memoryState.pushUnitValue();
    }

    pub fn createBoolValue(self: *Machine, v: bool) !void {
        try self.memoryState.pushBoolValue(v);
    }

    pub fn createIntValue(self: *Machine, v: i32) !void {
        try self.memoryState.pushIntValue(v);
    }

    pub fn createStringValue(self: *Machine, v: []const u8) !void {
        try self.memoryState.pushStringValue(v);
    }

    pub fn createListValue(self: *Machine, size: usize) !void {
        return self.memoryState.pushListValue(size);
    }

    pub fn eval(self: *Machine, e: *AST.Expression) !void {
        if (evalExpr(self, e)) {
            return error.InterpreterError;
        }
    }

    pub fn execute(self: *Machine, name: []const u8, buffer: []const u8) !void {
        const allocator = self.memoryState.allocator;

        var l = Lexer.Lexer.init(allocator);

        l.initBuffer(name, buffer) catch |err| {
            self.err = l.grabErr();
            return err;
        };

        var p = Parser.Parser.init(allocator, l);

        const ast = p.expression() catch |err| {
            self.err = p.grabErr();
            return err;
        };
        defer AST.destroy(allocator, ast);

        try self.eval(ast);
        // _ = try self.createVoidValue();
    }

    fn replaceErr(self: *Machine, err: Errors.Error) void {
        self.eraseErr();
        self.err = err;
    }

    pub fn eraseErr(self: *Machine) void {
        if (self.err != null) {
            self.err.?.deinit();
            self.err = null;
        }
    }

    pub fn grabErr(self: *Machine) ?Errors.Error {
        const err = self.err;
        self.err = null;

        return err;
    }

    pub fn pop(self: *Machine) *Value {
        return self.memoryState.pop();
    }

    pub fn topOfStack(self: *Machine) ?*Value {
        return self.memoryState.topOfStack();
    }

    pub fn reset(self: *Machine) void {
        self.eraseErr();
        self.memoryState.deinit();
        self.memoryState = try initMemoryState(self.memoryState.allocator);
    }
};
