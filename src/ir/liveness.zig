//! Liveness analysis + interference graph over the TAC stream :D

const std = @import("std");
const Allocator = std.mem.Allocator;
const Bits = std.DynamicBitSetUnmanaged;

const ir = @import("../ir.zig");
const TAC = ir.ThreeAddressCode;
const Operand = ir.Operand;
const CFG = ir.ControlFlowGraph;

const parser = @import("../parser.zig");

pub const VReg = u32;

pub const VRegs = struct {
    num_temps: usize,
    var_ids: std.StringHashMapUnmanaged(VReg) = .empty,
    var_names: std.ArrayList([]const u8) = .empty,

    pub fn init(
        alloc: Allocator,
        stream: []const TAC,
        func: *const parser.Function,
    ) Allocator.Error!VRegs {
        var vr: VRegs = .{ .num_temps = stream.len };
        errdefer vr.deinit(alloc);

        for (func.parameters.items) |p| _ = try vr.intern(alloc, p[0]);

        for (stream) |tac| {
            for ([_]Operand{ tac.arg1, tac.arg2 }) |op| switch (op) {
                .variable => |name| _ = try vr.intern(alloc, name),
                else => {},
            };
        }
        return vr;
    }

    pub fn deinit(vr: *VRegs, alloc: Allocator) void {
        vr.var_ids.deinit(alloc);
        vr.var_names.deinit(alloc);
    }

    fn intern(vr: *VRegs, alloc: Allocator, name: []const u8) Allocator.Error!VReg {
        const gop = try vr.var_ids.getOrPut(alloc, name);
        if (!gop.found_existing) {
            gop.value_ptr.* = @intCast(vr.num_temps + vr.var_names.items.len);
            try vr.var_names.append(alloc, name);
        }
        return gop.value_ptr.*;
    }

    pub fn count(vr: *const VRegs) usize {
        return vr.num_temps + vr.var_names.items.len;
    }

    pub fn param(vr: *const VRegs, k: usize) VReg {
        return @intCast(vr.num_temps + k);
    }

    pub fn of(vr: *const VRegs, op: Operand) ?VReg {
        return switch (op) {
            .reference => |t| @intCast(t),
            .variable => |name| vr.var_ids.get(name).?,
            else => null,
        };
    }
};

/// What a single TAC reads and writes
pub const Effects = struct {
    def: ?VReg = null,
    uses: [2]?VReg = .{ null, null },
    is_call: bool = false,
    move_src: ?VReg = null,
};

pub fn effects(vr: *const VRegs, idx: usize, tac: TAC) Effects {
    const self_t: VReg = @intCast(idx);
    return switch (tac.op) {
        .binary_op => .{ .def = self_t, .uses = .{ vr.of(tac.arg1), vr.of(tac.arg2) } },
        .unary_op => .{ .def = self_t, .uses = .{ vr.of(tac.arg1), null } },
        .call_fn => .{ .def = self_t, .is_call = true },
        .assignment => .{
            .def = vr.of(tac.arg1),
            .uses = .{ vr.of(tac.arg2), null },
            .move_src = vr.of(tac.arg2),
        },
        .load_arg => .{ .uses = .{ vr.of(tac.arg2), null } },
        .if_true_goto,
        .if_false_goto,
        .return_something,
        => .{ .uses = .{ vr.of(tac.arg1), null } },
        .label, .goto => .{},
    };
}

fn allocSets(alloc: Allocator, count: usize, bits: usize) Allocator.Error![]Bits {
    const sets = try alloc.alloc(Bits, count);
    var i: usize = 0;
    errdefer {
        for (sets[0..i]) |*s| s.deinit(alloc);
        alloc.free(sets);
    }
    while (i < count) : (i += 1) sets[i] = try Bits.initEmpty(alloc, bits);
    return sets;
}

fn freeSets(alloc: Allocator, sets: []Bits) void {
    for (sets) |*s| s.deinit(alloc);
    alloc.free(sets);
}

