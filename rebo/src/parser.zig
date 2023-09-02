const std = @import("std");

const Errors = @import("./errors.zig");
const Machine = @import("./machine.zig");
const Lexer = @import("./lexer.zig");

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: Lexer.Lexer,
    err: ?*Errors.Error,

    pub fn init(allocator: std.mem.Allocator, lexer: Lexer.Lexer) Parser {
        return Parser{
            .allocator = allocator,
            .lexer = lexer,
            .err = null,
        };
    }

    pub fn expr(self: *Parser) Errors.err!*Machine.Expr {
        switch (self.currentTokenKind()) {
            Lexer.TokenKind.LiteralBoolFalse => {
                const v = try self.allocator.create(Machine.Expr);
                v.* = Machine.Expr{ .literalBool = false };
                try self.nextToken();
                return v;
            },
            Lexer.TokenKind.LiteralBoolTrue => {
                const v = try self.allocator.create(Machine.Expr);
                v.* = Machine.Expr{ .literalBool = true };
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

    pub fn grabErr(self: *Parser) ?*Errors.Error {
        const err = self.err;
        self.err = null;

        return err;
    }
};

test "Invalid token throws an error" {}
