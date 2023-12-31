const std = @import("std");

const Machine = @import("./machine.zig").Machine;
const V = @import("./value.zig");

const importFile = @import("./builtins/import.zig").importFile;

pub const API = struct {
    machine: Machine,

    pub fn init(allocator1: std.mem.Allocator) !API {
        return API{ .machine = try Machine.init(allocator1) };
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
};
