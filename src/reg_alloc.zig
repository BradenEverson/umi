//! Register allocation via graph coloring, built on top of
//! InterferenceGraph (see ir/interference.zig)

const std = @import("std");
const Allocator = std.mem.Allocator;

const parser = @import("parser.zig");

const ir = @import("ir.zig");
const FunctionIR = ir.FunctionIR;
const CFG = ir.ControlFlowGraph;
const liveness = ir.liveness;
const VReg = liveness.VReg;

const arch = @import("arch.zig");
const Reg = arch.Reg;

const layout = @import("layout.zig");

pub const RegAllocError = Allocator.Error;

pub const Location = union(enum) {
    none,
    reg: Reg,
    stack: i32,
};

pub const StackFrame = struct {
    saved_size: u64 = 0,
    size: u64 = 0,

    pub fn allocSlot(sf: *StackFrame, l: layout.Layout) i32 {
        const total = layout.alignForward(sf.saved_size + sf.size + l.size, l.alignment);
        sf.size = total - sf.saved_size;
        return -@as(i32, @intCast(total));
    }

    pub fn subAmount(sf: *const StackFrame) u64 {
        return layout.alignForward(sf.saved_size + sf.size, 16) - sf.saved_size;
    }
};

pub const AllocatedFunction = struct {
    vregs: liveness.VRegs,
    locs: []Location,
    frame: StackFrame = .{},
    callee_saved_used: std.ArrayList(Reg) = .empty,

    pub fn deinit(af: *AllocatedFunction, alloc: Allocator) void {
        af.vregs.deinit(alloc);
        alloc.free(af.locs);
        af.callee_saved_used.deinit(alloc);
    }
};

pub fn regAllocFunction(
    alloc: Allocator,
    ri: *const arch.RegisterInfo,
    func: *const parser.Function,
    fir: *const FunctionIR,
) RegAllocError!AllocatedFunction {
    const stream = fir.instructions.items;

    var cfg = try CFG.fromIr(alloc, stream);
    defer cfg.deinit(alloc);

    var vregs = try liveness.VRegs.init(alloc, stream, func);
    errdefer vregs.deinit(alloc);

    var live = try liveness.Liveness.analyze(alloc, &cfg, &vregs);
    defer live.deinit(alloc);

    var ig = try liveness.InterferenceGraph.build(alloc, &cfg, &vregs, &live);
    defer ig.deinit(alloc);

    const colors = try colorGraph(alloc, &ig, ri);
    defer alloc.free(colors);

    const locs = try alloc.alloc(Location, vregs.count());
    errdefer alloc.free(locs);

    var af: AllocatedFunction = .{ .vregs = vregs, .locs = locs };
    errdefer af.callee_saved_used.deinit(alloc);

    var used = std.EnumSet(Reg).initEmpty();
    for (colors) |c| if (c) |r| used.insert(r);
    for (ri.callee_saved) |r| if (used.contains(r))
        try af.callee_saved_used.append(alloc, r);
    af.frame.saved_size = af.callee_saved_used.items.len * ri.word_size;

    const word: layout.Layout = .{ .size = ri.word_size, .alignment = ri.word_size };

    for (locs, 0..) |*loc, v| {
        if (!ig.present.isSet(v)) {
            loc.* = .none;
        } else if (colors[v]) |r| {
            loc.* = .{ .reg = r };
        } else {
            loc.* = .{ .stack = af.frame.allocSlot(word) };
        }
    }

    return af;
}

fn allowedRegs(
    g: *const liveness.InterferenceGraph,
    ri: *const arch.RegisterInfo,
    v: usize,
) []const Reg {
    return if (g.crosses_call.isSet(v)) ri.callee_saved else ri.allocatable;
}

/// Returns a color per VReg
pub fn colorGraph(
    alloc: Allocator,
    g: *const liveness.InterferenceGraph,
    ri: *const arch.RegisterInfo,
) RegAllocError![]?Reg {
    const n = g.adj.len;

    const colors = try alloc.alloc(?Reg, n);
    errdefer alloc.free(colors);
    @memset(colors, null);

    const degree = try alloc.alloc(usize, n);
    defer alloc.free(degree);

    var removed = try std.DynamicBitSetUnmanaged.initFull(alloc, n);
    defer removed.deinit(alloc);

    var remaining: usize = 0;
    for (0..n) |v| {
        if (!g.present.isSet(v)) continue;
        removed.unset(v);
        degree[v] = g.adj[v].count();
        remaining += 1;
    }

    var stack: std.ArrayList(VReg) = .empty;
    defer stack.deinit(alloc);

    while (remaining > 0) : (remaining -= 1) {
        var pick: ?usize = null;
        var worst: usize = 0;
        var worst_deg: usize = 0;

        for (0..n) |v| {
            if (removed.isSet(v)) continue;
            if (degree[v] < allowedRegs(g, ri, v).len) {
                pick = v;
                break;
            }

            // TODO: better spill cost
            if (degree[v] >= worst_deg) {
                worst = v;
                worst_deg = degree[v];
            }
        }

        const v = pick orelse worst;
        removed.set(v);
        try stack.append(alloc, @intCast(v));

        for (g.adj[v].keys()) |nbr| {
            if (!removed.isSet(nbr)) degree[nbr] -= 1;
        }
    }

    var i = stack.items.len;
    while (i > 0) {
        i -= 1;
        const v = stack.items[i];

        var taken = std.EnumSet(Reg).initEmpty();
        for (g.adj[v].keys()) |nbr| {
            if (colors[nbr]) |r| taken.insert(r);
        }

        for (allowedRegs(g, ri, v)) |r| {
            if (!taken.contains(r)) {
                colors[v] = r;
                break;
            }
        }
    }

    return colors;
}
