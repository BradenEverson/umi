//! The core Umi language spec :)

const std = @import("std");
const Io = std.Io;

pub const tokenizer = @import("tokenizer.zig");
pub const parser = @import("parser.zig");
pub const compiler = @import("compiler.zig");
pub const semantic_analysis =
    @import("semantic_analysis.zig");
pub const types = @import("type.zig");
pub const optimizer = @import("optimizer.zig");
pub const ir_gen = @import("ir.zig");
pub const reg_alloc = @import("reg_alloc.zig");

test {
    _ = @import("compiler.zig");
    _ = @import("ir.zig");
    _ = @import("optimizer.zig");
    _ = @import("parser.zig");
    _ = @import("tokenizer.zig");
    _ = @import("semantic_analysis.zig");
    _ = @import("vm.zig");
    _ = @import("type.zig");
    _ = @import("reg_alloc.zig");
}
