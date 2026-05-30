//! Constant folding optimization step

const std = @import("std");
const Allocator = std.mem.Allocator;

const parser = @import("../parser.zig");
const TopLevel = parser.TopLevel;
const Expr = parser.Expr;

const optimizer = @import("../optimizer.zig");

pub fn foldConsts(
    alloc: Allocator,
    tl: *TopLevel,
) optimizer.OptimizeError!void {
    var functions = tl.functions.iterator();
    while (functions.next()) |function| {
        for (function.value_ptr.body.ast.items) |expr| {
            try comptimeEval(alloc, expr);
        }
    }
}

pub fn comptimeEval(
    alloc: Allocator,
    expr: *Expr,
) optimizer.OptimizeError!void {
    switch (expr.*) {
        .binary_op => |b| {
            try comptimeEval(alloc, b.left);
            try comptimeEval(alloc, b.right);

            if (b.left.* == .literal and
                b.right.* == .literal)
            {
                comptimeBinOp(
                    alloc,
                    b.left.literal,
                    b.right.literal,
                    b.op,
                    expr,
                );
            }
        },

        .unary_op => |u| {
            try comptimeEval(alloc, u.expr);
            // TODO! Unary constant folding B)
        },

        .assignment => |a| try comptimeEval(alloc, a.val),
        .construction => |c| try comptimeEval(alloc, c.val),
        .fn_call => |f| {
            for (f.arguments.items) |i|
                try comptimeEval(alloc, i);
        },
        .return_val => |r| try comptimeEval(alloc, r),

        .literal, .variable => {},
        .if_statement => |i| {
            try comptimeEval(alloc, i.cond);
            for (i.block.items) |e|
                try comptimeEval(alloc, e);
        },
    }
}

pub fn comptimeBinOp(
    alloc: Allocator,
    left: parser.Literal,
    right: parser.Literal,
    op: parser.BinaryOp,
    expr: *Expr,
) void {
    const a, const b = left.getCompatible(right);

    const lit: parser.Literal = switch (op) {
        .add => switch (a) {
            .float => .{ .float = a.float + b.float },
            .int => .{ .int = a.int + b.int },
            .uint => .{ .uint = a.uint + b.uint },
            else => unreachable,
        },
        .sub => switch (a) {
            .float => .{ .float = a.float - b.float },
            .int => .{ .int = a.int - b.int },
            .uint => .{ .uint = a.uint - b.uint },
            else => unreachable,
        },
        .div => switch (a) {
            .float => .{ .float = a.float / b.float },
            .int => .{ .int = @divExact(a.int, b.int) },
            .uint => .{ .uint = @divExact(a.uint, b.uint) },
            else => unreachable,
        },
        .mul => switch (a) {
            .float => .{ .float = a.float * b.float },
            .int => .{ .int = a.int * b.int },
            .uint => .{ .uint = a.uint * b.uint },
            else => unreachable,
        },

        .eq => .{ .boolean = std.meta.eql(a, b) },

        .gt => switch (a) {
            .float => .{ .boolean = a.float > b.float },
            .int => .{ .boolean = a.int > b.int },
            .uint => .{ .boolean = a.uint > b.uint },
            else => unreachable,
        },

        .lt => switch (a) {
            .float => .{ .boolean = a.float < b.float },
            .int => .{ .boolean = a.int < b.int },
            .uint => .{ .boolean = a.uint < b.uint },
            else => unreachable,
        },
    };

    expr.deinit(alloc);
    expr.* = .{ .literal = lit };
}
