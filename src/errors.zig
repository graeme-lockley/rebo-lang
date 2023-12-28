const std = @import("std");

const AST = @import("./ast.zig");
const Builtin = @import("./builtins.zig");
const TokenKind = @import("./token_kind.zig").TokenKind;
const Value = @import("./value.zig");
const ValueKind = @import("./value.zig").ValueKind;
pub const err = error{ InterpreterError, OutOfMemory, NotYetImplemented };

pub const STREAM_SRC = "repl";

pub const Position = struct {
    start: usize,
    end: usize,
};

pub const DivideByZeroError = struct {
    pub fn deinit(self: DivideByZeroError) void {
        _ = self;
    }

    pub fn append(self: DivideByZeroError, buffer: *std.ArrayList(u8)) !void {
        _ = self;
        try buffer.appendSlice("Divide By Zero");
    }
};

pub const IncompatibleOperandTypesError = struct {
    op: AST.Operator,
    left: ValueKind,
    right: ValueKind,

    pub fn deinit(self: IncompatibleOperandTypesError) void {
        _ = self;
    }

    pub fn append(self: IncompatibleOperandTypesError, buffer: *std.ArrayList(u8)) !void {
        try std.fmt.format(buffer.writer(), "Incompatible Operands: '{s}' is incompatible with {s} and {s} operands", .{ self.op.toString(), self.left.toString(), self.right.toString() });
    }
};

pub const IndexOutOfRangeError = struct {
    idx: Value.IntType,
    lower: Value.IntType,
    upper: Value.IntType,

    pub fn deinit(self: IndexOutOfRangeError) void {
        _ = self;
    }

    pub fn append(self: IndexOutOfRangeError, buffer: *std.ArrayList(u8)) !void {
        try std.fmt.format(buffer.writer(), "Index Out Of Range: {d} is out of range [{d}..{d})", .{ self.idx, self.lower, self.upper });
    }
};

pub const InvalidLHSError = struct {
    pub fn deinit(self: InvalidLHSError) void {
        _ = self;
    }

    pub fn append(self: InvalidLHSError, buffer: *std.ArrayList(u8)) !void {
        _ = self;
        try buffer.appendSlice("Invalid Left on Assignment");
    }
};

pub const LexicalError = struct {
    lexeme: []u8,

    pub fn deinit(self: LexicalError, allocator: std.mem.Allocator) void {
        allocator.free(self.lexeme);
    }

    pub fn append(self: LexicalError, buffer: *std.ArrayList(u8), nature: []const u8) !void {
        try std.fmt.format(buffer.writer(), "{s}: \"{s}\"", .{ nature, self.lexeme });
    }
};

pub const ParserError = struct {
    lexeme: []const u8,
    expected: []const TokenKind,

    pub fn deinit(self: ParserError, allocator: std.mem.Allocator) void {
        allocator.free(self.lexeme);
        allocator.free(self.expected);
    }

    pub fn append(self: ParserError, buffer: *std.ArrayList(u8)) !void {
        try std.fmt.format(buffer.writer(), "Parser Error: Found \"{s}\" but expected: ", .{self.lexeme});
        for (self.expected, 0..) |expected, i| {
            if (i > 0) {
                try buffer.appendSlice(", ");
            }
            try buffer.appendSlice(expected.toString());
        }
    }
};

pub const ExpectedTypeError = struct {
    expected: []ValueKind,
    found: ValueKind,

    pub fn deinit(self: ExpectedTypeError, allocator: std.mem.Allocator) void {
        allocator.free(self.expected);
    }

    pub fn append(self: ExpectedTypeError, buffer: *std.ArrayList(u8)) !void {
        try std.fmt.format(buffer.writer(), "Expected Type: Received value of type {s} but expected ", .{self.found.toString()});
        for (self.expected, 0..) |expected, i| {
            if (i > 0) {
                try buffer.appendSlice(", ");
            }
            try buffer.appendSlice(expected.toString());
        }
    }
};

pub const NoMatchError = struct {
    pub fn deinit(self: NoMatchError) void {
        _ = self;
    }

    pub fn append(self: NoMatchError, buffer: *std.ArrayList(u8)) !void {
        _ = self;
        try buffer.appendSlice("No Pattern Match");
    }
};

pub const UnknownIdentifierError = struct {
    identifier: []u8,

    pub fn deinit(self: UnknownIdentifierError, allocator: std.mem.Allocator) void {
        allocator.free(self.identifier);
    }

    pub fn append(self: UnknownIdentifierError, buffer: *std.ArrayList(u8)) !void {
        try std.fmt.format(buffer.writer(), "Unknown Identifier: {s}", .{self.identifier});
    }
};

