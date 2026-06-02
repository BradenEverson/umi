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

    pub fn deinit(bb: *BasicBlock, alloc: Allocator) void {
        bb.connections.deinit(alloc);
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

    var i: usize = 0;
    var j: usize = 1;
    while (j < stream.len) {
        if (isLeader(stream, j)) {
            const bb = BasicBlock{
                .instructions = stream[i..j],
            };
            i = j;

            try cfg.blocks.append(alloc, bb);
        }
        j += 1;
    }

    const bb = BasicBlock{
        .instructions = stream[i..],
    };
    try cfg.blocks.append(alloc, bb);

    // TODO: Now we need to get all of the connections

    return cfg;
}
