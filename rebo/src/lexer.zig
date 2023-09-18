const std = @import("std");

const Errors = @import("./errors.zig");
pub const TokenKind = @import("./token_kind.zig").TokenKind;

pub const Token = struct { kind: TokenKind, start: usize, end: usize };

const keywords = std.ComptimeStringMap(TokenKind, .{
    .{ "true", TokenKind.LiteralBoolTrue },
    .{ "false", TokenKind.LiteralBoolFalse },
    .{ "fn", TokenKind.Fn },
    .{ "if", TokenKind.If },
    .{ "let", TokenKind.Let },
});

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    source: []const u8,
    sourceLength: u8,
    offset: u8,

    current: Token,
    err: ?Errors.Error,

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
        self.sourceLength = @intCast(source.len);
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
        while (!self.atEnd() and self.currentCharacter() <= ' ') {
            self.skipCharacter();
        }

        if (self.atEnd()) {
            self.current = Token{ .kind = TokenKind.EOS, .start = self.sourceLength, .end = self.sourceLength };
            return;
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

                self.current = Token{ .kind = keywords.get(text) orelse TokenKind.Identifier, .start = tokenStart, .end = self.offset };
            },
            '[' => self.setSymbolToken(TokenKind.LBracket, tokenStart),
            '{' => self.setSymbolToken(TokenKind.LCurly, tokenStart),
            '(' => self.setSymbolToken(TokenKind.LParen, tokenStart),
            ']' => self.setSymbolToken(TokenKind.RBracket, tokenStart),
            '}' => self.setSymbolToken(TokenKind.RCurly, tokenStart),
            ')' => self.setSymbolToken(TokenKind.RParen, tokenStart),
            ',' => self.setSymbolToken(TokenKind.Comma, tokenStart),
            '.' => self.setSymbolToken(TokenKind.Dot, tokenStart),
            ':' => self.setSymbolToken(TokenKind.Colon, tokenStart),
            ';' => self.setSymbolToken(TokenKind.Semicolon, tokenStart),
            '|' => self.setSymbolToken(TokenKind.Bar, tokenStart),
            '+' => self.setSymbolToken(TokenKind.Plus, tokenStart),
            '/' => self.setSymbolToken(TokenKind.Slash, tokenStart),
            '*' => self.setSymbolToken(TokenKind.Star, tokenStart),
            '=' => {
                self.skipCharacter();
                if (self.currentCharacter() == '=') {
                    self.skipCharacter();
                    self.current = Token{ .kind = TokenKind.EqualEqual, .start = tokenStart, .end = self.offset };
                } else {
                    self.current = Token{ .kind = TokenKind.Equal, .start = tokenStart, .end = self.offset };
                }
            },
            '-' => {
                self.skipCharacter();
                if (self.currentCharacter() == '>') {
                    self.skipCharacter();
                    self.current = Token{ .kind = TokenKind.MinusGreater, .start = tokenStart, .end = self.offset };
                } else {
                    while (self.currentCharacter() >= '0' and self.currentCharacter() <= '9') {
                        self.skipCharacter();
                    }

                    self.current = Token{ .kind = if (tokenStart + 1 == self.offset) TokenKind.Minus else TokenKind.LiteralInt, .start = tokenStart, .end = self.offset };
                }
            },
            '0'...'9' => {
                self.skipCharacter();
                while (self.currentCharacter() >= '0' and self.currentCharacter() <= '9') {
                    self.skipCharacter();
                }

                self.current = Token{ .kind = TokenKind.LiteralInt, .start = tokenStart, .end = self.offset };
            },
            else => {
                self.current = Token{ .kind = TokenKind.Invalid, .start = self.offset, .end = self.offset + 1 };
                self.skipCharacter();

                self.replaceErr(try Errors.lexicalError(self.allocator, Errors.Position{ .start = self.current.start, .end = self.current.end }, self.lexeme(self.current)));

                return error.InterpreterError;
            },
        }
    }

    fn setSymbolToken(self: *Lexer, kind: TokenKind, tokenStart: u32) void {
        self.skipCharacter();
        self.current = Token{ .kind = kind, .start = tokenStart, .end = self.offset };
    }

    fn replaceErr(self: *Lexer, err: Errors.Error) void {
        self.eraseErr();
        self.err = err;
    }

    pub fn eraseErr(self: *Lexer) void {
        if (self.err != null) {
            self.err.?.deinit();
            self.err = null;
        }
    }

    pub fn grabErr(self: *Lexer) ?Errors.Error {
        const err = self.err;
        self.err = null;

        return err;
    }

    pub fn currentLexeme(self: *Lexer) []const u8 {
        return self.lexeme(self.current);
    }
};

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "identifier and keywords" {
    var lexer = Lexer.init(std.heap.page_allocator);
    try lexer.initBuffer("console", " foo fn if let ");

    try expectEqual(lexer.current.kind, TokenKind.Identifier);
    try expectEqualStrings(lexer.lexeme(lexer.current), "foo");
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Fn);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.If);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Let);
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

fn expectLiteralInt(lexer: Lexer, expected: []const u8) !void {
    try expectEqual(lexer.current.kind, TokenKind.LiteralInt);
    try expectEqualStrings(lexer.lexeme(lexer.current), expected);
}

test "literal int" {
    var lexer = Lexer.init(std.heap.page_allocator);
    try lexer.initBuffer("console", "0 123 -1 -0 -123");

    try expectLiteralInt(lexer, "0");
    try lexer.next();
    try expectLiteralInt(lexer, "123");
    try lexer.next();
    try expectLiteralInt(lexer, "-1");
    try lexer.next();
    try expectLiteralInt(lexer, "-0");
    try lexer.next();
    try expectLiteralInt(lexer, "-123");
    try lexer.next();

    try expectEqual(lexer.current.kind, TokenKind.EOS);
}

test "+ - * / = == [ { ( , . : ; -> | ] } )" {
    var lexer = Lexer.init(std.heap.page_allocator);
    try lexer.initBuffer("console", " + - * / = == [ { ( , . : ; -> | ] } ) ");

    try expectEqual(lexer.current.kind, TokenKind.Plus);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Minus);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Star);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Slash);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Equal);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.EqualEqual);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.LBracket);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.LCurly);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.LParen);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Comma);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Dot);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Colon);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Semicolon);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.MinusGreater);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Bar);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.RBracket);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.RCurly);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.RParen);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.EOS);
}
