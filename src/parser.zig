const std = @import("std");

const AST = @import("./ast.zig");
const Errors = @import("./errors.zig");
const Machine = @import("./machine.zig");
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

    pub fn module(self: *Parser) Errors.err!*AST.Expression {
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

            const nextNextToken = try self.peekNextToken();
            if (self.currentTokenKind() == Lexer.TokenKind.Identifier and (nextNextToken == Lexer.TokenKind.Equal or nextNextToken == Lexer.TokenKind.LParen)) {
                const nameToken = try self.matchToken(Lexer.TokenKind.Identifier);
                const name = self.lexer.lexeme(nameToken);
                errdefer self.allocator.free(name);

                if (self.currentTokenKind() == Lexer.TokenKind.LParen) {
                    var literalFn = try self.functionTail(letToken.start);
                    errdefer literalFn.destroy(self.allocator);

                    const v = try self.allocator.create(AST.Expression);

                    v.* = AST.Expression{ .kind = AST.ExpressionKind{ .idDeclaration = AST.IdDeclarationExpression{ .name = try self.stringPool.intern(name), .value = literalFn } }, .position = Errors.Position{ .start = nameToken.start, .end = literalFn.position.end } };

                    return v;
                } else {
                    try self.matchSkipToken(Lexer.TokenKind.Equal);

                    const value = try self.expression();
                    errdefer value.destroy(self.allocator);

                    const v = try self.allocator.create(AST.Expression);
                    v.* = AST.Expression{ .kind = AST.ExpressionKind{ .idDeclaration = AST.IdDeclarationExpression{ .name = try self.stringPool.intern(name), .value = value } }, .position = Errors.Position{ .start = letToken.start, .end = value.position.end } };
                    return v;
                }
            } else {
                const pttrn = try self.pattern();
                errdefer pttrn.destroy(self.allocator);

                try self.matchSkipToken(Lexer.TokenKind.Equal);

                const value = try self.expression();
                errdefer value.destroy(self.allocator);

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .patternDeclaration = AST.PatternDeclarationExpression{ .pattern = pttrn, .value = value } }, .position = Errors.Position{ .start = letToken.start, .end = value.position.end } };
                return v;
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

            const v = try self.allocator.create(AST.Expression);
            v.* = AST.Expression{ .kind = AST.ExpressionKind{ .ifte = try couples.toOwnedSlice() }, .position = Errors.Position{ .start = ifToken.start, .end = self.lexer.current.end } };
            return v;
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
            const v = try self.allocator.create(AST.Expression);
            v.* = AST.Expression{ .kind = AST.ExpressionKind{ .match = AST.MatchExpression{ .value = value, .cases = try cases.toOwnedSlice(), .elseCase = null } }, .position = Errors.Position{ .start = matchTkn.start, .end = endPosition } };
            return v;
        } else if (self.currentTokenKind() == Lexer.TokenKind.Raise) {
            const raiseToken = try self.nextToken();
            const expr = try self.expression();
            errdefer expr.destroy(self.allocator);

            const v = try self.allocator.create(AST.Expression);
            v.* = AST.Expression{ .kind = AST.ExpressionKind{ .raise = AST.RaiseExpression{ .expr = expr } }, .position = Errors.Position{ .start = raiseToken.start, .end = expr.position.end } };
            return v;
        } else if (self.currentTokenKind() == Lexer.TokenKind.While) {
            const whileToken = try self.nextToken();

            const condition = try self.expression();
            errdefer condition.destroy(self.allocator);

            try self.matchSkipToken(Lexer.TokenKind.MinusGreater);

            const body = try self.expression();
            errdefer body.destroy(self.allocator);

            const v = try self.allocator.create(AST.Expression);
            v.* = AST.Expression{ .kind = AST.ExpressionKind{ .whilee = AST.WhileExpression{ .condition = condition, .body = body } }, .position = Errors.Position{ .start = whileToken.start, .end = body.position.end } };
            return v;
        } else {
            var lhs = try self.catchExpr();
            errdefer lhs.destroy(self.allocator);

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

    fn catchExpr(self: *Parser) Errors.err!*AST.Expression {
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
            const v = try self.allocator.create(AST.Expression);
            v.* = AST.Expression{ .kind = AST.ExpressionKind{ .catche = AST.CatchExpression{ .value = expr, .cases = try cases.toOwnedSlice() } }, .position = Errors.Position{ .start = expr.position.start, .end = endPosition } };
            return v;
        } else {
            return expr;
        }
    }

    fn pipeExpr(self: *Parser) Errors.err!*AST.Expression {
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
                    self.replaceErr(try Errors.functionValueExpectedError(self.allocator, self.lexer.name, rhs.position, V.ValueKind.UnitKind));
                    return error.InterpreterError;
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
                    self.replaceErr(try Errors.functionValueExpectedError(self.allocator, self.lexer.name, lhs.position, V.ValueKind.UnitKind));
                    return error.InterpreterError;
                }
            } else {
                break;
            }
        }

        return lhs;
    }

    fn matchCase(self: *Parser) Errors.err!AST.MatchCase {
        const pttrn = try self.pattern();
        errdefer pttrn.destroy(self.allocator);

        try self.matchSkipToken(Lexer.TokenKind.MinusGreater);

        const body = try self.expression();

        return AST.MatchCase{ .pattern = pttrn, .body = body };
    }

    fn orExpr(self: *Parser) Errors.err!*AST.Expression {
        var lhs = try self.andExpr();
        errdefer lhs.destroy(self.allocator);

        while (self.currentTokenKind() == Lexer.TokenKind.BarBar) {
            try self.skipToken();

            const rhs = try self.andExpr();
            errdefer rhs.destroy(self.allocator);

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
        errdefer lhs.destroy(self.allocator);

        while (self.currentTokenKind() == Lexer.TokenKind.AmpersandAmpersand) {
            try self.skipToken();

            const rhs = try self.equality();
            errdefer rhs.destroy(self.allocator);

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
        var lhs = try self.starpend();
        errdefer lhs.destroy(self.allocator);

        const kind = self.currentTokenKind();

        if (kind == Lexer.TokenKind.EqualEqual or kind == Lexer.TokenKind.BangEqual or kind == Lexer.TokenKind.LessThan or kind == Lexer.TokenKind.LessEqual or kind == Lexer.TokenKind.GreaterThan or kind == Lexer.TokenKind.GreaterEqual) {
            try self.skipToken();

            const rhs = try self.starpend();
            errdefer rhs.destroy(self.allocator);

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

    pub fn starpend(self: *Parser) Errors.err!*AST.Expression {
        var lhs = try self.additive();
        errdefer lhs.destroy(self.allocator);

        var kind = self.currentTokenKind();

        while (kind == Lexer.TokenKind.GreaterBang or kind == Lexer.TokenKind.GreaterGreater or kind == Lexer.TokenKind.LessBang or kind == Lexer.TokenKind.LessLess) {
            try self.skipToken();

            const rhs = try self.additive();
            errdefer rhs.destroy(self.allocator);

            const v = try self.allocator.create(AST.Expression);
            const op = switch (kind) {
                Lexer.TokenKind.GreaterBang => AST.Operator.PrependUpdate,
                Lexer.TokenKind.GreaterGreater => AST.Operator.Prepend,
                Lexer.TokenKind.LessBang => AST.Operator.AppendUpdate,
                Lexer.TokenKind.LessLess => AST.Operator.Append,
                else => unreachable,
            };

            v.* = AST.Expression{
                .kind = AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = op } },
                .position = Errors.Position{ .start = lhs.position.start, .end = rhs.position.end },
            };
            lhs = v;

            kind = self.currentTokenKind();
        }

        return lhs;
    }

    pub fn additive(self: *Parser) Errors.err!*AST.Expression {
        var lhs = try self.multiplicative();
        errdefer lhs.destroy(self.allocator);

        while (true) {
            const kind = self.currentTokenKind();

            if (kind == Lexer.TokenKind.Plus or kind == Lexer.TokenKind.Minus) {
                try self.skipToken();

                const rhs = try self.multiplicative();
                errdefer rhs.destroy(self.allocator);

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
        var lhs = try self.nullDefault();
        errdefer lhs.destroy(self.allocator);

        while (true) {
            const kind = self.currentTokenKind();

            if (kind == Lexer.TokenKind.Star or kind == Lexer.TokenKind.Slash or kind == Lexer.TokenKind.Percentage) {
                try self.skipToken();

                const rhs = try self.nullDefault();
                errdefer rhs.destroy(self.allocator);

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

    fn nullDefault(self: *Parser) Errors.err!*AST.Expression {
        var lhs = try self.qualifier();
        errdefer lhs.destroy(self.allocator);

        const kind = self.currentTokenKind();

        if (kind == Lexer.TokenKind.Hook) {
            try self.skipToken();

            const rhs = try self.qualifier();
            errdefer rhs.destroy(self.allocator);

            const v = try self.allocator.create(AST.Expression);
            v.* = AST.Expression{
                .kind = AST.ExpressionKind{ .binaryOp = AST.BinaryOpExpression{ .left = lhs, .right = rhs, .op = AST.Operator.Hook } },
                .position = Errors.Position{ .start = lhs.position.start, .end = rhs.position.end },
            };

            return v;
        } else {
            return lhs;
        }
    }

    pub fn qualifier(self: *Parser) Errors.err!*AST.Expression {
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
                        errdefer end.destroy(self.allocator);
                        const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                        const v = try self.allocator.create(AST.Expression);
                        v.* = AST.Expression{ .kind = AST.ExpressionKind{ .indexRange = AST.IndexRangeExpression{ .expr = result, .start = null, .end = end } }, .position = Errors.Position{ .start = lbracket.start, .end = rbracket.end } };
                        result = v;
                    }
                } else {
                    const index = try self.expression();
                    errdefer index.destroy(self.allocator);

                    if (self.currentTokenKind() == Lexer.TokenKind.Colon) {
                        try self.skipToken();
                        if (self.currentTokenKind() == Lexer.TokenKind.RBracket) {
                            const rbracket = try self.matchToken(Lexer.TokenKind.RBracket);

                            const v = try self.allocator.create(AST.Expression);
                            v.* = AST.Expression{ .kind = AST.ExpressionKind{ .indexRange = AST.IndexRangeExpression{ .expr = result, .start = index, .end = null } }, .position = Errors.Position{ .start = lbracket.start, .end = rbracket.end } };
                            result = v;
                        } else {
                            const end = try self.expression();
                            errdefer end.destroy(self.allocator);
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
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .dot = AST.DotExpression{ .record = result, .field = try self.stringPool.intern(self.lexer.lexeme(field)) } }, .position = Errors.Position{ .start = result.position.start, .end = field.end } };
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
                errdefer e.destroy(self.allocator);

                try self.matchSkipToken(Lexer.TokenKind.RParen);

                return e;
            },
            Lexer.TokenKind.LCurly => {
                const lcurly = try self.nextToken();

                if (self.currentTokenKind() == Lexer.TokenKind.RCurly or self.currentTokenKind() == Lexer.TokenKind.DotDotDot or self.currentTokenKind() == Lexer.TokenKind.Identifier and try self.peekNextToken() == Lexer.TokenKind.Colon) {
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

                    const v = try self.allocator.create(AST.Expression);
                    v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalRecord = try es.toOwnedSlice() }, .position = Errors.Position{ .start = lcurly.start, .end = rcurly.end } };
                    return v;
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

                    const v = try self.allocator.create(AST.Expression);
                    v.* = AST.Expression{ .kind = AST.ExpressionKind{ .exprs = try es.toOwnedSlice() }, .position = Errors.Position{ .start = lcurly.start, .end = rcurly.end } };
                    return v;
                }
            },
            Lexer.TokenKind.Identifier => {
                const lexeme = self.lexer.currentLexeme();

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .identifier = try self.stringPool.intern(lexeme) }, .position = Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end } };
                errdefer v.destroy(self.allocator);

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
                const r = try self.parseLiteralChar(self.lexer.currentLexeme());

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalChar = r }, .position = Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end } };

                try self.skipToken();

                return v;
            },
            Lexer.TokenKind.LiteralInt => {
                const literalInt = try self.parseLiteralInt(self.lexer.currentLexeme());

                const v = try self.allocator.create(AST.Expression);
                errdefer v.destroy(self.allocator);

                const token = try self.nextToken();
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalInt = literalInt }, .position = Errors.Position{ .start = token.start, .end = token.end } };

                return v;
            },
            Lexer.TokenKind.LiteralFloat => {
                const literalFloat = try self.parseLiteralFloat(self.lexer.currentLexeme());

                const v = try self.allocator.create(AST.Expression);
                errdefer v.destroy(self.allocator);

                const token = try self.nextToken();
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalFloat = literalFloat }, .position = Errors.Position{ .start = token.start, .end = token.end } };

                return v;
            },
            Lexer.TokenKind.LiteralString => {
                const text = try self.parseLiteralString(self.lexer.currentLexeme());
                errdefer self.allocator.free(text);

                const token = try self.nextToken();

                const v = try self.allocator.create(AST.Expression);
                errdefer v.destroy(self.allocator);

                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalString = text }, .position = Errors.Position{ .start = token.start, .end = token.end } };

                return v;
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

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .literalSequence = try es.toOwnedSlice() }, .position = Errors.Position{ .start = lbracket.start, .end = rbracket.end } };
                return v;
            },
            Lexer.TokenKind.Fn => {
                const fnToken = try self.nextToken();

                return self.functionTail(fnToken.start);
            },
            Lexer.TokenKind.Bang => {
                try self.skipToken();
                const value = try self.qualifier();
                errdefer value.destroy(self.allocator);

                const v = try self.allocator.create(AST.Expression);
                v.* = AST.Expression{ .kind = AST.ExpressionKind{ .notOp = AST.NotOpExpression{ .value = value } }, .position = Errors.Position{ .start = self.currentToken().start, .end = value.position.end } };
                return v;
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

                    self.replaceErr(try Errors.parserError(self.allocator, self.lexer.name, Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end }, self.currentTokenLexeme(), expected));
                }

                return error.InterpreterError;
            },
        }
    }

    fn parseLiteralChar(self: *Parser, lexeme: []const u8) !u8 {
        _ = self;
        if (lexeme.len == 3) {
            return lexeme[1];
        } else if (lexeme.len == 4) {
            if (lexeme[2] == 'n') {
                return 10;
            } else {
                return lexeme[2];
            }
        } else {
            return std.fmt.parseInt(u8, lexeme[3 .. lexeme.len - 1], 10) catch 0;
        }
    }

    fn parseLiteralFloat(self: *Parser, lexeme: []const u8) !V.FloatType {
        return std.fmt.parseFloat(f64, lexeme) catch {
            const token = self.currentToken();
            self.replaceErr(try Errors.literalFloatOverflowError(self.allocator, self.lexer.name, Errors.Position{ .start = token.start, .end = token.end }, lexeme));
            return error.InterpreterError;
        };
    }

    fn parseLiteralInt(self: *Parser, lexeme: []const u8) !V.IntType {
        return std.fmt.parseInt(V.IntType, lexeme, 10) catch {
            const token = self.currentToken();
            self.replaceErr(try Errors.literalIntOverflowError(self.allocator, self.lexer.name, Errors.Position{ .start = token.start, .end = token.end }, lexeme));
            return error.InterpreterError;
        };
    }

    fn parseLiteralString(self: *Parser, lexeme: []const u8) ![]u8 {
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

        return try buffer.toOwnedSlice();
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

        if (self.currentTokenKind() == Lexer.TokenKind.Equal) {
            try self.skipToken();
        }

        const body = try self.expression();
        errdefer body.destroy(self.allocator);

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

    fn recordEntry(self: *Parser) !AST.RecordEntry {
        if (self.currentTokenKind() == Lexer.TokenKind.DotDotDot) {
            try self.skipToken();
            const e = try self.expression();
            return AST.RecordEntry{ .record = e };
        } else {
            const key = try self.matchToken(Lexer.TokenKind.Identifier);
            try self.matchSkipToken(Lexer.TokenKind.Colon);
            const value = try self.expression();

            return AST.RecordEntry{ .value = .{ .key = try self.stringPool.intern(self.lexer.lexeme(key)), .value = value } };
        }
    }

    fn pattern(self: *Parser) Errors.err!*AST.Pattern {
        switch (self.currentTokenKind()) {
            Lexer.TokenKind.LParen => {
                const lparen = try self.nextToken();

                if (self.currentTokenKind() == Lexer.TokenKind.RParen) {
                    const rparen = try self.nextToken();

                    const v = try self.allocator.create(AST.Pattern);
                    v.* = AST.Pattern{ .kind = AST.PatternKind{ .void = void{} }, .position = Errors.Position{ .start = lparen.start, .end = rparen.end } };
                    return v;
                }

                const e = try self.pattern();
                errdefer e.destroy(self.allocator);

                try self.matchSkipToken(Lexer.TokenKind.RParen);

                return e;
            },
            Lexer.TokenKind.Identifier => {
                const lexeme = self.lexer.currentLexeme();

                const v = try self.allocator.create(AST.Pattern);
                v.* = AST.Pattern{ .kind = AST.PatternKind{ .identifier = try self.stringPool.intern(lexeme) }, .position = Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end } };
                errdefer v.destroy(self.allocator);

                try self.skipToken();

                return v;
            },
            Lexer.TokenKind.LiteralBoolFalse => {
                const token = try self.nextToken();

                const v = try self.allocator.create(AST.Pattern);
                v.* = AST.Pattern{ .kind = AST.PatternKind{ .literalBool = false }, .position = Errors.Position{ .start = token.start, .end = token.end } };
                return v;
            },
            Lexer.TokenKind.LiteralBoolTrue => {
                const token = try self.nextToken();

                const v = try self.allocator.create(AST.Pattern);
                v.* = AST.Pattern{ .kind = AST.PatternKind{ .literalBool = true }, .position = Errors.Position{ .start = token.start, .end = token.end } };
                return v;
            },
            Lexer.TokenKind.LiteralChar => {
                const literalChar = try self.parseLiteralChar(self.lexer.currentLexeme());
                const token = try self.nextToken();

                const v = try self.allocator.create(AST.Pattern);
                v.* = AST.Pattern{ .kind = AST.PatternKind{ .literalChar = literalChar }, .position = Errors.Position{ .start = token.start, .end = token.end } };
                return v;
            },
            Lexer.TokenKind.LiteralFloat => {
                const literalFloat = try self.parseLiteralFloat(self.lexer.currentLexeme());
                const token = try self.nextToken();

                const v = try self.allocator.create(AST.Pattern);
                v.* = AST.Pattern{ .kind = AST.PatternKind{ .literalFloat = literalFloat }, .position = Errors.Position{ .start = token.start, .end = token.end } };
                return v;
            },
            Lexer.TokenKind.LiteralInt => {
                const literalInt = try self.parseLiteralInt(self.lexer.currentLexeme());
                const token = try self.nextToken();

                const v = try self.allocator.create(AST.Pattern);
                v.* = AST.Pattern{ .kind = AST.PatternKind{ .literalInt = literalInt }, .position = Errors.Position{ .start = token.start, .end = token.end } };
                return v;
            },
            Lexer.TokenKind.LiteralString => {
                const literalString = try self.parseLiteralString(self.lexer.currentLexeme());
                const token = try self.nextToken();

                const v = try self.allocator.create(AST.Pattern);
                v.* = AST.Pattern{ .kind = AST.PatternKind{ .literalString = literalString }, .position = Errors.Position{ .start = token.start, .end = token.end } };
                return v;
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

                const v = try self.allocator.create(AST.Pattern);
                v.* = AST.Pattern{ .kind = AST.PatternKind{ .sequence = AST.SequencePattern{ .patterns = try es.toOwnedSlice(), .restOfPatterns = restOfPatterns, .id = id } }, .position = Errors.Position{ .start = lbracket.start, .end = rbracket.end } };
                return v;
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

                if (self.currentTokenKind() == Lexer.TokenKind.Identifier) {
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

                const v = try self.allocator.create(AST.Pattern);
                v.* = AST.Pattern{ .kind = AST.PatternKind{ .record = AST.RecordPattern{ .entries = try es.toOwnedSlice(), .id = id } }, .position = Errors.Position{ .start = lcurly.start, .end = rcurly.end } };
                return v;
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

                    self.replaceErr(try Errors.parserError(self.allocator, self.lexer.name, Errors.Position{ .start = self.currentToken().start, .end = self.currentToken().end }, self.currentTokenLexeme(), expected));
                }

                return error.InterpreterError;
            },
        }
    }

    fn recordPatternEntry(self: *Parser) !AST.RecordPatternEntry {
        const key = try self.matchToken(Lexer.TokenKind.Identifier);

        const keyValue = try self.stringPool.intern(self.lexer.lexeme(key));
        errdefer keyValue.decRef();

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

        return AST.RecordPatternEntry{ .key = keyValue, .pattern = pttrn, .id = id };
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
                self.replaceErr(try Errors.parserError(self.allocator, self.lexer.name, Errors.Position{ .start = token.start, .end = token.end }, self.currentTokenLexeme(), expected));
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
