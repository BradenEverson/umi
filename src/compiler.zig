//! Translating our optimized IR into a target,
//! possibly LLVM IR or raw machine code based
//! on the target set here

pub const Arch = enum {
    x86_64,
};

/// How many function parameters go to registers
/// before spilling to the stack
pub fn paramConvention(arch: Arch) usize {
    return switch (arch) {
        .x86_64 => 6,
    };
}

/// Word size by architecture
pub fn wordSize(arch: Arch) usize {
    return switch (arch) {
        .x86_64 => 8,
    };
}

const X86_64_REGISTERS: [][]const u8 = &[_][]const u8{
    "rax",
    "rbx",
    "rcx",
    "rdx",
    "rsi",
    "rdi",
    "rbp",
    "rsp",
    "r8",
    "r9",
    "r10",
    "r11",
    "r12",
    "r13",
    "r14",
    "r15",
};

/// Register count and names by architecture
pub fn registers(arch: Arch) [][]const u8 {
    return switch (arch) {
        .x86_64 => X86_64_REGISTERS,
    };
}
