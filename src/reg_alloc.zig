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
const CFG = ir.ControlFlowGraph;
const InterferenceGraph = ir.InterferenceGraph;

const arch = @import("arch.zig");

pub const StackFrame = struct {
    /// Holds the stack offset to all local and parameter
    /// variables
    variables: std.StringHashMapUnmanaged(usize) = .{},
    size: usize = 0,

    pub fn deinit(
        sf: *StackFrame,
        alloc: Allocator,
    ) void {
        sf.variables.deinit(alloc);
    }

    pub fn init(
        tl: *TopLevel,
        alloc: Allocator,
        ri: *const arch.RegisterInfo,
        func: *const Function,
    ) Allocator.Error!StackFrame {
        var sf: StackFrame = .{};
        errdefer sf.deinit(alloc);

        _ = tl;
        _ = ri;
        _ = func;

        // TODO: Based on the type of the
        // variable/parameter, need to allocate
        // more space on the stack for it

        return sf;
    }
};

pub const AllocatedFunction = struct {
    layout: StackFrame = .{},
};

pub const RegAllocError = Allocator.Error;

pub fn regAlloc(
    alloc: Allocator,
    tl: *TopLevel,
    target: arch.Arch,
    cfg: *
) RegAllocError!void {
    const ri = arch.registerInfo(target);
    _ = ri;
    _ = alloc;

    var functions = tl.ir.functions.iterator();
    while (functions.next()) |function| {
        try liveAnalysis(function.value_ptr);

        // _ = try regAllocFunction(
        //     ri,
        //     alloc,
        //     function.value_ptr,
        // );
    }
}

// pub fn liveAnalysis(
//     function: *FunctionIR,
// ) RegAllocError!void {
//     // TODO: This only goes forwards, after some research
//     // it looks like we need iterative dataflow analysis
//     // to handle things like loops and such
//     //
//     // https://www.cs.princeton.edu/courses/archive/spr03/cs320/notes/analysis2.pdf
//     for (0..function.instructions.items.len) |i| {
//         const curr = function.instructions.items[i];
//         var last_dep = i;
//
//         for (i..function.instructions.items.len) |j| {
//             const check = function.instructions.items[j];
//             if (curr.op == .assignment) {
//                 const variable = curr.arg1.variable;
//
//                 if (check.arg1.depOnVar(variable) or
//                     check.arg2.depOnVar(variable))
//                 {
//                     last_dep = j;
//                 }
//             } else if (check.arg1.depOn(i) or
//                 check.arg2.depOn(i))
//             {
//                 last_dep = j;
//             }
//         }
//
//         function.instructions.items[i].last_dep = last_dep;
//     }
// }

pub fn regAllocFunction(
    ri: *const arch.RegisterInfo,
    alloc: Allocator,
    function: *const FunctionIR,
) RegAllocError!AllocatedFunction {
    _ = ri;
    _ = alloc;
    _ = function;

    return RegAllocError.OutOfMemory;
}
