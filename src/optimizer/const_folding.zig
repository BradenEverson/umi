//! Constant folding optimization step

const std = @import("std");
const Allocator = std.mem.Allocator;

const parser = @import("../parser.zig");
const TopLevel = parser.TopLevel;

const optimizer = @import("../optimizer.zig");

pub fn foldConsts(alloc: Allocator, tl: *TopLevel) optimizer.OptimizeError!void {
    _ = alloc;
    _ = tl;
}
