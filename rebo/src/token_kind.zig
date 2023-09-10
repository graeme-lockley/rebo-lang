pub const TokenKind = enum {
    EOS,
    Invalid,
    Identifier,
    LiteralBoolFalse,
    LiteralBoolTrue,
    LiteralInt,

    Colon,
    Comma,
    LBracket,
    LCurly,
    LParen,
    Minus,
    Plus,
    RBracket,
    RCurly,
    RParen,
    Slash,
    Star,

    pub fn toString(self: TokenKind) []const u8 {
        switch (self) {
            TokenKind.EOS => return "end-of-stream",
            TokenKind.Invalid => return "invalid-token",
            TokenKind.Identifier => return "identifier",
            TokenKind.LiteralBoolFalse => return "false",
            TokenKind.LiteralBoolTrue => return "true",
            TokenKind.LiteralInt => return "literal int",

            TokenKind.Colon => return "':'",
            TokenKind.Comma => return "','",
            TokenKind.LBracket => return "'['",
            TokenKind.LCurly => return "'{'",
            TokenKind.LParen => return "'('",
            TokenKind.Minus => return "'-'",
            TokenKind.Plus => return "'+'",
            TokenKind.RBracket => return "']'",
            TokenKind.RCurly => return "'}'",
            TokenKind.RParen => return "')'",
            TokenKind.Slash => return "'/'",
            TokenKind.Star => return "'*'",
        }
    }
};
