const std = @import("std");

pub fn loadBinary(allocator: std.mem.Allocator, fileName: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    const fileSize = try file.getEndPos();
    const buffer: []u8 = try file.readToEndAlloc(allocator, fileSize);

    return buffer;
}

pub const cwd = @import("./builtins/cwd.zig").cwd;
pub const close = @import("./builtins/close.zig").close;
pub const exit = @import("./builtins/exit.zig").exit;
pub const eval = @import("./builtins/eval.zig").eval;
pub const gc = @import("./builtins/gc.zig").gc;
pub const import = @import("./builtins/import.zig").import;
pub const int = @import("./builtins/int.zig").int;
pub const float = @import("./builtins/float.zig").float;
pub const httpRequest = @import("./builtins/httpRequest.zig").httpRequest;
pub const keys = @import("./builtins/keys.zig").keys;
pub const listen = @import("./builtins/listen.zig").listen;
pub const len = @import("./builtins/len.zig").len;
pub const ls = @import("./builtins/ls.zig").ls;
pub const milliTimestamp = @import("./builtins/milliTimestamp.zig").milliTimestamp;
pub const open = @import("./builtins/open.zig").open;
pub const print = @import("./builtins/print.zig").print;
pub const println = @import("./builtins/print.zig").println;
pub const read = @import("./builtins/read.zig").read;
pub const scope = @import("./builtins/scope.zig").scope;
pub const socket = @import("./builtins/socket.zig").socket;
pub const str = @import("./builtins/str.zig").str;
pub const typeof = @import("./builtins/typeof.zig").typeof;
pub const write = @import("./builtins/write.zig").write;
