//! Type system structs and methods

const std = @import("std");
const Allocator = std.mem.Allocator;

const parser = @import("parser.zig");

const IntDef = struct {
    signed: enum { signed, unsigned },
    bits: u16,
};

const FloatDef = enum {
    float16,
    float32,
    float64,
};

pub const TypeCheckError = error{
    BinaryOpTypesDoNotAgree,
    FunctionArgumentsDoNotAgree,
    InvalidOpForType,
};

pub const Type = union(enum) {
    its_a_struct: StructDef,
    its_an_int: IntDef,
    its_a_float: FloatDef,
    // This is for literals that we do not yet constrain to
    // a width or int vs. floatness
    its_a_comptime_number,
    its_void,
    its_a_bool,
    its_a_pointer: *Type,
    slice: *Type,
    array: struct { ty: *Type, count: usize },

    pub fn binaryOpIsValidForType(a: Type, op: parser.BinaryOp) bool {
        switch (op) {
            .sub, .add, .mul, .div, .gt, .lt => switch (a) {
                .its_a_comptime_number,
                .its_an_int,
                .its_a_float,
                => return true,
                .its_a_struct => {
                    // TODO: I like operator overloading,
                    // so once structs can have methods,
                    // maybe we search the method names
                    // for an overloaded operator and
                    // check for that to see if op
                    // is valid.
                    return false;
                },
                else => return false,
            },

            .eq => switch (a) {
                .slice, .array, .its_a_struct => return false,
                else => return true,
            },
        }
    }

    pub fn agreesWith(a: Type, b: Type) TypeCheckError!Type {
        switch (a) {
            .its_a_comptime_number => switch (b) {
                .its_an_int, .its_a_float => return b,
                else => {},
            },
            else => {},
        }

        switch (b) {
            .its_a_comptime_number => switch (a) {
                .its_an_int, .its_a_float => return a,
                else => {},
            },
            else => {},
        }

        if (std.meta.eql(a, b)) {
            return a;
        } else {
            return TypeCheckError.BinaryOpTypesDoNotAgree;
        }
    }

    pub fn deinit(t: *Type, alloc: Allocator) void {
        switch (t.*) {
            .its_a_pointer => |p| {
                p.deinit(alloc);
                alloc.destroy(p);
            },

            .its_a_struct => |*s| s.deinit(alloc),

            .slice => |slice_type| {
                slice_type.deinit(alloc);
                alloc.destroy(slice_type);
            },

            .array => |arr| {
                arr.ty.deinit(alloc);
                alloc.destroy(arr.ty);
            },

            .its_an_int => {},
            .its_a_float => {},
            .its_a_comptime_number => {},
            .its_void => {},
            .its_a_bool => {},
        }
    }
};

pub const StructDef = struct {
    attributes: std.StringHashMapUnmanaged([]const u8) = .empty,

    pub fn deinit(s: *StructDef, alloc: Allocator) void {
        s.attributes.deinit(alloc);
    }
};

pub const VariableDef = struct {
    mutable: bool,
    ty: []const u8,
};
