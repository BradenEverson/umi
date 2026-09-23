//! Type based sizing, layout, padding, all that hubbub

const std = @import("std");

const parser = @import("parser.zig");
const TopLevel = parser.TopLevel;

const types = @import("type.zig");
const Type = types.Type;
const StructDef = types.StructDef;

const RegisterInfo = @import("arch.zig").RegisterInfo;

pub const Layout = struct {
    size: u64,
    alignment: u64,
};

/// Where a value of this type can live during register allocation.
pub const RegClass = enum {
    /// Fits in one general purpose register
    gpr,
    /// Fits in one SSE register
    fpr,
    /// Lives in the stack, load through a good ol ptr
    memory,
    none,
};

pub const LayoutError = error{UnknownType};

pub fn alignForward(x: u64, a: u64) u64 {
    return (x + a - 1) / a * a;
}

pub fn layoutOf(
    tl: *TopLevel,
    ri: *const RegisterInfo,
    ty: Type,
) LayoutError!Layout {
    return switch (ty) {
        .its_void, .its_a_comptime_number => .{ .size = 0, .alignment = 1 },
        .its_a_bool => .{ .size = 1, .alignment = 1 },
        .its_an_int => |i| intLayout(i.bits, ri),
        .its_a_float => |f| switch (f) {
            .float16 => .{ .size = 2, .alignment = 2 },
            .float32 => .{ .size = 4, .alignment = 4 },
            .float64 => .{ .size = 8, .alignment = 8 },
        },
        .its_a_pointer => .{ .size = ri.word_size, .alignment = ri.word_size },
        .slice => .{ .size = 2 * ri.word_size, .alignment = ri.word_size },
        .array => |a| blk: {
            const elem = try layoutOf(tl, ri, a.ty.*);
            break :blk .{ .size = elem.size * a.count, .alignment = elem.alignment };
        },
        .its_a_struct => |s| placeFields(tl, ri, s.attributes.values(), null),
    };
}

fn intLayout(bits: u16, ri: *const RegisterInfo) Layout {
    if (bits == 0) return .{ .size = 0, .alignment = 1 };
    const bytes = std.math.ceilPowerOfTwoAssert(u64, (@as(u64, bits) + 7) / 8);
    return .{ .size = bytes, .alignment = @min(bytes, ri.word_size) };
}

pub const StructLayout = struct {
    layout: Layout,
    offsets: []u64,

    pub fn deinit(sl: *StructLayout, alloc: std.mem.Allocator) void {
        alloc.free(sl.offsets);
    }
};

pub fn structLayout(
    alloc: std.mem.Allocator,
    tl: *TopLevel,
    ri: *const RegisterInfo,
    s: StructDef,
) (LayoutError || std.mem.Allocator.Error)!StructLayout {
    const field_types = s.attributes.values();
    const offsets = try alloc.alloc(u64, field_types.len);
    errdefer alloc.free(offsets);

    return .{
        .layout = try placeFields(tl, ri, field_types, offsets),
        .offsets = offsets,
    };
}

fn placeFields(
    tl: *TopLevel,
    ri: *const RegisterInfo,
    field_types: []const []const u8,
    offsets: ?[]u64,
) LayoutError!Layout {
    var off: u64 = 0;
    var max_align: u64 = 1;

    for (field_types, 0..) |ty_name, i| {
        const field_ty = tl.getType(ty_name) orelse return error.UnknownType;
        const fl = try layoutOf(tl, ri, field_ty);

        off = alignForward(off, fl.alignment);
        if (offsets) |o| o[i] = off;
        off += fl.size;
        max_align = @max(max_align, fl.alignment);
    }

    return .{ .size = alignForward(off, max_align), .alignment = max_align };
}

pub fn regClass(ri: *const RegisterInfo, ty: Type) RegClass {
    return switch (ty) {
        .its_void => .none,
        .its_a_comptime_number => .gpr,
        .its_a_bool, .its_a_pointer => .gpr,
        .its_an_int => |i| if (i.bits <= ri.word_size * 8) .gpr else .memory,
        .its_a_float => .fpr,
        .slice, .array, .its_a_struct => .memory,
    };
}
