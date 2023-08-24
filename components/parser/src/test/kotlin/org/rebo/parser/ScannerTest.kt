package org.rebo.parser

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe

class ScannerTest : FunSpec({
    test("Scanner should return EOS token when input is empty") {
        val scanner = Scanner("")
        scanner.token shouldBe Token(TokenType.EOS, "", Position(1, 1, 0))
    }
})
