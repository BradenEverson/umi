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
    FunctionDoesNotReturn,
    TypeDoesNotExist,
    BinaryTypesDontAgree,
    InvalidFunctionArgumentType,
    VariableAlreadyDefined,
    VariableUsedBeforeDefine,
    ImmutableVariableAssigned,
    ArgumentsLenDoesNotMatchUp,
};

const NameResolveError = SemanticAnalysisError ||
    Allocator.Error;

/// Ensures all named types and functions
/// actually exist in the context
pub fn nameResolution(
    alloc: Allocator,
    tl: *TopLevel,
) NameResolveError!void {
    // First, validate all function bodys,
    // parameters, and return types
    var functions = tl.functions.iterator();
    while (functions.next()) |entry| {
        const function = entry.value_ptr;

        if (!functionReturns(function))
            return NameResolveError
                .FunctionDoesNotReturn;

        for (function.parameters.items) |param| {
            if (tl.getType(param.@"1") == null)
                return SemanticAnalysisError
                    .TypeDoesNotExist;

            try function.scope.variables.put(
                alloc,
                param.@"0",
                .{
                    .ty = param.@"1",
                    .mutable = false,
                },
            );
        }

        // Ensure return type exists:
        if (tl.getType(function.returns) == null)
            return SemanticAnalysisError
                .TypeDoesNotExist;

        for (function.body.ast.items) |ast| {
            try nameResolveAst(
                alloc,
                tl,
                &function.scope,
                ast,
            );
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
            .array => {},
            .its_a_float => {},
            .its_a_pointer => {},
            .its_an_int => {},
            .slice => {},
            .its_a_bool => {},
            .its_a_comptime_number => {},
            .its_void => {},
        }
    }
}

// TODO: Also check all paths, right now we don't even
// have branching capabilities so we'll just need to do this
// later
fn functionReturns(func: *const parser.Function) bool {
    var valid = false;
    if (std.mem.eql(u8, "void", func.returns)) return true;

    for (func.body.ast.items) |expr| {
        if (exprReturns(expr)) valid = true;
    }

    return valid;
}

fn exprReturns(expr: *const Expr) bool {
    switch (expr.*) {
        // This is simple for now, but we gotta keep in
        // mind that blocks, if statements and loop
        // constructs will need to call this recursively
        // you feel
        .return_val => return true,
        .if_statement => |i| {
            var ret = exprReturns(i.if_stuff);
            if (i.else_stuff) |el| {
                ret = ret and exprReturns(el);
            }

            return ret;
        },
        .while_loop => |w| return exprReturns(w.do_stuff),
        .block => |b| {
            var valid = false;
            for (b.block.items) |e| {
                if (exprReturns(e)) valid = true;
            }
            return valid;
        },

        .assignment,
        .binary_op,
        .construction,
        .fn_call,
        .literal,
        .unary_op,
        .variable,
        => return false,
    }
}

fn nameResolveAst(
    alloc: Allocator,
    tl: *TopLevel,
    scope: *parser.Scope,
    expr: *Expr,
) NameResolveError!void {
    switch (expr.*) {
        .return_val => |r| try nameResolveAst(alloc, tl, scope, r),
        .construction => |c| {
            try nameResolveAst(alloc, tl, scope, c.val);
            if (tl.getType(c.ty) == null)
                return SemanticAnalysisError.TypeDoesNotExist;

            if (scope.variableExists(c.name))
                return SemanticAnalysisError.VariableAlreadyDefined;

            try scope.variables.put(alloc, c.name, .{
                .mutable = c.mutable,
                .ty = c.ty,
            });
        },
        .assignment => |a| {
            try nameResolveAst(alloc, tl, scope, a.val);
            if (!scope.variableExists(a.name))
                return SemanticAnalysisError.VariableUsedBeforeDefine;

            const variable = scope.getVariable(a.name).?;
            if (!variable.mutable)
                return SemanticAnalysisError.ImmutableVariableAssigned;
        },
        .variable => |v| {
            if (!scope.variableExists(v))
                return SemanticAnalysisError.VariableUsedBeforeDefine;
        },
        .binary_op => |b| {
            try nameResolveAst(alloc, tl, scope, b.left);
            try nameResolveAst(alloc, tl, scope, b.right);
        },
        .unary_op => |u| try nameResolveAst(alloc, tl, scope, u.expr),
        .fn_call => |f| {
            if (tl.functions.get(f.name) == null)
                return SemanticAnalysisError.FunctionDoesNotExist;

            for (f.arguments.items) |arg|
                try nameResolveAst(alloc, tl, scope, arg);

            const func = tl.functions.get(f.name).?;
            if (func.parameters.items.len != f.arguments.items.len)
                return SemanticAnalysisError.ArgumentsLenDoesNotMatchUp;
        },
        .if_statement => |is| {
            try nameResolveAst(alloc, tl, scope, is.cond);
            try nameResolveAst(alloc, tl, scope, is.if_stuff);
            if (is.else_stuff) |el|
                try nameResolveAst(alloc, tl, scope, el);
        },
        .while_loop => |l| {
            try nameResolveAst(alloc, tl, scope, l.cond);
            try nameResolveAst(alloc, tl, scope, l.do_stuff);
        },
        .block => |*b| {
            b.scope.parent = scope;

            for (b.block.items) |e|
                try nameResolveAst(alloc, tl, &b.scope, e);
        },
        .literal => {},
    }
}

