//! The core Umi language spec :)

const std = @import("std");
const Io = std.Io;

pub const tokenizer = @import("tokenizer.zig");
pub const parser = @import("parser.zig");
pub const compiler = @import("compiler.zig");

test {
    _ = @import("compiler.zig");
    _ = @import("ir.zig");
    _ = @import("optimizer.zig");
    _ = @import("parser.zig");
    _ = @import("tokenizer.zig");
    _ = @import("vm.zig");
}