pub const Liveness = struct {
    live_in: []Bits,
    live_out: []Bits,

    pub fn deinit(l: *Liveness, alloc: Allocator) void {
        freeSets(alloc, l.live_in);
        freeSets(alloc, l.live_out);
    }

    pub fn analyze(
        alloc: Allocator,
        cfg: *const CFG,
        vr: *const VRegs,
    ) Allocator.Error!Liveness {
        const nb = cfg.blocks.items.len;
        const n = vr.count();

        const live_in = try allocSets(alloc, nb, n);
        errdefer freeSets(alloc, live_in);
        const live_out = try allocSets(alloc, nb, n);
        errdefer freeSets(alloc, live_out);
        const def = try allocSets(alloc, nb, n);
        defer freeSets(alloc, def);

        for (cfg.blocks.items, 0..) |bb, b| {
            for (bb.instructions, bb.start..) |tac, gi| {
                const e = effects(vr, gi, tac);
                for (e.uses) |u_opt| if (u_opt) |u| {
                    if (!def[b].isSet(u)) live_in[b].set(u);
                };
                if (e.def) |d| def[b].set(d);
            }
        }

        var changed = true;
        while (changed) {
            changed = false;
            var b = nb;
            while (b > 0) {
                b -= 1;
                const before = live_in[b].count() + live_out[b].count();

                for (cfg.blocks.items[b].connections.items) |s|
                    live_out[b].setUnion(live_in[s]);

                var it = live_out[b].iterator(.{});
                while (it.next()) |v|
                    if (!def[b].isSet(v)) live_in[b].set(v);

                if (live_in[b].count() + live_out[b].count() != before)
                    changed = true;
            }
        }

        return .{ .live_in = live_in, .live_out = live_out };
    }
};

pub const InterferenceGraph = struct {
    adj: []std.AutoArrayHashMapUnmanaged(VReg, void),
    present: Bits,
    crosses_call: Bits,

    pub fn deinit(g: *InterferenceGraph, alloc: Allocator) void {
        for (g.adj) |*a| a.deinit(alloc);
        alloc.free(g.adj);
        g.present.deinit(alloc);
        g.crosses_call.deinit(alloc);
    }

    fn addEdge(g: *InterferenceGraph, alloc: Allocator, a: VReg, b: VReg) Allocator.Error!void {
        if (a == b) return;
        try g.adj[a].put(alloc, b, {});
        try g.adj[b].put(alloc, a, {});
    }

    pub fn build(
        alloc: Allocator,
        cfg: *const CFG,
        vr: *const VRegs,
        live: *const Liveness,
    ) Allocator.Error!InterferenceGraph {
        const n = vr.count();

        const adj = try alloc.alloc(std.AutoArrayHashMapUnmanaged(VReg, void), n);
        @memset(adj, .empty);

        var g: InterferenceGraph = .{
            .adj = adj,
            .present = try Bits.initEmpty(alloc, n),
            .crosses_call = try Bits.initEmpty(alloc, n),
        };
        errdefer g.deinit(alloc);

        var cur = try Bits.initEmpty(alloc, n);
        defer cur.deinit(alloc);

        for (cfg.blocks.items, 0..) |bb, b| {
            cur.unsetAll();
            cur.setUnion(live.live_out[b]);

            var i = bb.instructions.len;
            while (i > 0) {
                i -= 1;
                const e = effects(vr, bb.start + i, bb.instructions[i]);

                if (e.is_call) {
                    var it = cur.iterator(.{});
                    while (it.next()) |v| {
                        if (e.def) |d| if (v == d) continue;
                        g.crosses_call.set(v);
                    }
                }

                if (e.def) |d| {
                    g.present.set(d);
                    var it = cur.iterator(.{});
                    while (it.next()) |v| {
                        const vv: VReg = @intCast(v);
                        if (e.move_src) |src| if (vv == src) continue;
                        try g.addEdge(alloc, d, vv);
                    }
                    cur.unset(d);
                }

                for (e.uses) |u_opt| if (u_opt) |u| {
                    g.present.set(u);
                    cur.set(u);
                };
            }
        }

        if (cfg.blocks.items.len > 0) {
            var entry: std.ArrayList(VReg) = .empty;
            defer entry.deinit(alloc);

            var it = live.live_in[0].iterator(.{});
            while (it.next()) |v| {
                g.present.set(v);
                try entry.append(alloc, @intCast(v));
            }
            for (entry.items, 0..) |a, ai|
                for (entry.items[ai + 1 ..]) |b| try g.addEdge(alloc, a, b);
        }

        return g;
    }
};
