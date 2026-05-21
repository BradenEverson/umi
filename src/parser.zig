//! The parsing step :D makes a good ol' ast from our existing token stream

const std = @import("std");
const Allocator = std.mem.Allocator;

const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;
const TokenTag = tokenizer.TokenTag;

const ts = @import("type.zig");
const Type = ts.Type;
const StructDef = ts.StructDef;

pub const Function = struct {
    parameters: std.StringHashMapUnmanaged([]const u8) = .empty,
    returns: []const u8 = "void",
    body: Ast = .{},

    pub fn deinit(f: *Function, alloc: Allocator) void {
        f.parameters.deinit(alloc);
        f.body.deinit(alloc);
    }
};

pub const TopLevel = struct {
    types: std.StringHashMapUnmanaged(Type) = .empty,
    functions: std.StringHashMapUnmanaged(Function) = .empty,

    pub fn getType(tl: *TopLevel, ty: []const u8) ?Type {
        switch (ty[0]) {
            'i', 'u' => {
                // Check for if it's a valid int
                const bits_str = ty[1..];
                const bits = std.fmt.parseInt(u16, bits_str, 10) catch return null;
                return .{ .its_an_int = .{
                    .signed = if (ty[0] == 'u') .unsigned else .signed,
                    .bits = bits,
                } };
            },
            else => return tl.types.get(ty),
        }
    }

    /// Register top level types that should always exist :)
    pub fn initTypes(tl: *TopLevel, alloc: Allocator) !void {
        try tl.types.put(alloc, "void", .its_void);
    }

    pub fn deinit(tl: *TopLevel, alloc: Allocator) void {
        var types = tl.types.valueIterator();
        while (types.next()) |t| t.deinit(alloc);

        tl.types.deinit(alloc);

        var fns = tl.functions.valueIterator();
        while (fns.next()) |f| f.deinit(alloc);

        tl.functions.deinit(alloc);
    }
};

pub const Expr = union(enum) {
    assignment: struct { name: []const u8, val: *Expr },
    literal: Literal,
    variable: []const u8,

    fn_call: struct {
        name: []const u8,
        arguments: std.ArrayList(*Expr) = .empty,
    },

    binary_op: struct {
        left: *Expr,
        op: BinaryOp,
        right: *Expr,
    },

    unary_op: struct {
        op: tokenizer.Keyword,
        expr: *Expr,
    },

    /// Deinits while assuming child expressions are also allocated
    /// with the same allocator, destroys them.
    ///
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

            .fn_call => |*f| {
                for (f.arguments.items) |arg| {
                    arg.deinit(alloc);
                    alloc.destroy(arg);
                }

                f.arguments.deinit(alloc);
            },

            else => {},
        }
    }
};

