const std = @import("std");

const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const Lexer = @import("./lexer.zig");
const SP = @import("./string_pool.zig");
const V = @import("./value.zig");

pub const Parser = struct {
    allocator: std.mem.Allocator,
    stringPool: *SP.StringPool,
    lexer: Lexer.Lexer,
    err: ?Errors.Error,

    pub fn init(stringPool: *SP.StringPool, lexer: Lexer.Lexer) Parser {
        return Parser{
            .allocator = stringPool.allocator,
            .stringPool = stringPool,
            .lexer = lexer,
            .err = null,
        };
    }

    pub fn module(self: *Parser) Errors.ParserErrors!*AST.Expression {
        const start = self.currentToken().start;

        var exprs = std.ArrayList(*AST.Expression).init(self.allocator);
        defer exprs.deinit();
        errdefer {
            for (exprs.items) |expr| {
                expr.destroy(self.allocator);
            }
        }

        while (self.currentTokenKind() != Lexer.TokenKind.EOS) {
            try exprs.append(try self.expression());

            while (self.currentTokenKind() == Lexer.TokenKind.Semicolon) {
                try self.skipToken();
            }
        }

        return try AST.Expression.create(self.allocator, AST.ExpressionKind{ .exprs = try exprs.toOwnedSlice() }, Errors.Position{ .start = start, .end = self.currentToken().end });
    }

    pub fn expression(self: *Parser) Errors.ParserErrors!*AST.Expression {
        if (self.currentTokenKind() == Lexer.TokenKind.Let) {
            const letToken = try self.nextToken();

            const nextNextToken = try self.peekNextToken();
            if (self.currentTokenKind() == Lexer.TokenKind.Identifier and (nextNextToken == Lexer.TokenKind.Equal or nextNextToken == Lexer.TokenKind.LParen)) {
                const nameToken = try self.matchToken(Lexer.TokenKind.Identifier);
                const name = self.lexer.lexeme(nameToken);

                if (self.currentTokenKind() == Lexer.TokenKind.LParen) {
                    var literalFn = try self.functionTail(letToken.start);
                    errdefer literalFn.destroy(self.allocator);

                    return try AST.Expression.create(self.allocator, AST.ExpressionKind{ .idDeclaration = AST.IdDeclarationExpression{ .name = try self.stringPool.intern(name), .value = literalFn } }, Errors.Position{ .start = nameToken.start, .end = literalFn.position.end });
                } else {
                    try self.matchSkipToken(Lexer.TokenKind.Equal);

                    const value = try self.expression();
                    errdefer value.destroy(self.allocator);

                    return try AST.Expression.create(self.allocator, AST.ExpressionKind{ .idDeclaration = AST.IdDeclarationExpression{ .name = try self.stringPool.intern(name), .value = value } }, Errors.Position{ .start = letToken.start, .end = value.position.end });
                }
            } else {
                const pttrn = try self.pattern();
                errdefer pttrn.destroy(self.allocator);

                try self.matchSkipToken(Lexer.TokenKind.Equal);

                const value = try self.expression();
                errdefer value.destroy(self.allocator);

                return try AST.Expression.create(self.allocator, AST.ExpressionKind{ .patternDeclaration = AST.PatternDeclarationExpression{ .pattern = pttrn, .value = value } }, Errors.Position{ .start = letToken.start, .end = value.position.end });
            }
        } else if (self.currentTokenKind() == Lexer.TokenKind.If) {
            const ifToken = try self.nextToken();

            var couples = std.ArrayList(AST.IfCouple).init(self.allocator);
            defer couples.deinit();
            errdefer {
                for (couples.items, 0..) |couple, idx| {
                    if (idx > 0) {
                        if (couple.condition != null) {
                            couple.condition.?.destroy(self.allocator);
                        }
                        couple.then.destroy(self.allocator);
                    }
                }
            }

            if (self.currentTokenKind() == Lexer.TokenKind.Bar) {
                try self.skipToken();
            }

            const firstGuard = try self.expression();
            errdefer firstGuard.destroy(self.allocator);

            if (self.currentTokenKind() == Lexer.TokenKind.MinusGreater) {
                try self.skipToken();
                const then = try self.expression();
                errdefer then.destroy(self.allocator);

                try couples.append(AST.IfCouple{ .condition = firstGuard, .then = then });
                while (self.currentTokenKind() == Lexer.TokenKind.Bar) {
                    try self.skipToken();

                    const guard = try self.expression();
                    errdefer guard.destroy(self.allocator);

                    if (self.currentTokenKind() == Lexer.TokenKind.MinusGreater) {
                        try self.skipToken();

                        const then2 = try self.expression();
                        errdefer then2.destroy(self.allocator);

                        try couples.append(AST.IfCouple{ .condition = guard, .then = then2 });
                    } else {
                        try couples.append(AST.IfCouple{ .condition = null, .then = guard });
                        break;
                    }
                }
            } else {
                try couples.append(AST.IfCouple{ .condition = null, .then = firstGuard });
            }

            return try AST.Expression.create(self.allocator, AST.ExpressionKind{ .ifte = try couples.toOwnedSlice() }, Errors.Position{ .start = ifToken.start, .end = self.lexer.current.end });
        } else if (self.currentTokenKind() == Lexer.TokenKind.Match) {
            const matchTkn = try self.nextToken();

            const value = try self.expression();
            errdefer value.destroy(self.allocator);

            var cases = std.ArrayList(AST.MatchCase).init(self.allocator);
            defer cases.deinit();
            errdefer {
                for (cases.items) |*item| {
                    item.deinit(self.allocator);
                }
            }

            if (self.currentTokenKind() == Lexer.TokenKind.Bar) {
                try self.skipToken();
            }
            try cases.append(try self.matchCase());

            while (self.currentTokenKind() == Lexer.TokenKind.Bar) {
                try self.skipToken();
                try cases.append(try self.matchCase());
            }

            const endPosition = cases.getLast().body.position.end;

            return try AST.Expression.create(self.allocator, AST.ExpressionKind{ .match = AST.MatchExpression{ .value = value, .cases = try cases.toOwnedSlice(), .elseCase = null } }, Errors.Position{ .start = matchTkn.start, .end = endPosition });
        } else if (self.currentTokenKind() == Lexer.TokenKind.Raise) {
            const raiseToken = try self.nextToken();
            const expr = try self.expression();
            errdefer expr.destroy(self.allocator);

            return try AST.Expression.create(self.allocator, AST.ExpressionKind{ .raise = AST.RaiseExpression{ .expr = expr } }, Errors.Position{ .start = raiseToken.start, .end = expr.position.end });
        } else if (self.currentTokenKind() == Lexer.TokenKind.While) {
            const whileToken = try self.nextToken();

            const condition = try self.expression();
            errdefer condition.destroy(self.allocator);

            try self.matchSkipToken(Lexer.TokenKind.MinusGreater);

            const body = try self.expression();
            errdefer body.destroy(self.allocator);

            return try AST.Expression.create(self.allocator, AST.ExpressionKind{ .whilee = AST.WhileExpression{ .condition = condition, .body = body } }, Errors.Position{ .start = whileToken.start, .end = body.position.end });
        } else {
            var lhs = try self.catchExpr();
            errdefer lhs.destroy(self.allocator);

            if (self.currentTokenKind() == Lexer.TokenKind.ColonEqual) {
                try self.skipToken();
                const value = try self.expression();

                lhs = try AST.Expression.create(self.allocator, AST.ExpressionKind{ .assignment = AST.AssignmentExpression{ .lhs = lhs, .value = value } }, Errors.Position{ .start = lhs.position.start, .end = value.position.end });
            }

            return lhs;
        }
    }

    fn catchExpr(self: *Parser) Errors.ParserErrors!*AST.Expression {
        const expr = try self.pipeExpr();
        errdefer expr.destroy(self.allocator);

        if (self.currentTokenKind() == Lexer.TokenKind.Catch) {
            try self.skipToken();

            var cases = std.ArrayList(AST.MatchCase).init(self.allocator);
            defer cases.deinit();
            errdefer {
                for (cases.items) |*item| {
                    item.deinit(self.allocator);
                }
            }

            if (self.currentTokenKind() == Lexer.TokenKind.Bar) {
                try self.skipToken();
            }
            try cases.append(try self.matchCase());

            while (self.currentTokenKind() == Lexer.TokenKind.Bar) {
                try self.skipToken();
                try cases.append(try self.matchCase());
            }

            const endPosition = cases.getLast().body.position.end;

            return try AST.Expression.create(self.allocator, AST.ExpressionKind{ .catche = AST.CatchExpression{ .value = expr, .cases = try cases.toOwnedSlice() } }, Errors.Position{ .start = expr.position.start, .end = endPosition });
        } else {
            return expr;
        }
    }

    fn pipeExpr(self: *Parser) Errors.ParserErrors!*AST.Expression {
        var lhs = try self.orExpr();
        errdefer lhs.destroy(self.allocator);

        while (true) {
            if (self.currentTokenKind() == Lexer.TokenKind.BarGreater) {
                try self.skipToken();

                const rhs = try self.orExpr();
                errdefer rhs.destroy(self.allocator);

                if (rhs.kind == .call) {
                    const args = try self.allocator.alloc(*AST.Expression, rhs.kind.call.args.len + 1);
                    errdefer self.allocator.free(args);

                    args[0] = lhs;
                    for (rhs.kind.call.args, 0..) |arg, idx| {
                        args[idx + 1] = arg;
                    }
                    self.allocator.free(rhs.kind.call.args);
                    rhs.kind.call.args = args;

                    lhs = rhs;
                } else {
                    self.replaceErr(try Errors.functionValueExpectedError(self.allocator, self.lexer.name, rhs.position));
                    return error.FunctionValueExpectedError;
                }
            } else if (self.currentTokenKind() == Lexer.TokenKind.LessBar) {
                try self.skipToken();

                const rhs = try self.orExpr();
                errdefer rhs.destroy(self.allocator);

                if (lhs.kind == .call) {
                    const args = try self.allocator.alloc(*AST.Expression, lhs.kind.call.args.len + 1);
                    errdefer self.allocator.free(args);

                    args[lhs.kind.call.args.len] = rhs;
                    for (lhs.kind.call.args, 0..) |arg, idx| {
                        args[idx] = arg;
                    }
                    self.allocator.free(lhs.kind.call.args);
                    lhs.kind.call.args = args;
                } else {
                    self.replaceErr(try Errors.functionValueExpectedError(self.allocator, self.lexer.name, lhs.position));
                    return error.FunctionValueExpectedError;
                }
            } else {
                break;
            }
        }

        return lhs;
    }

    fn matchCase(self: *Parser) Errors.ParserErrors!AST.MatchCase {
        const pttrn = try self.pattern();
        errdefer pttrn.destroy(self.allocator);

        try self.matchSkipToken(Lexer.TokenKind.MinusGreater);

        const body = try self.expression();

        return AST.MatchCase{ .pattern = pttrn, .body = body };
    }

    fn orExpr(self: *Parser) Errors.ParserErrors!*AST.Expression {
        var lhs = try self.andExpr();
        errdefer lhs.destroy(self.allocator);

        while (self.currentTokenKind() == Lexer.TokenKind.BarBar) {
            try self.skipToken();

            const rhs = try self.andExpr();
            errdefer rhs.destroy(self.allocator);

            lhs = try AST.Expression.create(self.allocator, AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = AST.Operator.Or } }, Errors.Position{ .start = lhs.position.start, .end = rhs.position.end });
        }

        return lhs;
    }

    fn andExpr(self: *Parser) Errors.ParserErrors!*AST.Expression {
        var lhs = try self.equality();
        errdefer lhs.destroy(self.allocator);

        while (self.currentTokenKind() == Lexer.TokenKind.AmpersandAmpersand) {
            try self.skipToken();

            const rhs = try self.equality();
            errdefer rhs.destroy(self.allocator);

            lhs = try AST.Expression.create(self.allocator, AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = AST.Operator.And } }, Errors.Position{ .start = lhs.position.start, .end = rhs.position.end });
        }

        return lhs;
    }

    fn equality(self: *Parser) Errors.ParserErrors!*AST.Expression {
        var lhs = try self.starpend();
        errdefer lhs.destroy(self.allocator);

        const kind = self.currentTokenKind();

        if (kind == Lexer.TokenKind.EqualEqual or kind == Lexer.TokenKind.BangEqual or kind == Lexer.TokenKind.LessThan or kind == Lexer.TokenKind.LessEqual or kind == Lexer.TokenKind.GreaterThan or kind == Lexer.TokenKind.GreaterEqual) {
            try self.skipToken();

            const rhs = try self.starpend();
            errdefer rhs.destroy(self.allocator);

            const op = switch (kind) {
                Lexer.TokenKind.EqualEqual => AST.Operator.Equal,
                Lexer.TokenKind.BangEqual => AST.Operator.NotEqual,
                Lexer.TokenKind.LessEqual => AST.Operator.LessEqual,
                Lexer.TokenKind.LessThan => AST.Operator.LessThan,
                Lexer.TokenKind.GreaterEqual => AST.Operator.GreaterEqual,
                Lexer.TokenKind.GreaterThan => AST.Operator.GreaterThan,
                else => unreachable,
            };

            lhs = try AST.Expression.create(self.allocator, AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = op } }, Errors.Position{ .start = lhs.position.start, .end = rhs.position.end });
        }

        return lhs;
    }

    pub fn starpend(self: *Parser) Errors.ParserErrors!*AST.Expression {
        var lhs = try self.additive();
        errdefer lhs.destroy(self.allocator);

        var kind = self.currentTokenKind();

        while (kind == Lexer.TokenKind.GreaterBang or kind == Lexer.TokenKind.GreaterGreater or kind == Lexer.TokenKind.LessBang or kind == Lexer.TokenKind.LessLess) {
            try self.skipToken();

            const rhs = try self.additive();
            errdefer rhs.destroy(self.allocator);

            const op = switch (kind) {
                Lexer.TokenKind.GreaterBang => AST.Operator.PrependUpdate,
                Lexer.TokenKind.GreaterGreater => AST.Operator.Prepend,
                Lexer.TokenKind.LessBang => AST.Operator.AppendUpdate,
                Lexer.TokenKind.LessLess => AST.Operator.Append,
                else => unreachable,
            };

            lhs = try AST.Expression.create(self.allocator, AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = op } }, Errors.Position{ .start = lhs.position.start, .end = rhs.position.end });

            kind = self.currentTokenKind();
        }

        return lhs;
    }

    pub fn additive(self: *Parser) Errors.ParserErrors!*AST.Expression {
        var lhs = try self.multiplicative();
        errdefer lhs.destroy(self.allocator);

        while (true) {
            const kind = self.currentTokenKind();

            if (kind == Lexer.TokenKind.Plus or kind == Lexer.TokenKind.Minus) {
                try self.skipToken();

                const rhs = try self.multiplicative();
                errdefer rhs.destroy(self.allocator);

                const op = if (kind == Lexer.TokenKind.Plus) AST.Operator.Plus else AST.Operator.Minus;

                lhs = try AST.Expression.create(self.allocator, AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = op } }, Errors.Position{ .start = lhs.position.start, .end = rhs.position.end });
            } else {
                break;
            }
        }

        return lhs;
    }

    pub fn multiplicative(self: *Parser) Errors.ParserErrors!*AST.Expression {
        var lhs = try self.power();
        errdefer lhs.destroy(self.allocator);

        while (true) {
            const kind = self.currentTokenKind();

            if (kind == Lexer.TokenKind.Star or kind == Lexer.TokenKind.Slash or kind == Lexer.TokenKind.Percentage) {
                try self.skipToken();

                const rhs = try self.power();
                errdefer rhs.destroy(self.allocator);

                const op = if (kind == Lexer.TokenKind.Star) AST.Operator.Times else if (kind == Lexer.TokenKind.Slash) AST.Operator.Divide else AST.Operator.Modulo;

                lhs = try AST.Expression.create(self.allocator, AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = op } }, Errors.Position{ .start = lhs.position.start, .end = rhs.position.end });
            } else {
                break;
            }
        }

        return lhs;
    }

    fn power(self: *Parser) Errors.ParserErrors!*AST.Expression {
        var lhs = try self.nullDefault();
        errdefer lhs.destroy(self.allocator);

        while (self.currentTokenKind() == Lexer.TokenKind.StarStar) {
            try self.skipToken();

            const rhs = try self.nullDefault();
            errdefer rhs.destroy(self.allocator);

            lhs = try AST.Expression.create(self.allocator, AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = AST.Operator.Power } }, Errors.Position{ .start = lhs.position.start, .end = rhs.position.end });
        }

        return lhs;
    }

    fn nullDefault(self: *Parser) Errors.ParserErrors!*AST.Expression {
        var lhs = try self.qualifier();
        errdefer lhs.destroy(self.allocator);

        const kind = self.currentTokenKind();

        if (kind == Lexer.TokenKind.Hook) {
            try self.skipToken();

            const rhs = try self.qualifier();
            errdefer rhs.destroy(self.allocator);

            return try AST.Expression.create(self.allocator, AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = AST.Operator.Hook } }, Errors.Position{ .start = lhs.position.start, .end = rhs.position.end });
        } else {
            return lhs;
        }
    }

    pub fn qualifier(self: *Parser) Errors.ParserErrors!*AST.Expression {
        var result = try self.factor();
        errdefer result.destroy(self.allocator);

        while (true) {
            const kind = self.currentTokenKind();

            if (kind == Lexer.TokenKind.LParen) {
                const lparen = try self.nextToken();

                var args = std.ArrayList(*AST.Expression).init(self.allocator);
                defer args.deinit();
                errdefer {
                    for (args.items) |item| {
                        item.destroy(self.allocator);
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

                result = try AST.Expression.create(self.allocator, AST.ExpressionKind{ .call = AST.CallExpression{ .callee = result, .args = try args.toOwnedSlice() } }, Errors.Position{ .start = lparen.start, .end = rparen.end });
            } else if (kind == Lexer.TokenKind.LBracket) {
                const lbracket = try self.nextToken();

                if (self.currentTokenKind() == Lexer.TokenKind.Colon) {
                    try self.skipToken();
                    if (self.currentTokenKind() == Lexer.TokenKind.RBracket) {
                        const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                        result = try AST.Expression.create(self.allocator, AST.ExpressionKind{ .indexRange = AST.IndexRangeExpression{ .expr = result, .start = null, .end = null } }, Errors.Position{ .start = lbracket.start, .end = rbracket.end });
                    } else {
                        const end = try self.expression();
                        errdefer end.destroy(self.allocator);
                        const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                        result = try AST.Expression.create(
                            self.allocator,
                            AST.ExpressionKind{ .indexRange = AST.IndexRangeExpression{ .expr = result, .start = null, .end = end } },
                            Errors.Position{ .start = lbracket.start, .end = rbracket.end },
                        );
                    }
                } else {
                    const index = try self.expression();
                    errdefer index.destroy(self.allocator);

                    if (self.currentTokenKind() == Lexer.TokenKind.Colon) {
                        try self.skipToken();
                        if (self.currentTokenKind() == Lexer.TokenKind.RBracket) {
                            const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                            result = try AST.Expression.create(
                                self.allocator,
                                AST.ExpressionKind{ .indexRange = AST.IndexRangeExpression{ .expr = result, .start = index, .end = null } },
                                Errors.Position{ .start = lbracket.start, .end = rbracket.end },
                            );
                        } else {
                            const end = try self.expression();
                            errdefer end.destroy(self.allocator);
                            const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                            result = try AST.Expression.create(
                                self.allocator,
                                AST.ExpressionKind{ .indexRange = AST.IndexRangeExpression{ .expr = result, .start = index, .end = end } },
                                Errors.Position{ .start = lbracket.start, .end = rbracket.end },
                            );
                        }
                    } else {
                        const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                        result = try AST.Expression.create(
                            self.allocator,
                            AST.ExpressionKind{ .indexValue = AST.IndexValueExpression{ .expr = result, .index = index } },
                            Errors.Position{ .start = lbracket.start, .end = rbracket.end },
                        );
                    }
                }
            } else if (kind == Lexer.TokenKind.Dot) {
                try self.skipToken();

                const field = try self.matchToken(Lexer.TokenKind.Identifier);

                result = try AST.Expression.create(
                    self.allocator,
                    AST.ExpressionKind{ .dot = AST.DotExpression{ .record = result, .field = try self.stringPool.intern(self.lexer.lexeme(field)) } },
                    Errors.Position{ .start = result.position.start, .end = field.end },
                );
            } else {
                break;
            }
        }

        return result;
    }

    pub fn factor(self: *Parser) Errors.ParserErrors!*AST.Expression {
        switch (self.currentTokenKind()) {
            Lexer.TokenKind.LParen => {
                const lparen = try self.nextToken();

                if (self.currentTokenKind() == Lexer.TokenKind.RParen) {
                    const rparen = try self.nextToken();

                    return try AST.Expression.create(
                        self.allocator,
                        AST.ExpressionKind{ .literalVoid = void{} },
                        Errors.Position{ .start = lparen.start, .end = rparen.end },
                    );
                }

                const e = try self.expression();
                errdefer e.destroy(self.allocator);

                try self.matchSkipToken(Lexer.TokenKind.RParen);

                return e;
            },
            Lexer.TokenKind.LCurly => {
                const lcurly = try self.nextToken();

                if (self.currentTokenKind() == Lexer.TokenKind.RCurly or self.currentTokenKind() == Lexer.TokenKind.DotDotDot or (self.currentTokenKind() == Lexer.TokenKind.Identifier or self.currentTokenKind() == Lexer.TokenKind.LiteralString) and try self.peekNextToken() == Lexer.TokenKind.Colon) {
                    var es = std.ArrayList(AST.RecordEntry).init(self.allocator);
                    defer {
                        for (es.items) |item| {
                            switch (item) {
                                .value => {
                                    item.value.key.decRef();
                                    item.value.value.destroy(self.allocator);
                                },
                                .record => item.record.destroy(self.allocator),
                            }
                        }
                        es.deinit();
                    }

                    if (self.currentTokenKind() != Lexer.TokenKind.RCurly) {
                        try es.append(try self.recordEntry());

                        while (self.currentTokenKind() == Lexer.TokenKind.Comma) {
                            try self.skipToken();
                            try es.append(try self.recordEntry());
                        }
                    }

                    const rcurly = try self.matchToken(Lexer.TokenKind.RCurly);

                    return try AST.Expression.create(
                        self.allocator,
                        AST.ExpressionKind{ .literalRecord = try es.toOwnedSlice() },
                        Errors.Position{ .start = lcurly.start, .end = rcurly.end },
                    );
                } else {
                    var es = std.ArrayList(*AST.Expression).init(self.allocator);
                    defer {
                        for (es.items) |item| {
                            item.destroy(self.allocator);
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

                    return try AST.Expression.create(
                        self.allocator,
                        AST.ExpressionKind{ .exprs = try es.toOwnedSlice() },
                        Errors.Position{ .start = lcurly.start, .end = rcurly.end },
                    );
                }
            },
            Lexer.TokenKind.Identifier => {
                const token = try self.nextToken();
                const identifier = try self.stringPool.intern(self.lexer.lexeme(token));
                errdefer identifier.decRef();

                return try AST.Expression.create(
                    self.allocator,
                    AST.ExpressionKind{ .identifier = identifier },
                    token.position(),
                );
            },
            Lexer.TokenKind.LiteralBoolFalse => {
                const token = try self.nextToken();

                return try AST.Expression.create(
                    self.allocator,
                    AST.ExpressionKind{ .literalBool = false },
                    token.position(),
                );
            },
            Lexer.TokenKind.LiteralBoolTrue => {
                const token = try self.nextToken();

                return try AST.Expression.create(
                    self.allocator,
                    AST.ExpressionKind{ .literalBool = true },
                    token.position(),
                );
            },
            Lexer.TokenKind.LiteralChar => {
                const r = try self.parseLiteralChar(self.lexer.currentLexeme());
                const token = try self.nextToken();

                return try AST.Expression.create(
                    self.allocator,
                    AST.ExpressionKind{ .literalChar = r },
                    token.position(),
                );
            },
            Lexer.TokenKind.LiteralInt => {
                const literalInt = try self.parseLiteralInt(self.lexer.currentLexeme());
                const token = try self.nextToken();

                return try AST.Expression.create(
                    self.allocator,
                    AST.ExpressionKind{ .literalInt = literalInt },
                    token.position(),
                );
            },
            Lexer.TokenKind.LiteralFloat => {
                const literalFloat = try self.parseLiteralFloat(self.lexer.currentLexeme());
                const token = try self.nextToken();

                return try AST.Expression.create(
                    self.allocator,
                    AST.ExpressionKind{ .literalFloat = literalFloat },
                    token.position(),
                );
            },
            Lexer.TokenKind.LiteralString => {
                const token = try self.nextToken();

                const text = try self.parseLiteralString(self.lexer.lexeme(token));
                errdefer text.decRef();

                return try AST.Expression.create(
                    self.allocator,
                    AST.ExpressionKind{ .literalString = text },
                    token.position(),
                );
            },
            Lexer.TokenKind.LBracket => {
                const lbracket = try self.nextToken();

                var es = std.ArrayList(AST.LiteralSequenceValue).init(self.allocator);
                defer {
                    for (es.items) |item| {
                        switch (item) {
                            AST.LiteralSequenceValue.value => item.value.destroy(self.allocator),
                            AST.LiteralSequenceValue.sequence => item.sequence.destroy(self.allocator),
                        }
                    }
                    es.deinit();
                }

                if (self.currentTokenKind() != Lexer.TokenKind.RBracket) {
                    try es.append(try self.literalListItem());
                    while (self.currentTokenKind() == Lexer.TokenKind.Comma) {
                        try self.skipToken();
                        try es.append(try self.literalListItem());
                    }
                }

                const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                return try AST.Expression.create(
                    self.allocator,
                    AST.ExpressionKind{ .literalSequence = try es.toOwnedSlice() },
                    Errors.Position{ .start = lbracket.start, .end = rbracket.end },
                );
            },
            Lexer.TokenKind.Fn => {
                const fnToken = try self.nextToken();

                return self.functionTail(fnToken.start);
            },
            Lexer.TokenKind.Bang => {
                const notToken = self.currentToken();
                try self.skipToken();
                const value = try self.qualifier();
                errdefer value.destroy(self.allocator);

                return try AST.Expression.create(
                    self.allocator,
                    AST.ExpressionKind{ .notOp = AST.NotOpExpression{ .value = value } },
                    Errors.Position{ .start = notToken.start, .end = value.position.end },
                );
            },
            else => {
                self.replaceErr(try Errors.parserError(self.allocator, self.lexer.name, Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end }, self.currentTokenLexeme(), &[_]Lexer.TokenKind{ Lexer.TokenKind.LBracket, Lexer.TokenKind.LCurly, Lexer.TokenKind.Identifier, Lexer.TokenKind.LParen, Lexer.TokenKind.LiteralBoolFalse, Lexer.TokenKind.LiteralBoolTrue, Lexer.TokenKind.LiteralChar, Lexer.TokenKind.LiteralFloat, Lexer.TokenKind.LiteralInt, Lexer.TokenKind.LiteralString, Lexer.TokenKind.Fn }));

                return error.SyntaxError;
            },
        }
    }

    fn parseLiteralChar(self: *Parser, lexeme: []const u8) !u8 {
        _ = self;
        if (lexeme.len == 3) {
            return lexeme[1];
        } else if (lexeme.len == 4) {
            return if (lexeme[2] == 'n') 10 else lexeme[2];
        } else {
            return std.fmt.parseInt(u8, lexeme[3 .. lexeme.len - 1], 10) catch 0;
        }
    }

    fn parseLiteralFloat(self: *Parser, lexeme: []const u8) !V.FloatType {
        return std.fmt.parseFloat(f64, lexeme) catch {
            const token = self.currentToken();
            self.replaceErr(try Errors.literalFloatOverflowError(self.allocator, self.lexer.name, token.position(), lexeme));
            return error.LiteralFloatError;
        };
    }

    fn parseLiteralInt(self: *Parser, lexeme: []const u8) !V.IntType {
        return std.fmt.parseInt(V.IntType, lexeme, 10) catch {
            const token = self.currentToken();
            self.replaceErr(try Errors.literalIntOverflowError(self.allocator, self.lexer.name, token.position(), lexeme));
            return error.LiteralIntError;
        };
    }

    fn parseLiteralString(self: *Parser, lexeme: []const u8) !*SP.String {
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
                    },
                    else => {},
                }
            } else {
                try buffer.append(c);
            }

            i += 1;
        }

        return try self.stringPool.internOwned(try buffer.toOwnedSlice());
    }

    fn literalListItem(self: *Parser) !AST.LiteralSequenceValue {
        if (self.currentTokenKind() == Lexer.TokenKind.DotDotDot) {
            try self.skipToken();
            const expr = try self.expression();
            return AST.LiteralSequenceValue{ .sequence = expr };
        } else {
            return AST.LiteralSequenceValue{ .value = try self.expression() };
        }
    }

    fn functionTail(self: *Parser, start: usize) !*AST.Expression {
        var restOfParams: ?*SP.String = null;
        errdefer {
            if (restOfParams != null) {
                restOfParams.?.decRef();
            }
        }
        var params = try self.parameters(&restOfParams);
        errdefer {
            for (params) |*param| {
                param.deinit(self.allocator);
            }
            self.allocator.free(params);
        }

        if (self.currentTokenKind() == Lexer.TokenKind.Equal) {
            try self.skipToken();
        }

        const body = try self.expression();
        errdefer body.destroy(self.allocator);

        return try AST.Expression.create(
            self.allocator,
            AST.ExpressionKind{ .literalFunction = AST.LiteralFunction{ .params = params, .restOfParams = restOfParams, .body = body } },
            Errors.Position{ .start = start, .end = body.position.end },
        );
    }

    fn parameters(self: *Parser, restOfParams: *?*SP.String) ![]AST.FunctionParam {
        var params = std.ArrayList(AST.FunctionParam).init(self.allocator);
        defer params.deinit();
        errdefer for (params.items) |*param| {
            param.deinit(self.allocator);
        };

        try self.matchSkipToken(Lexer.TokenKind.LParen);

        if (self.currentTokenKind() == Lexer.TokenKind.DotDotDot) {
            try self.skipToken();
            const nameToken = try self.matchToken(Lexer.TokenKind.Identifier);
            restOfParams.* = try self.stringPool.intern(self.lexer.lexeme(nameToken));
        } else if (self.currentTokenKind() != Lexer.TokenKind.RParen) {
            try params.append(try self.parameter());
            while (self.currentTokenKind() == Lexer.TokenKind.Comma) {
                try self.skipToken();

                if (self.currentTokenKind() == Lexer.TokenKind.DotDotDot) {
                    try self.skipToken();
                    const nameToken = try self.matchToken(Lexer.TokenKind.Identifier);
                    restOfParams.* = try self.stringPool.intern(self.lexer.lexeme(nameToken));
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
        const name = try self.stringPool.intern(self.lexer.lexeme(nameToken));
        errdefer name.decRef();

        if (self.currentTokenKind() == Lexer.TokenKind.Equal) {
            try self.skipToken();

            const default = try self.expression();
            return AST.FunctionParam{ .name = name, .default = default };
        } else {
            return AST.FunctionParam{ .name = name, .default = null };
        }
    }

    fn recordEntry(self: *Parser) !AST.RecordEntry {
        if (self.currentTokenKind() == Lexer.TokenKind.DotDotDot) {
            try self.skipToken();
            const e = try self.expression();
            return AST.RecordEntry{ .record = e };
        } else {
            const key = switch (self.currentTokenKind()) {
                Lexer.TokenKind.Identifier => try self.stringPool.intern(self.lexer.lexeme(try self.matchToken(Lexer.TokenKind.Identifier))),
                Lexer.TokenKind.LiteralString => try self.parseLiteralString(self.lexer.lexeme(try self.matchToken(Lexer.TokenKind.LiteralString))),
                else => {
                    self.replaceErr(try Errors.parserError(self.allocator, self.lexer.name, Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end }, self.currentTokenLexeme(), &[_]Lexer.TokenKind{ Lexer.TokenKind.Identifier, Lexer.TokenKind.LiteralString }));

                    return error.SyntaxError;
                },
            };
            errdefer key.decRef();

            try self.matchSkipToken(Lexer.TokenKind.Colon);
            const value = try self.expression();

            return AST.RecordEntry{ .value = .{ .key = key, .value = value } };
        }
    }

    fn pattern(self: *Parser) Errors.ParserErrors!*AST.Pattern {
        switch (self.currentTokenKind()) {
            Lexer.TokenKind.LParen => {
                const lparen = try self.nextToken();

                if (self.currentTokenKind() == Lexer.TokenKind.RParen) {
                    const rparen = try self.nextToken();

                    return try AST.Pattern.create(
                        self.allocator,
                        AST.PatternKind{ .unit = void{} },
                        Errors.Position{ .start = lparen.start, .end = rparen.end },
                    );
                }

                const e = try self.pattern();
                errdefer e.destroy(self.allocator);

                try self.matchSkipToken(Lexer.TokenKind.RParen);

                return e;
            },
            Lexer.TokenKind.Identifier => {
                const token = try self.nextToken();
                const identifier = try self.stringPool.intern(self.lexer.lexeme(token));
                errdefer identifier.decRef();

                return try AST.Pattern.create(self.allocator, AST.PatternKind{ .identifier = identifier }, token.position());
            },
            Lexer.TokenKind.LiteralBoolFalse => {
                const token = try self.nextToken();

                return try AST.Pattern.create(self.allocator, AST.PatternKind{ .literalBool = false }, token.position());
            },
            Lexer.TokenKind.LiteralBoolTrue => {
                const token = try self.nextToken();

                return try AST.Pattern.create(self.allocator, AST.PatternKind{ .literalBool = true }, token.position());
            },
            Lexer.TokenKind.LiteralChar => {
                const literalChar = try self.parseLiteralChar(self.lexer.currentLexeme());
                const token = try self.nextToken();

                return try AST.Pattern.create(self.allocator, AST.PatternKind{ .literalChar = literalChar }, token.position());
            },
            Lexer.TokenKind.LiteralFloat => {
                const literalFloat = try self.parseLiteralFloat(self.lexer.currentLexeme());
                const token = try self.nextToken();

                return try AST.Pattern.create(self.allocator, AST.PatternKind{ .literalFloat = literalFloat }, token.position());
            },
            Lexer.TokenKind.LiteralInt => {
                const literalInt = try self.parseLiteralInt(self.lexer.currentLexeme());
                const token = try self.nextToken();

                return try AST.Pattern.create(self.allocator, AST.PatternKind{ .literalInt = literalInt }, token.position());
            },
            Lexer.TokenKind.LiteralString => {
                const literalString = try self.parseLiteralString(self.lexer.currentLexeme());
                errdefer literalString.decRef();
                const token = try self.nextToken();

                return try AST.Pattern.create(self.allocator, AST.PatternKind{ .literalString = literalString }, token.position());
            },
            Lexer.TokenKind.LBracket => {
                const lbracket = try self.nextToken();

                var es = std.ArrayList(*AST.Pattern).init(self.allocator);
                defer {
                    for (es.items) |item| {
                        item.destroy(self.allocator);
                    }
                    es.deinit();
                }

                var restOfPatterns: ?*SP.String = null;
                errdefer {
                    if (restOfPatterns != null) {
                        restOfPatterns.?.decRef();
                    }
                }

                var id: ?*SP.String = null;
                errdefer {
                    if (id != null) {
                        id.?.decRef();
                    }
                }

                if (self.currentTokenKind() != Lexer.TokenKind.RBracket) {
                    try es.append(try self.pattern());
                    while (restOfPatterns == null and self.currentTokenKind() == Lexer.TokenKind.Comma) {
                        try self.skipToken();

                        if (self.currentTokenKind() == Lexer.TokenKind.DotDotDot) {
                            try self.skipToken();
                            if (self.currentTokenKind() == Lexer.TokenKind.Identifier) {
                                restOfPatterns = try self.stringPool.intern(self.lexer.currentLexeme());

                                try self.skipToken();
                            } else {
                                restOfPatterns = try self.stringPool.intern("_");
                            }
                        } else {
                            try es.append(try self.pattern());
                        }
                    }
                }

                const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                if (self.currentTokenKind() == Lexer.TokenKind.At) {
                    try self.skipToken();
                    id = try self.stringPool.intern(self.lexer.currentLexeme());
                    try self.matchSkipToken(Lexer.TokenKind.Identifier);
                }

                return try AST.Pattern.create(
                    self.allocator,
                    AST.PatternKind{ .sequence = AST.SequencePattern{ .patterns = try es.toOwnedSlice(), .restOfPatterns = restOfPatterns, .id = id } },
                    Errors.Position{ .start = lbracket.start, .end = rbracket.end },
                );
            },
            Lexer.TokenKind.LCurly => {
                const lcurly = try self.nextToken();

                var es = std.ArrayList(AST.RecordPatternEntry).init(self.allocator);
                defer {
                    for (es.items) |*item| {
                        item.deinit(self.allocator);
                    }
                    es.deinit();
                }

                if (self.currentTokenKind() == Lexer.TokenKind.Identifier or self.currentTokenKind() == Lexer.TokenKind.LiteralString) {
                    try es.append(try self.recordPatternEntry());
                    while (self.currentTokenKind() == Lexer.TokenKind.Comma) {
                        try self.skipToken();
                        try es.append(try self.recordPatternEntry());
                    }
                }
                const rcurly = try self.matchToken(Lexer.TokenKind.RCurly);

                var id: ?*SP.String = null;
                errdefer if (id != null) id.?.decRef();

                if (self.currentTokenKind() == Lexer.TokenKind.At) {
                    try self.skipToken();
                    const alias = try self.matchToken(Lexer.TokenKind.Identifier);
                    id = try self.stringPool.intern(self.lexer.lexeme(alias));
                }

                return try AST.Pattern.create(
                    self.allocator,
                    AST.PatternKind{ .record = AST.RecordPattern{ .entries = try es.toOwnedSlice(), .id = id } },
                    Errors.Position{ .start = lcurly.start, .end = rcurly.end },
                );
            },
            else => {
                self.replaceErr(try Errors.parserError(self.allocator, self.lexer.name, Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end }, self.currentTokenLexeme(), &[_]Lexer.TokenKind{ Lexer.TokenKind.LBracket, Lexer.TokenKind.LCurly, Lexer.TokenKind.Identifier, Lexer.TokenKind.LParen, Lexer.TokenKind.LiteralBoolFalse, Lexer.TokenKind.LiteralBoolTrue, Lexer.TokenKind.LiteralChar, Lexer.TokenKind.LiteralFloat, Lexer.TokenKind.LiteralInt, Lexer.TokenKind.LiteralString, Lexer.TokenKind.Fn }));

                return error.SyntaxError;
            },
        }
    }

    fn recordPatternEntry(self: *Parser) !AST.RecordPatternEntry {
        const key = switch (self.currentTokenKind()) {
            Lexer.TokenKind.Identifier => try self.stringPool.intern(self.lexer.lexeme(try self.matchToken(Lexer.TokenKind.Identifier))),
            Lexer.TokenKind.LiteralString => try self.parseLiteralString(self.lexer.lexeme(try self.matchToken(Lexer.TokenKind.LiteralString))),
            else => {
                self.replaceErr(try Errors.parserError(self.allocator, self.lexer.name, Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end }, self.currentTokenLexeme(), &[_]Lexer.TokenKind{ Lexer.TokenKind.Identifier, Lexer.TokenKind.LiteralString }));

                return error.SyntaxError;
            },
        };

        errdefer key.decRef();

        var pttrn: ?*AST.Pattern = null;
        errdefer if (pttrn != null) pttrn.?.destroy(self.allocator);

        var id: ?*SP.String = null;
        errdefer if (id != null) id.?.decRef();

        if (self.currentTokenKind() == Lexer.TokenKind.Colon) {
            try self.skipToken();
            pttrn = try self.pattern();
        }

        if (self.currentTokenKind() == Lexer.TokenKind.At) {
            try self.skipToken();
            id = try self.stringPool.intern(self.lexer.currentLexeme());
            try self.matchSkipToken(Lexer.TokenKind.Identifier);
        }

        return AST.RecordPatternEntry{ .key = key, .pattern = pttrn, .id = id };
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

    fn nextToken(self: *Parser) Errors.ParserErrors!Lexer.Token {
        const token = self.lexer.current;

        try self.lexer.next();

        return token;
    }

    fn peekNextToken(self: *Parser) !Lexer.TokenKind {
        return try self.lexer.peekNext();
    }

    fn skipToken(self: *Parser) Errors.ParserErrors!void {
        try self.lexer.next();
    }

    fn matchToken(self: *Parser, kind: Lexer.TokenKind) Errors.ParserErrors!Lexer.Token {
        const token = self.currentToken();

        if (token.kind != kind) {
            var expected = [_]Lexer.TokenKind{Lexer.TokenKind.LBracket};
            expected[0] = kind;

            self.replaceErr(try Errors.parserError(self.allocator, self.lexer.name, token.position(), self.currentTokenLexeme(), &expected));

            return error.SyntaxError;
        }

        return self.nextToken();
    }

    fn matchSkipToken(self: *Parser, kind: Lexer.TokenKind) Errors.ParserErrors!void {
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
