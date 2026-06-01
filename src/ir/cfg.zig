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
