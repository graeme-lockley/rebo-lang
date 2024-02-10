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

pub fn httpRequest(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const url = (try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind})).v.StringKind.slice();
    const method = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.StringKind, Helper.ValueValue.UnitKind });
    const headers = try Helper.getArgument(machine, numberOfArgs, 2, &[_]Helper.ValueKind{ Helper.ValueValue.RecordKind, Helper.ValueValue.UnitKind });

    const uri = std.Uri.parse(url) catch |err| {
        const record = try Helper.pushOsError(machine, "httpRequest", err);
        try record.v.RecordKind.setU8(machine.stringPool, "url", try machine.newStringValue(url));
        return Helper.Errors.RuntimeErrors.InterpreterError;
    };

    var requestHeaders = std.http.Headers{ .allocator = machine.allocator };
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
        const record = try Helper.ER.pushNamedUserError(machine, "InvalidMethodError", null);
        try record.v.RecordKind.setU8(machine.stringPool, "method", method);
        return Helper.Errors.RuntimeErrors.InterpreterError;
    };

    var request = try machine.allocator.create(std.http.Client.Request);
    errdefer machine.allocator.destroy(request);

    request.* = client.request(requestMethod, uri, requestHeaders, .{}) catch |err| return Helper.raiseOsError(machine, "httpRequest", err);
    errdefer request.deinit();

    try machine.push(try machine.newValue(Helper.ValueValue{ .HttpClientRequestKind = Helper.V.HttpClientRequestValue.init(requestHeaders, request) }));
}

pub fn httpResponse(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const request = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.HttpClientRequestKind});

    if (request.v.HttpClientRequestKind.state != .Waiting and request.v.HttpClientRequestKind.state != .Finished) {
        try Helper.raiseOsError(machine, "rebo.os[\"http.client.response\"]", error.IllegalState);
    }

    const record = try machine.newRecordValue();
    try machine.push(record);

    try record.v.RecordKind.setU8(machine.stringPool, "version", try machine.newStringValue(@tagName(request.v.HttpClientRequestKind.request.response.version)));
    try record.v.RecordKind.setU8(machine.stringPool, "status", try machine.newIntValue(@intFromEnum(request.v.HttpClientRequestKind.request.response.status)));
    try record.v.RecordKind.setU8(machine.stringPool, "statusName", try machine.newStringValue(@tagName(request.v.HttpClientRequestKind.request.response.status)));
    try record.v.RecordKind.setU8(machine.stringPool, "reason", try machine.newStringValue(request.v.HttpClientRequestKind.request.response.reason));
    if (request.v.HttpClientRequestKind.request.response.content_length != null) {
        try record.v.RecordKind.setU8(machine.stringPool, "contentLength", try machine.newIntValue(@intCast(request.v.HttpClientRequestKind.request.response.content_length.?)));
    }
    if (request.v.HttpClientRequestKind.request.response.transfer_encoding != null) {
        try record.v.RecordKind.setU8(machine.stringPool, "transferEncoding", try machine.newStringValue(@tagName(request.v.HttpClientRequestKind.request.response.transfer_encoding.?)));
    }
    if (request.v.HttpClientRequestKind.request.response.transfer_compression != null) {
        try record.v.RecordKind.setU8(machine.stringPool, "transferCompression", try machine.newStringValue(@tagName(request.v.HttpClientRequestKind.request.response.transfer_compression.?)));
    }

    const header = try machine.newEmptySequenceValue();
    try record.v.RecordKind.setU8(machine.stringPool, "header", header);

    for (request.v.HttpClientRequestKind.request.response.headers.list.items) |field| {
        const headerField = try machine.newEmptySequenceValue();
        try header.v.SequenceKind.appendItem(headerField);
        try headerField.v.SequenceKind.appendItem(try machine.newStringValue(field.name));
        try headerField.v.SequenceKind.appendItem(try machine.newStringValue(field.value));
    }
}

pub fn httpStatus(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const request = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.HttpClientRequestKind});

    if (request.v.HttpClientRequestKind.state != .Waiting and request.v.HttpClientRequestKind.state != .Finished) {
        try Helper.raiseOsError(machine, "rebo.os[\"http.client.status\"]", error.IllegalState);
    }

    try machine.pushIntValue(@intFromEnum(request.v.HttpClientRequestKind.request.response.status));
}

pub fn httpStart(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const request = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.HttpClientRequestKind});

    request.v.HttpClientRequestKind.start() catch |err| return Helper.raiseOsError(machine, "rebo.os[\"http.client.start\"]", err);

    try machine.pushUnitValue();
}

pub fn httpFinish(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const request = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.HttpClientRequestKind});

    request.v.HttpClientRequestKind.finish() catch |err| return Helper.raiseOsError(machine, "rebo.os[\"http.client.finish\"]", err);

    try machine.pushUnitValue();
}

pub fn httpWait(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const request = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.HttpClientRequestKind});

    request.v.HttpClientRequestKind.wait() catch |err| return Helper.raiseOsError(machine, "rebo.os[\"http.client.wait\"]", err);

    try machine.pushUnitValue();
}

fn getHttpClient(machine: *Helper.Runtime) !*std.http.Client {
    const rebo = try machine.getU8FromScope("rebo");

    if (rebo != null and rebo.?.v == Helper.ValueKind.RecordKind) {
        const os = try rebo.?.v.RecordKind.getU8(machine.stringPool, "os");

        if (os != null and os.?.v == Helper.ValueKind.RecordKind) {
            const client = try os.?.v.RecordKind.getU8(machine.stringPool, "http.client");

            if (client != null and client.?.v == Helper.ValueKind.HttpClientKind) {
                return client.?.v.HttpClientKind.client;
            }
        }
    }

    const record = try Helper.ER.pushNamedUserError(machine, "ExpectedTypeError", null);
    try record.v.RecordKind.setU8(machine.stringPool, "name", try machine.newStringValue("rebo.os[\"http.client\"]"));
    try record.v.RecordKind.setU8(machine.stringPool, "expected", try machine.newStringValue("Record"));
    return Helper.Errors.RuntimeErrors.InterpreterError;
}
