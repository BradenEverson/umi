//! Register allocation using linear scan

const std = @import("std");
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const parser = @import("parser.zig");
const TopLevel = parser.TopLevel;
const Function = parser.Function;

const ir = @import("ir.zig");
const FunctionIR = ir.FunctionIR;
const ThreeAddressCode = ir.ThreeAddressCode;
const Operand = ir.Operand;

const arch = @import("arch.zig");

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

    pub fn init(
        alloc: Allocator,
        ri: *const arch.RegisterInfo,
        func: *const Function,
    ) Allocator.Error!StackFrame {
        var sf: StackFrame = .{};
        errdefer sf.deinit(alloc);

        _ = ri;
        _ = func;

        return sf;
    }
};

pub const AllocatedFunction = struct {
    layout: StackFrame = .{},
};

pub const RegAllocError = Allocator.Error;

pub fn regAlloc(
    target: arch.Arch,
    alloc: Allocator,
    tl: *TopLevel,
) RegAllocError!void {
    _ = arch.registerInfo(target);
    _ = alloc;
    _ = tl;
}

pub fn regAllocFunction(
    ri: *const arch.RegisterInfo,
    alloc: Allocator,
    fir: FunctionIR,
) RegAllocError!AllocatedFunction {
    _ = ri;
    _ = alloc;
    _ = fir;

    return RegAllocError.OutOfMemory;
}
