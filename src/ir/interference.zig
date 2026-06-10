//! An interference graph for overlapping temporaries/variables

const std = @import("std");

pub const Value = union(enum) {
    variable: []const u8,
    temporary: usize,

    pub fn eql(a: Value, b: Value) bool {
        return switch (a) {
            .variable => |n| b == .variable and std.mem.eql(u8, n, b.variable),
            .temporary => |i| b == .temporary and i == b.temporary,
        };
    }

    pub fn format(
        v: Value,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (v) {
            .variable => |n| try writer.print("{s}", .{n}),
            .temporary => |i| try writer.print("t{}", .{i}),
        }
    }
};