pub const UserError = struct {
    pub fn deinit(self: UserError) void {
        _ = self;
    }

    pub fn append(self: UserError, buffer: *std.ArrayList(u8)) !void {
        _ = self;
        try buffer.appendSlice("User Signal");
    }
};

pub fn locationFromOffsets(allocator: std.mem.Allocator, src: []const u8, position: Position) !LocationRange {
    const content = try Builtin.loadBinary(allocator, src);
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

    pub fn location(self: StackItem, allocator: std.mem.Allocator) !LocationRange {
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

    pub fn append(self: *Error, buffer: *std.ArrayList(u8)) !void {
        try self.detail.append(buffer);

        for (self.stack.items) |item| {
            if (std.mem.eql(u8, item.src, STREAM_SRC)) {
                continue;
            }

            const locationRange = try item.location(self.allocator);
            if (item.position.start == item.position.end or item.position.start == item.position.end - 1) {
                try std.fmt.format(buffer.writer(), "\n  at {s}: {d}:{d}", .{ item.src, locationRange.from.line, locationRange.from.column });
            } else if (locationRange.from.line == locationRange.to.line) {
                try std.fmt.format(buffer.writer(), "\n  at {s}: {d},{d}-{d}", .{ item.src, locationRange.from.line, locationRange.from.column, locationRange.to.column });
            } else {
                try std.fmt.format(buffer.writer(), "\n  at {s}: {d},{d}-{d},{d}", .{ item.src, locationRange.from.line, locationRange.from.column, locationRange.to.line, locationRange.to.column });
            }
        }
    }

    pub fn print(self: *Error) !void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try self.append(&buffer);
        const msg = try buffer.toOwnedSlice();
        defer self.allocator.free(msg);

        std.log.err("{s}", .{msg});
    }

    pub fn appendStackItem(self: *Error, src: []const u8, position: Position) !void {
        var stackItem = StackItem{ .src = try self.allocator.dupe(u8, src), .position = position };

        try self.stack.append(stackItem);
    }
};

pub const ErrorKind = enum {
    DivideByZeroKind,
    ExpectedTypeKind,
    IncompatibleOperandTypesKind,
    IndexOutOfRangeKind,
    InvalidLHSErrorKind,
    LexicalKind,
    LiteralFloatOverflowKind,
    LiteralIntOverflowKind,
    NoMatchKind,
    ParserKind,
    UnknownIdentifierKind,
    UserKind,
};

pub const ErrorDetail = union(ErrorKind) {
    DivideByZeroKind: DivideByZeroError,
    ExpectedTypeKind: ExpectedTypeError,
    IncompatibleOperandTypesKind: IncompatibleOperandTypesError,
    IndexOutOfRangeKind: IndexOutOfRangeError,
    InvalidLHSErrorKind: InvalidLHSError,
    LexicalKind: LexicalError,
    LiteralFloatOverflowKind: LexicalError,
    LiteralIntOverflowKind: LexicalError,
    NoMatchKind: NoMatchError,
    ParserKind: ParserError,
    UnknownIdentifierKind: UnknownIdentifierError,
    UserKind: UserError,

    pub fn deinit(self: ErrorDetail, allocator: std.mem.Allocator) void {
        switch (self) {
            .DivideByZeroKind => self.DivideByZeroKind.deinit(),
            .ExpectedTypeKind => self.ExpectedTypeKind.deinit(allocator),
            .IncompatibleOperandTypesKind => self.IncompatibleOperandTypesKind.deinit(),
            .IndexOutOfRangeKind => self.IndexOutOfRangeKind.deinit(),
            .InvalidLHSErrorKind => self.InvalidLHSErrorKind.deinit(),
            .LexicalKind => self.LexicalKind.deinit(allocator),
            .LiteralFloatOverflowKind => self.LiteralFloatOverflowKind.deinit(allocator),
            .LiteralIntOverflowKind => self.LiteralIntOverflowKind.deinit(allocator),
            .NoMatchKind => self.NoMatchKind.deinit(),
            .ParserKind => self.ParserKind.deinit(allocator),
            .UnknownIdentifierKind => self.UnknownIdentifierKind.deinit(allocator),
            .UserKind => self.UserKind.deinit(),
        }
    }

    pub fn append(self: ErrorDetail, buffer: *std.ArrayList(u8)) !void {
        switch (self) {
            .DivideByZeroKind => try self.DivideByZeroKind.append(buffer),
            .ExpectedTypeKind => try self.ExpectedTypeKind.append(buffer),
            .IncompatibleOperandTypesKind => try self.IncompatibleOperandTypesKind.append(buffer),
            .IndexOutOfRangeKind => try self.IndexOutOfRangeKind.append(buffer),
            .InvalidLHSErrorKind => try self.InvalidLHSErrorKind.append(buffer),
            .LexicalKind => try self.LexicalKind.append(buffer, "Lexical Error"),
            .LiteralFloatOverflowKind => try self.LiteralFloatOverflowKind.append(buffer, "Literal Float Overflow Error"),
            .LiteralIntOverflowKind => try self.LiteralIntOverflowKind.append(buffer, "Literal Int Overflow Error"),
            .NoMatchKind => try self.NoMatchKind.append(buffer),
            .ParserKind => try self.ParserKind.append(buffer),
            .UnknownIdentifierKind => try self.UnknownIdentifierKind.append(buffer),
            .UserKind => try self.UserKind.append(buffer),
        }
    }
};

