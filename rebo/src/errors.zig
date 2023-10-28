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

    pub fn print(self: DivideByZeroError) void {
        _ = self;
        std.log.err("Divide By Zero", .{});
    }
};

pub const IncompatibleOperandTypesError = struct {
    op: AST.Operator,
    left: ValueKind,
    right: ValueKind,

    pub fn deinit(self: IncompatibleOperandTypesError) void {
        _ = self;
    }

    pub fn print(self: IncompatibleOperandTypesError) void {
        std.log.err("Incompatible Operands: '{s}' is incompatible with {s} and {s} operands", .{ self.op.toString(), self.left.toString(), self.right.toString() });
    }
};

pub const IndexOutOfRangeError = struct {
    idx: Value.IntType,
    lower: Value.IntType,
    upper: Value.IntType,

    pub fn deinit(self: IndexOutOfRangeError) void {
        _ = self;
    }

    pub fn print(self: IndexOutOfRangeError) void {
        std.log.err("Index Out Of Range: {d} is out of range [{d}..{d})", .{ self.idx, self.lower, self.upper });
    }
};

pub const InvalidLHSError = struct {
    pub fn deinit(self: InvalidLHSError) void {
        _ = self;
    }

    pub fn print(self: InvalidLHSError) void {
        _ = self;
        std.log.err("Invalid Left on Assignment", .{});
    }
};

pub const LexicalError = struct {
    lexeme: []u8,

    pub fn deinit(self: LexicalError, allocator: std.mem.Allocator) void {
        allocator.free(self.lexeme);
    }

    pub fn print(self: LexicalError, nature: []const u8) void {
        std.log.err("{s}: \"{s}\"", .{ nature, self.lexeme });
    }
};

pub const ParserError = struct {
    lexeme: []const u8,
    expected: []const TokenKind,

    pub fn deinit(self: ParserError, allocator: std.mem.Allocator) void {
        allocator.free(self.lexeme);
        allocator.free(self.expected);
    }

    pub fn print(self: ParserError, allocator: std.mem.Allocator) !void {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        try std.fmt.format(buffer.writer(), "Parser Error: Found \"{s}\" but expected: ", .{self.lexeme});
        for (self.expected, 0..) |expected, i| {
            if (i > 0) {
                try buffer.appendSlice(", ");
            }
            try buffer.appendSlice(expected.toString());
        }

        const msg = try buffer.toOwnedSlice();
        defer allocator.free(msg);

        std.log.err("{s}", .{msg});
    }
};

pub const ExpectedTypeError = struct {
    expected: []ValueKind,
    found: ValueKind,

    pub fn deinit(self: ExpectedTypeError, allocator: std.mem.Allocator) void {
        allocator.free(self.expected);
    }

    pub fn print(self: ExpectedTypeError, allocator: std.mem.Allocator) !void {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        try std.fmt.format(buffer.writer(), "Expected Type: Received value of type {s} but expected ", .{self.found.toString()});
        for (self.expected, 0..) |expected, i| {
            if (i > 0) {
                try buffer.appendSlice(", ");
            }
            try buffer.appendSlice(expected.toString());
        }

        const msg = try buffer.toOwnedSlice();
        defer allocator.free(msg);

        std.log.err("{s}", .{msg});
    }
};

pub const UnknownIdentifierError = struct {
    identifier: []u8,

    pub fn deinit(self: UnknownIdentifierError, allocator: std.mem.Allocator) void {
        allocator.free(self.identifier);
    }

    pub fn print(self: UnknownIdentifierError) void {
        std.log.err("Unknown Identifier: {s}", .{self.identifier});
    }
};

