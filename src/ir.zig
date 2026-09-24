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
pub const liveness = @import("ir/liveness.zig");

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
    global: []const u8,
    fn_name: []const u8,
    int: usize,
    unused,

    pub fn format(
        self: Operand,
        writer: *std.Io.Writer,
    ) !void {
        switch (self) {
            .reference => |t| {
                try writer.print("t{}", .{t});
            },

            .literal => |l| {
                try writer.print("{f}", .{l});
            },

            .variable, .fn_name => |s| {
                try writer.print("{s}", .{s});
            },

            .global => |s| {
                try writer.print("{s}#g", .{s});
            },

            .int => |i| {
                try writer.print("{}", .{i});
            },

            .unused => {},
        }
    }

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

    pub fn format(
        self: ThreeAddressCode,
        writer: *std.Io.Writer,
    ) !void {
        switch (self.op) {
            .binary_op => |b| try writer.print(
                "{f}, {f} {f}",
                .{ b, self.arg1, self.arg2 },
            ),

            .unary_op => |u| try writer.print(
                "{f}, {f}",
                .{ u, self.arg1 },
            ),

            .label => |l| try writer.print(
                "Label {}",
                .{l},
            ),

            .if_true_goto => {
                try writer.print(
                    "GOTO {f} if {f} true",
                    .{ self.arg2, self.arg1 },
                );
            },

            .if_false_goto => {
                try writer.print(
                    "GOTO {f} if {f} false",
                    .{ self.arg2, self.arg1 },
                );
            },

            .goto => {
                try writer.print(
                    "GOTO {f}",
                    .{self.arg1},
                );
            },

            .assignment => {
                try writer.print(
                    "{f} = {f}",
                    .{ self.arg1, self.arg2 },
                );
            },

            .return_something => {
                try writer.print(
                    "RET {f}",
                    .{self.arg1},
                );
            },

            .call_fn => {
                try writer.print(
                    "CALL {f} ({f} args)",
                    .{ self.arg1, self.arg2 },
                );
            },

            .load_arg => {
                try writer.print(
                    "LOAD {f} {f}",
                    .{ self.arg1, self.arg2 },
                );
            },
        }
    }
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

    // load_global,
    // store_global,
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

            var code: ThreeAddressCode = .{
                .op = .assignment,
                .arg1 = .{ .variable = a.name },
                .arg2 = val,
            };

            if (tl.isGlobal(a.name)) {
                code.arg1 = .{ .global = a.name };
                try function.instructions.append(alloc, code);
                return Operand{ .global = a.name };
            } else {
                try function.instructions.append(alloc, code);
                return Operand{ .variable = a.name };
            }
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
            return Operand{ .variable = c.name };
        },
        .variable => |v| {
            if (tl.isGlobal(v)) {
                return Operand{ .global = v };
            } else {
                return Operand{ .variable = v };
            }
        },
        .literal => |l| return Operand{ .literal = l },

        .fn_call => |f| {
            const vals = try alloc.alloc(Operand, f.arguments.items.len);
            defer alloc.free(vals);

            for (f.arguments.items, vals) |arg, *val|
                val.* = try exprToIr(alloc, arg, tl, function);

            for (vals, 0..) |val, i| {
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
    _ = @import("ir/liveness.zig");
}
