package org.rebo.parser

public enum class TokenType {
    UpperIdentifier,
    LowerIdentifier,
    LiteralChar,
    LiteralString,
    LiteralInt,
    TTrue,
    TFalse,

    As,

    Comma,
    Minus,

    EOS,
    ERROR
}

public data class Token(
    public val type: TokenType,
    public val lexeme: String,
    public val location: Location
)
