const std = @import("std");
const Helper = @import("./helper.zig");

fn printValue(stdout: std.fs.File.Writer, v: *const Helper.Value) !void {
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
            var runner: ?*const Helper.Value = v;

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
        .UnitKind => try stdout.print("()", .{}),
    }
}

fn printSequence(stdout: std.fs.File.Writer, vs: *Helper.Value) !void {
    switch (vs.v) {
        Helper.ValueKind.SequenceKind => {
            for (vs.v.SequenceKind.items()) |v| {
                try printValue(stdout, v);
            }
        },
        else => try printValue(stdout, vs),
    }
}

pub fn print(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    const vs = machine.memoryState.getFromScope("vs") orelse machine.memoryState.unitValue.?;

    const stdout = std.io.getStdOut().writer();

    printSequence(stdout, vs) catch {};

    try machine.memoryState.pushUnitValue();
}

pub fn println(machine: *Helper.Machine, calleeAST: *Helper.Expression, argsAST: []*Helper.Expression) !void {
    _ = argsAST;
    _ = calleeAST;
    const vs = machine.memoryState.getFromScope("vs") orelse machine.memoryState.unitValue.?;

    const stdout = std.io.getStdOut().writer();

    printSequence(stdout, vs) catch {};
    stdout.print("\n", .{}) catch {};

    try machine.memoryState.pushUnitValue();
}
