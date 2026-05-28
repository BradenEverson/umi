//! Walks the AST to translate into an IR,
//! using three address codes (TAC!)

const std = @import("std");
const Allocator = std.mem.Allocator;

const parser = @import("parser.zig");
const TopLevel = parser.TopLevel;
const Literal = parser.Literal;
const BinaryOp = parser.BinaryOp;
const Type = @import("type.zig").Type;

pub const IrError = std.mem.Allocator.Error;

pub const Temp = usize;

/// The Top Level with functions translated to IR,
/// neither fields are owned and should be deinit-ed
/// separately
pub const IrTopLevel = struct {
    types: std.StringHashMapUnmanaged(Type) =
        .empty,
    ir: ProgramIR,
};

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
    instructions: std.ArrayList(Instruction) =
        .empty,
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

    pub fn deinit(
        ir: *ProgramIR,
        alloc: Allocator,
    ) void {
        ir.functions.deinit(alloc);
    }
};

pub fn genIr(
    alloc: Allocator,
    tl: *TopLevel,
) IrError!ProgramIR {
    var program: ProgramIR = .{};
    var functions = tl.functions.iterator();

    while (functions.next()) |function| {
        const function_ir =
            try translateFunction(
                alloc,
                tl,
                function.value_ptr,
            );

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
    tl: *TopLevel,
    function: *parser.Function,
) IrError!FunctionIR {
    const f: FunctionIR = .{};

    for (function.body.ast.items) |expr|
        try exprToIr(alloc, expr, tl);

    return f;
}

pub fn exprToIr(
    alloc: Allocator,
    expr: *parser.Expr,
    tl: *TopLevel,
) IrError!void {
    _ = alloc;
    _ = expr;
    _ = tl;
}
