const std = @import("std");

pub const err = error{ InterpreterError, OutOfMemory, NotYetImplemented };

pub const Position = struct {
    start: usize,
    end: usize,
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

pub const ParserError = struct { position: Position, lexeme: []const u8 };

pub const Error = union(enum) {
    lexicalError: LexicalError,
    literalIntOverflowError: LexicalError,
    parserError: ParserError,

    pub fn deinit(self: Error) void {
        switch (self) {
            .lexicalError, .literalIntOverflowError => {
                self.lexicalError.deinit();
            },
            .parserError => {
                // self.parserError.deinit();
            },
        }
    }

    pub fn print(self: Error) void {
        switch (self) {
            .lexicalError => {
                self.lexicalError.print("Lexical Error");
            },
            .literalIntOverflowError => {
                self.lexicalError.print("Literal Int Overflow Error");
            },
            else => {
                // std.log.err("Unknown error: {}", self.*);
            },
        }
    }
};

pub fn lexicalError(allocator: std.mem.Allocator, position: Position, lexeme: []const u8) !Error {
    return Error{ .lexicalError = .{
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
