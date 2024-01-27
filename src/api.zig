const std = @import("std");

const ASTInterpreter = @import("./ast-interpreter.zig");
const V = @import("./value.zig");

pub const API = struct {
    interpreter: ASTInterpreter.ASTInterpreter,

    pub fn init(allocator1: std.mem.Allocator) !API {
        return API{ .interpreter = try ASTInterpreter.ASTInterpreter.init(allocator1) };
    }

    pub fn deinit(self: *API) void {
        self.interpreter.deinit();
    }

    pub fn reset(self: *API) !void {
        try self.interpreter.reset();
    }

    pub inline fn allocator(self: *API) std.mem.Allocator {
        return self.interpreter.runtime.allocator;
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

        try self.interpreter.execute(path, buffer.items);
    }

    pub fn script(self: *API, text: []const u8) !void {
        try self.interpreter.execute("script", text);
    }

    pub fn topOfStack(self: *API) ?*V.Value {
        return self.interpreter.topOfStack();
    }

    pub fn stackDepth(self: *API) usize {
        return self.interpreter.runtime.stack.items.len;
    }

    pub fn swap(self: *API) !void {
        const v1 = self.interpreter.runtime.pop();
        const v2 = self.interpreter.runtime.pop();
        try self.interpreter.runtime.push(v1);
        try self.interpreter.runtime.push(v2);
    }

    pub fn call(self: *API, numberOfArgs: usize) !void {
        try ASTInterpreter.callFn(&self.interpreter, numberOfArgs);
    }

    pub fn pop(self: *API) void {
        _ = self.interpreter.runtime.pop();
    }

    pub fn pushString(self: *API, s: []const u8) !void {
        try self.interpreter.runtime.pushStringValue(s);
    }
};
