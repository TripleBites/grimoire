const std = @import("std");
const Lexer = @import("../lexer/Lexer.zig").Lexer;
const Token = @import("../lexer/Token.zig").Token;
const TokenType = @import("../lexer/Token.zig").TokenType;
const Form = @import("Form.zig").Form;
const FormType = @import("Form.zig").FormType;

pub const ReaderError = error{
    UnexpectedToken,
    UnmatchedDelimiter,
    EmptyInput,
    OddNumberOfMapEntries,
    OutOfMemory,
};

pub const Reader = struct {
    lexer: Lexer,
    current: Token,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) !Reader {
        var lexer = Lexer.init(source);
        const first = lexer.nextToken();
        return .{
            .lexer = lexer,
            .current = first,
            .allocator = allocator,
        };
    }

    pub fn readForm(self: *Reader) ReaderError!*Form {
        return self.readFormAdvanced(false);
    }

    fn readFormAdvanced(self: *Reader, in_map: bool) ReaderError!*Form {
        const tok = self.current;

        switch (tok.type) {
            .eof => return ReaderError.EmptyInput,
            .number => {
                self.advance();
                const form = try Form.create(self.allocator, .number, tok.line, tok.col);
                form.data = .{ .number = tok.text };
                return form;
            },
            .string => {
                self.advance();
                const form = try Form.create(self.allocator, .string, tok.line, tok.col);
                form.data = .{ .string = tok.text };
                return form;
            },
            .symbol => {
                self.advance();
                const form = try Form.create(self.allocator, .symbol, tok.line, tok.col);
                form.data = .{ .symbol = tok.text };
                return form;
            },
            .keyword => {
                self.advance();
                const form = try Form.create(self.allocator, .keyword, tok.line, tok.col);
                form.data = .{ .keyword = tok.text };
                return form;
            },
            .boolean => {
                self.advance();
                const form = try Form.create(self.allocator, .boolean, tok.line, tok.col);
                form.data = .{ .boolean = std.mem.eql(u8, tok.text, "true") };
                return form;
            },
            .nil => {
                self.advance();
                const form = try Form.create(self.allocator, .nil, tok.line, tok.col);
                form.data = .nil;
                return form;
            },
            .l_paren => return self.readList(),
            .l_bracket => return self.readVector(),
            .l_brace => return self.readMap(),
            .quote => return self.readWrapped(.quote),
            .syntax_quote => return self.readWrapped(.syntax_quote),
            .unquote => return self.readWrapped(.unquote),
            .unquote_splice => return self.readWrapped(.unquote_splice),
            .deref => return self.readWrapped(.deref),
            .meta => return self.readWrapped(.meta),
            .hash => {
                self.advance();
                // MVP: only support #{...} for sets
                if (self.current.type == .l_brace) {
                    return self.readSet();
                }
                // For other # macros (e.g., #()), just read next form
                const form = try self.readFormAdvanced(in_map);
                return form;
            },
            .r_paren, .r_bracket, .r_brace => {
                if (in_map) {
                    // Allow these to terminate a map/list
                    return ReaderError.UnexpectedToken;
                }
                return ReaderError.UnmatchedDelimiter;
            },
        }
    }

    fn readList(self: *Reader) ReaderError!*Form {
        const start_tok = self.current;
        std.debug.assert(start_tok.type == .l_paren);
        self.advance();

        const form = try Form.create(self.allocator, .list, start_tok.line, start_tok.col);
        form.data = .{ .list = std.ArrayList(*Form).empty };

        while (self.current.type != .r_paren and self.current.type != .eof) {
            const item = try self.readForm();
            try form.data.list.append(self.allocator, item);
        }

        if (self.current.type != .r_paren) {
            return ReaderError.UnmatchedDelimiter;
        }
        self.advance(); // consume )
        return form;
    }

    fn readVector(self: *Reader) ReaderError!*Form {
        const start_tok = self.current;
        std.debug.assert(start_tok.type == .l_bracket);
        self.advance();

        const form = try Form.create(self.allocator, .vector, start_tok.line, start_tok.col);
        form.data = .{ .vector = std.ArrayList(*Form).empty };

        while (self.current.type != .r_bracket and self.current.type != .eof) {
            const item = try self.readForm();
            try form.data.vector.append(self.allocator, item);
        }

        if (self.current.type != .r_bracket) {
            return ReaderError.UnmatchedDelimiter;
        }
        self.advance(); // consume ]
        return form;
    }

    fn readMap(self: *Reader) ReaderError!*Form {
        const start_tok = self.current;
        std.debug.assert(start_tok.type == .l_brace);
        self.advance();

        const form = try Form.create(self.allocator, .map, start_tok.line, start_tok.col);
        form.data = .{ .map = std.ArrayList(*Form).empty };

        while (self.current.type != .r_brace and self.current.type != .eof) {
            const key = try self.readForm();
            try form.data.map.append(self.allocator, key);
            if (self.current.type == .r_brace) break;
            const val = try self.readForm();
            try form.data.map.append(self.allocator, val);
        }

        if (self.current.type != .r_brace) {
            return ReaderError.UnmatchedDelimiter;
        }
        self.advance(); // consume }

        if (form.data.map.items.len % 2 != 0) {
            return ReaderError.OddNumberOfMapEntries;
        }
        return form;
    }

    fn readSet(self: *Reader) ReaderError!*Form {
        // For MVP, represent sets as (hash-set ...)
        const start_tok = self.current;
        std.debug.assert(start_tok.type == .l_brace);
        self.advance();

        const form = try Form.create(self.allocator, .list, start_tok.line, start_tok.col);
        form.data = .{ .list = std.ArrayList(*Form).empty };

        // Add hash-set symbol
        const sym = try Form.create(self.allocator, .symbol, start_tok.line, start_tok.col);
        sym.data = .{ .symbol = "hash-set" };
        try form.data.list.append(self.allocator, sym);

        while (self.current.type != .r_brace and self.current.type != .eof) {
            const item = try self.readForm();
            try form.data.list.append(self.allocator, item);
        }

        if (self.current.type != .r_brace) {
            return ReaderError.UnmatchedDelimiter;
        }
        self.advance(); // consume }
        return form;
    }

    fn readWrapped(self: *Reader, wrapper_type: FormType) ReaderError!*Form {
        const start_tok = self.current;
        self.advance();
        const inner = try self.readForm();
        const form = try Form.create(self.allocator, wrapper_type, start_tok.line, start_tok.col);
        switch (wrapper_type) {
            .quote => form.data = .{ .quote = inner },
            .syntax_quote => form.data = .{ .syntax_quote = inner },
            .unquote => form.data = .{ .unquote = inner },
            .unquote_splice => form.data = .{ .unquote_splice = inner },
            .deref => form.data = .{ .deref = inner },
            .meta => form.data = .{ .meta = inner },
            else => unreachable,
        }
        return form;
    }

    fn advance(self: *Reader) void {
        self.current = self.lexer.nextToken();
    }
};

// ── Tests ───────────────────────────────────────────────────────────────────

test "reader basic list" {
    const allocator = std.testing.allocator;
    var reader = try Reader.init(allocator, "(def x 42)");
    const form = try reader.readForm();
    defer form.destroy(allocator);

    try std.testing.expectEqual(FormType.list, form.type);
    try std.testing.expectEqual(@as(usize, 3), form.data.list.items.len);
}

test "reader quote" {
    const allocator = std.testing.allocator;
    var reader = try Reader.init(allocator, "'(1 2 3)");
    const form = try reader.readForm();
    defer form.destroy(allocator);

    try std.testing.expectEqual(FormType.quote, form.type);
}

test "reader vector and map" {
    const allocator = std.testing.allocator;
    var reader = try Reader.init(allocator, "[1 {:a 2}]");
    const form = try reader.readForm();
    defer form.destroy(allocator);

    try std.testing.expectEqual(FormType.vector, form.type);
    try std.testing.expectEqual(@as(usize, 2), form.data.vector.items.len);
}
