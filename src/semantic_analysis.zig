//! Name Resolution and Type Checking step

const std = @import("std");
const Allocator = std.mem.Allocator;

const parser = @import("parser.zig");
const TopLevel = parser.TopLevel;
const Expr = parser.Expr;

const ts = @import("type.zig");
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

pub fn typeCheck(tl: *TopLevel) SemanticAnalysisError!void {
    _ = tl;
}

test {}