pub fn exprEvalsTo(
    tl: *TopLevel,
    scope: *const parser.Scope,
    expr: *const Expr,
) TypeCheckError!Type {
    switch (expr.*) {
        // We can safely unwrap these optionals at this point because this
        // is assumed to run after the name resolution. We know these
        // variables all exist and the types of them must too
        //
        // TODO: Need parameters to show up here too
        .variable => |v| return tl.getType(scope.getVariable(v).?.ty).?,

        .fn_call => |f| return tl.getType(
            tl.functions.get(f.name).?.returns,
        ).?,

        .literal => |l| return l.getType(),
        .binary_op => |b| {
            const left = try exprEvalsTo(tl, scope, b.left);
            const right = try exprEvalsTo(tl, scope, b.right);

            const type_if_arithmetic = try left.agreesWith(right);

            return switch (b.op) {
                .eq, .lt, .gt => .its_a_bool,
                else => type_if_arithmetic,
            };
        },

        // TODO: This might not also be accurate, I just can't determine for sure rn
        .unary_op => |u| return exprEvalsTo(tl, scope, u.expr),
        .return_val => return .its_void,

        .construction => return .its_void,
        .assignment => return .its_void,
        .if_statement => return .its_void,
        .block => return .its_void,
        .while_loop => return .its_void,
    }
}

/// Checks each assignment and construction for valid
/// typing on both sides also checks return statements
/// from functions 🤓☝️
///
/// and and function parameters
///
/// THIS SHOULD BE RUN AFTER NAME RESOLUTION!!!!
/// IT MAKES ASSUMPTIONS THAT EVERYTHING IS ALREADY
/// VALIDATED
///
/// AND YES I KNOW I SHOULD PROBABLY HAVE NAME RESOLUTION
/// RETURN A STRUCT WITH DEFINITE TYPES INSTEAD OF LAZY
/// STRINGS BUT OH WELL MAYBE THATS A TODO LETS JUST GET
/// THIS DONE AND THEN WE CAN MAKE THIS RIGHT MKAY
pub fn typeCheck(tl: *TopLevel) TypeCheckError!void {
    var functions = tl.functions.iterator();
    while (functions.next()) |entry| {
        const function = entry.value_ptr;

        // we'll need this for checking any returns from
        // the fn
        const ret_type = tl.getType(function.returns).?;
        for (function.body.ast.items) |expr|
            try typeCheckExpr(tl, &function.scope, ret_type, expr);
    }

    var global_consts = tl.global_consts.iterator();

    while (global_consts.next()) |entry| {
        const key = entry.key_ptr.*;
        const val = entry.value_ptr.*;

        const ty = try exprEvalsTo(tl, &tl.global_scope, val);

        const ty_name = tl.global_scope.getVariable(key).?.ty;

        _ = try ty.agreesWith(tl.getType(ty_name).?);
    }

    var global_vars = tl.global_variables.iterator();

    while (global_vars.next()) |entry| {
        const key = entry.key_ptr.*;
        const val = entry.value_ptr.*;

        const ty = try exprEvalsTo(tl, &tl.global_scope, val);

        const ty_name = tl.global_scope.getVariable(key).?.ty;

        _ = try ty.agreesWith(tl.getType(ty_name).?);
    }
}

