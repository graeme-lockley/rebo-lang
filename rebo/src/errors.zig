const std = @import("std");

pub const err = error{ InterpreterError, OutOfMemory };

pub const Position = struct {
    name: []u8,
    start: usize,
    end: usize,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, start: usize, end: usize) !*Position {
        var result: *Position = try allocator.create(Position);
        result.name = try allocator.dupe(u8, name);
        result.start = start;
        result.end = end;

        return result;
    }

    pub fn deinit(self: *Position, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const LexicalError = struct {
    allocator: std.mem.Allocator,
    position: *Position,
    lexeme: []u8,

    pub fn init(allocator: std.mem.Allocator, position: *Position, lexeme: []const u8) !*Error {
        var result = try allocator.create(Error);

        result.* = Error{ .lexicalError = .{
            .allocator = allocator,
            .position = position,
            .lexeme = try allocator.dupe(u8, lexeme),
        } };

        return result;
    }

    pub fn deinit(self: *LexicalError) void {
        self.position.deinit(self.allocator);
        self.allocator.free(self.lexeme);
    }

    pub fn print(self: LexicalError) void {
        std.log.err("Lexical error: {s} at {d}-{d} \"{s}\"", .{ self.position.name, self.position.start, self.position.end, self.lexeme });
    }
};

pub const ParserError = struct { position: Position, lexeme: []const u8 };

pub const Error = union(enum) {
    lexicalError: LexicalError,
    parserError: ParserError,

    pub fn deinit(self: *Error) void {
        switch (self.*) {
            .lexicalError => {
                self.lexicalError.deinit();
            },
            .parserError => {
                // self.parserError.deinit();
            },
        }
    }

    pub fn print(self: *Error) void {
        switch (self.*) {
            .lexicalError => {
                self.*.lexicalError.print();
            },
            else => {
                // std.log.err("Unknown error: {}", self.*);
            },
        }
    }
};
