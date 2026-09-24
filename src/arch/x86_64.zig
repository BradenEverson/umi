//! x86-64 codegen :D

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const parser = @import("../parser.zig");
const TopLevel = parser.TopLevel;

const ir = @import("../ir.zig");
const TAC = ir.ThreeAddressCode;
const Operand = ir.Operand;

const arch = @import("../arch.zig");
const Reg = arch.Reg;

const reg_alloc = @import("../reg_alloc.zig");

pub const CodegenError = Allocator.Error || Writer.Error || error{
    UnsupportedOperand,
    TooManyArguments,
    UnallocatedValue,
    NonConstantInitializer,
};

fn evalConstExpr(e: *parser.Expr) CodegenError!i64 {
    return switch (e.*) {
        .literal => |l| switch (l) {
            .boolean => |b| @intFromBool(b),
            .int => |i| i,
            .uint => |u| @bitCast(u),
            .float => error.UnsupportedOperand,
        },
        .unary_op => |u| blk: {
            const v = try evalConstExpr(u.expr);
            break :blk switch (u.op) {
                .neg => -v,
                .not => @intFromBool(v == 0),
            };
        },
        .binary_op => |b| blk: {
            const l = try evalConstExpr(b.left);
            const r = try evalConstExpr(b.right);
            break :blk switch (b.op) {
                .add => l +% r,
                .sub => l -% r,
                .mul => l *% r,
                .div => @divTrunc(l, r),
                .lt => @intFromBool(l < r),
                .gt => @intFromBool(l > r),
                .eq => @intFromBool(l == r),
            };
        },
        else => error.NonConstantInitializer,
    };
}

/// A machine operand
const Opnd = union(enum) {
    reg: Reg,
    mem: i32,
    imm: i64,
    global: []const u8,

    pub fn format(o: Opnd, w: *Writer) Writer.Error!void {
        switch (o) {
            .reg => |r| try w.writeAll(@tagName(r)),
            .mem => |off| try w.print(
                "qword ptr [rbp {s} {d}]",
                .{ if (off < 0) "-" else "+", @abs(off) },
            ),
            .global => |s| try w.print("qword ptr [rip + {s}]", .{s}),
            .imm => |i| try w.print("{d}", .{i}),
        }
    }

    fn fitsImm32(o: Opnd) bool {
        return o == .imm and std.math.cast(i32, o.imm) != null;
    }

    fn isReg(o: Opnd, r: Reg) bool {
        return o == .reg and o.reg == r;
    }

    fn isMem(o: Opnd) bool {
        return o == .mem or o == .global;
    }
};

const r11: Opnd = .{ .reg = .r11 };
const rax: Opnd = .{ .reg = .rax };

