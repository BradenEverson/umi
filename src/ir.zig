//! Walks the AST to translate into an IR, using three address codes (TAC!)

const std = @import("std");
const Allocator = std.mem.Allocator;

const parser = @import("parser.zig");
const TopLevel = parser.TopLevel;
const Literal = parser.Literal;
const BinaryOp = parser.BinaryOp;

pub const Temp = u32;

pub const Operand = union(enum) {
    temp: Temp,
    literal: Literal,
    variable: []const u8,
};

pub const Instruction = union(enum) {
    bin_op: struct {
        dest: Temp,
        lhs: Operand,
        op: BinaryOp,
        rhs: Operand,
    },
    copy: struct { dest: Temp, src: Operand },
    ret: struct { val: Operand },
    call: struct {
        dest: ?Temp,
        name: []const u8,
        args: std.ArrayList(Operand),
    },
};

pub const FunctionIR = struct {
    instructions: std.ArrayList(Instruction),
    temp_count: Temp = 0,

    pub fn freshTemp(self: *FunctionIR) Temp {
        defer self.temp_count += 1;
        return self.temp_count;
    }
};

pub const ProgramIR = struct {
    functions: std.StringHashMapUnmanaged(
        FunctionIR,
    ) = .empty,
};

pub fn genIr(
    alloc: Allocator,
    tl: *TopLevel,
) !ProgramIR {
    _ = alloc;
    _ = tl;
}
