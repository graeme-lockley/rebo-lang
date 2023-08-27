const std = @import("std");

const expectEqual = std.testing.expectEqual;

pub const Lexer = struct {
    pub const TokenKind = enum {
        EOS,
        Invalid,
        Identifier,
        LiteralBoolFalse,
        LiteralBoolTrue,
    };

    pub const Token = struct { kind: TokenKind, start: usize, end: usize };

    source: []const u8,
    sourceLength: u8,
    offset: u8,

    current: Token,

    pub fn init(source: []const u8) Lexer {
        var result = Lexer{
            .source = source,
            .sourceLength = @intCast(u8, source.len),
            .offset = 0,
            .current = Token{
                .kind = TokenKind.EOS,
                .start = 0,
                .end = 0,
            },
        };

        result.next();

        return result;
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

    pub fn next(self: *Lexer) void {
        if (self.atEnd()) {
            self.current.kind = TokenKind.EOS;
            self.current.start = self.sourceLength;
            self.current.end = self.sourceLength;
            return;
        }

        while (self.currentCharacter() <= ' ') {
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
                if (std.mem.eql(u8, text, "true")) {
                    self.current.kind = TokenKind.LiteralBoolTrue;
                } else if (std.mem.eql(u8, text, "false")) {
                    self.current.kind = TokenKind.LiteralBoolFalse;
                } else {
                    self.current.kind = TokenKind.Identifier;
                }
                self.current.start = tokenStart;
                self.current.end = self.offset;
            },
            else => {
                self.current.kind = TokenKind.Invalid;
                self.current.start = self.offset;
                self.current.end = self.offset + 1;
                self.skipCharacter();
            },
        }
    }
};

test "identifier" {
    var lexer = Lexer.init("foo");

    try expectEqual(lexer.current.kind, Lexer.TokenKind.Identifier);
    try expectEqual(lexer.lexeme(lexer.current), "foo");
    lexer.next();
    try expectEqual(lexer.current.kind, Lexer.TokenKind.EOS);
}

test "literal bool" {
    var lexer = Lexer.init("true  false");

    try expectEqual(lexer.current.kind, Lexer.TokenKind.LiteralBoolTrue);
    lexer.next();
    try expectEqual(lexer.current.kind, Lexer.TokenKind.LiteralBoolFalse);
    lexer.next();
    try expectEqual(lexer.current.kind, Lexer.TokenKind.EOS);
}
