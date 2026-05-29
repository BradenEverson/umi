//! Register allocation using linear scan

const std = @import("std");
const Allocator = std.mem.Allocator;

const ir = @import("ir.zig");
const IrTopLevel = ir.IrTopLevel;
const FunctionIR = ir.FunctionIR;
const ThreeAddressCode = ir.ThreeAddressCode;
const Operand = ir.Operand;

const InstructionWithContext = struct {
    instr: ThreeAddressCode,
    last_instr_dep: usize,
};

fn dependsOn(code: ThreeAddressCode, op: Operand) bool {
    return std.mem.eql(Operand, code.arg1, op) or
        std.mem.eql(Operand, code.arg2, op);
}

pub const RegAllocError = Allocator.Error;

pub fn regAlloc(alloc: Allocator, fir: FunctionIR) RegAllocError!void {
    const context = try alloc.alloc(
        InstructionWithContext,
        fir.instructions.items.len,
    );
    defer alloc.free(context);

    for (0..context.len) |i| {
        context[i].instr = fir.instructions.items[i];
        var last_instr_dep = i;

        for (i..context.len) |j| {
            last_instr_dep = j;
        }

        context[i].last_instr_dep = last_instr_dep;
    }
}