const Gen = struct {
    w: *Writer,
    ri: *const arch.RegisterInfo,
    af: *const reg_alloc.AllocatedFunction,
    fn_name: []const u8,

    fn ins(g: *Gen, comptime fmt: []const u8, args: anytype) Writer.Error!void {
        try g.w.print("    " ++ fmt ++ "\n", args);
    }

    fn loc(g: *Gen, op: Operand) CodegenError!Opnd {
        switch (op) {
            .literal => |l| return .{ .imm = switch (l) {
                .boolean => |b| @intFromBool(b),
                .int => |i| i,
                .uint => |u| @bitCast(u),
                .float => return error.UnsupportedOperand,
            } },
            .global => |name| return .{ .global = name },
            .reference, .variable => {
                const v = g.af.vregs.of(op).?;
                return switch (g.af.locs[v]) {
                    .none => error.UnallocatedValue,
                    .reg => |r| .{ .reg = r },
                    .stack => |off| .{ .mem = off },
                };
            },
            else => return error.UnsupportedOperand,
        }
    }

    fn dst(g: *Gen, v: usize) ?Opnd {
        return switch (g.af.locs[v]) {
            .none => null,
            .reg => |r| .{ .reg = r },
            .stack => |off| .{ .mem = off },
        };
    }

    fn move(g: *Gen, to: Opnd, from: Opnd) Writer.Error!void {
        if (std.meta.eql(to, from)) return;
        const via_r11 = to.isMem() and
            (from.isMem() or (from == .imm and !from.fitsImm32()));
        if (via_r11) {
            try g.ins("mov r11, {f}", .{from});
            try g.ins("mov {f}, r11", .{to});
        } else {
            try g.ins("mov {f}, {f}", .{ to, from });
        }
    }

    fn aluSrc(g: *Gen, o: Opnd) Writer.Error!Opnd {
        if (o == .imm and !o.fitsImm32()) {
            try g.move(rax, o);
            return rax;
        }
        return o;
    }

    fn binary(g: *Gen, op: parser.BinaryOp, dst_opt: ?Opnd, a: Opnd, b: Opnd) CodegenError!void {
        const d = dst_opt orelse return; // dead & pure: drop it

        switch (op) {
            .add, .sub, .mul => {
                const work: Opnd = if (d == .reg and !b.isReg(d.reg)) d else r11;
                try g.move(work, a);
                const src = try g.aluSrc(b);
                switch (op) {
                    .add => try g.ins("add {f}, {f}", .{ work, src }),
                    .sub => try g.ins("sub {f}, {f}", .{ work, src }),
                    .mul => if (src == .imm)
                        try g.ins("imul {f}, {f}, {f}", .{ work, work, src })
                    else
                        try g.ins("imul {f}, {f}", .{ work, src }),
                    else => unreachable,
                }
                try g.move(d, work);
            },
            .div => {
                try g.move(rax, a);
                try g.ins("cqo", .{});
                const divisor = if (b == .imm) blk: {
                    try g.move(r11, b);
                    break :blk r11;
                } else b;
                try g.ins("idiv {f}", .{divisor});
                try g.move(d, rax);
            },
            .lt, .gt, .eq => {
                try g.move(r11, a);
                try g.ins("cmp r11, {f}", .{try g.aluSrc(b)});
                const cc = switch (op) {
                    .lt => "l",
                    .gt => "g",
                    .eq => "e",
                    else => unreachable,
                };
                try g.ins("set{s} al", .{cc});
                try g.ins("movzx eax, al", .{});
                try g.move(d, rax);
            },
        }
    }

    fn unary(g: *Gen, op: parser.UnaryOp, dst_opt: ?Opnd, a: Opnd) CodegenError!void {
        const d = dst_opt orelse return;
        const work: Opnd = if (d == .reg) d else r11;
        try g.move(work, a);
        switch (op) {
            .neg => try g.ins("neg {f}", .{work}),
            .not => try g.ins("xor {f}, 1", .{work}),
        }
        try g.move(d, work);
    }

    fn instr(g: *Gen, tac: TAC, idx: usize) CodegenError!void {
        switch (tac.op) {
            .label => |l| try g.w.print(".L{d}:\n", .{l}),

            .goto => try g.ins("jmp .L{d}", .{tac.arg1.int}),

            .if_true_goto, .if_false_goto => {
                const cond = try g.loc(tac.arg1);
                const target = tac.arg2.int;
                const on_true = tac.op == .if_true_goto;

                if (cond == .imm) { // folded condition
                    if ((cond.imm != 0) == on_true)
                        try g.ins("jmp .L{d}", .{target});
                    return;
                }
                try g.ins("cmp {f}, 0", .{cond});
                try g.ins("{s} .L{d}", .{ if (on_true) "jne" else "je", target });
            },

            .binary_op => |op| try g.binary(
                op,
                g.dst(idx),
                try g.loc(tac.arg1),
                try g.loc(tac.arg2),
            ),

            .unary_op => |op| try g.unary(op, g.dst(idx), try g.loc(tac.arg1)),

            .assignment => {
                if (tac.arg1 == .global) {
                    try g.move(.{ .global = tac.arg1.global }, try g.loc(tac.arg2));
                } else {
                    const v = g.af.vregs.of(tac.arg1).?;
                    if (g.dst(v)) |d| try g.move(d, try g.loc(tac.arg2));
                }
            },

            .load_arg => {
                const src = try g.loc(tac.arg2);
                if (src == .imm and !src.fitsImm32()) {
                    try g.move(r11, src);
                    try g.ins("push r11", .{});
                } else {
                    try g.ins("push {f}", .{src});
                }
            },

            .call_fn => {
                const argc = tac.arg2.int;
                if (argc > g.ri.arg_registers.len) return error.TooManyArguments;

                var k = argc;
                while (k > 0) {
                    k -= 1;
                    try g.ins("pop {s}", .{@tagName(g.ri.arg_registers[k])});
                }
                try g.ins("call {s}", .{tac.arg1.fn_name});
                if (g.dst(idx)) |d| try g.move(d, rax);
            },

            .return_something => {
                if (tac.arg1 != .unused) try g.move(rax, try g.loc(tac.arg1));
                try g.ins("jmp .Lret_{s}", .{g.fn_name});
            },
        }
    }
};

