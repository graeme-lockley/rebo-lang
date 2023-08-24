package org.rebo.parser

private val keywords = mapOf(
    "as" to TokenType.As,

    "False" to TokenType.False,
    "True" to TokenType.True
)

class Scanner(private val input: String) {
    private val inputLength = input.length
    private var offset = 0
    private var column = 1
    private var line = 1
    var token = Token(TokenType.EOS, "", Position(line, column, offset))
        private set

    init {
        next()
    }

    private fun atEnd(): Boolean {
        return offset >= inputLength
    }

    private fun positionAt(): Position {
        return Position(line, column, offset)
    }

    private fun skipWhile(predicate: (Char) -> Boolean) {
        while (!atEnd()) {
            if (predicate(input[offset])) {
                skipCharacter()
                continue
            }

            break
        }
    }

    fun next() {
        ignoreWhitespace()

        if (atEnd()) {
            token = Token(TokenType.EOS, "", Position(line, column, offset))
            return
        }

        val c = input[offset]
        when {
            c == ',' -> {
                token = Token(TokenType.Comma, ",", Position(line, column, offset))
                skipCharacter()
                return
            }

            c == '-' -> {
                val start = positionAt()
                skipCharacter()
                if (!atEnd() && isDigit(input[offset])) {
                    skipWhile { isDigit(it) }
                    token =
                        Token(TokenType.LiteralInt, input.substring(start.offset, offset), Range(start, positionAt()))
                    return
                }
                token = Token(TokenType.Minus, "-", Position(line, column, offset))
                return
            }

            isDigit(c) -> {
                val start = positionAt()
                skipCharacter()
                skipWhile { isDigit(it) }
                token =
                    Token(TokenType.LiteralInt, input.substring(start.offset, offset), Range(start, positionAt()))
            }

            isLowerAlpha(c) -> {
                val start = positionAt()
                skipCharacter()
                skipWhile { isAlpha(it) || isDigit(it) }

                val lexeme = input.substring(start.offset, offset)
                val type = keywords[lexeme] ?: TokenType.LowerIdentifier

                token = Token(type, input.substring(start.offset, offset), Range(start, positionAt()))
            }

            isUpperAlpha(c) -> {
                val start = positionAt()
                skipCharacter()
                skipWhile { isAlpha(it) || isDigit(it) }

                val lexeme = input.substring(start.offset, offset)
                val type = keywords[lexeme] ?: TokenType.UpperIdentifier

                token = Token(type, input.substring(start.offset, offset), Range(start, positionAt()))
            }

            else -> {
                val position = positionAt()
                skipCharacter()

                token = Token(TokenType.ERROR, "$c", position)
            }
        }

    }

    private fun ignoreWhitespace() {
        while (!atEnd()) {
            val c = input[offset]
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
                skipCharacter()
                continue
            }

            break
        }
    }

    private fun skipCharacter() {
        if (atEnd()) {
            return
        }

        val c = input[offset]
        if (c == '\n') {
            column = 1
            line++
        } else {
            column++
        }
        offset++
    }

    private fun isDigit(c: Char): Boolean {
        return c in '0'..'9'
    }

    private fun isAlpha(c: Char): Boolean {
        return c in 'a'..'z' || c in 'A'..'Z'
    }

    private fun isUpperAlpha(c: Char): Boolean {
        return c in 'A'..'Z'
    }

    private fun isLowerAlpha(c: Char): Boolean {
        return c in 'a'..'z'
    }
}