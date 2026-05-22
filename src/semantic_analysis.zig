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
};

/// Ensures all named types and functions actually exist in the
/// context
pub fn nameResolution(tl: *TopLevel) SemanticAnalysisError!void {
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
            try nameResolveAst(tl, function, ast);
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
    tl: *TopLevel,
    function: *const parser.Function,
    expr: *const Expr,
) SemanticAnalysisError!void {
    switch (expr.*) {
        .return_val => |r| try nameResolveAst(tl, function, r),
        .construction => |c| {
            try nameResolveAst(tl, function, c.val);
            if (tl.getType(c.ty) == null)
                return SemanticAnalysisError.TypeDoesNotExist;
        },
        .assignment => |a| {
            // TODO: We might need a local variable scope for the function?
            // like a.name should not exist right now because it's a declaration
            // although maybe this doesn't matter, just keeping this here so I
            // remember we need to make a decision
            try nameResolveAst(tl, function, a.val);
        },
        .variable => |v| {
            _ = v;
            // Yep okay, we DO need a local/global variable scope on the
            // top level. We should ensure this variable exists and is
            // declared BEFORE we make it to this step
            //
            // But actually, this will be solved during the next step, scope
            // resolution
        },
        .binary_op => |b| {
            try nameResolveAst(tl, function, b.left);
            try nameResolveAst(tl, function, b.right);
        },
        .unary_op => |u| try nameResolveAst(tl, function, u.expr),
        .fn_call => |f| {
            if (tl.functions.get(f.name) == null)
                return SemanticAnalysisError.FunctionDoesNotExist;

            for (f.arguments.items) |arg|
                try nameResolveAst(tl, function, arg);
        },
        .literal => {},
    }
}

pub fn scopeResolve(alloc: Allocator, tl: *TopLevel) SemanticAnalysisError!void {
    _ = alloc;
    _ = tl;
}

pub fn typeCheck(tl: *TopLevel) SemanticAnalysisError!void {
    _ = tl;
}

test {}
