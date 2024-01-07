const std = @import("std");
const Helper = @import("./helper.zig");

pub fn httpRequestResponse(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const request = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.HttpClientRequestKind});

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

// let response = httpRequest("https://jsonplaceholder.typicode.com/posts") ; rebo.os["http.client.response"](response)
// let response = httpRequest("https://jsonplaceholder.typicode.com/postss") ; rebo.os["http.client.response"](response)
