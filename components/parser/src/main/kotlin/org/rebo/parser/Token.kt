package org.rebo.parser

enum class TokenType {
    UpperIdentifier,
    LowerIdentifier,
    LiteralChar,
    LiteralString,
    LiteralInt,
    True,
    False,

    As,

    Comma,
    Minus,

    EOS,
    ERROR
}

data class Token(
    val type: TokenType,
    val lexeme: String,
    val location: Location
)
