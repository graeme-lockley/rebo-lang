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

    const args = [_][]const u8{ "ls", "-Fal", "/" };

    const proc = try std.ChildProcess.run(.{
        .allocator = allocator,
        .argv = &args,
    });

    // on success, we own the output streams
    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    const term = proc.term;

    std.debug.print("Stdout: {s}\n", .{proc.stdout});
    std.debug.print("Stderr: {s}\n", .{proc.stderr});
    std.debug.print("term: {d}\n", .{@intFromEnum(term)});
}