pub fn boolValueExpectedError(allocator: std.mem.Allocator, position: Position, found: ValueKind) !Error {
    return expectedATypeError(allocator, position, ValueKind.BoolKind, found);
}

pub fn divideByZeroError(allocator: std.mem.Allocator, src: []const u8, position: Position) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .DivideByZeroKind = .{} });

    try result.appendStackItem(src, position);

    return result;
}

pub fn expectedATypeError(allocator: std.mem.Allocator, src: []const u8, position: Position, expected: ValueKind, found: ValueKind) !Error {
    var exp = try allocator.alloc(ValueKind, 1);
    errdefer allocator.free(exp);

    exp[0] = expected;

    return expectedTypeError(allocator, src, position, exp, found);
}

pub fn reportExpectedTypeError(allocator: std.mem.Allocator, src: []const u8, position: Position, expected: []const ValueKind, v: ValueKind) !Error {
    var exp = try allocator.alloc(ValueKind, expected.len);
    errdefer allocator.free(exp);

    for (expected, 0..) |vk, i| {
        exp[i] = vk;
    }

    return try expectedTypeError(allocator, src, position, exp, v);
}

pub fn expectedTypeError(allocator: std.mem.Allocator, src: []const u8, position: Position, expected: []ValueKind, found: ValueKind) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .ExpectedTypeKind = .{ .expected = expected, .found = found } });

    try result.appendStackItem(src, position);

    return result;
}

pub fn functionValueExpectedError(allocator: std.mem.Allocator, src: []const u8, position: Position, found: ValueKind) !Error {
    return expectedATypeError(allocator, src, position, ValueKind.FunctionKind, found);
}

pub fn incompatibleOperandTypesError(
    allocator: std.mem.Allocator,
    src: []const u8,
    position: Position,
    op: AST.Operator,
    left: ValueKind,
    right: ValueKind,
) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .IncompatibleOperandTypesKind = .{
        .op = op,
        .left = left,
        .right = right,
    } });

    try result.appendStackItem(src, position);

    return result;
}

pub fn invalidLHSError(allocator: std.mem.Allocator, src: []const u8, position: Position) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .InvalidLHSErrorKind = .{} });

    try result.appendStackItem(src, position);

    return result;
}

pub fn indexOutOfRangeError(allocator: std.mem.Allocator, src: []const u8, position: Position, idx: Value.IntType, lower: Value.IntType, upper: Value.IntType) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .IndexOutOfRangeKind = .{
        .idx = idx,
        .lower = lower,
        .upper = upper,
    } });

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

pub fn noMatchError(allocator: std.mem.Allocator, src: []const u8, position: Position) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .NoMatchKind = NoMatchError{} });

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

pub fn recordValueExpectedError(allocator: std.mem.Allocator, src: []const u8, position: Position, found: ValueKind) !Error {
    return expectedATypeError(allocator, src, position, ValueKind.RecordKind, found);
}

pub fn unknownIdentifierError(allocator: std.mem.Allocator, src: []const u8, position: Position, identifier: []const u8) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .UnknownIdentifierKind = .{
        .identifier = try allocator.dupe(u8, identifier),
    } });

    try result.appendStackItem(src, position);

    return result;
}

pub fn userError(allocator: std.mem.Allocator, src: []const u8, position: Position) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .UserKind = .{} });

    try result.appendStackItem(src, position);

    return result;
}
