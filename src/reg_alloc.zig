//! Register allocation using linear scan

const std = @import("std");
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const ir = @import("ir.zig");
const IrTopLevel = ir.IrTopLevel;
const FunctionIR = ir.FunctionIR;
const ThreeAddressCode = ir.ThreeAddressCode;
const Operand = ir.Operand;

const compiler = @import("compiler.zig");

fn dependsOn(code: ThreeAddressCode, op: Operand) bool {
    return std.mem.eql(Operand, code.arg1, op) or
        std.mem.eql(Operand, code.arg2, op);
}

pub const StackFrame = struct {
    /// Holds the stack offset to all local and parameter
    /// variables
    variables: std.StringHashMapUnmanaged(usize) = .{},
    size: usize = 0,

    pub fn deinit(sf: *StackFrame, alloc: Allocator) void {
        sf.variables.deinit(alloc);
    }
};

pub const AllocatedFunction = struct {
    layout: StackFrame = .{},
};

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
