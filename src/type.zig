//! Type system structs and methods

const std = @import("std");
const Allocator = std.mem.Allocator;

const IntDef = struct {
    signed: enum { signed, unsigned },
    bits: u16,
};

pub const Type = union(enum) {
    its_a_struct: StructDef,
    its_an_int: IntDef,
    its_void,
    its_bool,
    slice: *Type,
    array: struct { ty: *Type, count: usize },

    pub fn deinit(t: *Type, alloc: Allocator) void {
        switch (t.*) {
            .its_a_struct => |*s| s.deinit(alloc),

            .slice => |slice_type| {
                slice_type.deinit(alloc);
                alloc.destroy(slice_type);
            },

            .array => |arr| {
                arr.ty.deinit(alloc);
                alloc.destroy(arr.ty);
            },

            else => {},
        }
    }
};

pub const StructDef = struct {
    attributes: std.StringHashMapUnmanaged([]const u8) = .empty,

    pub fn deinit(s: *StructDef, alloc: Allocator) void {
        s.attributes.deinit(alloc);
    }
};
