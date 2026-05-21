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

pub fn nameResolveAst(tl: *TopLevel, function: *const parser.Function, expr: *const Expr) SemanticAnalysisError!void {
    switch (expr.*) {
        .return_val => |r| try nameResolveAst(tl, function, r),
        else => {},
    }
}

pub fn typeCheck(tl: *TopLevel) SemanticAnalysisError!void {
    _ = tl;
}

test {}
