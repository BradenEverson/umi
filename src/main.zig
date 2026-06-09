const std = @import("std");
const Io = std.Io;

const umi = @import("umi");
const Token = umi.tokenizer.Token;
const TopLevel = umi.parser.TopLevel;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const alloc = init.gpa;

    var args = init.minimal.args.iterate();
    _ = args.next();

    var source: []u8 = undefined;

    if (args.next()) |file_path| {
        source = try std.Io.Dir.cwd()
            .readFileAlloc(
            io,
            file_path,
            alloc,
            .unlimited,
        );
    } else {
        std.debug.print(
            "Missing source code!!!\n",
            .{},
        );
        std.process.exit(1);
    }

    defer alloc.free(source);

    var tokens: std.ArrayList(Token) = .empty;
    defer tokens.deinit(alloc);

    try umi.tokenizer.tokenize(
        source,
        &tokens,
        alloc,
    );

    var tl: TopLevel = .{};
    defer tl.deinit(alloc);

    try tl.initTypes(alloc);

    var parser: umi.parser = .{
        .tokens = tokens.items,
    };
    try parser.parse(alloc, &tl);

    try umi.semantic_analysis.nameResolution(
        alloc,
        &tl,
    );
    try umi.semantic_analysis.typeCheck(&tl);

    try umi.optimizer.optimize(alloc, &tl);

    // for (tl.functions.get("main").?
    //     .body.ast.items) |instr|
    // {
    //     switch (instr.*) {
    //         .if_statement => |i| {
    //             std.debug.print("IF {any}:\n", .{i.cond});
    //             for (i.block.items) |b| {
    //                 std.debug.print("\t{any}\n", .{b});
    //             }
    //         },
    //         else => std.debug.print("{any}\n", .{instr}),
    //     }
    // }

    const ir = try umi.ir_gen.genIr(alloc, &tl);
    tl.ir = ir;

    for (ir.functions.get("main").?.instructions.items) |tac| {
        std.debug.print("{any}\n", .{tac});
    }

    var cfg = try umi.ir_gen.ControlFlowGraph.fromIr(
        alloc,
        tl.ir.functions.get("main").?.instructions.items,
    );
    defer cfg.deinit(alloc);

    for (cfg.blocks.items) |bb| {
        std.debug.print("{} instructions - {} connections - {} predecessors \n", .{ bb.instructions.len, bb.connections.items.len, bb.predecessors.items.len });
    }

    // try umi.reg_alloc.regAlloc(alloc, &tl, .x86_64);
    //
    // for (tl.ir.functions.get("main").?
    //     .instructions.items, 0..) |instr, i|
    // {
    //     std.debug.print("{} - {any}\n", .{ i, instr });
    // }

}
