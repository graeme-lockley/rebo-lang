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
        var lhs = try self.multiplicative();
        errdefer AST.destroy(self.allocator, lhs);

        while (true) {
            const kind = self.currentTokenKind();

            if (kind == Lexer.TokenKind.Plus or kind == Lexer.TokenKind.Minus) {
                try self.skipToken();

                const rhs = try self.multiplicative();
                errdefer AST.destroy(self.allocator, rhs);

                const v = try self.allocator.create(AST.Expression);
                const op = if (kind == Lexer.TokenKind.Plus) AST.Operator.Plus else AST.Operator.Minus;

                v.* = AST.Expression{
                    .kind = AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = op } },
                    .position = Errors.Position{ .start = lhs.position.start, .end = rhs.position.end },
                };
                lhs = v;
            } else {
                break;
            }
        }

        return lhs;
    }

    pub fn multiplicative(self: *Parser) Errors.err!*AST.Expression {
        var lhs = try self.factor();
        errdefer AST.destroy(self.allocator, lhs);

        while (true) {
            const kind = self.currentTokenKind();

            if (kind == Lexer.TokenKind.Star or kind == Lexer.TokenKind.Slash) {
                try self.skipToken();

                const rhs = try self.factor();
                errdefer AST.destroy(self.allocator, rhs);

                const v = try self.allocator.create(AST.Expression);
                const op = if (kind == Lexer.TokenKind.Star) AST.Operator.Times else AST.Operator.Divide;

                v.* = AST.Expression{
                    .kind = AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = op } },
                    .position = Errors.Position{ .start = lhs.position.start, .end = rhs.position.end },
                };
                lhs = v;
            } else {
                break;
            }
        }

        return lhs;
    }

    pub fn factor(self: *Parser) Errors.err!*AST.Expression {
        switch (self.currentTokenKind()) {
            Lexer.TokenKind.LParen => {
                const lparen = try self.nextToken();

                if (self.currentTokenKind() == Lexer.TokenKind.RParen) {
                    const rparen = try self.nextToken();

                    const v = try self.allocator.create(AST.Expression);
                    v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalVoid = void{} }, .position = Errors.Position{ .start = lparen.start, .end = rparen.end } };
                    return v;
                }

                const e = try self.expression();
                errdefer AST.destroy(self.allocator, e);

                try self.matchSkipToken(Lexer.TokenKind.RParen);

                return e;
            },
            Lexer.TokenKind.LiteralBoolFalse => {
                const token = try self.nextToken();

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalBool = false }, .position = Errors.Position{ .start = token.start, .end = token.end } };
                return v;
            },
            Lexer.TokenKind.LiteralBoolTrue => {
                const token = try self.nextToken();

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalBool = true }, .position = Errors.Position{ .start = token.start, .end = token.end } };
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

                const token = try self.nextToken();
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalInt = literalInt }, .position = Errors.Position{ .start = token.start, .end = token.end } };

                return v;
            },
            Lexer.TokenKind.LBracket => {
                const lbracket = try self.nextToken();

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

                const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalList = es.toOwnedSlice() }, .position = Errors.Position{ .start = lbracket.start, .end = rbracket.end } };
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
