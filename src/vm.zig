//! A VM interpreter so I can feel some dopamine in this project
//! and see a result go through before I have to tackle the
//! big beast that is register allocation and codegen
//!
//! Once regalloc is implemented, I'll then make a VM that's
//! constrained by register count and we can all be happy

const std = @import("std");
const ts = @import("type.zig");
const ir = @import("ir.zig");
const ProgramIr = ir.ProgramIR;
const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    a_struct: std.StringHashMapUnmanaged(Value),
    int: isize,
    uint: usize,
    float: f64,
    a_bool: bool,
    pointer: *Value,
    slice: []Value,

    pub fn deinit(v: *Value, alloc: Allocator) void {
        switch (v.*) {
            .a_struct => |*s| {
                var iter = s.valueIterator();
                while (iter.next()) |si|
                    si.deinit(alloc);
                s.deinit(alloc);
            },
            .pointer => |s| {
                s.deinit(alloc);
                alloc.destroy(s);
            },

            .slice => |s| {
                for (s) |*si| si.deinit(alloc);
                alloc.free(s);
            },
            else => {},
        }
    }
};

pub const VmError = error{NoMain} || Allocator.Error;

registers: std.ArrayList(Value) = .empty,
variables: std.StringHashMapUnmanaged(usize) = .empty,

program: ProgramIr,

const VM = @This();

pub fn deinit(vm: *VM, alloc: Allocator) void {
    for (vm.registers.items) |*item|
        item.deinit(alloc);
    vm.registers.deinit(alloc);
    vm.variables.deinit(alloc);
}

pub fn exec(vm: *VM) VmError!void {
    if (vm.program.functions.get("main")) |main| {
        for (main.instructions.items) |instruction| switch (instruction.op) {
            .binary_op => |b| {
                _ = b;
            },
            .unary_op => |u| {
                _ = u;
            },

            .if_true_goto => {},
            .if_false_goto => {},
            .goto => {},
            .assignment => {},
            .return_something => {},
            .call_fn => {},
            .load_arg => {},

            .label => {},
        };
    } else {
        return VmError.NoMain;
    }
}

pub fn execFn(vm: *VM, f: []const u8) VmError!void {
    _ = vm;
    _ = f;
}
