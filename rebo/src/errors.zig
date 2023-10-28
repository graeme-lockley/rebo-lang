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
    allocator: std.mem.Allocator,
    position: Position,
    op: AST.Operator,
    left: ValueKind,
    right: ValueKind,

    pub fn deinit(self: IncompatibleOperandTypesError) void {
        _ = self;
    }

    pub fn print(self: IncompatibleOperandTypesError) void {
        std.log.err("Incompatible Operands: {d}-{d}: '{s}' is incompatible with {s} and {s} operands", .{ self.position.start, self.position.end, self.op.toString(), self.left.toString(), self.right.toString() });
    }
};

pub const IndexOutOfRangeError = struct {
    position: Position,
    idx: Value.IntType,
    lower: Value.IntType,
    upper: Value.IntType,

    pub fn deinit(self: IndexOutOfRangeError) void {
        _ = self;
    }

    pub fn print(self: IndexOutOfRangeError) void {
        std.log.err("Index Out Of Range: {d}-{d}: {d} is out of range [{d}..{d})", .{ self.position.start, self.position.end, self.idx, self.lower, self.upper });
    }
};

pub const InvalidLHSError = struct {
    allocator: std.mem.Allocator,
    position: Position,

    pub fn deinit(self: InvalidLHSError) void {
        _ = self;
    }

    pub fn print(self: InvalidLHSError) void {
        std.log.err("Invalid Left on Assignment: {d}-{d}", .{ self.position.start, self.position.end });
    }
};

pub const LexicalError = struct {
    allocator: std.mem.Allocator,
    position: Position,
    lexeme: []u8,

    pub fn deinit(self: LexicalError) void {
        self.allocator.free(self.lexeme);
    }

    pub fn print(self: LexicalError, nature: []const u8) void {
        std.log.err("{s}: {d}-{d} \"{s}\"", .{ nature, self.position.start, self.position.end, self.lexeme });
    }
};

pub const ParserError = struct {
    allocator: std.mem.Allocator,
    position: Position,
    lexeme: []const u8,
    expected: []const TokenKind,

    pub fn deinit(self: ParserError) void {
        self.allocator.free(self.lexeme);
        self.allocator.free(self.expected);
    }

    pub fn print(self: ParserError) !void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try std.fmt.format(buffer.writer(), "Parser Error: {d}-{d}: Found \"{s}\" but expected: ", .{ self.position.start, self.position.end, self.lexeme });
        for (self.expected, 0..) |expected, i| {
            if (i > 0) {
                try buffer.appendSlice(", ");
            }
            try buffer.appendSlice(expected.toString());
        }

        const msg = try buffer.toOwnedSlice();
        std.log.err("{s}", .{msg});
        self.allocator.free(msg);
    }
};

pub const ExpectedTypeError = struct {
    position: Position,
    expected: []ValueKind,
    found: ValueKind,

    pub fn deinit(self: ExpectedTypeError, allocator: std.mem.Allocator) void {
        allocator.free(self.expected);
    }

    pub fn print(self: ExpectedTypeError, allocator: std.mem.Allocator) !void {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        try std.fmt.format(buffer.writer(), "Expected Type: {d}-{d}: received value of type {s} but expected ", .{ self.position.start, self.position.end, self.found.toString() });
        for (self.expected, 0..) |expected, i| {
            if (i > 0) {
                try buffer.appendSlice(", ");
            }
            try buffer.appendSlice(expected.toString());
        }

        const msg = try buffer.toOwnedSlice();
        std.log.err("{s}", .{msg});
        allocator.free(msg);
    }
};

