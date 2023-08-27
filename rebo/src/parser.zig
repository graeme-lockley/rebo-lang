const std = @import("std");

const Eval = @import("./eval.zig");
const Lexer = @import("./lexer.zig");

pub const Parser = struct {
    allocator: *const std.mem.Allocator,
    lexer: Lexer.Lexer,

    pub fn init(allocator: *const std.mem.Allocator, lexer: Lexer.Lexer) Parser {
        return Parser{
            .allocator = allocator,
            .lexer = lexer,
        };
    }

    pub fn expr(self: *Parser) error{OutOfMemory}!*Eval.Expr {
        const token = self.lexer.current;

        switch (token.kind) {
            Lexer.Lexer.TokenKind.LiteralBoolFalse => {
                const v = try self.allocator.create(Eval.Expr);
                v.literalBool = false;
                self.lexer.next();
                return v;
            },
            Lexer.Lexer.TokenKind.LiteralBoolTrue => {
                const v = try self.allocator.create(Eval.Expr);
                v.literalBool = true;
                self.lexer.next();
                return v;
            },
            else => std.debug.panic("unexpected token kind", .{}),
        }
    }
};
