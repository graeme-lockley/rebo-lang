const std = @import("std");
const Errors = @import("./errors.zig");

const expectEqual = std.testing.expectEqual;

pub const TokenKind = enum {
    EOS,
    Invalid,
    Identifier,
    LiteralBoolFalse,
    LiteralBoolTrue,
};

pub const Token = struct { kind: TokenKind, start: usize, end: usize };

const keywords = std.ComptimeStringMap(TokenKind, .{
    .{ "true", TokenKind.LiteralBoolTrue },
    .{ "false", TokenKind.LiteralBoolFalse },
});

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    source: []const u8,
    sourceLength: u8,
    offset: u8,

    current: Token,
    err: ?*Errors.Error,

    pub fn init(allocator: std.mem.Allocator) Lexer {
        return Lexer{
            .allocator = allocator,
            .name = "undefined",
            .source = "",
            .sourceLength = 0,
            .offset = 0,
            .current = Token{
                .kind = TokenKind.EOS,
                .start = 0,
                .end = 0,
            },
            .err = null,
        };
    }

    pub fn initBuffer(self: *Lexer, name: []const u8, source: []const u8) Errors.err!void {
        self.name = name;
        self.source = source;
        self.sourceLength = @intCast(u8, source.len);
        self.offset = 0;

        try self.next();
    }

    pub fn lexeme(self: *const Lexer, token: Token) []const u8 {
        return self.source[token.start..token.end];
    }

    fn atEnd(self: *const Lexer) bool {
        return self.offset >= self.sourceLength;
    }

    fn currentCharacter(self: *const Lexer) u8 {
        if (self.atEnd()) {
            return 0;
        }
        return self.source[self.offset];
    }

    fn skipCharacter(self: *Lexer) void {
        if (!self.atEnd()) {
            self.offset += 1;
        }
    }

    pub fn next(self: *Lexer) Errors.err!void {
        if (self.atEnd()) {
            self.current.kind = TokenKind.EOS;
            self.current.start = self.sourceLength;
            self.current.end = self.sourceLength;
            return;
        }

        while (!self.atEnd() and self.currentCharacter() <= ' ') {
            self.skipCharacter();
        }

        const tokenStart = self.offset;
        switch (self.currentCharacter()) {
            'a'...'z', 'A'...'Z', '_' => {
                self.skipCharacter();
                while (self.currentCharacter() == '_' or
                    (self.currentCharacter() >= 'a' and self.currentCharacter() <= 'z') or
                    (self.currentCharacter() >= 'A' and self.currentCharacter() <= 'Z') or
                    (self.currentCharacter() >= '0' and self.currentCharacter() <= '9'))
                {
                    self.skipCharacter();
                }
                if (self.currentCharacter() == '?' or self.currentCharacter() == '!') {
                    self.skipCharacter();
                }
                while (self.currentCharacter() == '\'') {
                    self.skipCharacter();
                }

                var text = self.source[tokenStart..self.offset];

                self.current.kind = keywords.get(text) orelse TokenKind.Identifier;

                self.current.start = tokenStart;
                self.current.end = self.offset;
            },
            else => {
                self.current.kind = TokenKind.Invalid;
                self.current.start = self.offset;
                self.current.end = self.offset + 1;
                self.skipCharacter();

                self.err = try Errors.LexicalError.init(self.allocator, try Errors.Position.init(self.allocator, self.name, self.current.start, self.current.end), self.lexeme(self.current));

                return error.InterpreterError;
            },
        }
    }

    pub fn grabErr(self: *Lexer) ?*Errors.Error {
        const err = self.err;
        self.err = null;

        return err;
    }
};

test "identifier" {
    var lexer = Lexer.init(std.heap.page_allocator);
    try lexer.initBuffer("console", "foo");

    try expectEqual(lexer.current.kind, TokenKind.Identifier);
    try expectEqual(lexer.lexeme(lexer.current), "foo");
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.EOS);
}

test "literal bool" {
    var lexer = Lexer.init(std.heap.page_allocator);
    try lexer.initBuffer("console", "true   false");

    try expectEqual(lexer.current.kind, TokenKind.LiteralBoolTrue);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.LiteralBoolFalse);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.EOS);
}
