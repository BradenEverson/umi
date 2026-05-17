//! Tokenizing Step

const std = @import("std");

const TokenizeError = error{
    UnexpectedEOF,
    UnexpectedCharacter,
};

pub const Keyword = enum {
    let,
    mut,
    fn_kw,
    struct_kw,
    enum_kw,
    defer_kw,
};

pub const KeywordLookup = std.StaticStringMap(Keyword).initComptime(.{
    .{ "let", .let },
    .{ "mut", .mut },
    .{ "fn", .fn_kw },
    .{ "struct", .struct_kw },
    .{ "enum", .enum_kw },
    .{ "defer", .defer_kw },
});

pub const TokenTag = enum {
    keyword,
    ident,
    number,
    string,

    plus,
    minus,
    at,
    star,
    slash,
    equals,
    equals_equals,
    eof,
    open_paren,
    open_brace,
    open_bracket,
    close_paren,
    close_brace,
    close_bracket,
    dot,
    comma,
    gt,
    lt,

    colon,
    semicolon,
};

pub const TokenLookup = std.StaticStringMap(TokenTag).initComptime(.{
    .{ ";", .semicolon },
    .{ ":", .colon },
    .{ ",", .comma },
    .{ ".", .dot },
    .{ "+", .plus },
    .{ "-", .minus },
    .{ "*", .star },
    .{ "/", .slash },
    .{ "(", .open_paren },
    .{ "{", .open_brace },
    .{ "[", .open_bracket },
    .{ ")", .close_paren },
    .{ "}", .close_brace },
    .{ "]", .close_bracket },
    .{ ">", .gt },
    .{ "<", .lt },
});

pub const Token = struct {
    tag: TokenTag,
    line: usize = 0,
    col: usize = 0,
    data: []const u8 = "no data",
};

pub fn tokenize(stream: []const u8, tokens: *std.ArrayList(Token), alloc: std.mem.Allocator) !void {
    var idx: usize = 0;
    var line: usize = 1;
    var col: usize = 1;

    var curr: ?Token = undefined;

    while (idx < stream.len) {
        curr = null;

        const start_idx = idx;
        const start_col = col;

        if (TokenLookup.get(stream[idx .. idx + 1])) |tag| {
            idx += 1;
            col += 1;
            curr = Token{
                .tag = tag,
                .line = line,
                .col = start_col,
                .data = stream[start_idx..idx],
            };
        } else switch (stream[idx]) {
            'a'...'z', 'A'...'Z', '_' => {
                while (idx < stream.len and (std.ascii.isAlphanumeric(stream[idx]) or stream[idx] == '_')) {
                    idx += 1;
                    col += 1;
                }
                const ident = stream[start_idx..idx];

                const tag: TokenTag = if (KeywordLookup.get(ident)) |_|
                    .keyword
                else
                    .ident;

                curr = Token{
                    .tag = tag,
                    .line = line,
                    .col = start_col,
                    .data = ident,
                };
            },

            '=' => {
                var tag: TokenTag = .equals;
                if (idx < stream.len and stream[idx + 1] == '=') {
                    idx += 1;
                    tag = .equals_equals;
                }

                idx += 1;
                col += 1;
                curr = Token{
                    .tag = tag,
                    .line = line,
                    .col = start_col,
                    .data = stream[start_idx..idx],
                };
            },

            '"' => {
                idx += 1;
                col += 1;

                while (idx < stream.len and stream[idx] != '"') {
                    idx += 1;
                    col += 1;
                }

                const string = stream[start_idx + 1 .. idx];
                idx += 1;

                curr = Token{
                    .tag = .string,
                    .line = line,
                    .col = start_col,
                    .data = string,
                };
            },

            '0'...'9' => {
                var seen_dot = false;
                while (idx < stream.len and (std.ascii.isDigit(stream[idx]) or (stream[idx] == '.' and !seen_dot))) {
                    if (stream[idx] == '.')
                        seen_dot = true;

                    idx += 1;
                    col += 1;
                }
                const number = stream[start_idx..idx];
                curr = Token{
                    .tag = .number,
                    .line = line,
                    .col = start_col,
                    .data = number,
                };
            },

            ' ', '\t', '\r' => {
                while (idx < stream.len and (stream[idx] == ' ' or stream[idx] == '\t')) {
                    idx += 1;
                    col += 1;
                }
            },

            '\n' => {
                idx += 1;
                line += 1;
                col = 1;
            },

            else => {
                std.debug.print("Unexpected character: '{c}' at line {}, col {}\n", .{ stream[idx], line, col });

                return TokenizeError.UnexpectedCharacter;
            },
        }

        if (curr) |tok| {
            try tokens.append(alloc, tok);
        }
    }

    try tokens.append(alloc, .{ .col = col, .line = line, .tag = .eof });
}

test "basic tokenize" {
    const alloc = std.testing.allocator;
    var tokens = std.ArrayList(Token).empty;
    defer tokens.deinit(alloc);

    const simple = "b = 10;";

    try tokenize(simple, &tokens, alloc);

    try std.testing.expectEqual(tokens.items[0].tag, .ident);
    try std.testing.expectEqualSlices(u8, tokens.items[0].data, "b");

    try std.testing.expectEqual(tokens.items[1].tag, .equals);

    try std.testing.expectEqual(tokens.items[2].tag, .number);
    try std.testing.expectEqualSlices(u8, tokens.items[2].data, "10");

    try std.testing.expectEqual(tokens.items[3].tag, .semicolon);

    try std.testing.expectEqual(tokens.items[4].tag, .eof);
}
