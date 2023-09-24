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

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlphaDigit(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    source: []const u8,
    sourceLength: u32,
    offset: u32,

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

    fn reportLexicalError(self: *Lexer, tokenStart: usize) Errors.err!void {
        self.current = Token{ .kind = TokenKind.Invalid, .start = tokenStart, .end = self.offset };

        self.replaceErr(try Errors.lexicalError(self.allocator, Errors.Position{ .start = tokenStart, .end = self.offset }, self.lexeme(self.current)));

        return error.InterpreterError;
    }

    pub fn peekNext(self: *Lexer) Errors.err!TokenKind {
        const offset = self.offset;
        const token = self.current;

        try self.next();
        const kind = self.current.kind;
        self.offset = offset;
        self.current = token;

        return kind;
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
                while (isAlphaDigit(self.currentCharacter())) {
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
            '!' => {
                self.skipCharacter();
                if (self.currentCharacter() == '=') {
                    self.skipCharacter();
                    self.current = Token{ .kind = TokenKind.BangEqual, .start = tokenStart, .end = self.offset };
                } else {
                    try self.reportLexicalError(tokenStart);
                }
            },
            '[' => self.setSymbolToken(TokenKind.LBracket, tokenStart),
            '{' => self.setSymbolToken(TokenKind.LCurly, tokenStart),
            '(' => self.setSymbolToken(TokenKind.LParen, tokenStart),
            ']' => self.setSymbolToken(TokenKind.RBracket, tokenStart),
            '}' => self.setSymbolToken(TokenKind.RCurly, tokenStart),
            ')' => self.setSymbolToken(TokenKind.RParen, tokenStart),
            ',' => self.setSymbolToken(TokenKind.Comma, tokenStart),
            '.' => self.setSymbolToken(TokenKind.Dot, tokenStart),
            ':' => {
                self.skipCharacter();
                if (self.currentCharacter() == '=') {
                    self.skipCharacter();
                    self.current = Token{ .kind = TokenKind.ColonEqual, .start = tokenStart, .end = self.offset };
                } else {
                    self.current = Token{ .kind = TokenKind.Colon, .start = tokenStart, .end = self.offset };
                }
            },
            ';' => self.setSymbolToken(TokenKind.Semicolon, tokenStart),
            '|' => {
                self.skipCharacter();
                if (self.currentCharacter() == '|') {
                    self.skipCharacter();
                    self.current = Token{ .kind = TokenKind.BarBar, .start = tokenStart, .end = self.offset };
                } else {
                    self.current = Token{ .kind = TokenKind.Bar, .start = tokenStart, .end = self.offset };
                }
            },
            '+' => self.setSymbolToken(TokenKind.Plus, tokenStart),
            '*' => self.setSymbolToken(TokenKind.Star, tokenStart),
            '/' => self.setSymbolToken(TokenKind.Slash, tokenStart),
            '%' => self.setSymbolToken(TokenKind.Percentage, tokenStart),
            '=' => {
                self.skipCharacter();
                if (self.currentCharacter() == '=') {
                    self.skipCharacter();
                    self.current = Token{ .kind = TokenKind.EqualEqual, .start = tokenStart, .end = self.offset };
                } else {
                    self.current = Token{ .kind = TokenKind.Equal, .start = tokenStart, .end = self.offset };
                }
            },
            '<' => {
                self.skipCharacter();
                if (self.currentCharacter() == '=') {
                    self.skipCharacter();
                    self.current = Token{ .kind = TokenKind.LessEqual, .start = tokenStart, .end = self.offset };
                } else {
                    self.current = Token{ .kind = TokenKind.LessThan, .start = tokenStart, .end = self.offset };
                }
            },
            '>' => {
                self.skipCharacter();
                if (self.currentCharacter() == '=') {
                    self.skipCharacter();
                    self.current = Token{ .kind = TokenKind.GreaterEqual, .start = tokenStart, .end = self.offset };
                } else {
                    self.current = Token{ .kind = TokenKind.GreaterThan, .start = tokenStart, .end = self.offset };
                }
            },
            '&' => {
                self.skipCharacter();
                if (self.currentCharacter() == '&') {
                    self.skipCharacter();
                    self.current = Token{ .kind = TokenKind.AmpersandAmpersand, .start = tokenStart, .end = self.offset };
                } else {
                    try self.reportLexicalError(tokenStart);
                }
            },
            '-' => {
                self.skipCharacter();
                if (self.currentCharacter() == '>') {
                    self.skipCharacter();
                    self.current = Token{ .kind = TokenKind.MinusGreater, .start = tokenStart, .end = self.offset };
                } else if (isDigit(self.currentCharacter())) {
                    self.skipCharacter();
                    while (isDigit(self.currentCharacter())) {
                        self.skipCharacter();
                    }

                    if (self.currentCharacter() == '.') {
                        self.skipCharacter();
                        while (isDigit(self.currentCharacter())) {
                            self.skipCharacter();
                        }
                        if (self.currentCharacter() == 'e' or self.currentCharacter() == 'E') {
                            self.skipCharacter();
                            if (self.currentCharacter() == '+' or self.currentCharacter() == '-') {
                                self.skipCharacter();
                            }
                            while (isDigit(self.currentCharacter())) {
                                self.skipCharacter();
                            }
                        }
                        self.current = Token{ .kind = TokenKind.LiteralFloat, .start = tokenStart, .end = self.offset };
                    } else {
                        self.current = Token{ .kind = TokenKind.LiteralInt, .start = tokenStart, .end = self.offset };
                    }
                } else {
                    self.current = Token{ .kind = TokenKind.Minus, .start = tokenStart, .end = self.offset };
                }
            },
            '0'...'9' => {
                self.skipCharacter();
                while (isDigit(self.currentCharacter())) {
                    self.skipCharacter();
                }

                if (self.currentCharacter() == '.') {
                    self.skipCharacter();
                    while (isDigit(self.currentCharacter())) {
                        self.skipCharacter();
                    }
                    if (self.currentCharacter() == 'e' or self.currentCharacter() == 'E') {
                        self.skipCharacter();
                        if (self.currentCharacter() == '+' or self.currentCharacter() == '-') {
                            self.skipCharacter();
                        }
                        while (isDigit(self.currentCharacter())) {
                            self.skipCharacter();
                        }
                    }
                    self.current = Token{ .kind = TokenKind.LiteralFloat, .start = tokenStart, .end = self.offset };
                } else {
                    self.current = Token{ .kind = TokenKind.LiteralInt, .start = tokenStart, .end = self.offset };
                }
            },
            '\'' => {
                self.skipCharacter();
                if (self.currentCharacter() == '\\') {
                    self.skipCharacter();
                    if (self.currentCharacter() == '\'' or self.currentCharacter() == '\\' or self.currentCharacter() == 'n') {
                        self.skipCharacter();
                        if (self.currentCharacter() == '\'') {
                            self.skipCharacter();
                            self.current = Token{ .kind = TokenKind.LiteralChar, .start = tokenStart, .end = self.offset };

                            return;
                        }
                    } else if (self.currentCharacter() == 'x') {
                        self.skipCharacter();
                        if (isDigit(self.currentCharacter())) {
                            self.skipCharacter();
                            while (isDigit(self.currentCharacter())) {
                                self.skipCharacter();
                            }
                            if (self.currentCharacter() == '\'') {
                                self.skipCharacter();
                                self.current = Token{ .kind = TokenKind.LiteralChar, .start = tokenStart, .end = self.offset };

                                return;
                            }
                        }
                    }
                } else if (self.currentCharacter() != '\'') {
                    self.skipCharacter();
                    if (self.currentCharacter() == '\'') {
                        self.skipCharacter();
                        self.current = Token{ .kind = TokenKind.LiteralChar, .start = tokenStart, .end = self.offset };

                        return;
                    }
                }

                try self.reportLexicalError(tokenStart);
            },
            '"' => {
                self.skipCharacter();
                while (self.currentCharacter() != '"') {
                    if (self.currentCharacter() == 0) {
                        try self.reportLexicalError(tokenStart);
                    }

                    if (self.currentCharacter() == '\\') {
                        self.skipCharacter();

                        if (self.currentCharacter() == 'n' or self.currentCharacter() == '\\' or self.currentCharacter() == '"') {
                            self.skipCharacter();
                        } else if (self.currentCharacter() == 'x') {
                            self.skipCharacter();
                            if (isDigit(self.currentCharacter())) {
                                self.skipCharacter();
                                while (isDigit(self.currentCharacter())) {
                                    self.skipCharacter();
                                }
                                if (self.currentCharacter() == ';') {
                                    self.skipCharacter();
                                } else {
                                    try self.reportLexicalError(tokenStart);
                                }
                            } else {
                                try self.reportLexicalError(tokenStart);
                            }
                        } else {
                            try self.reportLexicalError(tokenStart);
                        }
                    } else {
                        self.skipCharacter();
                    }
                }
                self.skipCharacter();

                self.current = Token{ .kind = TokenKind.LiteralString, .start = tokenStart, .end = self.offset };
            },
            else => {
                try self.reportLexicalError(tokenStart);
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

fn expectTokenEqual(lexer: *Lexer, kind: TokenKind, lexeme: []const u8) !void {
    try expectEqual(
        kind,
        lexer.current.kind,
    );
    try expectEqualStrings(lexeme, lexer.lexeme(lexer.current));

    try lexer.next();
}

test "literal char" {
    var lexer = Lexer.init(std.heap.page_allocator);
    try lexer.initBuffer("console", "'x' '\\n' '\\\\' '\\'' '\\x31'");

    try expectTokenEqual(&lexer, TokenKind.LiteralChar, "'x'");
    try expectTokenEqual(&lexer, TokenKind.LiteralChar, "'\\n'");
    try expectTokenEqual(&lexer, TokenKind.LiteralChar, "'\\\\'");
    try expectTokenEqual(&lexer, TokenKind.LiteralChar, "'\\''");
    try expectTokenEqual(&lexer, TokenKind.LiteralChar, "'\\x31'");
    try expectEqual(lexer.current.kind, TokenKind.EOS);
}

test "literal float" {
    var lexer = Lexer.init(std.heap.page_allocator);
    try lexer.initBuffer("console", "1.0 -1.0 1.0e1 -1.0e1 1.0e+1 -1.0e+1 1.0e-1 -1.0e-1");

    try expectTokenEqual(&lexer, TokenKind.LiteralFloat, "1.0");
    try expectTokenEqual(&lexer, TokenKind.LiteralFloat, "-1.0");
    try expectTokenEqual(&lexer, TokenKind.LiteralFloat, "1.0e1");
    try expectTokenEqual(&lexer, TokenKind.LiteralFloat, "-1.0e1");
    try expectTokenEqual(&lexer, TokenKind.LiteralFloat, "1.0e+1");
    try expectTokenEqual(&lexer, TokenKind.LiteralFloat, "-1.0e+1");
    try expectTokenEqual(&lexer, TokenKind.LiteralFloat, "1.0e-1");
    try expectTokenEqual(&lexer, TokenKind.LiteralFloat, "-1.0e-1");

    try expectEqual(lexer.current.kind, TokenKind.EOS);
}

test "literal int" {
    var lexer = Lexer.init(std.heap.page_allocator);
    try lexer.initBuffer("console", "0 123 -1 -0 -123");

    try expectTokenEqual(&lexer, TokenKind.LiteralInt, "0");
    try expectTokenEqual(&lexer, TokenKind.LiteralInt, "123");
    try expectTokenEqual(&lexer, TokenKind.LiteralInt, "-1");
    try expectTokenEqual(&lexer, TokenKind.LiteralInt, "-0");
    try expectTokenEqual(&lexer, TokenKind.LiteralInt, "-123");

    try expectEqual(lexer.current.kind, TokenKind.EOS);
}

test "literal string" {
    var lexer = Lexer.init(std.heap.page_allocator);
    try lexer.initBuffer("console", "\"\" \"hello world\" \"\\n\\\\\\\" \\x123;x\"");

    try expectTokenEqual(&lexer, TokenKind.LiteralString, "\"\"");
    try expectTokenEqual(&lexer, TokenKind.LiteralString, "\"hello world\"");
    try expectTokenEqual(&lexer, TokenKind.LiteralString, "\"\\n\\\\\\\" \\x123;x\"");

    try expectEqual(lexer.current.kind, TokenKind.EOS);
}

test "+ - * / % = == != < <= > >= && || [ { ( , . : := ; -> | ] } )" {
    var lexer = Lexer.init(std.heap.page_allocator);
    try lexer.initBuffer("console", " + - * / % = == != < <= > >= && || [ { ( , . : := ; -> | ] } ) ");

    try expectEqual(lexer.current.kind, TokenKind.Plus);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Minus);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Star);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Slash);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Percentage);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.Equal);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.EqualEqual);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.BangEqual);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.LessThan);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.LessEqual);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.GreaterThan);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.GreaterEqual);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.AmpersandAmpersand);
    try lexer.next();
    try expectEqual(lexer.current.kind, TokenKind.BarBar);
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
    try expectEqual(lexer.current.kind, TokenKind.ColonEqual);
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
