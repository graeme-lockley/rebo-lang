package org.rebo.parser

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe

private fun tokens(scanner: Scanner): List<Token> {
    val tokens = mutableListOf<Token>()
    while (scanner.token.type != TokenType.EOS) {
        tokens.add(scanner.token)
        scanner.next()
    }

    return tokens
}

private fun tokenTypesLexemes(scanner: Scanner): List<Pair<TokenType, String>> =
    tokens(scanner).map { Pair(it.type, it.lexeme) }

private fun tokenTypesLexemes(input: String): List<Pair<TokenType, String>> =
    tokenTypesLexemes(Scanner(input))

class ScannerTest : FunSpec({
    test("Scanner should return EOS token when input is empty") {
        Scanner("").token shouldBe Token(TokenType.EOS, "", Position(1, 1, 0))
        Scanner("   ").token shouldBe Token(TokenType.EOS, "", Position(1, 4, 3))
    }

    test("Scanner should return ERROR token when input is invalid") {
        Scanner(" @ ").token shouldBe Token(TokenType.ERROR, "@", Position(1, 2, 1))
    }

    test("Scanner should return Keyword tokens") {
        tokenTypesLexemes(" as  False  True ") shouldBe listOf(
            Pair(TokenType.As, "as"),
            Pair(TokenType.False, "False"),
            Pair(TokenType.True, "True")
        )
    }

    test("Scanner should return LiteralChar tokens") {
        tokenTypesLexemes("  'a'  '1'  ") shouldBe listOf(
            Pair(TokenType.LiteralChar, "'a'"),
            Pair(TokenType.LiteralChar, "'1'")
        )

        tokenTypesLexemes("  '\\''  '\\\\'  '\\n'   '\\0'  ") shouldBe listOf(
            Pair(TokenType.LiteralChar, "'\\''"),
            Pair(TokenType.LiteralChar, "'\\\\'"),
            Pair(TokenType.LiteralChar, "'\\n'"),
            Pair(TokenType.LiteralChar, "'\\0'"),
        )
    }

    test("Scanner should return LiteralInt tokens") {
        tokenTypesLexemes("0") shouldBe listOf(Pair(TokenType.LiteralInt, "0"))
        tokenTypesLexemes("1 23 456 -1 -23 -456") shouldBe listOf(
            Pair(TokenType.LiteralInt, "1"),
            Pair(TokenType.LiteralInt, "23"),
            Pair(TokenType.LiteralInt, "456"),
            Pair(TokenType.LiteralInt, "-1"),
            Pair(TokenType.LiteralInt, "-23"),
            Pair(TokenType.LiteralInt, "-456")
        )
    }

    test("Scanner should return LowerIdentifier tokens") {
        tokenTypesLexemes("hello") shouldBe listOf(Pair(TokenType.LowerIdentifier, "hello"))
        tokenTypesLexemes("hello world") shouldBe listOf(
            Pair(TokenType.LowerIdentifier, "hello"),
            Pair(TokenType.LowerIdentifier, "world")
        )
        tokenTypesLexemes("  hello   world   ") shouldBe listOf(
            Pair(TokenType.LowerIdentifier, "hello"),
            Pair(TokenType.LowerIdentifier, "world")
        )
    }

    test("Scanner should return UpperIdentifier tokens") {
        tokenTypesLexemes("Hello") shouldBe listOf(Pair(TokenType.UpperIdentifier, "Hello"))
        tokenTypesLexemes("Hello World") shouldBe listOf(
            Pair(TokenType.UpperIdentifier, "Hello"),
            Pair(TokenType.UpperIdentifier, "World")
        )
        tokenTypesLexemes("  Hello   World   ") shouldBe listOf(
            Pair(TokenType.UpperIdentifier, "Hello"),
            Pair(TokenType.UpperIdentifier, "World")
        )
    }
})

