const std = @import("std");
const Helper = @import("./helper.zig");

pub const protocol_map = std.ComptimeStringMap(std.http.Method, .{
    .{ "GET", .GET },
    .{ "POST", .POST },
    .{ "PUT", .PUT },
    .{ "DELETE", .DELETE },
    .{ "HEAD", .HEAD },
    .{ "OPTIONS", .OPTIONS },
    .{ "PATH", .PATCH },
});

pub fn httpRequest(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const url = (try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind})).v.StringKind.slice();
    const method = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.StringKind, Helper.ValueValue.UnitKind });
    const headers = try Helper.getArgument(machine, numberOfArgs, 2, &[_]Helper.ValueKind{ Helper.ValueValue.RecordKind, Helper.ValueValue.UnitKind });

    const uri = std.Uri.parse(url) catch |err| {
        const record = try Helper.pushOsError(machine, "httpRequest", err);
        try record.v.RecordKind.setU8(machine.memoryState.stringPool, "url", try machine.memoryState.newStringValue(url));
        return Helper.Errors.RuntimeErrors.InterpreterError;
    };

    var requestHeaders = std.http.Headers{ .allocator = machine.memoryState.allocator };
    errdefer requestHeaders.deinit();

    if (headers.isRecord()) {
        var iterator = headers.v.RecordKind.iterator();

        while (iterator.next()) |entry| {
            if (entry.value_ptr.*.isString()) {
                try requestHeaders.append(entry.key_ptr.*.slice(), entry.value_ptr.*.v.StringKind.slice());
            }
        }
    }

    const client = try getHttpClient(machine);

    const requestMethod = if (method.isUnit()) .GET else if (protocol_map.get(method.v.StringKind.slice())) |v| v else {
        const record = try Helper.ER.pushNamedUserError(&machine.memoryState, "InvalidMethodError", null);
        try record.v.RecordKind.setU8(machine.memoryState.stringPool, "method", method);
        return Helper.Errors.RuntimeErrors.InterpreterError;
    };

    var request = try machine.memoryState.allocator.create(std.http.Client.Request);
    errdefer machine.memoryState.allocator.destroy(request);

    request.* = client.request(requestMethod, uri, requestHeaders, .{}) catch |err| return Helper.raiseOsError(machine, "httpRequest", err);
    errdefer request.deinit();

    try machine.memoryState.push(try machine.memoryState.newValue(Helper.ValueValue{ .HttpClientRequestKind = Helper.V.HttpClientRequestValue.init(requestHeaders, request) }));
}

pub fn httpResponse(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const request = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.HttpClientRequestKind});

    if (request.v.HttpClientRequestKind.state != .Waiting and request.v.HttpClientRequestKind.state != .Finished) {
        try Helper.raiseOsError(machine, "rebo.os[\"http.client.response\"]", error.IllegalState);
    }

    const record = try machine.memoryState.newRecordValue();
    try machine.memoryState.push(record);

    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "version", try machine.memoryState.newStringValue(@tagName(request.v.HttpClientRequestKind.request.response.version)));
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "status", try machine.memoryState.newIntValue(@intFromEnum(request.v.HttpClientRequestKind.request.response.status)));
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "statusName", try machine.memoryState.newStringValue(@tagName(request.v.HttpClientRequestKind.request.response.status)));
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "reason", try machine.memoryState.newStringValue(request.v.HttpClientRequestKind.request.response.reason));
    if (request.v.HttpClientRequestKind.request.response.content_length != null) {
        try record.v.RecordKind.setU8(machine.memoryState.stringPool, "contentLength", try machine.memoryState.newIntValue(@intCast(request.v.HttpClientRequestKind.request.response.content_length.?)));
    }
    if (request.v.HttpClientRequestKind.request.response.transfer_encoding != null) {
        try record.v.RecordKind.setU8(machine.memoryState.stringPool, "transferEncoding", try machine.memoryState.newStringValue(@tagName(request.v.HttpClientRequestKind.request.response.transfer_encoding.?)));
    }
    if (request.v.HttpClientRequestKind.request.response.transfer_compression != null) {
        try record.v.RecordKind.setU8(machine.memoryState.stringPool, "transferCompression", try machine.memoryState.newStringValue(@tagName(request.v.HttpClientRequestKind.request.response.transfer_compression.?)));
    }

    const header = try machine.memoryState.newEmptySequenceValue();
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "header", header);

    for (request.v.HttpClientRequestKind.request.response.headers.list.items) |field| {
        const headerField = try machine.memoryState.newEmptySequenceValue();
        try header.v.SequenceKind.appendItem(headerField);
        try headerField.v.SequenceKind.appendItem(try machine.memoryState.newStringValue(field.name));
        try headerField.v.SequenceKind.appendItem(try machine.memoryState.newStringValue(field.value));
    }
}

pub fn httpStatus(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const request = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.HttpClientRequestKind});

    if (request.v.HttpClientRequestKind.state != .Waiting and request.v.HttpClientRequestKind.state != .Finished) {
        try Helper.raiseOsError(machine, "rebo.os[\"http.client.status\"]", error.IllegalState);
    }

    try machine.memoryState.pushIntValue(@intFromEnum(request.v.HttpClientRequestKind.request.response.status));
}

pub fn httpStart(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const request = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.HttpClientRequestKind});

    request.v.HttpClientRequestKind.start() catch |err| return Helper.raiseOsError(machine, "rebo.os[\"http.client.start\"]", err);

    try machine.memoryState.pushUnitValue();
}

pub fn httpFinish(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const request = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.HttpClientRequestKind});

    request.v.HttpClientRequestKind.finish() catch |err| return Helper.raiseOsError(machine, "rebo.os[\"http.client.finish\"]", err);

    try machine.memoryState.pushUnitValue();
}

pub fn httpWait(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const request = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.HttpClientRequestKind});

    request.v.HttpClientRequestKind.wait() catch |err| return Helper.raiseOsError(machine, "rebo.os[\"http.client.wait\"]", err);

    try machine.memoryState.pushUnitValue();
}

fn getHttpClient(machine: *Helper.ASTInterpreter) !*std.http.Client {
    const rebo = try machine.memoryState.getU8FromScope("rebo");

    if (rebo != null and rebo.?.v == Helper.ValueKind.RecordKind) {
        const os = try rebo.?.v.RecordKind.getU8(machine.memoryState.stringPool, "os");

        if (os != null and os.?.v == Helper.ValueKind.RecordKind) {
            const client = try os.?.v.RecordKind.getU8(machine.memoryState.stringPool, "http.client");

            if (client != null and client.?.v == Helper.ValueKind.HttpClientKind) {
                return client.?.v.HttpClientKind.client;
            }
        }
    }

    const record = try Helper.ER.pushNamedUserError(&machine.memoryState, "ExpectedTypeError", null);
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "name", try machine.memoryState.newStringValue("rebo.os[\"http.client\"]"));
    try record.v.RecordKind.setU8(machine.memoryState.stringPool, "expected", try machine.memoryState.newStringValue("Record"));
    return Helper.Errors.RuntimeErrors.InterpreterError;
}
