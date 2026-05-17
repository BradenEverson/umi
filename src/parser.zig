//! The parsing step :D makes a good ol' ast from our existing token stream

const std = @import("std");
const Allocator = std.mem.Allocator;

const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;
const TokenTag = tokenizer.TokenTag;

pub const Expr = union(enum) {
    assignment: struct { name: []const u8, val: *Expr },
    binary_op: struct { left: *Expr, op: BinaryOp, right: *Expr },
    unary_op: struct { op: tokenizer.Keyword, expr: *Expr },
    literal: Literal,
    variable: []const u8,

    /// Deinits while assuming child expressions are also allocated with the same allocator, destroys them.
    /// TODO: Maybe this is better for an arena, who knows
    pub fn deinit(self: *Expr, alloc: Allocator) void {
        switch (self.*) {
            .assignment => |a| {
                a.val.deinit(alloc);
                alloc.destroy(a.val);
            },
            .unary_op => |u| {
                u.expr.deinit(alloc);
                alloc.destroy(u.expr);
            },

            .binary_op => |bop| {
                bop.left.deinit(alloc);
                bop.right.deinit(alloc);

                alloc.destroy(bop.left);
                alloc.destroy(bop.right);
            },

            else => {},
        }
    }
};

pub const Literal = union(enum) {
    uint: u64,
    int: i64,
    float: f64,
};

pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    gt,
    lt,
    eq,
};

pub const ParserError = error{
    UnexpectedToken,
    UnexpectedKeywordHere,
    ExpectedSemicolon,
    OutOfTokens,
};

pub const Ast = struct {
    ast: std.ArrayList(*Expr) = .empty,

    pub fn deinit(self: *Ast, alloc: Allocator) void {
        for (self.ast.items) |a| {
            a.deinit(alloc);
            alloc.destroy(a);
        }
        self.ast.deinit(alloc);
    }
};

const AnyParserError = ParserError || std.mem.Allocator.Error || std.fmt.ParseIntError;

tokens: []const Token,
cursor: usize = 0,

const Parser = @This();

fn peekTok(self: *const Parser) Token {
    if (self.cursor >= self.tokens.len) {
        return .{ .tag = .eof };
    }
    return self.tokens[self.cursor];
}

fn peek(self: *const Parser) TokenTag {
    if (self.cursor >= self.tokens.len) {
        return .eof;
    }
    return self.tokens[self.cursor].tag;
}

fn peek_n(self: *const Parser, n: comptime_int) TokenTag {
    if (self.cursor + n >= self.tokens.len) {
        return .eof;
    }
    return self.tokens[self.cursor + n].tag;
}

fn advance(self: *Parser) void {
    if (self.cursor < self.tokens.len) {
        self.cursor += 1;
    }
}

fn consume(self: *Parser, tok: TokenTag) ParserError!void {
    if (self.peek() == tok) {
        self.advance();
        return;
    } else {
        return ParserError.UnexpectedToken;
    }
}

fn at_end(self: *Parser) bool {
    return self.peek() == .eof;
}

pub fn parse(self: *Parser, alloc: Allocator, ast: *Ast) AnyParserError!void {
    while (!self.at_end()) {
        const expr = try self.statement(alloc);
        try ast.ast.append(alloc, expr);
    }
}

pub fn statement(self: *Parser, alloc: Allocator) AnyParserError!*Expr {
    const expr = try self.expression(alloc);
    try self.consume(.semicolon);
    return expr;
}

pub fn expression(self: *Parser, alloc: Allocator) AnyParserError!*Expr {
    if (self.peek() == .ident and self.peek_n(1) == .equals) {
        const name = self.tokens[self.cursor].data;
        self.advance();
        self.advance();

        const val = try self.term(alloc);

        const assignment_expr = try alloc.create(Expr);
        assignment_expr.* = .{
            .assignment = .{
                .name = name,
                .val = val,
            },
        };
        return assignment_expr;
    }

    return self.term(alloc);
}

