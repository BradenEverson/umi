//! An interference graph for overlapping temporaries/variables

const std = @import("std");
const Allocator = std.mem.Allocator;

const CFG = @import("cfg.zig");
const LivenessInfo = @import("live_analysis.zig").LivenessInfo;

pub const Value = union(enum) {
    variable: []const u8,
    temporary: usize,

    pub fn eql(a: Value, b: Value) bool {
        return switch (a) {
            .variable => |n| b == .variable and
                std.mem.eql(u8, n, b.variable),

            .temporary => |i| b == .temporary and
                i == b.temporary,
        };
    }
};

pub const Node = struct {
    val: Value,
    edges: std.ArrayList(usize) = .empty,

    pub fn deinit(self: *Node, alloc: Allocator) void {
        self.edges.deinit(alloc);
    }
};

nodes: std.ArrayList(Node) = .empty,

pub const InterferenceGraphError = Allocator.Error;
const InterferenceGraph = @This();

pub fn deinit(
    igraph: *InterferenceGraph,
    alloc: Allocator,
) void {
    for (igraph.nodes.items) |*node|
        node.deinit(alloc);

    igraph.nodes.deinit(alloc);
}

pub fn build(
    alloc: Allocator,
    cfg: *const CFG,
    live: *const LivenessInfo,
) InterferenceGraphError!InterferenceGraph {
    _ = alloc;
    _ = live;

    for (0..cfg.blocks.items.len) |i| {
        const idx = cfg.blocks.items.len - i - 1;
        _ = idx;
    }

    return InterferenceGraphError.OutOfMemory;
}
