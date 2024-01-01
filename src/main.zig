const std = @import("std");

const API = @import("./api.zig").API;
const V = @import("./value.zig");

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

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2 and std.mem.eql(u8, args[1], "help")) {
        try stdout.print("Usage: {s} [file ...args | repl | help]\n", .{args[0]});
        std.process.exit(1);
    } else if (args.len == 1 or args.len == 2 and std.mem.eql(u8, args[1], "repl")) {
        var buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(buffer);

        var rebo = try API.init(allocator);
        defer rebo.deinit();

        const stdin = std.io.getStdIn().reader();

        while (true) {
            try stdout.print("> ", .{});

            if (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |line| {
                if (line.len == 0) {
                    break;
                }
                rebo.script(line) catch |err| {
                    try errorHandler(err, &rebo);
                    continue;
                };

                try printResult(allocator, &rebo);
                try rebo.reset();
            } else {
                break;
            }
        }
    } else {
        const startTime = std.time.milliTimestamp();

        var rebo = try API.init(allocator);
        defer rebo.deinit();

        try rebo.import(args[1]);

        const executeTime = std.time.milliTimestamp();
        std.log.info("time: {d}ms", .{executeTime - startTime});
    }
}

fn printResult(allocator: std.mem.Allocator, rebo: *API) !void {
    if (rebo.topOfStack()) |v| {
        const result = try v.toString(allocator, V.Style.Pretty);
        std.debug.print("Result: {s}\n", .{result});
        allocator.free(result);
    }
}

fn errorHandler(err: anyerror, rebo: *API) !void {
    err catch {};
    // if (err == Errors.RuntimeErrors.InterpreterError) {
    //     const v = machine.memoryState.topOfStack() orelse machine.memoryState.unitValue.?;

    // } else {
    // try stdout.print("Unknown Error: {}\n", err);
    const result = try rebo.topOfStack().?.toString(rebo.allocator(), V.Style.Pretty);
    try stdout.print("Error: {s}\n", .{result});
    rebo.allocator().free(result);
    // }
}
