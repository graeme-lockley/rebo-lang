const std = @import("std");

const AST = @import("./ast.zig");
const Builtin = @import("./builtins.zig");
const TokenKind = @import("./token_kind.zig").TokenKind;
const Value = @import("./value.zig");
const ValueKind = @import("./value.zig").ValueKind;

pub const ParserErrors = error{ FunctionValueExpectedError, LexicalError, LiteralIntError, LiteralFloatError, SyntaxError, OutOfMemory, NotYetImplemented };
pub const RuntimeErrors = error{ InterpreterError, OutOfMemory, NotYetImplemented };

pub const STREAM_SRC = "repl";

pub const Position = struct {
    start: usize,
    end: usize,
};

pub const FunctionValueExpectedError = struct {};

pub const LexicalError = struct {
    lexeme: []u8,

    pub fn deinit(self: LexicalError, allocator: std.mem.Allocator) void {
        allocator.free(self.lexeme);
    }
};

pub const ParserError = struct {
    lexeme: []const u8,
    expected: []const TokenKind,

    pub fn deinit(self: ParserError, allocator: std.mem.Allocator) void {
        allocator.free(self.lexeme);
        allocator.free(self.expected);
    }
};

pub const StackItem = struct {
    src: []const u8,
    position: Position,

    pub fn deinit(self: *StackItem, allocator: std.mem.Allocator) void {
        allocator.free(self.src);
    }

    pub fn location(self: StackItem, allocator: std.mem.Allocator) !?LocationRange {
        const content = Builtin.loadBinary(allocator, self.src) catch return null;
        defer allocator.free(content);

        var line: usize = 1;
        var column: usize = 1;

        var from = Location{ .line = 0, .column = 0 };
        var to = Location{ .line = 0, .column = 0 };

        for (content, 0..) |c, i| {
            if (i == self.position.start) {
                from = Location{ .line = line, .column = column };
            }
            if (i == self.position.end - 1) {
                to = Location{ .line = line, .column = column };
            }
            if (i >= self.position.start and i >= self.position.end) {
                break;
            }

            if (c == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
        }

        return LocationRange{ .from = from, .to = to };
    }
};

const Location = struct {
    line: usize,
    column: usize,
};

const LocationRange = struct {
    from: Location,
    to: Location,
};

pub const Error = struct {
    allocator: std.mem.Allocator,
    detail: ErrorDetail,
    stackItem: StackItem,

    pub fn init(allocator: std.mem.Allocator, detail: ErrorDetail, stackItem: StackItem) !Error {
        return Error{ .allocator = allocator, .detail = detail, .stackItem = stackItem };
    }

    pub fn deinit(self: *Error) void {
        self.detail.deinit(self.allocator);
        self.stackItem.deinit(self.allocator);
    }
};

pub const ErrorKind = enum {
    FunctionValueExpectedKind,
    LexicalKind,
    LiteralFloatOverflowKind,
    LiteralIntOverflowKind,
    ParserKind,
};

pub const ErrorDetail = union(ErrorKind) {
    FunctionValueExpectedKind: FunctionValueExpectedError,
    LexicalKind: LexicalError,
    LiteralFloatOverflowKind: LexicalError,
    LiteralIntOverflowKind: LexicalError,
    ParserKind: ParserError,

    pub fn deinit(self: ErrorDetail, allocator: std.mem.Allocator) void {
        switch (self) {
            .FunctionValueExpectedKind => {},
            .LexicalKind => self.LexicalKind.deinit(allocator),
            .LiteralFloatOverflowKind => self.LiteralFloatOverflowKind.deinit(allocator),
            .LiteralIntOverflowKind => self.LiteralIntOverflowKind.deinit(allocator),
            .ParserKind => self.ParserKind.deinit(allocator),
        }
    }
};

pub fn functionValueExpectedError(allocator: std.mem.Allocator, src: []const u8, position: Position) !Error {
    return try Error.init(allocator, ErrorDetail{ .FunctionValueExpectedKind = .{} }, StackItem{ .src = try allocator.dupe(u8, src), .position = position });
}

pub fn lexicalError(allocator: std.mem.Allocator, src: []const u8, position: Position, lexeme: []const u8) !Error {
    return try Error.init(allocator, ErrorDetail{ .LexicalKind = .{
        .lexeme = try allocator.dupe(u8, lexeme),
    } }, StackItem{ .src = try allocator.dupe(u8, src), .position = position });
}

pub fn literalFloatOverflowError(allocator: std.mem.Allocator, src: []const u8, position: Position, lexeme: []const u8) !Error {
    return try Error.init(allocator, ErrorDetail{ .LiteralFloatOverflowKind = .{
        .lexeme = try allocator.dupe(u8, lexeme),
    } }, StackItem{ .src = try allocator.dupe(u8, src), .position = position });
}

pub fn literalIntOverflowError(allocator: std.mem.Allocator, src: []const u8, position: Position, lexeme: []const u8) !Error {
    return try Error.init(allocator, ErrorDetail{ .LiteralIntOverflowKind = .{
        .lexeme = try allocator.dupe(u8, lexeme),
    } }, StackItem{ .src = try allocator.dupe(u8, src), .position = position });
}

pub fn parserError(allocator: std.mem.Allocator, src: []const u8, position: Position, lexeme: []const u8, expected: []const TokenKind) !Error {
    return try Error.init(allocator, ErrorDetail{ .ParserKind = .{
        .lexeme = try allocator.dupe(u8, lexeme),
        .expected = expected,
    } }, StackItem{ .src = try allocator.dupe(u8, src), .position = position });
}
