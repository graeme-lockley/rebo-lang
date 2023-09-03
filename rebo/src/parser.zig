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

    pub fn expr(self: *Parser) Errors.err!*AST.Expr {
        switch (self.currentTokenKind()) {
            Lexer.TokenKind.LiteralBoolFalse => {
                const v = try self.allocator.create(AST.Expr);
                errdefer AST.destroy(self.allocator, v);

                v.* = AST.Expr{ .literalBool = false };
                try self.nextToken();

                return v;
            },
            Lexer.TokenKind.LiteralBoolTrue => {
                const v = try self.allocator.create(AST.Expr);
                errdefer AST.destroy(self.allocator, v);

                v.* = AST.Expr{ .literalBool = true };
                try self.nextToken();

                return v;
            },
            Lexer.TokenKind.LiteralInt => {
                const lexeme = self.lexer.currentLexeme();

                const literalInt = std.fmt.parseInt(i32, lexeme, 10) catch {
                    const token = self.currentToken();
                    self.err = try Errors.literalIntOverflowError(self.allocator, Errors.Position{ .start = token.start, .end = token.end }, lexeme);
                    return error.InterpreterError;
                };

                const v = try self.allocator.create(AST.Expr);
                errdefer AST.destroy(self.allocator, v);

                v.* = AST.Expr{ .literalInt = literalInt };
                try self.nextToken();

                return v;
            },
            else => {
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

    fn nextToken(self: *Parser) Errors.err!void {
        try self.lexer.next();
    }

    pub fn eraseErr(self: *Parser) void {
        if (self.err != null) {
            self.err.deinit(self.allocator);
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
