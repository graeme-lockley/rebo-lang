const std = @import("std");
const Helper = @import("./helper.zig");

pub fn listen(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const host = (try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind})).v.StringKind.slice();
    const port = (try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.IntKind})).v.IntKind;
    const cb = (try Helper.getArgument(machine, numberOfArgs, 2, &[_]Helper.ValueKind{Helper.ValueValue.FunctionKind})).v.FunctionKind;

    var server = std.net.StreamServer.init(.{});
    server.reuse_address = true;
    defer server.deinit();

    server.listen(std.net.Address.parseIp(host, @intCast(port)) catch |err| return Helper.raiseOsError(machine, "listen", err)) catch |err| return Helper.raiseOsError(machine, "listen", err);

    while (true) {
        var conn = server.accept() catch |err| return Helper.raiseOsError(machine, "listen", err);
        const stream = conn.stream;

        try machine.memoryState.openScopeFrom(cb.scope);

        errdefer machine.memoryState.restoreScope();

        if (cb.arguments.len > 0) {
            try machine.memoryState.addToScope(cb.arguments[0].name, try machine.memoryState.newStreamValue(stream));
        }
        var lp: u8 = 1;
        while (lp < cb.arguments.len) {
            try machine.memoryState.addToScope(cb.arguments[lp].name, machine.memoryState.unitValue.?);
            lp += 1;
        }

        machine.eval(cb.body) catch |err| {
            machine.memoryState.restoreScope();
            return err;
        };

        _ = machine.pop();
        machine.memoryState.restoreScope();
    }
}
