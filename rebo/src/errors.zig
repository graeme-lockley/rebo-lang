const std = @import("std");

pub const err = error{ InterpreterError, OutOfMemory };

pub const Position = struct {
    start: usize,
    end: usize,
};

pub const LexicalError = struct {
    allocator: std.mem.Allocator,
    position: Position,
    lexeme: []u8,

    pub fn init(allocator: std.mem.Allocator, position: Position, lexeme: []const u8) !Error {
        return Error{ .lexicalError = .{
            .allocator = allocator,
            .position = position,
            .lexeme = try allocator.dupe(u8, lexeme),
        } };
    }

    pub fn deinit(self: LexicalError) void {
        self.allocator.free(self.lexeme);
    }

    pub fn print(self: LexicalError) void {
        std.log.err("Lexical error: {d}-{d} \"{s}\"", .{ self.position.start, self.position.end, self.lexeme });
    }
};

pub const ParserError = struct { position: Position, lexeme: []const u8 };

pub const Error = union(enum) {
    lexicalError: LexicalError,
    parserError: ParserError,

    pub fn deinit(self: Error) void {
        switch (self) {
            .lexicalError => {
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
                self.lexicalError.print();
            },
            else => {
                // std.log.err("Unknown error: {}", self.*);
            },
        }
    }
};