pub const Literal = union(enum) {
    uint: u64,
    int: i64,
    float: f64,
    void_ty,
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
    InvalidTopLevelStart,
    InvalidType,
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

const AnyParserError = ParserError ||
    std.mem.Allocator.Error ||
    std.fmt.ParseIntError;

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

fn peekN(self: *const Parser, n: comptime_int) TokenTag {
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

pub fn parse(
    self: *Parser,
    alloc: Allocator,
    tl: *TopLevel,
) AnyParserError!void {
    while (!self.at_end()) {
        const top_level_token_ident = self.peekTok();
        try self.consume(.keyword);

        const kw = tokenizer.KeywordLookup
            .get(top_level_token_ident.data).?;

        switch (kw) {
            .struct_kw => {
                var struct_def: StructDef = .{};
                errdefer struct_def.deinit(alloc);

                const struct_name = self.peekTok().data;
                try self.consume(.ident);

                try self.consume(.open_brace);

                while (self.peek() != .close_brace) {
                    const attr_name = self.peekTok().data;
                    try self.consume(.ident);

                    try self.consume(.colon);

                    const attr_type = self.peekTok().data;
                    try self.consume(.ident);

                    try self.consume(.comma);

                    try struct_def.attributes.put(
                        alloc,
                        attr_name,
                        attr_type,
                    );
                }

                try self.consume(.close_brace);

                try tl.types.put(
                    alloc,
                    struct_name,
                    .{ .its_a_struct = struct_def },
                );
            },
            .fn_kw => {
                var func: Function = .{};
                errdefer func.deinit(alloc);

                const fn_name = self.peekTok().data;
                try self.consume(.ident);

                try self.consume(.open_paren);

                // Start parsing out the parameters
                while (self.peek() != .close_paren) {
                    const param_name = self.peekTok().data;
                    try self.consume(.ident);

                    try self.consume(.colon);

                    const param_ty = self.peekTok().data;
                    try self.consume(.ident);

                    try func.parameters.put(
                        alloc,
                        param_name,
                        param_ty,
                    );
                }
                try self.consume(.close_paren);

                // Get the return type
                try self.consume(.minus);
                try self.consume(.gt);

                func.returns = self.peekTok().data;
                try self.consume(.ident);

                // Begin parsing the body ast
                try self.consume(.open_brace);

                while (self.peek() != .close_brace) {
                    const expr = try self.statement(alloc);
                    try func.body.ast.append(alloc, expr);
                }

                try self.consume(.close_brace);

                try tl.functions.put(alloc, fn_name, func);
            },

            else => return ParserError.InvalidTopLevelStart,
        }
    }
}

pub fn statement(
    self: *Parser,
    alloc: Allocator,
) AnyParserError!*Expr {
    const expr = try self.expression(alloc);
    try self.consume(.semicolon);
    return expr;
}

pub fn expression(
    self: *Parser,
    alloc: Allocator,
) AnyParserError!*Expr {
    if (self.peek() == .ident and self.peekN(1) == .equals) {
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

fn term(
    self: *Parser,
    alloc: Allocator,
) !*Expr {
    var left = try self.comparison(alloc);

    while (self.peek() == .plus or
        self.peek() == .minus)
    {
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

fn comparison(
    self: *Parser,
    alloc: Allocator,
) AnyParserError!*Expr {
    var left = try self.factor(alloc);

    if (self.peek() == .gt or
        self.peek() == .lt or
        self.peek() == .equals_equals)
    {
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

fn factor(
    self: *Parser,
    alloc: Allocator,
) AnyParserError!*Expr {
    var left = try self.power(alloc);

    while (self.peek() == .star or
        self.peek() == .slash or
        self.peek() == .at)
    {
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

fn power(
    self: *Parser,
    alloc: Allocator,
) AnyParserError!*Expr {
    const left = try self.primary(alloc);
    return left;
}

fn primary(
    self: *Parser,
    alloc: Allocator,
) AnyParserError!*Expr {
    const current_token = self.peekTok();
    var expr: *Expr = undefined;

    switch (current_token.tag) {
        .ident => {
            self.advance();

            if (self.peek() == .open_paren) {
                // We're a function call!!!
                const func_call = try alloc.create(Expr);
                func_call.* = .{ .fn_call = .{ .name = current_token.data } };

                self.advance();
                while (self.peek() != .close_paren) {
                    const arg = try self.term(alloc);

                    try func_call.fn_call.arguments
                        .append(alloc, arg);

                    if (self.peek() != .close_paren)
                        try self.consume(.comma);
                }

                try self.consume(.close_paren);

                expr = func_call;
            } else {
                // We're just a variable reference
                const variable_expr = try alloc.create(Expr);
                variable_expr.* = .{ .variable = current_token.data };
                expr = variable_expr;
            }
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

fn literal(
    self: *Parser,
    alloc: Allocator,
) AnyParserError!*Expr {
    const current_token = self.tokens[self.cursor];
    self.advance();

    switch (current_token.tag) {
        .number => {
            const number_val = try std.fmt.parseInt(
                u64,
                current_token.data,
                10,
            );

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

    const s = try p.statement(alloc);
    defer s.deinit(alloc);
    defer alloc.destroy(s);

    try std.testing.expectEqualStrings(
        s.assignment.name,
        "W",
    );

    try std.testing.expectEqual(
        s.assignment.val.literal.uint,
        1,
    );
}

test "top level type parsing" {
    var tl: TopLevel = .{};
    defer tl.deinit(std.testing.allocator);

    var ty = tl.getType("u31").?;

    try std.testing.expectEqual(.unsigned, ty.its_an_int.signed);
    try std.testing.expectEqual(31, ty.its_an_int.bits);

    ty = tl.getType("i5").?;

    try std.testing.expectEqual(.signed, ty.its_an_int.signed);
    try std.testing.expectEqual(5, ty.its_an_int.bits);
}
