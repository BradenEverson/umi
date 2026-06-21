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

fn getOrAddNode(
    igraph: *InterferenceGraph,
    alloc: Allocator,
    val: Value,
) Allocator.Error!usize {
    for (igraph.nodes.items, 0..) |node, i|
        if (node.val.eql(val)) return i;

    const idx = igraph.nodes.items.len;
    try igraph.nodes.append(alloc, .{ .val = val });
    return idx;
}

fn addEdge(
    igraph: *InterferenceGraph,
    alloc: Allocator,
    a: usize,
    b: usize,
) Allocator.Error!void {
    if (a == b) return;

    for (igraph.nodes.items[a].edges.items) |e|
        if (e == b) return;

    try igraph.nodes.items[a].edges.append(alloc, b);
    try igraph.nodes.items[b].edges.append(alloc, a);
}

pub fn build(
    alloc: Allocator,
    cfg: *const CFG,
    live: *const LivenessInfo,
) InterferenceGraphError!InterferenceGraph {
    var igraph: InterferenceGraph = .{};
    errdefer igraph.deinit(alloc);

    for (cfg.blocks.items, 0..) |bb, block_idx| {
        var live_now: std.StringHashMapUnmanaged(void) = .{};
        defer live_now.deinit(alloc);

        var out_it = live.out[block_idx].keyIterator();
        while (out_it.next()) |k|
            try live_now.put(alloc, k.*, {});

        var i = bb.instructions.len;
        while (i > 0) {
            i -= 1;
            const tac = bb.instructions[i];
            const is_move = tac.op == .assignment;

            const def_name: ?[]const u8 =
                if (is_move and tac.arg1 == .variable)
                    tac.arg1.variable
                else
                    null;

            const move_src: ?[]const u8 =
                if (is_move and tac.arg2 == .variable)
                    tac.arg2.variable
                else
                    null;

            if (move_src) |s| _ = live_now.remove(s);

            if (def_name) |d| {
                const d_idx = try igraph.getOrAddNode(
                    alloc,
                    .{ .variable = d },
                );

                var live_it = live_now.keyIterator();
                while (live_it.next()) |v| {
                    const v_idx = try igraph.getOrAddNode(
                        alloc,
                        .{ .variable = v.* },
                    );
                    try igraph.addEdge(alloc, d_idx, v_idx);
                }

                _ = live_now.remove(d);
            }

            if (move_src) |s| {
                try live_now.put(alloc, s, {});
            } else {
                if (tac.arg1 == .variable)
                    try live_now.put(alloc, tac.arg1.variable, {});
                if (tac.arg2 == .variable)
                    try live_now.put(alloc, tac.arg2.variable, {});
            }
        }
    }

    return igraph;
}