fn emitGlobals(w: *Writer, tl: *TopLevel) CodegenError!void {
    var consts = tl.global_consts.iterator();
    while (consts.next()) |entry| {
        const val = try evalConstExpr(entry.value_ptr.*);
        try w.print(".section .rodata\n.p2align 3\n{s}:\n    .quad {d}\n", .{ entry.key_ptr.*, val });
    }

    var vars = tl.global_variables.iterator();
    while (vars.next()) |entry| {
        const val = try evalConstExpr(entry.value_ptr.*);
        if (val == 0) {
            try w.print(".bss\n.p2align 3\n{s}:\n    .zero 8\n", .{entry.key_ptr.*});
        } else {
            try w.print(".data\n.p2align 3\n{s}:\n    .quad {d}\n", .{ entry.key_ptr.*, val });
        }
    }
}

pub fn emitFunction(
    alloc: Allocator,
    w: *Writer,
    ri: *const arch.RegisterInfo,
    name: []const u8,
    func: *const parser.Function,
    fir: *const ir.FunctionIR,
) CodegenError!void {
    const np = func.parameters.items.len;
    if (np > ri.arg_registers.len) return error.TooManyArguments;

    var af = try reg_alloc.regAllocFunction(alloc, ri, func, fir);
    defer af.deinit(alloc);

    var g: Gen = .{ .w = w, .ri = ri, .af = &af, .fn_name = name };

    try w.print("\n.globl {s}\n{s}:\n", .{ name, name });
    try g.ins("push rbp", .{});
    try g.ins("mov rbp, rsp", .{});
    for (af.callee_saved_used.items) |r| try g.ins("push {s}", .{@tagName(r)});
    const sub = af.frame.subAmount();
    if (sub > 0) try g.ins("sub rsp, {d}", .{sub});

    for (ri.arg_registers[0..np]) |r| try g.ins("push {s}", .{@tagName(r)});
    var k = np;
    while (k > 0) {
        k -= 1;
        switch (af.locs[af.vregs.param(k)]) {
            .none => try g.ins("pop r11", .{}),
            .reg => |r| try g.ins("pop {s}", .{@tagName(r)}),
            .stack => |off| try g.ins("pop {f}", .{Opnd{ .mem = off }}),
        }
    }

    for (fir.instructions.items, 0..) |tac, idx| try g.instr(tac, idx);

    try w.print(".Lret_{s}:\n", .{name});
    try g.ins("lea rsp, [rbp - {d}]", .{af.frame.saved_size});
    var i = af.callee_saved_used.items.len;
    while (i > 0) {
        i -= 1;
        try g.ins("pop {s}", .{@tagName(af.callee_saved_used.items[i])});
    }
    try g.ins("pop rbp", .{});
    try g.ins("ret", .{});
}

pub fn emitProgram(
    alloc: Allocator,
    w: *Writer,
    tl: *TopLevel,
    target: arch.Arch,
) CodegenError!void {
    const ri = arch.registerInfo(target);

    try w.writeAll(".intel_syntax noprefix\n");
    try emitGlobals(w, tl);
    try w.writeAll(".text\n");

    var it = tl.ir.functions.iterator();
    while (it.next()) |entry| {
        const func = tl.functions.getPtr(entry.key_ptr.*).?;
        try emitFunction(alloc, w, ri, entry.key_ptr.*, func, entry.value_ptr);
    }

    try w.writeAll(".section .note.GNU-stack,\"\",@progbits\n");
}
