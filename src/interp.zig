//! Just a good ol' tree walkin' interpreter for early tests

const std = @import("std");
const Allocator = std.mem.Allocator;

const parser = @import("parser.zig");
const TopLevel = parser.TopLevel;

pub fn interpret(tl: *TopLevel) !void {
    _ = tl;
}
