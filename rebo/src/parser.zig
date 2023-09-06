const std = @import("std");

const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const Machine = @import("./machine.zig");
const Lexer = @import("./lexer.zig");

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: Lexer.Lexer,
    err: ?Errors.Error,

    pub fn init(allocator: std.mem.Allocator, lexer: Lexer.Lexer) Parser {
        return Parser{
            .allocator = allocator,
            .lexer = lexer,
            .err = null,
        };
    }

    pub fn expression(self: *Parser) Errors.err!*AST.Expression {
        return try self.additive();
    }

    pub fn additive(self: *Parser) Errors.err!*AST.Expression {
        var lhs = try self.factor();
        errdefer AST.destroy(self.allocator, lhs);

        while (true) {
            switch (self.currentTokenKind()) {
                Lexer.TokenKind.Plus => {
                    try self.skipToken();

                    const rhs = try self.factor();
                    errdefer AST.destroy(self.allocator, rhs);

                    const v = try self.allocator.create(AST.Expression);
                    v.* = AST.Expression{ .plus = AST.PlusExpression{ .left = lhs, .right = rhs } };
                    lhs = v;
                },
                Lexer.TokenKind.Minus => {
                    try self.skipToken();

                    const rhs = try self.factor();
                    errdefer AST.destroy(self.allocator, rhs);

                    const v = try self.allocator.create(AST.Expression);
                    v.* = AST.Expression{ .minus = AST.MinusExpression{ .left = lhs, .right = rhs } };
                    lhs = v;
                },
                else => break,
            }
        }

        return lhs;
    }

    pub fn factor(self: *Parser) Errors.err!*AST.Expression {
        switch (self.currentTokenKind()) {
            Lexer.TokenKind.LParen => {
                try self.skipToken();

                if (self.currentTokenKind() == Lexer.TokenKind.RParen) {
                    try self.skipToken();

                    const v = try self.allocator.create(AST.Expression);
                    v.* = AST.Expression{ .literalVoid = void{} };
                    return v;
                }

                const e = try self.expression();
                errdefer AST.destroy(self.allocator, e);

                try self.matchSkipToken(Lexer.TokenKind.RParen);

                return e;
            },
            Lexer.TokenKind.LiteralBoolFalse => {
                try self.skipToken();

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .literalBool = false };
                return v;
            },
            Lexer.TokenKind.LiteralBoolTrue => {
                try self.skipToken();

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .literalBool = true };
                return v;
            },
            Lexer.TokenKind.LiteralInt => {
                const lexeme = self.lexer.currentLexeme();

                const literalInt = std.fmt.parseInt(i32, lexeme, 10) catch {
                    const token = self.currentToken();
                    self.replaceErr(try Errors.literalIntOverflowError(self.allocator, Errors.Position{ .start = token.start, .end = token.end }, lexeme));
                    return error.InterpreterError;
                };

                const v = try self.allocator.create(AST.Expression);
                errdefer AST.destroy(self.allocator, v);

                v.* = AST.Expression{ .literalInt = literalInt };
                try self.skipToken();

                return v;
            },
            Lexer.TokenKind.LBracket => {
                try self.skipToken();

                var es = std.ArrayList(*AST.Expression).init(self.allocator);
                defer {
                    for (es.items) |item| {
                        AST.destroy(self.allocator, item);
                    }
                    es.deinit();
                }

                if (self.currentTokenKind() != Lexer.TokenKind.RBracket) {
                    try es.append(try self.expression());
                    while (self.currentTokenKind() == Lexer.TokenKind.Comma) {
                        try self.skipToken();
                        try es.append(try self.expression());
                    }
                }

                try self.matchSkipToken(Lexer.TokenKind.RBracket);

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .literalList = es.toOwnedSlice() };
                return v;
            },
            else => {
                {
                    var expected = try self.allocator.alloc(Lexer.TokenKind, 5);
                    errdefer self.allocator.free(expected);

                    expected[0] = Lexer.TokenKind.RParen;
                    expected[1] = Lexer.TokenKind.LiteralBoolFalse;
                    expected[2] = Lexer.TokenKind.LiteralBoolTrue;
                    expected[3] = Lexer.TokenKind.LiteralInt;
                    expected[4] = Lexer.TokenKind.LBracket;

                    self.replaceErr(try Errors.parserError(self.allocator, Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end }, self.currentTokenLexeme(), expected));
                }

                return error.InterpreterError;
            },
        }
    }

    fn currentToken(self: *Parser) Lexer.Token {
        return self.lexer.current;
    }

    fn currentTokenKind(self: *Parser) Lexer.TokenKind {
        return self.lexer.current.kind;
    }

    fn currentTokenLexeme(self: *Parser) []const u8 {
        return self.lexer.lexeme(self.lexer.current);
    }

    fn nextToken(self: *Parser) Errors.err!Lexer.Token {
        const token = self.lexer.current;

        try self.lexer.next();

        return token;
    }

    fn skipToken(self: *Parser) Errors.err!void {
        try self.lexer.next();
    }

    fn matchToken(self: *Parser, kind: Lexer.TokenKind) Errors.err!Lexer.Token {
        const token = try self.nextToken();

        if (token.kind != kind) {
            {
                var expected = try self.allocator.alloc(Lexer.TokenKind, 1);
                errdefer self.allocator.free(expected);

                expected[0] = kind;
                self.replaceErr(try Errors.parserError(self.allocator, Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end }, self.currentTokenLexeme(), expected));
            }

            return error.InterpreterError;
        }

        return token;
    }

    fn matchSkipToken(self: *Parser, kind: Lexer.TokenKind) Errors.err!void {
        _ = try self.matchToken(kind);
    }

    fn replaceErr(self: *Parser, err: Errors.Error) void {
        self.eraseErr();
        self.err = err;
    }

    pub fn eraseErr(self: *Parser) void {
        if (self.err != null) {
            self.err.?.deinit();
            self.err = null;
        }
        self.lexer.eraseErr();
    }

    pub fn grabErr(self: *Parser) ?Errors.Error {
        var err = self.err;

        if (err == null) {
            err = self.lexer.grabErr();
        }
        self.err = null;
        self.lexer.eraseErr();

        return err;
    }
};
