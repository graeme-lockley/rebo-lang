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

pub const UserError = struct {};

pub fn locationFromOffsets(allocator: std.mem.Allocator, src: []const u8, position: Position) !?LocationRange {
    const content = Builtin.loadBinary(allocator, src) catch return null;
    defer allocator.free(content);

    var line: usize = 1;
    var column: usize = 1;

    var from = Location{ .line = 0, .column = 0 };
    var to = Location{ .line = 0, .column = 0 };

    for (content, 0..) |c, i| {
        if (i == position.start) {
            from = Location{ .line = line, .column = column };
        }
        if (i == position.end - 1) {
            to = Location{ .line = line, .column = column };
        }
        if (i >= position.start and i >= position.end) {
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

pub const StackItem = struct {
    src: []const u8,
    position: Position,

    pub fn location(self: StackItem, allocator: std.mem.Allocator) !?LocationRange {
        return try locationFromOffsets(allocator, self.src, self.position);
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
    stack: std.ArrayList(StackItem),

    pub fn init(allocator: std.mem.Allocator, detail: ErrorDetail) !Error {
        return Error{ .allocator = allocator, .detail = detail, .stack = std.ArrayList(StackItem).init(allocator) };
    }

    pub fn deinit(self: *Error) void {
        self.detail.deinit(self.allocator);

        for (self.stack.items) |item| {
            self.allocator.free(item.src);
        }

        self.stack.deinit();
    }

    pub fn appendStackItem(self: *Error, src: []const u8, position: Position) !void {
        var stackItem = StackItem{ .src = try self.allocator.dupe(u8, src), .position = position };

        try self.stack.append(stackItem);
    }
};

pub const ErrorKind = enum {
    FunctionValueExpectedKind,
    LexicalKind,
    LiteralFloatOverflowKind,
    LiteralIntOverflowKind,
    ParserKind,
    UserKind,
};

pub const ErrorDetail = union(ErrorKind) {
    FunctionValueExpectedKind: FunctionValueExpectedError,
    LexicalKind: LexicalError,
    LiteralFloatOverflowKind: LexicalError,
    LiteralIntOverflowKind: LexicalError,
    ParserKind: ParserError,
    UserKind: UserError,

    pub fn deinit(self: ErrorDetail, allocator: std.mem.Allocator) void {
        switch (self) {
            .FunctionValueExpectedKind, .UserKind => {},
            .LexicalKind => self.LexicalKind.deinit(allocator),
            .LiteralFloatOverflowKind => self.LiteralFloatOverflowKind.deinit(allocator),
            .LiteralIntOverflowKind => self.LiteralIntOverflowKind.deinit(allocator),
            .ParserKind => self.ParserKind.deinit(allocator),
        }
    }
};

pub fn functionValueExpectedError(allocator: std.mem.Allocator, src: []const u8, position: Position) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .FunctionValueExpectedKind = .{} });

    try result.appendStackItem(src, position);

    return result;
}

pub fn lexicalError(allocator: std.mem.Allocator, src: []const u8, position: Position, lexeme: []const u8) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .LexicalKind = .{
        .lexeme = try allocator.dupe(u8, lexeme),
    } });

    try result.appendStackItem(src, position);

    return result;
}

pub fn literalFloatOverflowError(allocator: std.mem.Allocator, src: []const u8, position: Position, lexeme: []const u8) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .LiteralFloatOverflowKind = .{
        .lexeme = try allocator.dupe(u8, lexeme),
    } });

    try result.appendStackItem(src, position);

    return result;
}

pub fn literalIntOverflowError(allocator: std.mem.Allocator, src: []const u8, position: Position, lexeme: []const u8) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .LiteralIntOverflowKind = .{
        .lexeme = try allocator.dupe(u8, lexeme),
    } });

    try result.appendStackItem(src, position);

    return result;
}

pub fn parserError(allocator: std.mem.Allocator, src: []const u8, position: Position, lexeme: []const u8, expected: []const TokenKind) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .ParserKind = .{
        .lexeme = try allocator.dupe(u8, lexeme),
        .expected = expected,
    } });

    try result.appendStackItem(src, position);

    return result;
}

pub fn userError(allocator: std.mem.Allocator, src: []const u8, position: ?Position) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .UserKind = .{} });

    if (position != null) {
        try result.appendStackItem(src, position.?);
    }

    return result;
}
