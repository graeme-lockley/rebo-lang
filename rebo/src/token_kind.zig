pub const TokenKind = enum {
    EOS,
    Invalid,
    Identifier,
    LiteralBoolFalse,
    LiteralBoolTrue,
    LiteralInt,

    Comma,
    LBracket,
    LParen,
    Minus,
    RBracket,
    RParen,

    pub fn toString(self: TokenKind) []const u8 {
        switch (self) {
            TokenKind.EOS => return "end-of-stream",
            TokenKind.Invalid => return "invalid-token",
            TokenKind.Identifier => return "identifier",
            TokenKind.LiteralBoolFalse => return "false",
            TokenKind.LiteralBoolTrue => return "true",
            TokenKind.LiteralInt => return "literal int",
            TokenKind.Comma => return "','",
            TokenKind.LBracket => return "'['",
            TokenKind.LParen => return "'('",
            TokenKind.Minus => return "'-'",
            TokenKind.RBracket => return "']'",
            TokenKind.RParen => return "')'",
        }
    }
};
