const std = @import("std");
const Io = std.Io;

const umi = @import("umi");
const Token = umi.tokenizer.Token;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const alloc = init.gpa;

    var args = init.minimal.args.iterate();
    _ = args.next();

    var source: []u8 = undefined;

    if (args.next()) |file_path| {
        source = try std.Io.Dir.cwd().readFileAlloc(
            io,
            file_path,
            alloc,
            .unlimited,
        );
    } else {
        std.debug.print("Missing source code!!!\n", .{});
        std.process.exit(1);
    }

    defer alloc.free(source);

    var tokens: std.ArrayList(Token) = .empty;
    defer tokens.deinit(alloc);

    try umi.tokenizer.tokenize(source, &tokens, alloc);

    std.debug.print("{any}\n", .{tokens.items});
}
