const std = @import("std");

const Machine = @import("./machine.zig");
const V = @import("./value.zig");

const importFile = @import("./builtins/import.zig").importFile;

pub const API = struct {
    machine: Machine.Machine,

    pub fn init(allocator1: std.mem.Allocator) !API {
        return API{ .machine = try Machine.Machine.init(allocator1) };
    }

    pub fn deinit(self: *API) void {
        self.machine.deinit();
    }

    pub fn reset(self: *API) !void {
        try self.machine.reset();
    }

    pub inline fn allocator(self: *API) std.mem.Allocator {
        return self.machine.memoryState.allocator;
    }

    pub fn import(self: *API, path: []const u8) !void {
        try importFile(&self.machine, path);
    }

    pub fn script(self: *API, text: []const u8) !void {
        try self.machine.execute("script", text);
    }

    pub fn topOfStack(self: *API) ?*V.Value {
        return self.machine.topOfStack();
    }

    pub fn stackDepth(self: *API) usize {
        return self.machine.memoryState.stack.items.len;
    }

    pub fn swap(self: *API) !void {
        const v1 = self.machine.memoryState.pop();
        const v2 = self.machine.memoryState.pop();
        try self.machine.memoryState.push(v1);
        try self.machine.memoryState.push(v2);
    }

    pub fn call(self: *API, numberOfArgs: usize) !void {
        try Machine.callFn(&self.machine, numberOfArgs);
    }

    pub fn pushString(self: *API, s: []const u8) !void {
        try self.machine.memoryState.pushStringValue(s);
    }
};
