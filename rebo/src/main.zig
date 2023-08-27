const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const eval = @import("eval.zig");

pub fn main() !void {
    var allocator = &std.heap.page_allocator;

    var args = try std.process.argsAlloc(allocator.*);
    defer std.process.argsFree(allocator.*, args);

    if (args.len == 3 and std.mem.eql(u8, args[1], "run")) {
        const buffer: []u8 = try loadBinary(allocator, args[2]);
        defer allocator.free(buffer);

        const v = try execute(allocator, buffer);

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
                const v = try execute(allocator, line);

                std.debug.print("Result: {}\n", .{v});
            } else {
                break;
            }
        }
    } else {
        std.debug.print("Usage: {s} [repl|run <filename>]\n", .{args[0]});
    }
}

fn execute(allocator: *const std.mem.Allocator, buffer: []u8) !*eval.Value {
    var l = lexer.Lexer.init(buffer);
    var p = parser.Parser.init(allocator, l);

    const ast = try p.expr();

    const machine = eval.Machine.init(allocator);

    return try machine.eval(ast);
}

fn loadBinary(allocator: *const std.mem.Allocator, fileName: [:0]const u8) ![]u8 {
    var file = std.fs.cwd().openFile(fileName, .{}) catch {
        std.debug.print("Unable to open file: {s}\n", .{fileName});
        std.os.exit(1);
    };
    defer file.close();

    const fileSize = try file.getEndPos();
    const buffer: []u8 = try file.readToEndAlloc(allocator.*, fileSize);

    return buffer;
}

test "pull in all dependencies" {
    _ = lexer;
    _ = parser;
    _ = eval;
}
