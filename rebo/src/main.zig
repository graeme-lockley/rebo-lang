const std = @import("std");
const Machine = @import("./machine.zig");

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 3 and std.mem.eql(u8, args[1], "run")) {
        const buffer: []u8 = try loadBinary(allocator, args[2]);
        defer allocator.free(buffer);

        const v = try execute(allocator, args[2], buffer);

        std.debug.print("Result: {}\n", .{v});
    } else if (args.len == 2 and std.mem.eql(u8, args[1], "repl")) {
        var buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(buffer);

        const stdin = std.io.getStdIn().reader();

        while (true) {
            std.debug.print("> ", .{});

            if (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |line| {
                if (line.len == 0) {
                    break;
                }
                const v = try execute(allocator, "console", line);

                std.debug.print("Result: {}\n", .{v});
            } else {
                break;
            }
        }
    } else {
        std.debug.print("Usage: {s} [repl|run <filename>]\n", .{args[0]});
    }
}

fn errorHandler(err: anyerror, machine: *Machine.Machine) !*Machine.Value {
    const e = machine.grabErr();
    if (e == null) {
        std.debug.print("Error: {}\n", .{err});
    } else {
        e.?.print();
        std.log.err("\n", .{});
        e.?.deinit();
    }

    // std.os.exit(1);
    return try machine.createVoidValue();
}

fn execute(allocator: std.mem.Allocator, name: []const u8, buffer: []u8) !*Machine.Value {
    var machine = Machine.Machine.init(allocator);

    return machine.execute(name, buffer) catch |err| errorHandler(err, &machine);
}

fn loadBinary(allocator: std.mem.Allocator, fileName: [:0]const u8) ![]u8 {
    var file = std.fs.cwd().openFile(fileName, .{}) catch {
        std.debug.print("Unable to open file: {s}\n", .{fileName});
        std.os.exit(1);
    };
    defer file.close();

    const fileSize = try file.getEndPos();
    const buffer: []u8 = try file.readToEndAlloc(allocator, fileSize);

    return buffer;
}

test "pull in all dependencies" {
    _ = Machine;
}
