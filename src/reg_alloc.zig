//! Register allocation via graph coloring, built on top of
//! InterferenceGraph (see ir/interference.zig)

const std = @import("std");
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const parser = @import("parser.zig");
const TopLevel = parser.TopLevel;
const Function = parser.Function;

const ir = @import("ir.zig");
const FunctionIR = ir.FunctionIR;
const ThreeAddressCode = ir.ThreeAddressCode;
const Operand = ir.Operand;
const CFG = ir.ControlFlowGraph;
const LiveAnalysis = ir.LiveAnalysis;
const InterferenceGraph = ir.InterferenceGraph;

const arch = @import("arch.zig");

pub const StackFrame = struct {
    /// Holds the stack offset to all local and parameter
    /// variables
    variables: std.StringHashMapUnmanaged(usize) = .{},
    size: usize = 0,

    pub fn deinit(
        sf: *StackFrame,
        alloc: Allocator,
    ) void {
        sf.variables.deinit(alloc);
    }

    pub fn init(
        tl: *TopLevel,
        alloc: Allocator,
        ri: *const arch.RegisterInfo,
        func: *const Function,
    ) Allocator.Error!StackFrame {
        var sf: StackFrame = .{};
        errdefer sf.deinit(alloc);

        _ = tl;
        _ = ri;
        _ = func;

        // TODO: Based on the type of the
        // variable/parameter, need to allocate
        // more space on the stack for it

        return sf;
    }
};

pub const AllocatedFunction = struct {
    layout: StackFrame = .{},
};

pub const Color = union(enum) {
    register: []const u8,
    spilled,
};

pub const RegAllocError = Allocator.Error;

pub fn regAlloc(
    alloc: Allocator,
    tl: *TopLevel,
    target: arch.Arch,
) RegAllocError!std.StringHashMapUnmanaged(AllocatedFunction) {
    const ri = arch.registerInfo(target);
    var afs: std.StringHashMapUnmanaged(AllocatedFunction) = .empty;
    errdefer afs.deinit(alloc);

    var functions = tl.ir.functions.iterator();
    while (functions.next()) |function| {
        const allocated = try regAllocFunction(
            ri,
            alloc,
            function.value_ptr,
        );

        try afs.put(alloc, function.key_ptr.*, allocated);
    }

    return afs;
}

pub fn regAllocFunction(
    ri: *const arch.RegisterInfo,
    alloc: Allocator,
    function: *const FunctionIR,
) RegAllocError!AllocatedFunction {
    var cfg = try CFG.fromIr(alloc, function.instructions.items);
    defer cfg.deinit(alloc);

    var live = try LiveAnalysis.analyze(alloc, &cfg);
    defer live.deinit(alloc);

    var igraph = try InterferenceGraph.build(alloc, &cfg, &live);
    defer igraph.deinit(alloc);

    var assignment = try colorGraph(alloc, &igraph, ri);
    defer assignment.deinit(alloc);

    // TODO: handle spilled stuff as stack slots

    return .{};
}

pub fn colorGraph(
    alloc: Allocator,
    igraph: *const InterferenceGraph,
    ri: *const arch.RegisterInfo,
) RegAllocError!std.StringHashMapUnmanaged(Color) {
    const k = ri.general_purpose.len;
    const n = igraph.nodes.items.len;

    var assignment: std.StringHashMapUnmanaged(Color) = .{};
    errdefer assignment.deinit(alloc);

    if (n == 0) return assignment;

    const degree = try alloc.alloc(usize, n);
    defer alloc.free(degree);
    for (igraph.nodes.items, 0..) |node, i|
        degree[i] = node.edges.items.len;

    var removed = try std.DynamicBitSet.initEmpty(alloc, n);
    defer removed.deinit();

    var stack: std.ArrayList(usize) = .empty;
    defer stack.deinit(alloc);

    for (0..n) |_| {
        var pick: ?usize = null;
        for (0..n) |i| {
            if (removed.isSet(i)) continue;
            if (degree[i] < k) {
                pick = i;
                break;
            }
        }

        if (pick == null) {
            var best: usize = 0;
            var best_degree: usize = 0;
            var found = false;

            for (0..n) |i| {
                if (removed.isSet(i)) continue;
                if (!found or degree[i] > best_degree) {
                    best = i;
                    best_degree = degree[i];
                    found = true;
                }
            }

            pick = best;
        }

        const node_idx = pick.?;
        removed.set(node_idx);
        try stack.append(alloc, node_idx);

        for (igraph.nodes.items[node_idx].edges.items) |nbr|
            if (!removed.isSet(nbr)) {
                degree[nbr] -= 1;
            };
    }

    const colors = try alloc.alloc(?Color, n);
    defer alloc.free(colors);
    @memset(colors, null);

    const used = try alloc.alloc(bool, k);
    defer alloc.free(used);

    var idx = stack.items.len;
    while (idx > 0) {
        idx -= 1;
        const node_idx = stack.items[idx];

        @memset(used, false);
        for (igraph.nodes.items[node_idx].edges.items) |nbr| {
            const c = colors[nbr] orelse continue;
            if (c != .register) continue;

            for (ri.general_purpose, 0..) |reg, ci| {
                if (std.mem.eql(u8, reg, c.register)) {
                    used[ci] = true;
                    break;
                }
            }
        }

        var chosen: ?Color = null;
        for (ri.general_purpose, 0..) |reg, ci| {
            if (!used[ci]) {
                chosen = .{ .register = reg };
                break;
            }
        }

        colors[node_idx] = chosen orelse .spilled;
    }

    for (igraph.nodes.items, 0..) |node, i| {
        // TODO: References need to be implemented too
        if (node.val != .variable) continue;
        try assignment.put(alloc, node.val.variable, colors[i].?);
    }

    return assignment;
}