pub fn typeCheckExpr(
    tl: *TopLevel,
    scope: *const parser.Scope,
    fn_ret_ty: Type,
    expr: *const Expr,
) TypeCheckError!void {
    switch (expr.*) {
        .return_val => |r| {
            const ret_resolved_type = try exprEvalsTo(tl, scope, r);
            _ = try fn_ret_ty.agreesWith(ret_resolved_type);
        },

        .construction => |c| {
            const expected_type = tl.getType(c.ty).?;
            const actual_type = try exprEvalsTo(tl, scope, c.val);

            _ = try expected_type.agreesWith(actual_type);
        },

        .assignment => |a| {
            const variable = scope.getVariable(a.name).?;
            const variable_type = tl.getType(variable.ty).?;
            const assignment_var = try exprEvalsTo(tl, scope, a.val);

            _ = try variable_type.agreesWith(assignment_var);
        },

        .binary_op => |b| {
            const left = try exprEvalsTo(tl, scope, b.left);
            const right = try exprEvalsTo(tl, scope, b.right);

            const result_ty = try left.agreesWith(right);
            if (!result_ty.binaryOpIsValidForType(b.op))
                return TypeCheckError.InvalidOpForType;
        },

        .fn_call => |f| {
            const func = tl.functions.get(f.name).?;

            for (0..func.parameters.items.len) |i| {
                const arg = f.arguments.items[i];
                const param = func.parameters.items[i];

                const arg_type = try exprEvalsTo(tl, scope, arg);
                const param_type = tl.getType(param.@"1").?;

                _ = try arg_type.agreesWith(param_type);
            }
        },

        .if_statement => |f| {
            const cond = try exprEvalsTo(tl, scope, f.cond);
            if (cond != .its_a_bool)
                return TypeCheckError.ExpectedABool;

            try typeCheckExpr(tl, scope, fn_ret_ty, f.if_stuff);

            if (f.else_stuff) |el|
                try typeCheckExpr(tl, scope, fn_ret_ty, el);
        },

        .while_loop => |f| {
            const cond = try exprEvalsTo(tl, scope, f.cond);
            if (cond != .its_a_bool)
                return TypeCheckError.ExpectedABool;

            try typeCheckExpr(tl, scope, fn_ret_ty, f.do_stuff);
        },

        .block => |b| {
            for (b.block.items) |e|
                try typeCheckExpr(tl, &b.scope, fn_ret_ty, e);
        },

        .variable, .unary_op, .literal => {},
    }
}

test "type resolution" {
    var tl: TopLevel = .{};
    var f: parser.Function = .{ .scope = .{} };

    var a: Expr = .{ .literal = .{ .int = 1 } };
    var b: Expr = .{ .literal = .{ .int = 2 } };

    const apb: Expr = .{
        .binary_op = .{
            .left = &a,
            .right = &b,
            .op = .add,
        },
    };

    const ty = try exprEvalsTo(&tl, &f.scope, &apb);
    try std.testing.expectEqual(.its_a_comptime_number, ty);
}

test "variable type resolution" {
    var tl: TopLevel = .{};
    var f: parser.Function = .{ .scope = .{} };
    defer f.deinit(std.testing.allocator);

    try f.scope.variables.put(
        std.testing.allocator,
        "A",
        .{
            .ty = "u32",
            .mutable = false,
        },
    );

    const variable: Expr = .{ .variable = "A" };
    const ty = try exprEvalsTo(&tl, &f.scope, &variable);

    try std.testing.expectEqual(32, ty.its_an_int.bits);
    try std.testing.expectEqual(.unsigned, ty.its_an_int.signed);
}

test "binary op type resolution" {
    var tl: TopLevel = .{};
    var f: parser.Function = .{ .scope = .{} };
    defer f.deinit(std.testing.allocator);

    try f.scope.variables.put(
        std.testing.allocator,
        "A",
        .{
            .ty = "f16",
            .mutable = false,
        },
    );

    var variable: Expr = .{ .variable = "A" };
    var constant: Expr = .{ .literal = .{ .int = 10 } };

    const sum: Expr = .{ .binary_op = .{
        .right = &variable,
        .left = &constant,
        .op = .add,
    } };
    const ty = try exprEvalsTo(&tl, &f.scope, &sum);

    try std.testing.expectEqual(.float16, ty.its_a_float);
}
