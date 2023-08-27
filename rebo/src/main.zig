const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const eval = @import("eval.zig");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    var allocator = &std.heap.page_allocator;

    var l = lexer.Lexer.init("true");
    var p = parser.Parser.init(allocator, l);

    var e = try p.expr();

    const m = eval.Machine.init(allocator);

    const v = try m.eval(e);

    std.debug.print("Result: {}\n", .{v});
}

test "pull in all dependencies" {
    _ = lexer;
    _ = parser;
    _ = eval;
}