fn term(self: *Parser, alloc: Allocator) !*Expr {
    var left = try self.comparison(alloc);

    while (self.peek() == .plus or self.peek() == .minus) {
        const op_token = self.tokens[self.cursor];
        self.advance();
        const right = try self.comparison(alloc);

        const op = switch (op_token.tag) {
            .plus => BinaryOp.add,
            .minus => BinaryOp.sub,
            else => unreachable,
        };

        const binary_op_expr = try alloc.create(Expr);
        binary_op_expr.* = .{
            .binary_op = .{
                .left = left,
                .op = op,
                .right = right,
            },
        };
        left = binary_op_expr;
    }

    return left;
}

fn comparison(self: *Parser, alloc: Allocator) AnyParserError!*Expr {
    var left = try self.factor(alloc);

    if (self.peek() == .gt or self.peek() == .lt or self.peek() == .equals_equals) {
        const op_token = self.tokens[self.cursor];
        self.advance();
        const right = try self.factor(alloc);

        const op = switch (op_token.tag) {
            .gt => BinaryOp.gt,
            .lt => BinaryOp.lt,
            .equals_equals => BinaryOp.eq,
            else => unreachable,
        };

        const binary_op_expr = try alloc.create(Expr);
        binary_op_expr.* = .{
            .binary_op = .{
                .left = left,
                .op = op,
                .right = right,
            },
        };
        left = binary_op_expr;
    }

    return left;
}

fn factor(self: *Parser, alloc: Allocator) AnyParserError!*Expr {
    var left = try self.power(alloc);

    while (self.peek() == .star or self.peek() == .slash or self.peek() == .at) {
        const op_token = self.tokens[self.cursor];
        self.advance();
        const right = try self.power(alloc);

        const op = switch (op_token.tag) {
            .star => BinaryOp.mul,
            .slash => BinaryOp.div,
            else => unreachable,
        };

        const binary_op_expr = try alloc.create(Expr);
        binary_op_expr.* = .{
            .binary_op = .{
                .left = left,
                .op = op,
                .right = right,
            },
        };
        left = binary_op_expr;
    }

    return left;
}

fn power(self: *Parser, alloc: Allocator) AnyParserError!*Expr {
    const left = try self.primary(alloc);
    return left;
}

fn primary(self: *Parser, alloc: Allocator) AnyParserError!*Expr {
    const current_token = self.tokens[self.cursor];
    var expr: *Expr = undefined;

    switch (current_token.tag) {
        .ident => {
            const variable_expr = try alloc.create(Expr);
            variable_expr.* = .{ .variable = current_token.data };
            self.advance();
            expr = variable_expr;
        },

        .open_paren => {
            self.advance();
            const inner = try self.term(alloc);
            try self.consume(.close_paren);
            expr = inner;
        },

        else => {
            expr = try self.literal(alloc);
        },
    }

    return expr;
}

fn literal(self: *Parser, alloc: Allocator) AnyParserError!*Expr {
    const current_token = self.tokens[self.cursor];
    self.advance();

    switch (current_token.tag) {
        .number => {
            const number_val = try std.fmt.parseInt(u64, current_token.data, 10);
            const literal_expr = try alloc.create(Expr);
            literal_expr.* = .{ .literal = .{ .uint = number_val } };
            return literal_expr;
        },
        else => {
            return ParserError.UnexpectedToken;
        },
    }
}

test "create a parser" {
    const tokens: []Token = &[_]Token{};
    const p: Parser = .{ .tokens = tokens };
    try std.testing.expectEqual(0, p.cursor);
}

test "basic parse" {
    const alloc = std.testing.allocator;
    const tokens: []const Token = &[_]Token{
        .{ .tag = .ident, .data = "W" },
        .{ .tag = .equals },
        .{ .tag = .number, .data = "1" },
        .{ .tag = .semicolon },
    };

    var p: Parser = .{ .tokens = tokens };

    var ast: Ast = .{};
    defer ast.deinit(alloc);

    try p.parse(alloc, &ast);

    try std.testing.expectEqualStrings(ast.ast.items[0].assignment.name, "W");
    try std.testing.expectEqual(ast.ast.items[0].assignment.val.literal.uint, 1);
}