pub const StackItem = struct {
    src: []const u8,
    position: Position,

    pub fn location(self: StackItem, allocator: std.mem.Allocator) !LocationRange {
        const content = try Builtin.loadBinary(allocator, self.src);
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

    pub fn print(self: *Error) !void {
        try self.detail.print(self.allocator);

        for (self.stack.items) |item| {
            if (std.mem.eql(u8, item.src, STREAM_SRC)) {
                continue;
            }

            const locationRange = try item.location(self.allocator);
            if (item.position.start == item.position.end or item.position.start == item.position.end - 1) {
                std.log.err("  at {s}: {d}:{d}", .{ item.src, locationRange.from.line, locationRange.from.column });
            } else if (locationRange.from.line == locationRange.to.line) {
                std.log.err("  at {s}: {d},{d}-{d}", .{ item.src, locationRange.from.line, locationRange.from.column, locationRange.to.column });
            } else {
                std.log.err("  at {s}: {d},{d}-{d},{d}", .{ item.src, locationRange.from.line, locationRange.from.column, locationRange.to.line, locationRange.to.column });
            }
        }
    }

    pub fn appendStackItem(self: *Error, src: []const u8, position: Position) !void {
        var stackItem = StackItem{ .src = try self.allocator.dupe(u8, src), .position = position };

        try self.stack.append(stackItem);
    }
};

pub const ErrorDetail = union(enum) {
    divideByZero: DivideByZeroError,
    expectedTypeError: ExpectedTypeError,
    incompatibleOperandTypesError: IncompatibleOperandTypesError,
    indexOutOfRangeError: IndexOutOfRangeError,
    invalidLHSError: InvalidLHSError,
    lexicalError: LexicalError,
    literalFloatOverflowError: LexicalError,
    literalIntOverflowError: LexicalError,
    parserError: ParserError,
    unknownIdentifierError: UnknownIdentifierError,

    pub fn deinit(self: ErrorDetail, allocator: std.mem.Allocator) void {
        switch (self) {
            .divideByZero => {
                self.divideByZero.deinit();
            },
            .expectedTypeError => {
                self.expectedTypeError.deinit(allocator);
            },
            .incompatibleOperandTypesError => {
                self.incompatibleOperandTypesError.deinit();
            },
            .indexOutOfRangeError => {
                self.indexOutOfRangeError.deinit();
            },
            .invalidLHSError => {
                self.invalidLHSError.deinit();
            },
            .lexicalError => {
                self.lexicalError.deinit(allocator);
            },
            .literalFloatOverflowError => {
                self.literalFloatOverflowError.deinit(allocator);
            },
            .literalIntOverflowError => {
                self.literalIntOverflowError.deinit(allocator);
            },
            .parserError => {
                self.parserError.deinit(allocator);
            },
            .unknownIdentifierError => {
                self.unknownIdentifierError.deinit(allocator);
            },
        }
    }

    pub fn print(self: ErrorDetail, allocator: std.mem.Allocator) !void {
        switch (self) {
            .divideByZero => {
                self.divideByZero.print();
            },
            .expectedTypeError => {
                try self.expectedTypeError.print(allocator);
            },
            .incompatibleOperandTypesError => {
                self.incompatibleOperandTypesError.print();
            },
            .indexOutOfRangeError => {
                self.indexOutOfRangeError.print();
            },
            .invalidLHSError => {
                self.invalidLHSError.print();
            },
            .lexicalError => {
                self.lexicalError.print("Lexical Error");
            },
            .literalFloatOverflowError => {
                self.literalFloatOverflowError.print("Literal Float Overflow Error");
            },
            .literalIntOverflowError => {
                self.literalIntOverflowError.print("Literal Int Overflow Error");
            },
            .parserError => {
                try self.parserError.print(allocator);
            },
            .unknownIdentifierError => {
                self.unknownIdentifierError.print();
            },
        }
    }
};

pub fn boolValueExpectedError(allocator: std.mem.Allocator, position: Position, found: ValueKind) !Error {
    return expectedATypeError(allocator, position, ValueKind.BoolKind, found);
}

pub fn divideByZeroError(allocator: std.mem.Allocator, src: []const u8, position: Position) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .divideByZero = .{} });

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
    var result = try Error.init(allocator, ErrorDetail{ .expectedTypeError = .{ .expected = expected, .found = found } });

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
    var result = try Error.init(allocator, ErrorDetail{ .incompatibleOperandTypesError = .{
        .op = op,
        .left = left,
        .right = right,
    } });

    try result.appendStackItem(src, position);

    return result;
}

pub fn invalidLHSError(allocator: std.mem.Allocator, src: []const u8, position: Position) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .invalidLHSError = .{} });

    try result.appendStackItem(src, position);

    return result;
}

pub fn indexOutOfRangeError(allocator: std.mem.Allocator, src: []const u8, position: Position, idx: Value.IntType, lower: Value.IntType, upper: Value.IntType) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .indexOutOfRangeError = .{
        .idx = idx,
        .lower = lower,
        .upper = upper,
    } });

    try result.appendStackItem(src, position);

    return result;
}

pub fn lexicalError(allocator: std.mem.Allocator, src: []const u8, position: Position, lexeme: []const u8) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .lexicalError = .{
        .lexeme = try allocator.dupe(u8, lexeme),
    } });

    try result.appendStackItem(src, position);

    return result;
}

pub fn literalFloatOverflowError(allocator: std.mem.Allocator, src: []const u8, position: Position, lexeme: []const u8) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .literalFloatOverflowError = .{
        .lexeme = try allocator.dupe(u8, lexeme),
    } });

    try result.appendStackItem(src, position);

    return result;
}

pub fn literalIntOverflowError(allocator: std.mem.Allocator, src: []const u8, position: Position, lexeme: []const u8) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .literalIntOverflowError = .{
        .lexeme = try allocator.dupe(u8, lexeme),
    } });

    try result.appendStackItem(src, position);

    return result;
}

pub fn parserError(allocator: std.mem.Allocator, src: []const u8, position: Position, lexeme: []const u8, expected: []const TokenKind) !Error {
    var result = try Error.init(allocator, ErrorDetail{ .parserError = .{
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
    var result = try Error.init(allocator, ErrorDetail{ .unknownIdentifierError = .{
        .identifier = try allocator.dupe(u8, identifier),
    } });

    try result.appendStackItem(src, position);

    return result;
}
