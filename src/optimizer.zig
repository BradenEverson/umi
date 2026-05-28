//! Single step for walking a chain of optimization
//! steps that are registered here

const std = @import("std");
const Allocator = std.mem.Allocator;

const parser = @import("parser.zig");
const TopLevel = parser.TopLevel;

pub const OptimizeError = Allocator.Error;

const cf = @import("optimizer/const_folding.zig");

/// Runs all optimization passes over the ast
pub fn optimize(
    alloc: Allocator,
    tl: *TopLevel,
) OptimizeError!void {
    try cf.foldConsts(alloc, tl);
}
