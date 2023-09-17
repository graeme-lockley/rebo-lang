pub const TokenKind = enum {
    EOS,
    Invalid,

    LiteralBoolFalse,
    LiteralBoolTrue,
    LiteralInt,

    Identifier,

    Fn,
    If,
    Let,

    Bar,
    Colon,
    Comma,
    Dot,
    Equal,
    LBracket,
    LCurly,
    LParen,
    Minus,
    MinusGreater,
    Plus,
    RBracket,
    RCurly,
    RParen,
    Semicolon,
    Slash,
    Star,

    pub fn toString(self: TokenKind) []const u8 {
        switch (self) {
            TokenKind.EOS => return "end-of-stream",
            TokenKind.Invalid => return "invalid-token",
            TokenKind.LiteralBoolFalse => return "false",
            TokenKind.LiteralBoolTrue => return "true",
            TokenKind.LiteralInt => return "literal int",

            TokenKind.Identifier => return "identifier",

            TokenKind.Fn => return "fn",
            TokenKind.If => return "if",
            TokenKind.Let => return "let",

            TokenKind.Bar => return "'|'",
            TokenKind.Colon => return "':'",
            TokenKind.Comma => return "','",
            TokenKind.Dot => return "'.'",
            TokenKind.Equal => return "'='",
            TokenKind.LBracket => return "'['",
            TokenKind.LCurly => return "'{'",
            TokenKind.LParen => return "'('",
            TokenKind.Minus => return "'-'",
            TokenKind.MinusGreater => return "'->'",
            TokenKind.Plus => return "'+'",
            TokenKind.RBracket => return "']'",
            TokenKind.RCurly => return "'}'",
            TokenKind.RParen => return "')'",
            TokenKind.Semicolon => return "';'",
            TokenKind.Slash => return "'/'",
            TokenKind.Star => return "'*'",
        }
    }
};
