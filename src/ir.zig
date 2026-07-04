//! Walks the AST to translate into an IR,
//! using three address codes (TAC!)

const std = @import("std");
const Allocator = std.mem.Allocator;

const parser = @import("parser.zig");
const TopLevel = parser.TopLevel;
const Literal = parser.Literal;
const BinaryOp = parser.BinaryOp;
const UnaryOp = parser.UnaryOp;

pub const ControlFlowGraph = @import("ir/cfg.zig");

const Type = @import("type.zig").Type;

pub const IrError = std.mem.Allocator.Error;

pub const Temp = usize;

var label: usize = 0;

fn nextLabel() usize {
    defer label += 1;
    return label;
}

pub const Operand = union(enum) {
    reference: Temp,
    literal: Literal,
    variable: []const u8,
    fn_name: []const u8,
    int: usize,
    unused,

    pub fn depOn(self: Operand, ref: usize) bool {
        return switch (self) {
            .reference => |r| r == ref,
            else => false,
        };
    }

    pub fn depOnVar(
        self: Operand,
        var_name: []const u8,
    ) bool {
        return switch (self) {
            .variable => |v| std.mem.eql(
                u8,
                v,
                var_name,
            ),

            else => false,
        };
    }
};

pub const ThreeAddressCode = struct {
    op: Operator,
    arg1: Operand = .unused,
    arg2: Operand = .unused,

    // Calculated and used during
    // register allocation
    last_dep: usize = 0,
};

pub const Operator = union(enum) {
    binary_op: BinaryOp,
    unary_op: UnaryOp,
    label: usize,

    if_true_goto,
    if_false_goto,
    goto,

    assignment,
    return_something,

    call_fn,
    load_arg,
};

pub const FunctionIR = struct {
    instructions: std.ArrayList(ThreeAddressCode) =
        .empty,
    cfg: ControlFlowGraph = .{},
};

pub const ProgramIR = struct {
    functions: std.StringHashMapUnmanaged(
        FunctionIR,
    ) = .empty,

    pub fn deinit(
        ir: *ProgramIR,
        alloc: Allocator,
    ) void {
        var functions = ir.functions.iterator();
        while (functions.next()) |function|
            function.value_ptr.instructions.deinit(alloc);

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
    var f: FunctionIR = .{};

    for (function.body.ast.items) |expr|
        _ = try exprToIr(alloc, expr, tl, &f);

    return f;
}

pub fn exprToIr(
    alloc: Allocator,
    expr: *parser.Expr,
    tl: *TopLevel,
    function: *FunctionIR,
) IrError!Operand {
    switch (expr.*) {
        .binary_op => |b| {
            const left = try exprToIr(
                alloc,
                b.left,
                tl,
                function,
            );
            const right = try exprToIr(
                alloc,
                b.right,
                tl,
                function,
            );

            const code = ThreeAddressCode{
                .op = .{ .binary_op = b.op },
                .arg1 = left,
                .arg2 = right,
            };
            try function.instructions.append(alloc, code);

            return Operand{
                .reference = function.instructions.items.len - 1,
            };
        },
        .unary_op => |u| {
            const val = try exprToIr(
                alloc,
                u.expr,
                tl,
                function,
            );
            const code = ThreeAddressCode{
                .op = .{ .unary_op = u.op },
                .arg1 = val,
            };
            try function.instructions.append(alloc, code);

            return Operand{
                .reference = function.instructions.items.len - 1,
            };
        },
        .assignment => |a| {
            const val = try exprToIr(
                alloc,
                a.val,
                tl,
                function,
            );

            const code: ThreeAddressCode = .{
                .op = .assignment,
                .arg1 = .{ .variable = a.name },
                .arg2 = val,
            };
            try function.instructions.append(alloc, code);
            return Operand{
                .reference = function.instructions
                    .items.len - 1,
            };
        },
        .construction => |c| {
            const val = try exprToIr(
                alloc,
                c.val,
                tl,
                function,
            );

            const code: ThreeAddressCode = .{
                .op = .assignment,
                .arg1 = .{ .variable = c.name },
                .arg2 = val,
            };
            try function.instructions.append(alloc, code);
            return Operand{
                .reference = function.instructions
                    .items.len - 1,
            };
        },
        .variable => |v| return Operand{ .variable = v },
        .literal => |l| return Operand{ .literal = l },

        .fn_call => |f| {
            for (f.arguments.items, 0..) |arg, i| {
                const val = try exprToIr(
                    alloc,
                    arg,
                    tl,
                    function,
                );

                const load_arg = ThreeAddressCode{
                    .op = .load_arg,
                    .arg1 = .{ .int = i },
                    .arg2 = val,
                };
                try function.instructions.append(alloc, load_arg);
            }

            const fn_call = ThreeAddressCode{
                .op = .call_fn,
                .arg1 = .{ .fn_name = f.name },
                .arg2 = .{ .int = f.arguments.items.len },
            };

            try function.instructions.append(alloc, fn_call);
            return Operand{
                .reference = function.instructions
                    .items.len - 1,
            };
        },

        .return_val => |r| {
            const ret = try exprToIr(alloc, r, tl, function);
            const code: ThreeAddressCode = .{
                .op = .return_something,
                .arg1 = ret,
            };

            try function.instructions.append(alloc, code);
            return Operand{
                .reference = function.instructions
                    .items.len - 1,
            };
        },

        .if_statement => |i| {
            const cond = try exprToIr(alloc, i.cond, tl, function);
            const l = nextLabel();

            const branch = ThreeAddressCode{
                .op = .if_false_goto,
                .arg1 = cond,
                .arg2 = .{ .int = l },
            };

            try function.instructions.append(alloc, branch);

            _ = try exprToIr(alloc, i.if_stuff, tl, function);

            if (i.else_stuff) |el| {
                const l2 = nextLabel();

                try function.instructions.append(
                    alloc,
                    .{ .op = .goto, .arg1 = .{ .int = l2 } },
                );

                try function.instructions.append(
                    alloc,
                    .{ .op = .{ .label = l } },
                );

                _ = try exprToIr(alloc, el, tl, function);

                try function.instructions.append(
                    alloc,
                    .{ .op = .{ .label = l2 } },
                );
            } else {
                try function.instructions.append(
                    alloc,
                    .{ .op = .{ .label = l } },
                );
            }

            return .unused;
        },

        .while_loop => |w| {
            const l1 = nextLabel();
            const l2 = nextLabel();

            try function.instructions.append(
                alloc,
                .{ .op = .{ .label = l1 } },
            );

            const cond = try exprToIr(alloc, w.cond, tl, function);

            const branch = ThreeAddressCode{
                .op = .if_false_goto,
                .arg1 = cond,
                .arg2 = .{ .int = l2 },
            };

            try function.instructions.append(alloc, branch);

            _ = try exprToIr(alloc, w.do_stuff, tl, function);

            try function.instructions.append(
                alloc,
                .{
                    .op = .goto,
                    .arg1 = .{ .int = l1 },
                },
            );

            try function.instructions.append(
                alloc,
                .{ .op = .{ .label = l2 } },
            );

            return .unused;
        },

        .block => |b| {
            for (b.block.items) |ex| {
                _ = try exprToIr(alloc, ex, tl, function);
            }

            return .unused;
        },
    }
}

test {
    _ = @import("ir/cfg.zig");
}
