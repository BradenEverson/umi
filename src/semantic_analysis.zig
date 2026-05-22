//! Name Resolution and Type Checking step

const std = @import("std");
const Allocator = std.mem.Allocator;

const parser = @import("parser.zig");
const TopLevel = parser.TopLevel;
const Expr = parser.Expr;

const ts = @import("type.zig");
const TypeCheckError = ts.TypeCheckError;
const Type = ts.Type;

pub const SemanticAnalysisError = error{
    FunctionDoesNotExist,
    TypeDoesNotExist,
    BinaryTypesDontAgree,
    InvalidFunctionArgumentType,
    VariableAlreadyDefined,
    VariableUsedBeforeDefine,
    ImmutableVariableAssigned,
};

const NameResolveError = SemanticAnalysisError || Allocator.Error;

/// Ensures all named types and functions actually exist in the
/// context
pub fn nameResolution(alloc: Allocator, tl: *TopLevel) NameResolveError!void {
    // First, validate all function bodys, parameters, and return types
    var functions = tl.functions.iterator();
    while (functions.next()) |entry| {
        const function = entry.value_ptr;

        var param_types = function.parameters.iterator();
        while (param_types.next()) |param| {
            if (tl.getType(param.value_ptr.*) == null)
                return SemanticAnalysisError.TypeDoesNotExist;
        }

        // Ensure return type exists:
        if (tl.getType(function.returns) == null)
            return SemanticAnalysisError.TypeDoesNotExist;

        for (function.body.ast.items) |ast| {
            try nameResolveAst(alloc, tl, function, ast);
        }
    }

    // Now we gotta validate all the structure definitions that exist in our
    // top level
    var types = tl.types.iterator();
    while (types.next()) |ty| {
        switch (ty.value_ptr.*) {
            .its_a_struct => |struct_def| {
                var attributes = struct_def.attributes.iterator();
                while (attributes.next()) |attr| {
                    if (tl.getType(attr.value_ptr.*) == null)
                        return SemanticAnalysisError.TypeDoesNotExist;
                }
            },
            else => {},
        }
    }
}

fn nameResolveAst(
    alloc: Allocator,
    tl: *TopLevel,
    function: *parser.Function,
    expr: *const Expr,
) NameResolveError!void {
    switch (expr.*) {
        .return_val => |r| try nameResolveAst(alloc, tl, function, r),
        .construction => |c| {
            try nameResolveAst(alloc, tl, function, c.val);
            if (tl.getType(c.ty) == null)
                return SemanticAnalysisError.TypeDoesNotExist;

            if (function.variableExists(c.name))
                return SemanticAnalysisError.VariableAlreadyDefined;

            try function.variables.put(alloc, c.name, .{
                .mutable = c.mutable,
                .ty = c.ty,
            });
        },
        .assignment => |a| {
            try nameResolveAst(alloc, tl, function, a.val);
            if (!function.variableExists(a.name))
                return SemanticAnalysisError.VariableUsedBeforeDefine;

            const variable = function.variables.get(a.name).?;
            if (!variable.mutable)
                return SemanticAnalysisError.ImmutableVariableAssigned;
        },
        .variable => |v| {
            if (!function.variableExists(v))
                return SemanticAnalysisError.VariableUsedBeforeDefine;
        },
        .binary_op => |b| {
            try nameResolveAst(alloc, tl, function, b.left);
            try nameResolveAst(alloc, tl, function, b.right);
        },
        .unary_op => |u| try nameResolveAst(alloc, tl, function, u.expr),
        .fn_call => |f| {
            if (tl.functions.get(f.name) == null)
                return SemanticAnalysisError.FunctionDoesNotExist;

            for (f.arguments.items) |arg|
                try nameResolveAst(alloc, tl, function, arg);
        },
        .literal => {},
    }
}

pub fn exprEvalsTo(tl: *TopLevel, scope: *parser.Function, expr: *const Expr) TypeCheckError!Type {
    switch (expr.*) {
        // We can safely unwrap these optionals at this point because this
        // is assumed to run after the name resolution. We know these
        // variables all exist and the types of them must too
        .variable => |v| return tl.getType(scope.variables.get(v).?.ty).?,

        .fn_call => |f| return tl.types.get(
            tl.functions.get(f.name).?.returns,
        ).?,

        .literal => |l| return l.getType(),
        .binary_op => |b| {
            const left = try exprEvalsTo(tl, scope, b.left);
            const right = try exprEvalsTo(tl, scope, b.right);

            return left.agreesWith(right);
        },

        // TODO: This might not also be accurate, I just can't determine for sure rn
        .unary_op => |u| return exprEvalsTo(tl, scope, u.expr),
        .return_val => return .its_void,

        .construction => return .its_void,
        .assignment => return .its_void,
    }
}

pub fn typeCheck(tl: *TopLevel) SemanticAnalysisError!void {
    _ = tl;
}

test "type resolution" {
    var tl: TopLevel = .{};
    var f: parser.Function = .{};

    var a: Expr = .{ .literal = .{ .int = 1 } };
    var b: Expr = .{ .literal = .{ .int = 2 } };

    const apb: Expr = .{ .binary_op = .{ .left = &a, .right = &b, .op = .add } };

    const ty = try exprEvalsTo(&tl, &f, &apb);
    try std.testing.expectEqual(.its_a_comptime_number, ty);
}

test "variable type resolution" {
    var tl: TopLevel = .{};
    var f: parser.Function = .{};
    defer f.deinit(std.testing.allocator);

    try f.variables.put(
        std.testing.allocator,
        "A",
        .{
            .ty = "u32",
            .mutable = false,
        },
    );

    const variable: Expr = .{ .variable = "A" };
    const ty = try exprEvalsTo(&tl, &f, &variable);

    try std.testing.expectEqual(32, ty.its_an_int.bits);
    try std.testing.expectEqual(.unsigned, ty.its_an_int.signed);
}

test "binary op type resolution" {
    var tl: TopLevel = .{};
    var f: parser.Function = .{};
    defer f.deinit(std.testing.allocator);

    try f.variables.put(
        std.testing.allocator,
        "A",
        .{
            .ty = "f16",
            .mutable = false,
        },
    );

    var variable: Expr = .{ .variable = "A" };
    var constant: Expr = .{ .literal = .{ .int = 10 } };

    const sum: Expr = .{ .binary_op = .{ .right = &variable, .left = &constant, .op = .add } };
    const ty = try exprEvalsTo(&tl, &f, &sum);

    try std.testing.expectEqual(.float16, ty.its_a_float);
}
