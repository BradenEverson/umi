//! Architecture dependent information like how many registers,
//! what they do, word size, you get the jist

pub const x86_64 = @import("arch/x86_64.zig");

pub const Arch = enum {
    x86_64,
};

pub const Reg = enum {
    rax,
    rbx,
    rcx,
    rdx,
    rsi,
    rdi,
    rbp,
    rsp,
    r8,
    r9,
    r10,
    r11,
    r12,
    r13,
    r14,
    r15,
};

pub const RegisterInfo = struct {
    allocatable: []const Reg,
    callee_saved: []const Reg,
    arg_registers: []const Reg,
    return_register: Reg,
    stack_pointer: Reg,
    frame_pointer: Reg,
    scratch: []const Reg,
    word_size: u64,
};

const X86_64_INFO: RegisterInfo = .{
    .allocatable = &.{
        .rcx, .rsi, .rdi, .r8,  .r9,  .r10,
        .rbx, .r12, .r13, .r14, .r15,
    },
    .callee_saved = &.{ .rbx, .r12, .r13, .r14, .r15 },
    .arg_registers = &.{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 },
    .return_register = .rax,
    .stack_pointer = .rsp,
    .frame_pointer = .rbp,
    .scratch = &.{ .rax, .rdx, .r11 },
    .word_size = 8,
};

pub fn registerInfo(arch: Arch) *const RegisterInfo {
    return switch (arch) {
        .x86_64 => &X86_64_INFO,
    };
}

test {
    _ = @import("arch/x86_64.zig");
}
