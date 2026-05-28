//! VM interpreter for running the flat IR instead of compiling :)

const IrTopLevel = @import("ir.zig").IrTopLevel;

pub fn interpret(tl: *IrTopLevel) void {
    _ = tl;
}
