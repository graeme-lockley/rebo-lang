const std = @import("std");
const Helper = @import("./helper.zig");

pub fn listen(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    const host = (try Helper.getArgument(machine, calleeAST, argsAST, "host", 0, &[_]Helper.ValueKind{Helper.ValueValue.OldStringKind})).v.OldStringKind;
    const port = (try Helper.getArgument(machine, calleeAST, argsAST, "port", 1, &[_]Helper.ValueKind{Helper.ValueValue.IntKind})).v.IntKind;
    const cb = (try Helper.getArgument(machine, calleeAST, argsAST, "cb", 2, &[_]Helper.ValueKind{Helper.ValueValue.FunctionKind})).v.FunctionKind;

    var server = std.net.StreamServer.init(.{});
    server.reuse_address = true;
    defer server.deinit();

    server.listen(std.net.Address.parseIp(host, @intCast(port)) catch |err| return Helper.silentOsError(machine, "listen", err)) catch |err| return Helper.silentOsError(machine, "listen", err);

    while (true) {
        var conn = server.accept() catch |err| return Helper.silentOsError(machine, "listen", err);
        const stream = conn.stream;

        machine.memoryState.openScopeFrom(cb.scope) catch |err| return Helper.silentOsError(machine, "listen", err);

        errdefer machine.memoryState.restoreScope();

        if (cb.arguments.len > 0) {
            try machine.memoryState.addToScope(cb.arguments[0].name, try machine.memoryState.newStreamValue(stream));
        }
        var lp: u8 = 1;
        while (lp < cb.arguments.len) {
            machine.memoryState.addToScope(cb.arguments[lp].name, machine.memoryState.unitValue.?) catch |err| return Helper.osError(machine, "addToScope", err);
            lp += 1;
        }

        if (Helper.evalExpr(machine, cb.body)) {
            machine.memoryState.restoreScope();
            return;
        } else {
            _ = machine.pop();
            machine.memoryState.restoreScope();
        }
    }
}
