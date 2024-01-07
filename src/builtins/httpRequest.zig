const std = @import("std");
const Helper = @import("./helper.zig");

pub fn httpRequest(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const url = (try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind})).v.StringKind.slice();
    const method = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.StringKind, Helper.ValueValue.UnitKind });
    _ = method;

    const rebo = try machine.memoryState.getU8FromScope("rebo");

    if (rebo != null and rebo.?.v == Helper.ValueKind.RecordKind) {
        const os = try rebo.?.v.RecordKind.getU8(machine.memoryState.stringPool, "os");

        if (os != null and os.?.v == Helper.ValueKind.RecordKind) {
            const client = try os.?.v.RecordKind.getU8(machine.memoryState.stringPool, "httpClient");

            if (client != null and client.?.v == Helper.ValueKind.HttpClientKind) {
                const uri = std.Uri.parse(url) catch |err| {
                    const record = try Helper.pushOsError(machine, "httpRequest", err);
                    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "url", try machine.memoryState.newStringValue(url));
                    return Helper.Errors.RuntimeErrors.InterpreterError;
                };

                var headers = std.http.Headers{ .allocator = machine.memoryState.allocator };
                defer headers.deinit();

                try headers.append("accept", "*/*");
                var request = try machine.memoryState.allocator.create(std.http.Client.Request);
                errdefer machine.memoryState.allocator.destroy(request);
                request.* = client.?.v.HttpClientKind.client.request(.GET, uri, headers, .{}) catch |err| return Helper.raiseOsError(machine, "httpRquest", err);
                errdefer request.deinit();

                request.start() catch |err| return Helper.raiseOsError(machine, "httpRquest", err);
                request.wait() catch |err| return Helper.raiseOsError(machine, "httpRquest", err);

                try machine.memoryState.push(try machine.memoryState.newValue(Helper.ValueValue{ .HttpClientRequestKind = Helper.V.HttpClientRequestValue.init(request) }));
                return;
            }
        }
    }

    const record = try Helper.M.pushNamedUserError(machine, "ExpectedTypeError", null);
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "name", try machine.memoryState.newStringValue("rebo.os.httpClient"));
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "expected", try machine.memoryState.newStringValue("Record"));
    return Helper.Errors.RuntimeErrors.InterpreterError;
}
