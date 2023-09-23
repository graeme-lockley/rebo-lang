pub const TokenKind = enum {
    EOS,
    Invalid,

    LiteralBoolFalse,
    LiteralBoolTrue,
    LiteralChar,
    LiteralFloat,
    LiteralInt,
    LiteralString,

    Identifier,

    Fn,
    If,
    Let,

    BangEqual,
    Bar,
    Colon,
    Comma,
    Dot,
    Equal,
    EqualEqual,
    LBracket,
    LCurly,
    LParen,
    Minus,
    MinusGreater,
    Percentage,
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
            TokenKind.LiteralChar => return "literal char",
            TokenKind.LiteralFloat => return "literal float",
            TokenKind.LiteralInt => return "literal int",
            TokenKind.LiteralString => return "literal string",

            TokenKind.Identifier => return "identifier",

            TokenKind.Fn => return "fn",
            TokenKind.If => return "if",
            TokenKind.Let => return "let",

            TokenKind.BangEqual => return "'!='",
            TokenKind.Bar => return "'|'",
            TokenKind.Colon => return "':'",
            TokenKind.Comma => return "','",
            TokenKind.Dot => return "'.'",
            TokenKind.Equal => return "'='",
            TokenKind.EqualEqual => return "'=='",
            TokenKind.LBracket => return "'['",
            TokenKind.LCurly => return "'{'",
            TokenKind.LParen => return "'('",
            TokenKind.Minus => return "'-'",
            TokenKind.MinusGreater => return "'->'",
            TokenKind.Percentage => return "'%'",
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
