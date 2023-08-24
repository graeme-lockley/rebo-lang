package org.rebo.parser

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

    fun next() {
        if (atEnd()) {
            token = Token(TokenType.EOS, "", Position(line, column, offset))
            return
        }
    }
}