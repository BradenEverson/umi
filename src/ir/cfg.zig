//! Control Flow Graph for later IR passes

const std = @import("std");
const Allocator = std.mem.Allocator;

const ir = @import("../ir.zig");
const TAC = ir.ThreeAddressCode;

pub const BasicBlock = struct {
    /// A slice into the existing TAC stream
    instructions: []TAC = &[0]TAC{},

    // todo: Might need connection type too
    // like conditional etc
    connections: std.ArrayList(usize) =
        .empty,
    predecessors: std.ArrayList(usize) = .empty,

    pub fn deinit(bb: *BasicBlock, alloc: Allocator) void {
        bb.connections.deinit(alloc);
        bb.predecessors.deinit(alloc);
    }
};

blocks: std.ArrayList(BasicBlock) = .empty,

pub const CfgError = Allocator.Error;

const CFG = @This();

fn isLeader(
    stream: []const TAC,
    idx: usize,
) bool {
    const is_label =
        stream[idx].op == .label;

    return is_label;
}

pub fn deinit(cfg: *CFG, alloc: Allocator) void {
    for (cfg.blocks.items) |*bb|
        bb.deinit(alloc);

    cfg.blocks.deinit(alloc);
}

pub fn fromIr(
    alloc: Allocator,
    stream: []TAC,
) CfgError!CFG {
    var cfg: CFG = .{};
    if (stream.len == 0) return cfg;

    var leaders = try std.DynamicBitSet.initEmpty(alloc, stream.len);
    defer leaders.deinit();

    leaders.set(0);

    for (stream, 0..) |tac, i| {
        const is_branch = switch (tac.op) {
            .if_true_goto, .if_false_goto, .goto => true,
            else => false,
        };
        const is_label = switch (tac.op) {
            .label => true,
            else => false,
        };

        if (is_label) leaders.set(i);

        if (is_branch and i + 1 < stream.len)
            leaders.set(i + 1);
    }

    var label_to_block = std.AutoHashMap(usize, usize).init(alloc);
    defer label_to_block.deinit();

    var block_start: usize = 0;
    for (1..stream.len + 1) |i| {
        const at_end = i == stream.len;
        const at_leader = !at_end and leaders.isSet(i);

        if (at_end or at_leader) {
            const block_idx = cfg.blocks.items.len;
            try cfg.blocks.append(alloc, .{
                .instructions = stream[block_start..i],
            });

            const first = stream[block_start];
            if (first.op == .label) {
                const lbl = first.op.label;
                try label_to_block.put(lbl, block_idx);
            }

            block_start = i;
        }
    }

    for (cfg.blocks.items, 0..) |*bb, block_idx| {
        if (bb.instructions.len == 0) continue;
        const last = bb.instructions[bb.instructions.len - 1];

        switch (last.op) {
            .goto => {
                const target_lbl = last.arg1.int;
                if (label_to_block.get(target_lbl)) |target_idx|
                    try bb.connections.append(alloc, target_idx);
            },
            .if_true_goto, .if_false_goto => {
                if (block_idx + 1 < cfg.blocks.items.len)
                    try bb.connections.append(alloc, block_idx + 1);

                const target_lbl = last.arg2.int;
                if (label_to_block.get(target_lbl)) |target_idx|
                    try bb.connections.append(alloc, target_idx);
            },
            .return_something => {},
            else => {
                if (block_idx + 1 < cfg.blocks.items.len)
                    try bb.connections.append(alloc, block_idx + 1);
            },
        }
    }

    for (cfg.blocks.items, 0..) |*bb, block_idx| {
        for (bb.connections.items) |succ_idx| {
            try cfg.blocks.items[succ_idx].predecessors.append(alloc, block_idx);
        }
    }

    return cfg;
}
