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

    pub fn module(self: *Parser) Errors.err!*AST.Expression {
        const start = self.currentToken().start;

        var exprs = std.ArrayList(*AST.Expression).init(self.allocator);
        defer exprs.deinit();
        errdefer {
            for (exprs.items) |expr| {
                AST.destroy(self.allocator, expr);
            }
        }

        while (self.currentTokenKind() != Lexer.TokenKind.EOS) {
            try exprs.append(try self.expression());

            while (self.currentTokenKind() == Lexer.TokenKind.Semicolon) {
                try self.skipToken();
            }
        }

        const v = try self.allocator.create(AST.Expression);
        v.* = AST.Expression{
            .kind = AST.ExpressionKind{ .exprs = try exprs.toOwnedSlice() },
            .position = Errors.Position{ .start = start, .end = self.currentToken().end },
        };
        return v;
    }

    pub fn expression(self: *Parser) Errors.err!*AST.Expression {
        if (self.currentTokenKind() == Lexer.TokenKind.Let) {
            const letToken = try self.nextToken();

            const nameToken = try self.matchToken(Lexer.TokenKind.Identifier);
            const name = try self.allocator.dupe(u8, self.lexer.lexeme(nameToken));
            errdefer self.allocator.free(name);

            if (self.currentTokenKind() == Lexer.TokenKind.LParen) {
                var literalFn = try self.functionTail(letToken.start);
                errdefer AST.destroy(self.allocator, literalFn);

                const v = try self.allocator.create(AST.Expression);

                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .declaration = AST.DeclarationExpression{ .name = name, .value = literalFn } }, .position = Errors.Position{ .start = nameToken.start, .end = literalFn.position.end } };

                return v;
            } else {
                try self.matchSkipToken(Lexer.TokenKind.Equal);

                const value = try self.expression();
                errdefer AST.destroy(self.allocator, value);

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .declaration = AST.DeclarationExpression{ .name = name, .value = value } }, .position = Errors.Position{ .start = letToken.start, .end = value.position.end } };
                return v;
            }

            // } else if (self.currentTokenKind() == Lexer.TokenKind.If) {
            //     const ifToken = try self.nextToken();

            //     const condition = try self.expression();
            //     errdefer AST.destroy(self.allocator, condition);

            //     try self.matchSkipToken(Lexer.TokenKind.Then);

            //     const then = try self.expression();
            //     errdefer AST.destroy(self.allocator, then);

            //     try self.matchSkipToken(Lexer.TokenKind.Else);

            //     const else_ = try self.expression();
            //     errdefer AST.destroy(self.allocator, else_);

            //     const v = try self.allocator.create(AST.Expression);
            //     v.* = AST.Expression{ .kind = AST.ExpressionKind{ .if = AST.IfExpression{ .condition = condition, .then = then, .else = else_ } }, .position = Errors.Position{ .start = ifToken.start, .end = else_.position.end } };
            //     return v;
            // } else if (self.currentTokenKind() == Lexer.TokenKind.While) {
            //     const whileToken = try self.nextToken();

            //     const condition = try self.expression();
            //     errdefer AST.destroy(self.allocator, condition);

            //     try self.matchSkipToken(Lexer.TokenKind.Do);

            //     const body = try self.expression();
            //     errdefer AST.destroy(self.allocator, body);

            //     const v = try self.allocator.create(AST.Expression);
            //     v.* = AST.Expression{ .kind = AST.ExpressionKind{ .while = AST.WhileExpression{ .condition = condition, .body = body } }, .position = Errors.Position{ .start = whileToken.start, .end = body.position
        } else if (self.currentTokenKind() == Lexer.TokenKind.If) {
            const ifToken = try self.nextToken();

            var couples = std.ArrayList(AST.IfCouple).init(self.allocator);
            defer couples.deinit();
            errdefer {
                for (couples.items) |couple| {
                    if (couple.condition != null) {
                        AST.destroy(self.allocator, couple.condition.?);
                    }
                    AST.destroy(self.allocator, couple.then);
                }
            }

            if (self.currentTokenKind() == Lexer.TokenKind.Bar) {
                try self.skipToken();
            }

            const firstGuard = try self.expression();
            errdefer AST.destroy(self.allocator, firstGuard);

            if (self.currentTokenKind() == Lexer.TokenKind.MinusGreater) {
                try self.skipToken();
                const then = try self.expression();

                try couples.append(AST.IfCouple{ .condition = firstGuard, .then = then });
                while (self.currentTokenKind() == Lexer.TokenKind.Bar) {
                    try self.skipToken();

                    const guard = try self.expression();
                    errdefer AST.destroy(self.allocator, guard);

                    if (self.currentTokenKind() == Lexer.TokenKind.MinusGreater) {
                        try self.skipToken();

                        const then2 = try self.expression();
                        errdefer AST.destroy(self.allocator, then2);

                        try couples.append(AST.IfCouple{ .condition = guard, .then = then2 });
                    } else {
                        try couples.append(AST.IfCouple{ .condition = null, .then = guard });
                        break;
                    }
                }
            } else {
                try couples.append(AST.IfCouple{ .condition = null, .then = firstGuard });
            }

            const v = try self.allocator.create(AST.Expression);
            v.* = AST.Expression{ .kind = AST.ExpressionKind{ .ifte = try couples.toOwnedSlice() }, .position = Errors.Position{ .start = ifToken.start, .end = self.lexer.current.end } };
            return v;
        } else {
            var lhs = try self.orExpr();

            if (self.currentTokenKind() == Lexer.TokenKind.ColonEqual) {
                try self.skipToken();
                const value = try self.expression();

                const v = try self.allocator.create(AST.Expression);

                v.* = AST.Expression{
                    .kind = AST.ExpressionKind{ .assignment = AST.AssignmentExpression{ .lhs = lhs, .value = value } },
                    .position = Errors.Position{ .start = lhs.position.start, .end = value.position.end },
                };
                lhs = v;
            }

            return lhs;
        }
    }

    fn orExpr(self: *Parser) Errors.err!*AST.Expression {
        var lhs = try self.andExpr();
        errdefer AST.destroy(self.allocator, lhs);

        while (self.currentTokenKind() == Lexer.TokenKind.BarBar) {
            try self.skipToken();

            const rhs = try self.andExpr();
            errdefer AST.destroy(self.allocator, rhs);

            const v = try self.allocator.create(AST.Expression);

            v.* = AST.Expression{
                .kind = AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = AST.Operator.Or } },
                .position = Errors.Position{ .start = lhs.position.start, .end = rhs.position.end },
            };
            lhs = v;
        }

        return lhs;
    }

    fn andExpr(self: *Parser) Errors.err!*AST.Expression {
        var lhs = try self.equality();
        errdefer AST.destroy(self.allocator, lhs);

        while (self.currentTokenKind() == Lexer.TokenKind.AmpersandAmpersand) {
            try self.skipToken();

            const rhs = try self.equality();
            errdefer AST.destroy(self.allocator, rhs);

            const v = try self.allocator.create(AST.Expression);

            v.* = AST.Expression{
                .kind = AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = AST.Operator.And } },
                .position = Errors.Position{ .start = lhs.position.start, .end = rhs.position.end },
            };
            lhs = v;
        }

        return lhs;
    }

    fn equality(self: *Parser) Errors.err!*AST.Expression {
        var lhs = try self.additive();
        errdefer AST.destroy(self.allocator, lhs);

        const kind = self.currentTokenKind();

        if (kind == Lexer.TokenKind.EqualEqual or kind == Lexer.TokenKind.BangEqual or kind == Lexer.TokenKind.LessThan or kind == Lexer.TokenKind.LessEqual or kind == Lexer.TokenKind.GreaterThan or kind == Lexer.TokenKind.GreaterEqual) {
            try self.skipToken();

            const rhs = try self.additive();
            errdefer AST.destroy(self.allocator, rhs);

            const v = try self.allocator.create(AST.Expression);
            const op = switch (kind) {
                Lexer.TokenKind.EqualEqual => AST.Operator.Equal,
                Lexer.TokenKind.BangEqual => AST.Operator.NotEqual,
                Lexer.TokenKind.LessEqual => AST.Operator.LessEqual,
                Lexer.TokenKind.LessThan => AST.Operator.LessThan,
                Lexer.TokenKind.GreaterEqual => AST.Operator.GreaterEqual,
                Lexer.TokenKind.GreaterThan => AST.Operator.GreaterThan,
                else => unreachable,
            };

            v.* = AST.Expression{
                .kind = AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = op } },
                .position = Errors.Position{ .start = lhs.position.start, .end = rhs.position.end },
            };
            lhs = v;
        }

        return lhs;
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
        var lhs = try self.qualifier();
        errdefer AST.destroy(self.allocator, lhs);

        while (true) {
            const kind = self.currentTokenKind();

            if (kind == Lexer.TokenKind.Star or kind == Lexer.TokenKind.Slash or kind == Lexer.TokenKind.Percentage) {
                try self.skipToken();

                const rhs = try self.qualifier();
                errdefer AST.destroy(self.allocator, rhs);

                const v = try self.allocator.create(AST.Expression);
                const op = if (kind == Lexer.TokenKind.Star) AST.Operator.Times else if (kind == Lexer.TokenKind.Slash) AST.Operator.Divide else AST.Operator.Modulo;

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

    pub fn qualifier(self: *Parser) Errors.err!*AST.Expression {
        var result = try self.factor();
        errdefer AST.destroy(self.allocator, result);

        while (true) {
            const kind = self.currentTokenKind();

            if (kind == Lexer.TokenKind.LParen) {
                const lparen = try self.nextToken();

                var args = std.ArrayList(*AST.Expression).init(self.allocator);
                defer args.deinit();
                errdefer {
                    for (args.items) |item| {
                        AST.destroy(self.allocator, item);
                    }
                }

                if (self.currentTokenKind() != Lexer.TokenKind.RParen) {
                    try args.append(try self.expression());
                    while (self.currentTokenKind() == Lexer.TokenKind.Comma) {
                        try self.skipToken();
                        try args.append(try self.expression());
                    }
                }

                const rparen = try self.matchToken(Lexer.TokenKind.RParen);

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .call = AST.CallExpression{ .callee = result, .args = try args.toOwnedSlice() } }, .position = Errors.Position{ .start = lparen.start, .end = rparen.end } };
                result = v;
            } else if (kind == Lexer.TokenKind.LBracket) {
                const lbracket = try self.nextToken();

                if (self.currentTokenKind() == Lexer.TokenKind.Colon) {
                    try self.skipToken();
                    if (self.currentTokenKind() == Lexer.TokenKind.RBracket) {
                        const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);
                        const v = try self.allocator.create(AST.Expression);
                        v.* = AST.Expression{ .kind = AST.ExpressionKind{ .indexRange = AST.IndexRangeExpression{ .expr = result, .start = null, .end = null } }, .position = Errors.Position{ .start = lbracket.start, .end = rbracket.end } };
                        result = v;
                    } else {
                        const end = try self.expression();
                        errdefer AST.destroy(self.allocator, end);
                        const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                        const v = try self.allocator.create(AST.Expression);
                        v.* = AST.Expression{ .kind = AST.ExpressionKind{ .indexRange = AST.IndexRangeExpression{ .expr = result, .start = null, .end = end } }, .position = Errors.Position{ .start = lbracket.start, .end = rbracket.end } };
                        result = v;
                    }
                } else {
                    const index = try self.expression();
                    errdefer AST.destroy(self.allocator, index);

                    if (self.currentTokenKind() == Lexer.TokenKind.Colon) {
                        try self.skipToken();
                        if (self.currentTokenKind() == Lexer.TokenKind.RBracket) {
                            const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                            const v = try self.allocator.create(AST.Expression);
                            v.* = AST.Expression{ .kind = AST.ExpressionKind{ .indexRange = AST.IndexRangeExpression{ .expr = result, .start = index, .end = null } }, .position = Errors.Position{ .start = lbracket.start, .end = rbracket.end } };
                            result = v;
                        } else {
                            const end = try self.expression();
                            errdefer AST.destroy(self.allocator, end);
                            const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                            const v = try self.allocator.create(AST.Expression);
                            v.* = AST.Expression{ .kind = AST.ExpressionKind{ .indexRange = AST.IndexRangeExpression{ .expr = result, .start = index, .end = end } }, .position = Errors.Position{ .start = lbracket.start, .end = rbracket.end } };
                            result = v;
                        }
                    } else {
                        const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                        const v = try self.allocator.create(AST.Expression);
                        v.* = AST.Expression{ .kind = AST.ExpressionKind{ .indexValue = AST.IndexValueExpression{ .expr = result, .index = index } }, .position = Errors.Position{ .start = lbracket.start, .end = rbracket.end } };
                        result = v;
                    }
                }
            } else if (kind == Lexer.TokenKind.Dot) {
                try self.skipToken();

                const field = try self.matchToken(Lexer.TokenKind.Identifier);

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .dot = AST.DotExpression{ .record = result, .field = try self.allocator.dupe(u8, self.lexer.lexeme(field)) } }, .position = Errors.Position{ .start = result.position.start, .end = field.end } };
                result = v;
            } else {
                break;
            }
        }

        return result;
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
            Lexer.TokenKind.LCurly => {
                const lcurly = try self.nextToken();

                if (self.currentTokenKind() == Lexer.TokenKind.RCurly or self.currentTokenKind() == Lexer.TokenKind.Identifier and try self.peekNextToken() == Lexer.TokenKind.Colon) {
                    var es = std.ArrayList(AST.RecordEntry).init(self.allocator);
                    defer {
                        for (es.items) |item| {
                            self.allocator.free(item.key);
                            AST.destroy(self.allocator, item.value);
                        }
                        es.deinit();
                    }

                    if (self.currentTokenKind() != Lexer.TokenKind.RCurly) {
                        const me = try self.RecordEntry();
                        try es.append(me);

                        while (self.currentTokenKind() == Lexer.TokenKind.Comma) {
                            try self.skipToken();
                            try es.append(try self.RecordEntry());
                        }
                    }

                    const rcurly = try self.matchToken(Lexer.TokenKind.RCurly);

                    const v = try self.allocator.create(AST.Expression);
                    v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalRecord = try es.toOwnedSlice() }, .position = Errors.Position{ .start = lcurly.start, .end = rcurly.end } };
                    return v;
                } else {
                    var es = std.ArrayList(*AST.Expression).init(self.allocator);
                    defer {
                        for (es.items) |item| {
                            AST.destroy(self.allocator, item);
                        }
                        es.deinit();
                    }

                    while (self.currentTokenKind() != Lexer.TokenKind.RCurly) {
                        try es.append(try self.expression());
                        while (self.currentTokenKind() == Lexer.TokenKind.Semicolon) {
                            try self.skipToken();
                        }
                    }

                    const rcurly = try self.matchToken(Lexer.TokenKind.RCurly);

                    const v = try self.allocator.create(AST.Expression);
                    v.* = AST.Expression{ .kind = AST.ExpressionKind{ .exprs = try es.toOwnedSlice() }, .position = Errors.Position{ .start = lcurly.start, .end = rcurly.end } };
                    return v;
                }
            },
            Lexer.TokenKind.Identifier => {
                const lexeme = self.lexer.currentLexeme();

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .identifier = try self.allocator.dupe(u8, lexeme) }, .position = Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end } };

                try self.skipToken();

                return v;
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
            Lexer.TokenKind.LiteralChar => {
                const lexeme = self.lexer.currentLexeme();
                var r: u8 = 0;

                if (lexeme.len == 3) {
                    r = lexeme[1];
                } else if (lexeme.len == 4) {
                    if (lexeme[2] == 'n') {
                        r = 10;
                    } else {
                        r = lexeme[2];
                    }
                } else {
                    r = std.fmt.parseInt(u8, lexeme[3 .. lexeme.len - 1], 10) catch 0;
                }

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalChar = r }, .position = Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end } };

                try self.skipToken();

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
            Lexer.TokenKind.LiteralFloat => {
                const lexeme = self.lexer.currentLexeme();

                const literalFloat = std.fmt.parseFloat(f64, lexeme) catch {
                    const token = self.currentToken();
                    self.replaceErr(try Errors.literalFloatOverflowError(self.allocator, Errors.Position{ .start = token.start, .end = token.end }, lexeme));
                    return error.InterpreterError;
                };

                const v = try self.allocator.create(AST.Expression);
                errdefer AST.destroy(self.allocator, v);

                const token = try self.nextToken();
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalFloat = literalFloat }, .position = Errors.Position{ .start = token.start, .end = token.end } };

                return v;
            },
            Lexer.TokenKind.LiteralString => {
                const lexeme = self.lexer.currentLexeme();
                var buffer = std.ArrayList(u8).init(self.allocator);
                defer buffer.deinit();

                var i: usize = 1;

                while (i < lexeme.len - 1) {
                    const c = lexeme[i];

                    if (c == '\\') {
                        i += 1;

                        switch (lexeme[i]) {
                            'n' => try buffer.append('\n'),
                            '\\' => try buffer.append('\\'),
                            '"' => try buffer.append('"'),
                            'x' => {
                                i += 1;
                                const start = i;

                                while (lexeme[i] != ';') {
                                    i += 1;
                                }

                                const c2 = std.fmt.parseInt(u8, lexeme[start..i], 10) catch 0;
                                try std.fmt.format(buffer.writer(), "{c}", .{c2});

                                i += 1;
                            },
                            else => {},
                        }
                    } else {
                        try buffer.append(c);
                    }

                    i += 1;
                }

                const token = try self.nextToken();

                const v = try self.allocator.create(AST.Expression);
                errdefer AST.destroy(self.allocator, v);

                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalString = try buffer.toOwnedSlice() }, .position = Errors.Position{ .start = token.start, .end = token.end } };

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
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalSequence = try es.toOwnedSlice() }, .position = Errors.Position{ .start = lbracket.start, .end = rbracket.end } };
                return v;
            },
            Lexer.TokenKind.Fn => {
                const fnToken = try self.nextToken();

                return self.functionTail(fnToken.start);
            },
            else => {
                {
                    var expected = try self.allocator.alloc(Lexer.TokenKind, 11);
                    errdefer self.allocator.free(expected);

                    expected[0] = Lexer.TokenKind.LBracket;
                    expected[1] = Lexer.TokenKind.LCurly;
                    expected[2] = Lexer.TokenKind.Identifier;
                    expected[3] = Lexer.TokenKind.LParen;
                    expected[4] = Lexer.TokenKind.LiteralBoolFalse;
                    expected[5] = Lexer.TokenKind.LiteralBoolTrue;
                    expected[6] = Lexer.TokenKind.LiteralChar;
                    expected[7] = Lexer.TokenKind.LiteralFloat;
                    expected[8] = Lexer.TokenKind.LiteralInt;
                    expected[9] = Lexer.TokenKind.LiteralString;
                    expected[10] = Lexer.TokenKind.Fn;

                    self.replaceErr(try Errors.parserError(self.allocator, Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end }, self.currentTokenLexeme(), expected));
                }

                return error.InterpreterError;
            },
        }
    }

    fn functionTail(self: *Parser, start: usize) !*AST.Expression {
        var restOfParams: ?[]u8 = null;
        errdefer {
            if (restOfParams != null) {
                self.allocator.free(restOfParams.?);
            }
        }
        var params = try self.parameters(&restOfParams);
        errdefer {
            for (params) |*param| {
                param.deinit(self.allocator);
            }
            self.allocator.free(params);
        }

        try self.matchSkipToken(Lexer.TokenKind.Equal);

        const body = try self.expression();
        errdefer AST.destroy(self.allocator, body);

        const v = try self.allocator.create(AST.Expression);
        v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalFunction = AST.Function{ .params = params, .restOfParams = restOfParams, .body = body } }, .position = Errors.Position{ .start = start, .end = body.position.end } };
        return v;
    }

    fn parameters(self: *Parser, restOfParams: *?[]u8) ![]AST.FunctionParam {
        var params = std.ArrayList(AST.FunctionParam).init(self.allocator);
        defer params.deinit();
        errdefer for (params.items) |*param| {
            param.deinit(self.allocator);
        };

        try self.matchSkipToken(Lexer.TokenKind.LParen);

        if (self.currentTokenKind() == Lexer.TokenKind.DotDotDot) {
            try self.skipToken();
            const nameToken = try self.matchToken(Lexer.TokenKind.Identifier);
            restOfParams.* = try self.allocator.dupe(u8, self.lexer.lexeme(nameToken));
        } else if (self.currentTokenKind() != Lexer.TokenKind.RParen) {
            try params.append(try self.parameter());
            while (self.currentTokenKind() == Lexer.TokenKind.Comma) {
                try self.skipToken();

                if (self.currentTokenKind() == Lexer.TokenKind.DotDotDot) {
                    try self.skipToken();
                    const nameToken = try self.matchToken(Lexer.TokenKind.Identifier);
                    restOfParams.* = try self.allocator.dupe(u8, self.lexer.lexeme(nameToken));
                    break;
                }
                try params.append(try self.parameter());
            }
        }

        try self.matchSkipToken(Lexer.TokenKind.RParen);

        return try params.toOwnedSlice();
    }

    fn parameter(self: *Parser) !AST.FunctionParam {
        const nameToken = try self.matchToken(Lexer.TokenKind.Identifier);
        const name = try self.allocator.dupe(u8, self.lexer.lexeme(nameToken));
        errdefer self.allocator.free(name);

        if (self.currentTokenKind() == Lexer.TokenKind.Equal) {
            try self.skipToken();

            const default = try self.expression();
            return AST.FunctionParam{ .name = name, .default = default };
        } else {
            return AST.FunctionParam{ .name = name, .default = null };
        }
    }

    fn RecordEntry(self: *Parser) !AST.RecordEntry {
        const key = try self.matchToken(Lexer.TokenKind.Identifier);
        try self.matchSkipToken(Lexer.TokenKind.Colon);
        const value = try self.expression();

        const keyValue = try self.allocator.dupe(u8, self.lexer.lexeme(key));

        return AST.RecordEntry{ .key = keyValue, .value = value };
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

    fn peekNextToken(self: *Parser) !Lexer.TokenKind {
        return try self.lexer.peekNext();
    }

    fn skipToken(self: *Parser) Errors.err!void {
        try self.lexer.next();
    }

    fn matchToken(self: *Parser, kind: Lexer.TokenKind) Errors.err!Lexer.Token {
        const token = self.currentToken();

        if (token.kind != kind) {
            {
                var expected = try self.allocator.alloc(Lexer.TokenKind, 1);
                errdefer self.allocator.free(expected);

                expected[0] = kind;
                self.replaceErr(try Errors.parserError(self.allocator, Errors.Position{ .start = token.start, .end = token.end }, self.currentTokenLexeme(), expected));
            }

            return error.InterpreterError;
        }

        return self.nextToken();
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
