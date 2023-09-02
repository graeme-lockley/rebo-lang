const std = @import("std");

const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const Lexer = @import("./lexer.zig");
const Parser = @import("./parser.zig");

const Colour = enum(u2) {
    Black = 0,
    White = 1,
};

pub const Value = struct {
    colour: Colour,
    next: ?*Value,

    v: ValueValue,

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        _ = allocator;
        switch (self.v) {
            .void, .bool => {},
        }
    }
};

pub const ValueValue = union(enum) {
    void: void,
    bool: bool,
};

pub const MemoryState = struct {
    allocator: std.mem.Allocator,
    stack: std.ArrayList(*Value),
    colour: Colour,
    root: ?*Value,
    memory_size: u32,
    memory_capacity: u32,

    fn push_value(self: *MemoryState, vv: ValueValue) error{OutOfMemory}!*Value {
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

    pub fn push_bool_value(self: *MemoryState, b: bool) error{OutOfMemory}!*Value {
        return try self.push_value(ValueValue{ .bool = b });
    }

    pub fn push_unit_value(self: *MemoryState) error{OutOfMemory}!*Value {
        return try self.push_value(ValueValue{ .void = void{} });
    }

    pub fn pop(self: *MemoryState) *Value {
        return self.stack.pop();
    }

    pub fn push(self: *MemoryState, v: *Value) error{OutOfMemory}!void {
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
    _ = state;
    if (possible_value == null) {
        return;
    }

    const v = possible_value.?;

    if (v.colour == colour) {
        return;
    }

    v.colour = colour;

    switch (v.v) {
        .bool, .void => {},
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

fn evalExpr(machine: *Machine, e: *AST.Expr) !void {
    switch (e.*) {
        .literalBool => {
            _ = try machine.createBoolValue(e.literalBool);
        },
        .literalVoid => {
            _ = try machine.createVoidValue();
        },
    }
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
        self.memoryState.deinit();
    }

    pub fn createVoidValue(self: *Machine) !*Value {
        return self.memoryState.push_unit_value();
    }

    pub fn createBoolValue(self: *Machine, v: bool) !*Value {
        return self.memoryState.push_bool_value(v);
    }

    pub fn eval(self: *Machine, e: *AST.Expr) !void {
        try evalExpr(self, e);
    }

    pub fn execute(self: *Machine, name: []const u8, buffer: []u8) !void {
        const allocator = self.memoryState.allocator;

        var l = Lexer.Lexer.init(allocator);

        l.initBuffer(name, buffer) catch |err| {
            self.err = l.grabErr();
            return err;
        };

        var p = Parser.Parser.init(allocator, l);

        const ast = p.expr() catch |err| {
            self.err = p.grabErr();
            return err;
        };
        defer AST.destroy(allocator, ast);

        try self.eval(ast);
    }

    pub fn grabErr(self: *Machine) ?Errors.Error {
        const err = self.err;
        self.err = null;

        return err;
    }

    pub fn topOfStack(self: *Machine) ?*Value {
        return self.memoryState.topOfStack();
    }

    pub fn reset(self: *Machine) void {
        self.memoryState.deinit();
        self.memoryState = try initMemoryState(self.memoryState.allocator);
    }
};

test "pull in all dependencies" {
    _ = Parser;
    _ = Lexer;
}