pub const UnknownIdentifierError = struct {
    allocator: std.mem.Allocator,
    position: Position,
    identifier: []u8,

    pub fn deinit(self: UnknownIdentifierError) void {
        self.allocator.free(self.identifier);
    }

    pub fn print(self: UnknownIdentifierError) void {
        std.log.err("Unknown Identifier: {d}-{d}: {s}", .{ self.position.start, self.position.end, self.identifier });
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
                self.lexicalError.deinit();
            },
            .literalFloatOverflowError => {
                self.literalFloatOverflowError.deinit();
            },
            .literalIntOverflowError => {
                self.literalIntOverflowError.deinit();
            },
            .parserError => {
                self.parserError.deinit();
            },
            .unknownIdentifierError => {
                self.unknownIdentifierError.deinit();
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
                try self.parserError.print();
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

pub fn expectedATypeError(allocator: std.mem.Allocator, position: Position, expected: ValueKind, found: ValueKind) !Error {
    var exp = try allocator.alloc(ValueKind, 1);
    errdefer allocator.free(exp);

    exp[0] = expected;

    return expectedTypeError(allocator, position, exp, found);
}

pub fn reportExpectedTypeError(allocator: std.mem.Allocator, position: Position, expected: []const ValueKind, v: ValueKind) !Error {
    var exp = try allocator.alloc(ValueKind, expected.len);
    errdefer allocator.free(exp);

    for (expected, 0..) |vk, i| {
        exp[i] = vk;
    }

    return try expectedTypeError(allocator, position, exp, v);
}

pub fn expectedTypeError(allocator: std.mem.Allocator, position: Position, expected: []ValueKind, found: ValueKind) !Error {
    return Error.init(allocator, ErrorDetail{ .expectedTypeError = .{ .position = position, .expected = expected, .found = found } });
}

pub fn functionValueExpectedError(allocator: std.mem.Allocator, position: Position, found: ValueKind) !Error {
    return expectedATypeError(allocator, position, ValueKind.FunctionKind, found);
}

pub fn incompatibleOperandTypesError(
    allocator: std.mem.Allocator,
    position: Position,
    op: AST.Operator,
    left: ValueKind,
    right: ValueKind,
) !Error {
    return Error.init(allocator, ErrorDetail{ .incompatibleOperandTypesError = .{
        .allocator = allocator,
        .position = position,
        .op = op,
        .left = left,
        .right = right,
    } });
}

pub fn invalidLHSError(allocator: std.mem.Allocator, position: Position) !Error {
    return Error.init(allocator, ErrorDetail{ .invalidLHSError = .{ .allocator = allocator, .position = position } });
}

pub fn indexOutOfRangeError(allocator: std.mem.Allocator, position: Position, idx: Value.IntType, lower: Value.IntType, upper: Value.IntType) !Error {
    return Error.init(allocator, ErrorDetail{ .indexOutOfRangeError = .{
        .position = position,
        .idx = idx,
        .lower = lower,
        .upper = upper,
    } });
}

pub fn lexicalError(allocator: std.mem.Allocator, position: Position, lexeme: []const u8) !Error {
    return Error.init(allocator, ErrorDetail{ .lexicalError = .{
        .allocator = allocator,
        .position = position,
        .lexeme = try allocator.dupe(u8, lexeme),
    } });
}

pub fn literalFloatOverflowError(allocator: std.mem.Allocator, position: Position, lexeme: []const u8) !Error {
    return Error.init(allocator, ErrorDetail{ .literalFloatOverflowError = .{
        .allocator = allocator,
        .position = position,
        .lexeme = try allocator.dupe(u8, lexeme),
    } });
}

pub fn literalIntOverflowError(allocator: std.mem.Allocator, position: Position, lexeme: []const u8) !Error {
    return Error.init(allocator, ErrorDetail{ .literalIntOverflowError = .{
        .allocator = allocator,
        .position = position,
        .lexeme = try allocator.dupe(u8, lexeme),
    } });
}

pub fn parserError(allocator: std.mem.Allocator, position: Position, lexeme: []const u8, expected: []const TokenKind) !Error {
    return Error.init(allocator, ErrorDetail{ .parserError = .{
        .allocator = allocator,
        .position = position,
        .lexeme = try allocator.dupe(u8, lexeme),
        .expected = expected,
    } });
}

pub fn recordValueExpectedError(allocator: std.mem.Allocator, position: Position, found: ValueKind) !Error {
    return expectedATypeError(allocator, position, ValueKind.RecordKind, found);
}

pub fn unknownIdentifierError(allocator: std.mem.Allocator, position: Position, identifier: []const u8) !Error {
    return Error.init(allocator, ErrorDetail{ .unknownIdentifierError = .{
        .allocator = allocator,
        .position = position,
        .identifier = try allocator.dupe(u8, identifier),
    } });
}
