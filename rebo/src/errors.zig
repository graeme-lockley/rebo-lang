const std = @import("std");

const AST = @import("./ast.zig");
const TokenKind = @import("./token_kind.zig").TokenKind;
const Value = @import("./value.zig");
const ValueKind = @import("./value.zig").ValueKind;
pub const err = error{ InterpreterError, OutOfMemory, NotYetImplemented };

pub const Position = struct {
    start: usize,
    end: usize,
};

pub const BoolValueExpectedError = struct {
    allocator: std.mem.Allocator,
    position: Position,
    found: ValueKind,

    pub fn deinit(self: BoolValueExpectedError) void {
        _ = self;
    }

    pub fn print(self: BoolValueExpectedError) void {
        std.log.err("Type Error: {d}-{d}: if guard needs to be boolean rather than {s}", .{ self.position.start, self.position.end, self.found.toString() });
    }
};

pub const DivideByZeroError = struct {
    allocator: std.mem.Allocator,
    position: Position,

    pub fn deinit(self: DivideByZeroError) void {
        _ = self;
    }

    pub fn print(self: DivideByZeroError) void {
        std.log.err("Divide By Zero: {d}-{d}", .{ self.position.start, self.position.end });
    }
};

pub const FunctionValueExpectedError = struct {
    allocator: std.mem.Allocator,
    position: Position,

    pub fn deinit(self: FunctionValueExpectedError) void {
        _ = self;
    }

    pub fn print(self: FunctionValueExpectedError) void {
        std.log.err("Function Value Expected: {d}-{d}: expression value is not a function", .{ self.position.start, self.position.end });
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

pub const RecordValueExpectedError = struct {
    allocator: std.mem.Allocator,
    position: Position,

    pub fn deinit(self: RecordValueExpectedError) void {
        _ = self;
    }

    pub fn print(self: RecordValueExpectedError) void {
        std.log.err("Record Value Expected: {d}-{d}: expression value is not a record", .{ self.position.start, self.position.end });
    }
};

pub const ExpectedTypeError = struct {
    allocator: std.mem.Allocator,
    position: Position,
    expected: []ValueKind,
    found: ValueKind,

    pub fn deinit(self: ExpectedTypeError) void {
        self.allocator.free(self.expected);
    }

    pub fn print(self: ExpectedTypeError) !void {
        var buffer = std.ArrayList(u8).init(self.allocator);
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
        self.allocator.free(msg);
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

pub const Error = union(enum) {
    boolValueExpected: BoolValueExpectedError,
    divideByZero: DivideByZeroError,
    expectedTypeError: ExpectedTypeError,
    functionValueExpectedError: FunctionValueExpectedError,
    incompatibleOperandTypesError: IncompatibleOperandTypesError,
    indexOutOfRangeError: IndexOutOfRangeError,
    invalidLHSError: InvalidLHSError,
    lexicalError: LexicalError,
    literalFloatOverflowError: LexicalError,
    literalIntOverflowError: LexicalError,
    parserError: ParserError,
    recordValueExpectedError: RecordValueExpectedError,
    unknownIdentifierError: UnknownIdentifierError,

    pub fn deinit(self: Error) void {
        switch (self) {
            .boolValueExpected => {
                self.boolValueExpected.deinit();
            },
            .divideByZero => {
                self.divideByZero.deinit();
            },
            .expectedTypeError => {
                self.expectedTypeError.deinit();
            },
            .functionValueExpectedError => {
                self.functionValueExpectedError.deinit();
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
            .lexicalError, .literalFloatOverflowError, .literalIntOverflowError => {
                self.lexicalError.deinit();
            },
            .parserError => {
                self.parserError.deinit();
            },
            .recordValueExpectedError => {
                self.recordValueExpectedError.deinit();
            },
            .unknownIdentifierError => {
                self.unknownIdentifierError.deinit();
            },
        }
    }

    pub fn print(self: Error) !void {
        switch (self) {
            .boolValueExpected => {
                self.boolValueExpected.print();
            },
            .divideByZero => {
                self.divideByZero.print();
            },
            .expectedTypeError => {
                try self.expectedTypeError.print();
            },
            .functionValueExpectedError => {
                self.functionValueExpectedError.print();
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
                self.lexicalError.print("Literal Float Overflow Error");
            },
            .literalIntOverflowError => {
                self.lexicalError.print("Literal Int Overflow Error");
            },
            .parserError => {
                try self.parserError.print();
            },
            .recordValueExpectedError => {
                self.recordValueExpectedError.print();
            },
            .unknownIdentifierError => {
                self.unknownIdentifierError.print();
            },
        }
    }
};

pub fn boolValueExpectedError(allocator: std.mem.Allocator, position: Position, found: ValueKind) Error {
    return Error{ .boolValueExpected = .{ .allocator = allocator, .position = position, .found = found } };
}

pub fn divideByZeroError(allocator: std.mem.Allocator, position: Position) Error {
    return Error{ .divideByZero = .{ .allocator = allocator, .position = position } };
}

pub fn expectedTypeError(allocator: std.mem.Allocator, position: Position, expected: []ValueKind, found: ValueKind) Error {
    return Error{ .expectedTypeError = .{ .allocator = allocator, .position = position, .expected = expected, .found = found } };
}

pub fn functionValueExpectedError(allocator: std.mem.Allocator, position: Position) Error {
    return Error{ .functionValueExpectedError = .{ .allocator = allocator, .position = position } };
}

pub fn incompatibleOperandTypesError(
    allocator: std.mem.Allocator,
    position: Position,
    op: AST.Operator,
    left: ValueKind,
    right: ValueKind,
) Error {
    return Error{ .incompatibleOperandTypesError = .{
        .allocator = allocator,
        .position = position,
        .op = op,
        .left = left,
        .right = right,
    } };
}

pub fn invalidLHSError(allocator: std.mem.Allocator, position: Position) Error {
    return Error{ .invalidLHSError = .{ .allocator = allocator, .position = position } };
}

pub fn indexOutOfRangeError(position: Position, idx: Value.IntType, lower: Value.IntType, upper: Value.IntType) Error {
    return Error{ .indexOutOfRangeError = .{
        .position = position,
        .idx = idx,
        .lower = lower,
        .upper = upper,
    } };
}

pub fn lexicalError(allocator: std.mem.Allocator, position: Position, lexeme: []const u8) !Error {
    return Error{ .lexicalError = .{
        .allocator = allocator,
        .position = position,
        .lexeme = try allocator.dupe(u8, lexeme),
    } };
}

pub fn literalFloatOverflowError(allocator: std.mem.Allocator, position: Position, lexeme: []const u8) !Error {
    return Error{ .literalFloatOverflowError = .{
        .allocator = allocator,
        .position = position,
        .lexeme = try allocator.dupe(u8, lexeme),
    } };
}

pub fn literalIntOverflowError(allocator: std.mem.Allocator, position: Position, lexeme: []const u8) !Error {
    return Error{ .literalIntOverflowError = .{
        .allocator = allocator,
        .position = position,
        .lexeme = try allocator.dupe(u8, lexeme),
    } };
}

pub fn parserError(allocator: std.mem.Allocator, position: Position, lexeme: []const u8, expected: []const TokenKind) !Error {
    return Error{ .parserError = .{
        .allocator = allocator,
        .position = position,
        .lexeme = try allocator.dupe(u8, lexeme),
        .expected = expected,
    } };
}

pub fn recordValueExpectedError(allocator: std.mem.Allocator, position: Position) Error {
    return Error{ .recordValueExpectedError = .{ .allocator = allocator, .position = position } };
}

pub fn unknownIdentifierError(allocator: std.mem.Allocator, position: Position, identifier: []const u8) !Error {
    return Error{ .unknownIdentifierError = .{
        .allocator = allocator,
        .position = position,
        .identifier = try allocator.dupe(u8, identifier),
    } };
}
