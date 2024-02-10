const std = @import("std");

const ASTInterpreter = @import("./ast-interpreter.zig");
const Runtime = @import("./runtime.zig").Runtime;

const V = @import("./value.zig");

pub const API = struct {
    runtime: Runtime,

    pub fn init(allocator1: std.mem.Allocator) !API {
        return API{ .runtime = try Runtime.init(allocator1) };
    }

    pub fn deinit(self: *API) void {
        self.runtime.deinit();
    }

    pub fn reset(self: *API) !void {
        try self.runtime.reset();
    }

    pub fn allocator(self: *API) std.mem.Allocator {
        return self.runtime.allocator;
    }

    pub fn import(self: *API, path: []const u8) !void {
        var buffer = std.ArrayList(u8).init(self.allocator());
        defer buffer.deinit();

        try buffer.appendSlice("import(\"");
        for (path) |c| {
            switch (c) {
                10 => try buffer.appendSlice("\\n"),
                34 => try buffer.appendSlice("\\\""),
                92 => try buffer.appendSlice("\\\\"),
                0...9, 11...31 => try std.fmt.format(buffer.writer(), "\\x{d};", .{c}),
                else => try buffer.append(c),
            }
        }
        try buffer.appendSlice("\")");

        try ASTInterpreter.execute(&self.runtime, path, buffer.items);
    }

    pub fn script(self: *API, text: []const u8) !void {
        try ASTInterpreter.execute(&self.runtime, "script", text);
    }

    pub fn topOfStack(self: *API) ?*V.Value {
        return self.runtime.topOfStack();
    }

    pub fn stackDepth(self: *API) usize {
        return self.runtime.stack.items.len;
    }

    pub fn swap(self: *API) !void {
        const v1 = self.runtime.pop();
        const v2 = self.runtime.pop();
        try self.runtime.push(v1);
        try self.runtime.push(v2);
    }

    pub fn call(self: *API, numberOfArgs: usize) !void {
        try ASTInterpreter.callFn(&self.runtime, numberOfArgs);
    }

    pub fn pop(self: *API) void {
        _ = self.runtime.pop();
    }

    pub fn pushString(self: *API, s: []const u8) !void {
        try self.runtime.pushStringValue(s);
    }
};
