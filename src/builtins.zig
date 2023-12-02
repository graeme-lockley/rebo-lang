const std = @import("std");

const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const M = @import("./machine.zig");
const Machine = M.Machine;
const MS = @import("./memory_state.zig");
const Main = @import("./main.zig");
const V = @import("./value.zig");

fn reportExpectedTypeError(machine: *Machine, position: Errors.Position, expected: []const V.ValueKind, v: V.ValueKind) !void {
    machine.replaceErr(try Errors.reportExpectedTypeError(machine.memoryState.allocator, machine.src(), position, expected, v));
    return Errors.err.InterpreterError;
}

pub fn loadBinary(allocator: std.mem.Allocator, fileName: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    const fileSize = try file.getEndPos();
    const buffer: []u8 = try file.readToEndAlloc(allocator, fileSize);

    return buffer;
}

fn osError(machine: *Machine, operation: []const u8, err: anyerror) !void {
    try machine.memoryState.pushEmptyMapValue();

    const record = machine.memoryState.peek(0);
    try record.v.RecordKind.set(machine.memoryState.allocator, "error", try machine.memoryState.newStringValue("SystemError"));
    try record.v.RecordKind.set(machine.memoryState.allocator, "operation", try machine.memoryState.newStringValue(operation));

    var buffer = std.ArrayList(u8).init(machine.memoryState.allocator);
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{err});

    try record.v.RecordKind.set(machine.memoryState.allocator, "kind", try machine.memoryState.newOwnedStringValue(&buffer));
}

pub const cwd = @import("./builtins/cwd.zig").cwd;
pub const close = @import("./builtins/close.zig").close;
pub const exit = @import("./builtins/exit.zig").exit;
pub const eval = @import("./builtins/eval.zig").eval;
pub const gc = @import("./builtins/gc.zig").gc;
pub const import = @import("./builtins/import.zig").import;
pub const imports = @import("./builtins/imports.zig").imports;
pub const int = @import("./builtins/int.zig").int;
pub const listen = @import("./builtins/listen.zig").listen;
pub const len = @import("./builtins/len.zig").len;
pub const ls = @import("./builtins/ls.zig").ls;
pub const milliTimestamp = @import("./builtins/milliTimestamp.zig").milliTimestamp;
pub const open = @import("./builtins/open.zig").open;
pub const print = @import("./builtins/print.zig").print;
pub const println = @import("./builtins/print.zig").println;
pub const read = @import("./builtins/read.zig").read;
pub const socket = @import("./builtins/socket.zig").socket;
pub const str = @import("./builtins/str.zig").str;
pub const typeof = @import("./builtins/typeof.zig").typeof;
pub const write = @import("./builtins/write.zig").write;
