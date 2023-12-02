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

fn booleanOption(options: *V.Value, name: []const u8, default: bool) bool {
    const option = options.v.RecordKind.get(name);

    if (option == null or option.?.v != V.ValueKind.BoolKind) {
        return default;
    }

    return option.?.v.BoolKind;
}

pub fn open(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    const path = machine.memoryState.getFromScope("path") orelse machine.memoryState.unitValue;
    const options = machine.memoryState.getFromScope("options") orelse machine.memoryState.unitValue;

    if (path.?.v != V.ValueKind.StringKind) {
        const position = if (argsAST.len > 0) argsAST[0].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.StringKind}, path.?.v);
    }
    if (options.?.v != V.ValueKind.RecordKind and options.?.v != V.ValueKind.VoidKind) {
        const position = if (argsAST.len > 1) argsAST[1].position else calleeAST.position;
        try reportExpectedTypeError(machine, position, &[_]V.ValueKind{V.ValueValue.RecordKind}, options.?.v);
    }

    if (options.?.v == V.ValueKind.VoidKind) {
        try machine.memoryState.push(try machine.memoryState.newFileValue(std.fs.cwd().openFile(path.?.v.StringKind, .{}) catch |err| return osError(machine, "open", err)));
        return;
    }

    const readF = booleanOption(options.?, "read", false);
    const writeF = booleanOption(options.?, "write", false);
    const appendF = booleanOption(options.?, "append", false);
    const truncateF = booleanOption(options.?, "truncate", false);
    const createF = booleanOption(options.?, "create", false);

    if (createF) {
        try machine.memoryState.push(try machine.memoryState.newFileValue(std.fs.cwd().createFile(path.?.v.StringKind, .{ .read = readF, .truncate = truncateF, .exclusive = true }) catch |err| return osError(machine, "open", err)));
    } else {
        const mode = if (readF and writeF) std.fs.File.OpenMode.read_write else if (readF) std.fs.File.OpenMode.read_only else std.fs.File.OpenMode.write_only;
        var file = std.fs.cwd().openFile(path.?.v.StringKind, .{ .mode = mode }) catch |err| return osError(machine, "open", err);

        try machine.memoryState.push(try machine.memoryState.newFileValue(file));

        if (appendF) {
            file.seekFromEnd(0) catch |err| return osError(machine, "open", err);
        }
    }
}

fn printValue(stdout: std.fs.File.Writer, v: *const V.Value) !void {
    switch (v.v) {
        .BoolKind => try stdout.print("{s}", .{if (v.v.BoolKind) "true" else "false"}),
        .BuiltinKind => {
            try stdout.print("fn(", .{});
            for (v.v.BuiltinKind.arguments, 0..) |argument, i| {
                if (i != 0) {
                    try stdout.print(", ", .{});
                }

                try stdout.print("{s}", .{argument.name});
                if (argument.default != null) {
                    try stdout.print(" = ", .{});
                    try printValue(stdout, argument.default.?);
                }
            }
            if (v.v.BuiltinKind.restOfArguments != null) {
                if (v.v.BuiltinKind.arguments.len > 0) {
                    try stdout.print(", ", .{});
                }

                try stdout.print("...{s}", .{v.v.BuiltinKind.restOfArguments.?});
            }
            try stdout.print(")", .{});
        },
        .CharKind => try stdout.print("{c}", .{v.v.CharKind}),
        .FileKind => try stdout.print("file: {d}", .{v.v.FileKind.file.handle}),
        .FloatKind => try stdout.print("{d}", .{v.v.FloatKind}),
        .FunctionKind => {
            try stdout.print("fn(", .{});
            for (v.v.FunctionKind.arguments, 0..) |argument, i| {
                if (i != 0) {
                    try stdout.print(", ", .{});
                }

                try stdout.print("{s}", .{argument.name});
                if (argument.default != null) {
                    try stdout.print(" = ", .{});
                    try printValue(stdout, argument.default.?);
                }
            }
            if (v.v.FunctionKind.restOfArguments != null) {
                if (v.v.BuiltinKind.arguments.len > 0) {
                    try stdout.print(", ", .{});
                }

                try stdout.print("...{s}", .{v.v.BuiltinKind.restOfArguments.?});
            }
            try stdout.print(")", .{});
        },
        .IntKind => try stdout.print("{d}", .{v.v.IntKind}),
        .RecordKind => {
            var first = true;

            try stdout.print("{s}", .{"{"});
            var iterator = v.v.RecordKind.iterator();
            while (iterator.next()) |entry| {
                if (first) {
                    first = false;
                } else {
                    try stdout.print(", ", .{});
                }

                try stdout.print("{s}: ", .{entry.key_ptr.*});
                try printValue(stdout, entry.value_ptr.*);
            }
            try stdout.print("{s}", .{"}"});
        },
        .ScopeKind => {
            var first = true;
            var runner: ?*const V.Value = v;

            try stdout.print("<", .{});
            while (true) {
                if (first) {
                    first = false;
                } else {
                    try stdout.print(" ", .{});
                }

                try stdout.print("{s}", .{"{"});
                var innerFirst = true;
                var iterator = runner.?.v.ScopeKind.values.iterator();
                while (iterator.next()) |entry| {
                    if (innerFirst) {
                        innerFirst = false;
                    } else {
                        try stdout.print(", ", .{});
                    }
                    try stdout.print("{s}: ", .{entry.key_ptr.*});
                    try printValue(stdout, entry.value_ptr.*);
                }
                try stdout.print("{s}", .{"}"});

                if (runner.?.v.ScopeKind.parent == null) {
                    break;
                }

                runner = runner.?.v.ScopeKind.parent;
            }
            try stdout.print(">", .{});
        },
        .SequenceKind => {
            try stdout.print("[", .{});
            for (v.v.SequenceKind.items(), 0..) |item, i| {
                if (i != 0) {
                    try stdout.print(", ", .{});
                }

                try printValue(stdout, item);
            }
            try stdout.print("]", .{});
        },
        .StreamKind => try stdout.print("stream: {d}", .{v.v.StreamKind.stream.handle}),
        .StringKind => try stdout.print("{s}", .{v.v.StringKind}),
        .VoidKind => try stdout.print("()", .{}),
    }
}

fn printSequence(stdout: std.fs.File.Writer, vs: *V.Value) !void {
    switch (vs.v) {
        V.ValueKind.SequenceKind => {
            for (vs.v.SequenceKind.items()) |v| {
                try printValue(stdout, v);
            }
        },
        else => try printValue(stdout, vs),
    }
}

pub fn print(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    const stdout = std.io.getStdOut().writer();
    const vs = machine.memoryState.getFromScope("vs") orelse machine.memoryState.unitValue;

    printSequence(stdout, vs.?) catch {};

    try machine.memoryState.pushUnitValue();
}

pub fn println(machine: *Machine, calleeAST: *AST.Expression, argsAST: []*AST.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    const stdout = std.io.getStdOut().writer();
    const vs = machine.memoryState.getFromScope("vs") orelse machine.memoryState.unitValue;

    printSequence(stdout, vs.?) catch {};
    stdout.print("\n", .{}) catch {};

    try machine.memoryState.pushUnitValue();
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
pub const read = @import("./builtins/read.zig").read;
pub const socket = @import("./builtins/socket.zig").socket;
pub const str = @import("./builtins/str.zig").str;
pub const typeof = @import("./builtins/typeof.zig").typeof;
pub const write = @import("./builtins/write.zig").write;
