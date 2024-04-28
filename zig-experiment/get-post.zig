//usr/bin/env zig run "$0" -- "$@"; exit

const std = @import("std");

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const err = gpa.deinit();
        if (err == std.heap.Check.leak) {
            stdout.print("Failed to deinit allocator\n", .{}) catch {};
            std.process.exit(1);
        }
    }

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    if (false) {
        const payload = "{\"name\": \"Apple MacBook Pro 16\", \"data\": {\"Hard disk size\": \"1 TB\", \"CPU model\": \"Intel Core i9\", \"year\": 2019, \"price\": 1849.99}}";

        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();

        const headerBuffer = try allocator.alloc(u8, 1024);
        defer allocator.free(headerBuffer);

        const requestHeaders = try allocator.alloc(std.http.Header, 1);
        errdefer allocator.free(requestHeaders);

        // requestHeaders[0].name = "transfer-encoding";
        // requestHeaders[0].value = "chunked";
        requestHeaders[0].name = "Content-Length";
        requestHeaders[0].value = "130";
        // requestHeaders[2].name = "Content-Type";
        // requestHeaders[2].value = "application/json";

        try stdout.print("-- 1\n", .{});
        var result = try client.open(.POST, try std.Uri.parse("https://api.restful-api.dev/objects"), std.http.Client.RequestOptions{ .server_header_buffer = headerBuffer, .headers = std.http.Client.Request.Headers{ .content_type = .{ .override = "application/json" } }, .extra_headers = requestHeaders });
        defer result.deinit();

        try stdout.print("-- 2\n", .{});
        try result.send();
        try stdout.print("-- 3: {d}\n", .{payload.len});
        try result.writeAll(payload);
        try stdout.print("-- 4\n", .{});
        try result.finish();
        try stdout.print("-- 5\n", .{});
        try result.wait();

        try stdout.print("-- 6\n", .{});
        const buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(buffer);

        while (true) {
            const readResult = try result.read(buffer);
            if (readResult == 0) {
                break;
            }
            try response.appendSlice(buffer[0..readResult]);
        }
        try stdout.print("-- 7\n", .{});

        try stdout.print("Status: {s}\n", .{response.items});
    } else {
        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();

        const headerBuffer = try allocator.alloc(u8, 1024);
        defer allocator.free(headerBuffer);

        var result = try client.open(.GET, try std.Uri.parse("https://api.restful-api.dev/objects"), std.http.Client.RequestOptions{ .server_header_buffer = headerBuffer });

        try result.send();
        try result.finish();
        try result.wait();

        const buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(buffer);

        while (true) {
            const readResult = try result.read(buffer);
            if (readResult == 0) {
                break;
            }
            try response.appendSlice(buffer[0..readResult]);
        }

        result.deinit();

        try stdout.print("Status: {s}\n", .{response.items});
    }
}
