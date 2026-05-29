//! Register allocation using linear scan

const std = @import("std");
const Allocator = std.mem.Allocator;

const ir = @import("ir.zig");
const IrTopLevel = ir.IrTopLevel;
const FunctionIR = ir.FunctionIR;
const ThreeAddressCode = ir.ThreeAddressCode;
const Operand = ir.Operand;

fn dependsOn(code: ThreeAddressCode, op: Operand) bool {
    return std.mem.eql(Operand, code.arg1, op) or
        std.mem.eql(Operand, code.arg2, op);
}

pub const RegAllocError = Allocator.Error;

pub fn regAlloc(
    alloc: Allocator,
    irtl: *IrTopLevel,
) RegAllocError!void {
    _ = alloc;
    _ = irtl;
}

pub fn regAllocFunction(
    alloc: Allocator,
    fir: FunctionIR,
) RegAllocError!void {
    _ = alloc;
    _ = fir;
}
