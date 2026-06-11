const std = @import("std");

pub const TokenType = enum {
    // Literals
    number,
    string,
    keyword,
    boolean,
    nil,

    // Identifiers / symbols
    symbol,

    // Delimiters
    l_paren, // (
    r_paren, // )
    l_bracket, // [
    r_bracket, // ]
    l_brace, // {
    r_brace, // }

    // Special prefix chars
    quote, // '
    syntax_quote, // `
    unquote, // ~
    unquote_splice, // ~@
    deref, // @
    hash, // #
    meta, // ^

    // EOF
    eof,
};

pub const Token = struct {
    type: TokenType,
    text: []const u8,
    line: u32,
    col: u32,

    pub fn format(
        self: Token,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Token{{ .{s}, '{s}', {}:{} }}", .{
            @tagName(self.type),
            self.text,
            self.line,
            self.col,
        });
    }
};
