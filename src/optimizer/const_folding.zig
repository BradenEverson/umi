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
    _ = alloc;
    _ = tl;
}

pub fn comptimeEval(
    alloc: Allocator,
    expr: *Expr,
) optimizer.OptimizeError!void {
    switch (expr.*) {
        .binary_op => |b| {
            if (b.left.* == .literal and
                b.right.* == .literal)
            {
                const newVal = comptimeBinOp(
                    alloc,
                    b.left.literal,
                    b.right.literal,
                    b.op,
                );
                _ = newVal;
            }
        },
        else => {},
    }
}

pub fn comptimeBinOp(
    alloc: Allocator,
    left: parser.Literal,
    right: parser.Literal,
    op: parser.BinaryOp,
) optimizer.OptimizeError!*Expr {
    _ = alloc;
    _ = left;
    _ = right;
    _ = op;
}
