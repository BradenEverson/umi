//! Name Resolution and Type Checking step

const std = @import("std");

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
    var functions = tl.functions.iterator();
    while (functions.next()) |entry| {
        const name = entry.key_ptr;
        std.debug.print("{s}\n", .{name.*});

        const function = entry.value_ptr;

        // Ensure return type exists:
        if (tl.getType(function.returns) == null)
            return SemanticAnalysisError.TypeDoesNotExist;

        for (function.body.ast.items) |ast| {
            try nameResolveAst(tl, function, ast);
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

pub fn typeCheck(tl: *TopLevel) SemanticAnalysisError!void {
    _ = tl;
}

test {}
