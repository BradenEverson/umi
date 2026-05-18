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

pub fn name_resolution(tl: *TopLevel) SemanticAnalysisError!void {
    _ = tl;
}

pub fn type_check(tl: *TopLevel) SemanticAnalysisError!void {
    _ = tl;
}
