const std = @import("std");
const Helper = @import("./helper.zig");

fn printValue(stdout: std.fs.File.Writer, v: *const Helper.Value) !void {
    switch (v.v) {
        .ASTFunctionKind => {
            try stdout.print("fn(", .{});
            for (v.v.ASTFunctionKind.arguments, 0..) |argument, i| {
                if (i != 0) {
                    try stdout.print(", ", .{});
                }

                try stdout.print("{s}", .{argument.name.slice()});
                if (argument.default != null) {
                    try stdout.print(" = ", .{});
                    try printValue(stdout, argument.default.?);
                }
            }
            if (v.v.ASTFunctionKind.restOfArguments != null) {
                if (v.v.ASTFunctionKind.arguments.len > 0) {
                    try stdout.print(", ", .{});
                }

                try stdout.print("...{s}", .{v.v.ASTFunctionKind.restOfArguments.?.slice()});
            }
            try stdout.print(")", .{});
        },
        .BCFunctionKind => {
            try stdout.print("fn(", .{});
            for (v.v.BCFunctionKind.arguments, 0..) |argument, i| {
                if (i != 0) {
                    try stdout.print(", ", .{});
                }

                try stdout.print("{s}", .{argument.name.slice()});
                if (argument.default != null) {
                    try stdout.print(" = ", .{});
                    try printValue(stdout, argument.default.?);
                }
            }
            if (v.v.BCFunctionKind.restOfArguments != null) {
                if (v.v.BCFunctionKind.arguments.len > 0) {
                    try stdout.print(", ", .{});
                }

                try stdout.print("...{s}", .{v.v.BCFunctionKind.restOfArguments.?.slice()});
            }
            try stdout.print(")", .{});
        },
        .BoolKind => try stdout.print("{s}", .{if (v.v.BoolKind) "true" else "false"}),
        .BuiltinFunctionKind => try stdout.print("fn(...)", .{}),
        .CharKind => try stdout.print("{c}", .{v.v.CharKind}),
        .FileKind => try stdout.print("file: {d}", .{v.v.FileKind.file.handle}),
        .FloatKind => try stdout.print("{d}", .{v.v.FloatKind}),
        .HttpClientKind => try stdout.print("<http client>", .{}),
        .HttpClientRequestKind => try stdout.print("<http client response {s}>", .{@tagName(v.v.HttpClientRequestKind.state)}),
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

                try stdout.print("{s}: ", .{entry.key_ptr.*.slice()});
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
                    try stdout.print("{s}: ", .{entry.key_ptr.*.slice()});
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
        .StringKind => try stdout.print("{s}", .{v.v.StringKind.slice()}),
        .UnitKind => try stdout.print("()", .{}),
    }
}

fn printSequence(machine: *Helper.Runtime, stdout: std.fs.File.Writer, numberOfArgs: usize) !void {
    var i: usize = 1;
    while (i <= numberOfArgs) {
        const v = machine.peek(numberOfArgs - i);
        try printValue(stdout, v);

        i += 1;
    }
}

pub fn print(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const stdout = std.io.getStdOut().writer();

    printSequence(machine, stdout, numberOfArgs) catch {};

    try machine.pushUnitValue();
}

pub fn println(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const stdout = std.io.getStdOut().writer();

    printSequence(machine, stdout, numberOfArgs) catch {};
    stdout.print("\n", .{}) catch {};

    try machine.pushUnitValue();
}
