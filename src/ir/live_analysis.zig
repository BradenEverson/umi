// Live analysis!!!!!!!! from a cfg in reverse order this time around

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("../ir.zig");
const CFG = @import("cfg.zig");
const Operand = ir.Operand;
const TAC = ir.ThreeAddressCode;

pub const LivenessInfo = struct {
    use: []std.StringHashMapUnmanaged(void),
    def: []std.StringHashMapUnmanaged(void),
    in: []std.StringHashMapUnmanaged(void),
    out: []std.StringHashMapUnmanaged(void),
    len: usize,

    pub fn deinit(self: *LivenessInfo, alloc: Allocator) void {
        for (0..self.len) |i| {
            self.use[i].deinit(alloc);
            self.def[i].deinit(alloc);
            self.in[i].deinit(alloc);
            self.out[i].deinit(alloc);
        }
        alloc.free(self.use);
        alloc.free(self.def);
        alloc.free(self.in);
        alloc.free(self.out);
    }
};

pub fn isLiveIn(
    info: *const LivenessInfo,
    block_idx: usize,
    name: []const u8,
) bool {
    return info.in[block_idx].contains(name);
}

const Set = std.StringHashMapUnmanaged(void);

pub fn analyze(
    alloc: Allocator,
    cfg: *const CFG,
) !LivenessInfo {
    const n = cfg.blocks.items.len;

    const use = try alloc.alloc(Set, n);
    const def = try alloc.alloc(Set, n);
    const in = try alloc.alloc(Set, n);
    const out = try alloc.alloc(Set, n);

    for (0..n) |i| {
        use[i] = .{};
        def[i] = .{};
        in[i] = .{};
        out[i] = .{};
    }

    for (cfg.blocks.items, 0..) |bb, i|
        try computeUseDef(alloc, bb.instructions, &use[i], &def[i]);

    var changed = true;
    while (changed) {
        changed = false;

        var i = n;
        while (i > 0) {
            i -= 1;
            const bb = &cfg.blocks.items[i];

            for (bb.connections.items) |succ| {
                var it = in[succ].keyIterator();
                while (it.next()) |key| {
                    if (try putIfAbsent(&out[i], alloc, key.*))
                        changed = true;
                }
            }

            var use_it = use[i].keyIterator();
            while (use_it.next()) |key| {
                if (try putIfAbsent(&in[i], alloc, key.*))
                    changed = true;
            }

            var out_it = out[i].keyIterator();
            while (out_it.next()) |key| {
                if (!def[i].contains(key.*)) {
                    if (try putIfAbsent(&in[i], alloc, key.*))
                        changed = true;
                }
            }
        }
    }

    return .{ .use = use, .def = def, .in = in, .out = out, .len = n };
}

fn putIfAbsent(
    set: *std.StringHashMapUnmanaged(void),
    alloc: Allocator,
    key: []const u8,
) !bool {
    const result = try set.getOrPut(alloc, key);
    return !result.found_existing;
}

fn computeUseDef(
    alloc: Allocator,
    instructions: []const TAC,
    use: *std.StringHashMapUnmanaged(void),
    def: *std.StringHashMapUnmanaged(void),
) !void {
    for (instructions) |tac| {
        switch (tac.op) {
            .assignment => {
                try addRead(alloc, tac.arg2, use, def);
            },
            else => {
                try addRead(alloc, tac.arg1, use, def);
                try addRead(alloc, tac.arg2, use, def);
            },
        }

        if (tac.op == .assignment) {
            if (tac.arg1 == .variable) {
                const name = tac.arg1.variable;
                try def.put(alloc, name, {});
            }
        }
    }
}

fn addRead(
    alloc: Allocator,
    operand: Operand,
    use: *std.StringHashMapUnmanaged(void),
    def: *std.StringHashMapUnmanaged(void),
) !void {
    if (operand != .variable) return;
    const name = operand.variable;
    if (!def.contains(name))
        try use.put(alloc, name, {});
}
