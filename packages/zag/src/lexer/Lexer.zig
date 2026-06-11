const std = @import("std");
const Token = @import("Token.zig").Token;
const TokenType = @import("Token.zig").TokenType;

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: u32,
    col: u32,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .col = 1,
        };
    }

    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespaceAndComments();

        if (self.isAtEnd()) {
            return self.makeToken(.eof, "");
        }

        const start_line = self.line;
        const start_col = self.col;
        const c = self.advance();

        switch (c) {
            '(' => return self.makeTokenLoc(.l_paren, "(", start_line, start_col),
            ')' => return self.makeTokenLoc(.r_paren, ")", start_line, start_col),
            '[' => return self.makeTokenLoc(.l_bracket, "[", start_line, start_col),
            ']' => return self.makeTokenLoc(.r_bracket, "]", start_line, start_col),
            '{' => return self.makeTokenLoc(.l_brace, "{", start_line, start_col),
            '}' => return self.makeTokenLoc(.r_brace, "}", start_line, start_col),
            '\'' => return self.makeTokenLoc(.quote, "'", start_line, start_col),
            '`' => return self.makeTokenLoc(.syntax_quote, "`", start_line, start_col),
            '^' => return self.makeTokenLoc(.meta, "^", start_line, start_col),
            '@' => return self.makeTokenLoc(.deref, "@", start_line, start_col),
            '~' => {
                if (self.peek() == '@') {
                    _ = self.advance();
                    return self.makeTokenLoc(.unquote_splice, "~@", start_line, start_col);
                }
                return self.makeTokenLoc(.unquote, "~", start_line, start_col);
            },
            '#' => return self.makeTokenLoc(.hash, "#", start_line, start_col),
            '"' => return self.readString(start_line, start_col),
            ':' => return self.readKeyword(start_line, start_col),
            else => {
                if (isDigit(c) or (c == '-' and isDigit(self.peek()))) {
                    return self.readNumber(start_line, start_col);
                }
                if (isSymbolStart(c)) {
                    return self.readSymbolOrBoolean(start_line, start_col);
                }
                // Unknown character — skip and return next token
                return self.nextToken();
            },
        }
    }

    fn readString(self: *Lexer, start_line: u32, start_col: u32) Token {
        const start = self.pos - 1; // include opening quote
        while (!self.isAtEnd() and self.peek() != '"') {
            if (self.peek() == '\\') {
                _ = self.advance(); // skip backslash
                if (!self.isAtEnd()) _ = self.advance(); // skip escaped char
            } else {
                _ = self.advance();
            }
        }
        if (!self.isAtEnd()) {
            _ = self.advance(); // closing quote
        }
        const text = self.source[start..self.pos];
        return self.makeTokenLoc(.string, text, start_line, start_col);
    }

    fn readKeyword(self: *Lexer, start_line: u32, start_col: u32) Token {
        const start = self.pos;
        while (!self.isAtEnd() and isKeywordChar(self.peek())) {
            _ = self.advance();
        }
        const text = self.source[start - 1 .. self.pos]; // include :
        return self.makeTokenLoc(.keyword, text, start_line, start_col);
    }

    fn readNumber(self: *Lexer, start_line: u32, start_col: u32) Token {
        const start = self.pos - 1; // include first char
        while (!self.isAtEnd() and (isDigit(self.peek()) or self.peek() == '.' or self.peek() == '_')) {
            _ = self.advance();
        }
        const text = self.source[start..self.pos];
        return self.makeTokenLoc(.number, text, start_line, start_col);
    }

    fn readSymbolOrBoolean(self: *Lexer, start_line: u32, start_col: u32) Token {
        const start = self.pos - 1; // include first char
        while (!self.isAtEnd() and isSymbolChar(self.peek())) {
            _ = self.advance();
        }
        const text = self.source[start..self.pos];

        if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false")) {
            return self.makeTokenLoc(.boolean, text, start_line, start_col);
        }
        if (std.mem.eql(u8, text, "nil")) {
            return self.makeTokenLoc(.nil, text, start_line, start_col);
        }
        return self.makeTokenLoc(.symbol, text, start_line, start_col);
    }

    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (!self.isAtEnd()) {
            const c = self.peek();
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == ',') {
                _ = self.advance();
            } else if (c == ';') {
                while (!self.isAtEnd() and self.peek() != '\n') {
                    _ = self.advance();
                }
            } else {
                break;
            }
        }
    }

    fn advance(self: *Lexer) u8 {
        const c = self.peek();
        self.pos += 1;
        if (c == '\n') {
            self.line += 1;
            self.col = 1;
        } else {
            self.col += 1;
        }
        return c;
    }

    fn peek(self: Lexer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.pos];
    }

    fn isAtEnd(self: Lexer) bool {
        return self.pos >= self.source.len;
    }

    fn makeToken(self: *Lexer, ttype: TokenType, text: []const u8) Token {
        return self.makeTokenLoc(ttype, text, self.line, self.col);
    }

    fn makeTokenLoc(_: *Lexer, ttype: TokenType, text: []const u8, line: u32, col: u32) Token {
        return .{
            .type = ttype,
            .text = text,
            .line = line,
            .col = col,
        };
    }
};

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isSymbolStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_' or c == '>' or c == '<' or c == '=' or c == '!' or c == '*' or c == '/' or c == '+' or c == '-' or c == '?' or c == '.';
}

fn isSymbolChar(c: u8) bool {
    return isSymbolStart(c) or isDigit(c) or c == '-' or c == '?' or c == '!';
}

fn isKeywordChar(c: u8) bool {
    return isSymbolChar(c) or c == '/';
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "lexer basic tokens" {
    const source = "(def x 42)";
    var lexer = Lexer.init(source);

    const expected = [_]TokenType{
        .l_paren, .symbol, .symbol, .number, .r_paren, .eof,
    };

    for (expected) |tt| {
        const tok = lexer.nextToken();
        try std.testing.expectEqual(tt, tok.type);
    }
}

test "lexer string and keyword" {
    const source = ":key \"hello\"";
    var lexer = Lexer.init(source);

    const t1 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.keyword, t1.type);
    try std.testing.expectEqualStrings(":key", t1.text);

    const t2 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.string, t2.type);
    try std.testing.expectEqualStrings("\"hello\"", t2.text);
}
