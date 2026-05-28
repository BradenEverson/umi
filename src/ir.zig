//! Walks the AST to translate into an IR, using three address codes (TAC!)

const std = @import("std");
const Allocator = std.mem.Allocator;

const parser = @import("parser.zig");
const TopLevel = parser.TopLevel;
const Literal = parser.Literal;
const BinaryOp = parser.BinaryOp;

pub const IrError = std.mem.Allocator.Error;

pub const Temp = usize;

pub const Operand = union(enum) {
    reference: Temp,
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
) IrError!ProgramIR {
    var program: ProgramIR = .{};
    var functions = tl.functions.iterator();

    while (functions.next()) |function| {
        const function_ir =
            try translateFunction(alloc, function.value_ptr);

        try program.functions.put(
            alloc,
            function.key_ptr.*,
            function_ir,
        );
    }

    return program;
}

pub fn translateFunction(
    alloc: Allocator,
    function: *parser.Function,
) IrError!FunctionIR {
    _ = alloc;
    _ = function;
}
