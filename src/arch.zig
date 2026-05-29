//! Architecture dependent information like how many registers,
//! what they do, word size, you get the jist

pub const Arch = enum {
    x86_64,
};

pub const RegisterInfo = struct {
    general_purpose: []const []const u8,
    arg_registers: []const []const u8,
    return_register: []const u8,
    stack_pointer: []const u8,
    frame_pointer: []const u8,
    word_size: usize,
};

const X86_64_INFO: RegisterInfo = .{
    .general_purpose = &[_][]const u8{
        "rax", "rcx", "rdx", "rsi", "rdi",
        "r8",  "r9",  "r10", "r11", "rbx",
        "r12", "r13", "r14", "r15",
    },
    .arg_registers = &[_][]const u8{
        "rdi", "rsi", "rdx", "rcx", "r8", "r9",
    },
    .return_register = "rax",
    .stack_pointer = "rsp",
    .frame_pointer = "rbp",
    .word_size = 8,
};

pub fn registerInfo(arch: Arch) *const RegisterInfo {
    return switch (arch) {
        .x86_64 => &X86_64_INFO,
    };
}
