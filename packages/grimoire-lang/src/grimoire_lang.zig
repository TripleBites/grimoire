const std = @import("std");
pub const runtime_src = @embedFile("gr_runtime.zig");

// ═════════════════════════════════════════════════════════════════════════════
// Errors
// ═════════════════════════════════════════════════════════════════════════════

pub const GrimoireLangError = error{
    OutOfMemory,
    InvalidChar,
    UnmatchedOpen,
    UnmatchedClose,
    BadForm,
};

// ═════════════════════════════════════════════════════════════════════════════
// Lexer
// ═════════════════════════════════════════════════════════════════════════════

const Tok = struct {
    tag: Tag,
    text: []const u8,
    line: u32,
    col: u32,

    const Tag = enum {
        l, // (
        r, // )
        lb, // [
        rb, // ]
        lc, // {
        rc, // }
        num,
        str,
        sym,
        kw,
        boolean,
        nil,
        q, // '
        sq, // `
        uq, // ~
        uqs, // ~@
        dr, // @
        hash, // #
        meta, // ^
        eof,
    };
};

const Lex = struct {
    src: []const u8,
    i: usize,
    line: u32,
    col: u32,

    fn init(src: []const u8) Lex {
        return .{ .src = src, .i = 0, .line = 1, .col = 1 };
    }

    fn next(self: *Lex) GrimoireLangError!Tok {
        self.skipSpace();
        if (self.i >= self.src.len) return tok(.eof, "", self.line, self.col);
        const sl = self.line;
        const sc = self.col;
        const c = self.bump();
        return switch (c) {
            '(' => tok(.l, "(", sl, sc),
            ')' => tok(.r, ")", sl, sc),
            '[' => tok(.lb, "[", sl, sc),
            ']' => tok(.rb, "]", sl, sc),
            '{' => tok(.lc, "{", sl, sc),
            '}' => tok(.rc, "}", sl, sc),
            '\'' => tok(.q, "'", sl, sc),
            '`' => tok(.sq, "`", sl, sc),
            '^' => tok(.meta, "^", sl, sc),
            '@' => tok(.dr, "@", sl, sc),
            '#' => tok(.hash, "#", sl, sc),
            '~' => if (self.peek() == '@') {
                _ = self.bump();
                return tok(.uqs, "~@", sl, sc);
            } else return tok(.uq, "~", sl, sc),
            '"' => self.readStr(sl, sc),
            ':' => self.readKw(sl, sc),
            else => {
                if (dig(c) or (c == '-' and dig(self.peek()))) return self.readNum(sl, sc, c);
                if (symStart(c)) return self.readSym(sl, sc, c);
                return GrimoireLangError.InvalidChar;
            },
        };
    }

    fn readStr(self: *Lex, sl: u32, sc: u32) GrimoireLangError!Tok {
        const s = self.i - 1;
        while (self.peek() != '"' and self.peek() != 0) {
            if (self.peek() == '\\') _ = self.bump();
            _ = self.bump();
        }
        if (self.peek() == '"') _ = self.bump();
        return tok(.str, self.src[s..self.i], sl, sc);
    }

    fn readKw(self: *Lex, sl: u32, sc: u32) GrimoireLangError!Tok {
        const s = self.i - 1;
        while (symChar(self.peek()) or self.peek() == '/') _ = self.bump();
        return tok(.kw, self.src[s..self.i], sl, sc);
    }

    fn readNum(self: *Lex, sl: u32, sc: u32, _: u8) GrimoireLangError!Tok {
        const s = self.i - 1;
        while (dig(self.peek()) or self.peek() == '.' or self.peek() == '_') _ = self.bump();
        return tok(.num, self.src[s..self.i], sl, sc);
    }

    fn readSym(self: *Lex, sl: u32, sc: u32, _: u8) GrimoireLangError!Tok {
        const s = self.i - 1;
        while (symChar(self.peek())) _ = self.bump();
        const txt = self.src[s..self.i];
        if (std.mem.eql(u8, txt, "true") or std.mem.eql(u8, txt, "false")) return tok(.boolean, txt, sl, sc);
        if (std.mem.eql(u8, txt, "nil")) return tok(.nil, txt, sl, sc);
        return tok(.sym, txt, sl, sc);
    }

    fn skipSpace(self: *Lex) void {
        while (true) {
            const c = self.peek();
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == ',') {
                _ = self.bump();
            } else if (c == ';') {
                while (self.peek() != '\n' and self.peek() != 0) _ = self.bump();
            } else break;
        }
    }

    fn peek(self: Lex) u8 {
        return if (self.i < self.src.len) self.src[self.i] else 0;
    }

    fn bump(self: *Lex) u8 {
        const c = self.peek();
        self.i += 1;
        if (c == '\n') { self.line += 1; self.col = 1; } else { self.col += 1; }
        return c;
    }
};

fn tok(tag: Tok.Tag, text: []const u8, line: u32, col: u32) Tok {
    return .{ .tag = tag, .text = text, .line = line, .col = col };
}
fn dig(c: u8) bool { return c >= '0' and c <= '9'; }
fn symStart(c: u8) bool { return std.ascii.isAlphabetic(c) or c == '_' or c == '>' or c == '<' or c == '=' or c == '!' or c == '*' or c == '/' or c == '+' or c == '-' or c == '?' or c == '.' or c == '&'; }
fn symChar(c: u8) bool { return symStart(c) or dig(c) or c == '-' or c == '?' or c == '!'; }

// ═════════════════════════════════════════════════════════════════════════════
// AST
// ═════════════════════════════════════════════════════════════════════════════

const Form = union(enum) {
    number: []const u8,
    string: []const u8,
    symbol: []const u8,
    keyword: []const u8,
    boolean: bool,
    nil,
    list: std.ArrayList(*Form),
    vector: std.ArrayList(*Form),
    map: std.ArrayList(*Form),
    quote: *Form,
    syntax_quote: *Form,
    unquote: *Form,
    unquote_splice: *Form,
    deref: *Form,
    meta: *Form,
};

// ═════════════════════════════════════════════════════════════════════════════
// Reader
// ═════════════════════════════════════════════════════════════════════════════

const Read = struct {
    lex: Lex,
    cur: Tok,
    arena: *std.heap.ArenaAllocator,

    fn init(arena: *std.heap.ArenaAllocator, src: []const u8) GrimoireLangError!Read {
        var lex = Lex.init(src);
        const cur = try lex.next();
        return .{ .lex = lex, .cur = cur, .arena = arena };
    }

    fn al(self: Read) std.mem.Allocator { return self.arena.allocator(); }

    fn readAll(self: *Read) GrimoireLangError!std.ArrayList(*Form) {
        var out = std.ArrayList(*Form).empty;
        while (self.cur.tag != .eof) {
            try out.append(self.al(), try self.readForm());
        }
        return out;
    }

    fn readForm(self: *Read) GrimoireLangError!*Form {
        const t = self.cur;
        switch (t.tag) {
            .eof => return GrimoireLangError.BadForm,
            .num => { self.bump(); return self.leaf(.{ .number = t.text }); },
            .str => { self.bump(); return self.leaf(.{ .string = t.text }); },
            .sym => { self.bump(); return self.leaf(.{ .symbol = t.text }); },
            .kw => { self.bump(); return self.leaf(.{ .keyword = t.text }); },
            .boolean => { self.bump(); return self.leaf(.{ .boolean = std.mem.eql(u8, t.text, "true") }); },
            .nil => { self.bump(); return self.leaf(.{ .nil = {} }); },
            .l => return self.readList(),
            .lb => return self.readVec(),
            .lc => return self.readMap(),
            .q => return self.wrap(.quote),
            .sq => return self.expandSyntaxQuote(try self.wrap(.syntax_quote)),
            .uq => return self.wrap(.unquote),
            .uqs => return self.wrap(.unquote_splice),
            .dr => return self.wrap(.deref),
            .meta => return self.wrap(.meta),
            .hash => { self.bump(); if (self.cur.tag == .lc) return self.readSet(); return self.readForm(); },
            .r, .rb, .rc => return GrimoireLangError.UnmatchedClose,
        }
    }

    fn makeSymbol(self: *Read, s: []const u8) GrimoireLangError!*Form {
        const f = try self.al().create(Form);
        f.* = .{ .symbol = s };
        return f;
    }

    fn makeList(self: *Read, items: std.ArrayList(*Form)) GrimoireLangError!*Form {
        const f = try self.al().create(Form);
        f.* = .{ .list = items };
        return f;
    }

    fn makeVector(self: *Read, items: std.ArrayList(*Form)) GrimoireLangError!*Form {
        const f = try self.al().create(Form);
        f.* = .{ .vector = items };
        return f;
    }

    fn makeQuote(self: *Read, inner: *Form) GrimoireLangError!*Form {
        const f = try self.al().create(Form);
        f.* = .{ .quote = inner };
        return f;
    }

    fn expandSyntaxQuote(self: *Read, f: *Form) GrimoireLangError!*Form {
        const inner = f.syntax_quote;
        return try self.expandSQForm(inner);
    }

    fn expandSQForm(self: *Read, f: *Form) GrimoireLangError!*Form {
        switch (f.*) {
            .unquote => |inner| return inner,
            .list => return self.expandSQList(f.list.items),
            .vector => return self.expandSQVec(f.vector.items),
            .map => return self.expandSQMap(f.map.items),
            else => return self.makeQuote(f),
        }
    }

    fn expandSQList(self: *Read, items: []const *Form) GrimoireLangError!*Form {
        var has_splice = false;
        for (items) |it| { if (it.* == .unquote_splice) has_splice = true; }
        if (!has_splice) {
            var out = std.ArrayList(*Form).empty;
            try out.append(self.al(), try self.makeSymbol("list"));
            for (items) |it| try out.append(self.al(), try self.expandSQForm(it));
            return self.makeList(out);
        }
        return self.expandSQSpliced(items, "list");
    }

    fn expandSQVec(self: *Read, items: []const *Form) GrimoireLangError!*Form {
        var has_splice = false;
        for (items) |it| { if (it.* == .unquote_splice) has_splice = true; }
        if (!has_splice) {
            var out = std.ArrayList(*Form).empty;
            try out.append(self.al(), try self.makeSymbol("vector"));
            for (items) |it| try out.append(self.al(), try self.expandSQForm(it));
            return self.makeList(out);
        }
        return self.expandSQSpliced(items, "vector");
    }

    fn expandSQSpliced(self: *Read, items: []const *Form, ctor: []const u8) GrimoireLangError!*Form {
        var segments = std.ArrayList(*Form).empty;
        var current = std.ArrayList(*Form).empty;
        try current.append(self.al(), try self.makeSymbol(ctor));
        for (items) |it| {
            if (it.* == .unquote_splice) {
                if (current.items.len > 1) {
                    try segments.append(self.al(), try self.makeList(current));
                    current = std.ArrayList(*Form).empty;
                    try current.append(self.al(), try self.makeSymbol(ctor));
                }
                try segments.append(self.al(), it.unquote_splice);
            } else {
                try current.append(self.al(), try self.expandSQForm(it));
            }
        }
        if (current.items.len > 1) {
            try segments.append(self.al(), try self.makeList(current));
        }
        if (segments.items.len == 0) {
            var empty = std.ArrayList(*Form).empty;
            try empty.append(self.al(), try self.makeSymbol(ctor));
            return self.makeList(empty);
        }
        var acc = segments.items[0];
        var i: usize = 1;
        while (i < segments.items.len) : (i += 1) {
            var concat = std.ArrayList(*Form).empty;
            try concat.append(self.al(), try self.makeSymbol("concat"));
            try concat.append(self.al(), acc);
            try concat.append(self.al(), segments.items[i]);
            acc = try self.makeList(concat);
        }
        return acc;
    }

    fn expandSQMap(self: *Read, items: []const *Form) GrimoireLangError!*Form {
        var out = std.ArrayList(*Form).empty;
        try out.append(self.al(), try self.makeSymbol("map"));
        var i: usize = 0;
        while (i < items.len) : (i += 1) {
            try out.append(self.al(), try self.expandSQForm(items[i]));
        }
        return self.makeList(out);
    }

    fn leaf(self: *Read, val: Form) GrimoireLangError!*Form {
        const f = try self.al().create(Form);
        f.* = val;
        return f;
    }

    fn wrap(self: *Read, comptime tag: std.meta.Tag(Form)) GrimoireLangError!*Form {
        self.bump();
        const inner = try self.readForm();
        return self.leaf(@unionInit(Form, @tagName(tag), inner));
    }

    fn readList(self: *Read) GrimoireLangError!*Form {
        self.bump(); // consume (
        var items = std.ArrayList(*Form).empty;
        while (true) {
            if (self.cur.tag == .r or self.cur.tag == .eof) break;
            try items.append(self.al(), try self.readForm());
        }
        if (self.cur.tag != .r) return GrimoireLangError.UnmatchedOpen;
        self.bump(); // consume )
        return self.leaf(.{ .list = items });
    }

    fn readVec(self: *Read) GrimoireLangError!*Form {
        self.bump(); // [
        var items = std.ArrayList(*Form).empty;
        while (self.cur.tag != .rb and self.cur.tag != .eof) {
            try items.append(self.al(), try self.readForm());
        }
        if (self.cur.tag != .rb) return GrimoireLangError.UnmatchedOpen;
        self.bump();
        const f = try self.al().create(Form);
        f.* = .{ .vector = items };
        return f;
    }

    fn readMap(self: *Read) GrimoireLangError!*Form {
        self.bump(); // {
        var items = std.ArrayList(*Form).empty;
        while (self.cur.tag != .rc and self.cur.tag != .eof) {
            try items.append(self.al(), try self.readForm());
            if (self.cur.tag == .rc) break;
            try items.append(self.al(), try self.readForm());
        }
        if (self.cur.tag != .rc) return GrimoireLangError.UnmatchedOpen;
        self.bump();
        if (items.items.len % 2 != 0) return GrimoireLangError.BadForm;
        const f = try self.al().create(Form);
        f.* = .{ .map = items };
        return f;
    }

    fn readSet(self: *Read) GrimoireLangError!*Form {
        self.bump(); // {
        var items = std.ArrayList(*Form).empty;
        while (self.cur.tag != .rc and self.cur.tag != .eof) {
            try items.append(self.al(), try self.readForm());
        }
        if (self.cur.tag != .rc) return GrimoireLangError.UnmatchedOpen;
        self.bump();
        var list = std.ArrayList(*Form).empty;
        const sym = try self.al().create(Form);
        sym.* = .{ .symbol = "hash-set" };
        try list.append(self.al(), sym);
        for (items.items) |it| try list.append(self.al(), it);
        const f = try self.al().create(Form);
        f.* = .{ .list = list };
        return f;
    }

    fn bump(self: *Read) void {
        self.cur = self.lex.next() catch Tok{ .tag = .eof, .text = "", .line = 0, .col = 0 };
    }
};

// ═════════════════════════════════════════════════════════════════════════════
// Macros
// ═════════════════════════════════════════════════════════════════════════════

const Macro = struct {
    arena: *std.heap.ArenaAllocator,
    defs: std.StringHashMapUnmanaged(*MacroDef),

    const MacroDef = struct {
        params: []*Form,
        template: *Form,
        rest_param: ?[]const u8,
    };

    fn init(arena: *std.heap.ArenaAllocator) Macro {
        return .{ .arena = arena, .defs = std.StringHashMapUnmanaged(*MacroDef).empty };
    }

    fn al(self: Macro) std.mem.Allocator { return self.arena.allocator(); }

    fn expandAll(self: *Macro, forms: []*Form) GrimoireLangError![]*Form {
        var out = std.ArrayList(*Form).empty;
        for (forms) |f| try out.append(self.al(), try self.expandForm(f));
        return out.toOwnedSlice(self.al());
    }

    fn register(self: *Macro, name: []const u8, params: []*Form, template: *Form) GrimoireLangError!void {
        var rest_param: ?[]const u8 = null;
        var normal_params = std.ArrayList(*Form).empty;
        var i: usize = 0;
        while (i < params.len) : (i += 1) {
            const p = params[i];
            if (p.* == .symbol and eql(p.symbol, "&")) {
                if (i + 1 >= params.len) return GrimoireLangError.BadForm;
                const rest = params[i + 1];
                if (rest.* != .symbol) return GrimoireLangError.BadForm;
                rest_param = rest.symbol;
                break;
            }
            try normal_params.append(self.al(), p);
        }
        const def = try self.al().create(MacroDef);
        def.* = .{ .params = normal_params.items, .template = template, .rest_param = rest_param };
        try self.defs.put(self.al(), name, def);
    }

    fn expandForm(self: *Macro, f: *Form) GrimoireLangError!*Form {
        switch (f.*) {
            .list => return self.expandList(f),
            .vector => {
                var out = std.ArrayList(*Form).empty;
                for (f.vector.items) |it| try out.append(self.al(), try self.expandForm(it));
                const nf = try self.al().create(Form);
                nf.* = .{ .vector = out };
                return nf;
            },
            .map => {
                var out = std.ArrayList(*Form).empty;
                for (f.map.items) |it| try out.append(self.al(), try self.expandForm(it));
                const nf = try self.al().create(Form);
                nf.* = .{ .map = out };
                return nf;
            },
            .quote => |inner| {
                const nf = try self.al().create(Form);
                nf.* = .{ .quote = try self.expandForm(inner) };
                return nf;
            },
            .syntax_quote => |inner| {
                const nf = try self.al().create(Form);
                nf.* = .{ .syntax_quote = try self.expandForm(inner) };
                return nf;
            },
            else => return f,
        }
    }

    fn expandList(self: *Macro, f: *Form) GrimoireLangError!*Form {
        const items = f.list.items;
        if (items.len == 0) return f;
        const head = items[0];
        if (head.* == .symbol) {
            const s = head.symbol;
            if (eql(s, "defmacro")) {
                if (items.len != 4) return GrimoireLangError.BadForm;
                const name = items[1];
                const params = items[2];
                const template = items[3];
                if (name.* != .symbol or params.* != .vector) return GrimoireLangError.BadForm;
                try self.register(name.symbol, params.vector.items, template);
                const nilf = try self.al().create(Form);
                nilf.* = .{ .nil = {} };
                return nilf;
            }
            if (eql(s, "when")) return self.expandWhen(items);
            if (eql(s, "unless")) return self.expandUnless(items);
            if (eql(s, "cond")) return self.expandCond(items);
            if (eql(s, "->")) return self.expandThread(items, true);
            if (eql(s, "->>")) return self.expandThread(items, false);
            if (self.defs.get(s)) |def| {
                return self.expandUserMacro(def, items[1..]);
            }
        }
        var out = std.ArrayList(*Form).empty;
        for (items) |it| try out.append(self.al(), try self.expandForm(it));
        const nf = try self.al().create(Form);
        nf.* = .{ .list = out };
        return nf;
    }

    fn expandWhen(self: *Macro, items: []*Form) GrimoireLangError!*Form {
        if (items.len < 3) return GrimoireLangError.BadForm;
        return self.makeIf(items[1], try self.makeDo(items[2..]), try self.makeNil());
    }

    fn expandUnless(self: *Macro, items: []*Form) GrimoireLangError!*Form {
        if (items.len < 3) return GrimoireLangError.BadForm;
        return self.makeIf(items[1], try self.makeNil(), try self.makeDo(items[2..]));
    }

    fn expandCond(self: *Macro, items: []*Form) GrimoireLangError!*Form {
        if (items.len < 3 or items.len % 2 == 0) return GrimoireLangError.BadForm;
        return self.expandCondPairs(items[1..]);
    }

    fn expandCondPairs(self: *Macro, pairs: []*Form) GrimoireLangError!*Form {
        if (pairs.len == 0) return self.makeNil();
        if (pairs.len == 2) return self.makeIf(pairs[0], pairs[1], try self.makeNil());
        const else_sym = try self.al().create(Form);
        else_sym.* = .{ .symbol = ":else" };
        if (pairs[0].* == .symbol and eql(pairs[0].symbol, ":else")) return pairs[1];
        return self.makeIf(pairs[0], pairs[1], try self.expandCondPairs(pairs[2..]));
    }

    fn expandThread(self: *Macro, items: []*Form, first: bool) GrimoireLangError!*Form {
        if (items.len < 3) return GrimoireLangError.BadForm;
        var acc = items[1];
        var i: usize = 2;
        while (i < items.len) : (i += 1) {
            acc = try self.threadStep(acc, items[i], first);
        }
        return acc;
    }

    fn threadStep(self: *Macro, acc: *Form, expr: *Form, first: bool) GrimoireLangError!*Form {
        var out = std.ArrayList(*Form).empty;
        if (expr.* == .list) {
            try out.append(self.al(), expr.list.items[0]);
            if (first) try out.append(self.al(), acc);
            for (expr.list.items[1..]) |it| try out.append(self.al(), it);
            if (!first) try out.append(self.al(), acc);
        } else if (expr.* == .symbol) {
            try out.append(self.al(), expr);
            try out.append(self.al(), acc);
        } else {
            return GrimoireLangError.BadForm;
        }
        const nf = try self.al().create(Form);
        nf.* = .{ .list = out };
        return nf;
    }

    fn expandUserMacro(self: *Macro, def: *MacroDef, args: []*Form) GrimoireLangError!*Form {
        if (def.rest_param == null and args.len != def.params.len) return GrimoireLangError.BadForm;
        if (def.rest_param != null and args.len < def.params.len) return GrimoireLangError.BadForm;
        var bindings = std.StringHashMapUnmanaged(*Form).empty;
        var i: usize = 0;
        while (i < def.params.len) : (i += 1) {
            const p = def.params[i];
            if (p.* != .symbol) return GrimoireLangError.BadForm;
            try bindings.put(self.al(), p.symbol, args[i]);
        }
        var rest_items = std.ArrayList(*Form).empty;
        while (i < args.len) : (i += 1) try rest_items.append(self.al(), args[i]);
        return self.expandTemplate(def.template, &bindings, def.rest_param, rest_items.items);
    }

    fn expandTemplate(self: *Macro, f: *Form, bindings: *std.StringHashMapUnmanaged(*Form), rest_param: ?[]const u8, rest_args: []*Form) GrimoireLangError!*Form {
        switch (f.*) {
            .unquote => |inner| {
                if (inner.* == .symbol) {
                    if (bindings.get(inner.symbol)) |arg| return arg;
                }
                return inner;
            },
            .unquote_splice => |inner| {
                if (inner.* == .symbol and rest_param != null and eql(inner.symbol, rest_param.?)) {
                    const nf = try self.al().create(Form);
                    nf.* = .{ .unquote_splice = try self.makeListFromSlice(rest_args) };
                    return nf;
                }
                return inner;
            },
            .list => return self.expandTemplateList(f.list.items, bindings, rest_param, rest_args),
            .vector => {
                var out = std.ArrayList(*Form).empty;
                for (f.vector.items) |it| try out.append(self.al(), try self.expandTemplate(it, bindings, rest_param, rest_args));
                const nf = try self.al().create(Form);
                nf.* = .{ .vector = out };
                return nf;
            },
            .map => {
                var out = std.ArrayList(*Form).empty;
                for (f.map.items) |it| try out.append(self.al(), try self.expandTemplate(it, bindings, rest_param, rest_args));
                const nf = try self.al().create(Form);
                nf.* = .{ .map = out };
                return nf;
            },
            else => return f,
        }
    }

    fn expandTemplateList(self: *Macro, items: []*Form, bindings: *std.StringHashMapUnmanaged(*Form), rest_param: ?[]const u8, rest_args: []*Form) GrimoireLangError!*Form {
        var out = std.ArrayList(*Form).empty;
        var i: usize = 0;
        while (i < items.len) : (i += 1) {
            const it = items[i];
            if (it.* == .unquote_splice and it.unquote_splice.* == .symbol and rest_param != null and eql(it.unquote_splice.symbol, rest_param.?)) {
                for (rest_args) |a| try out.append(self.al(), a);
            } else {
                try out.append(self.al(), try self.expandTemplate(it, bindings, rest_param, rest_args));
            }
        }
        const nf = try self.al().create(Form);
        nf.* = .{ .list = out };
        return nf;
    }

    fn makeListFromSlice(self: *Macro, items: []*Form) GrimoireLangError!*Form {
        var out = std.ArrayList(*Form).empty;
        for (items) |it| try out.append(self.al(), it);
        const nf = try self.al().create(Form);
        nf.* = .{ .list = out };
        return nf;
    }

    fn makeIf(self: *Macro, cond: *Form, then_branch: *Form, else_branch: *Form) GrimoireLangError!*Form {
        var out = std.ArrayList(*Form).empty;
        const sym = try self.al().create(Form);
        sym.* = .{ .symbol = "if" };
        try out.append(self.al(), sym);
        try out.append(self.al(), cond);
        try out.append(self.al(), then_branch);
        try out.append(self.al(), else_branch);
        const nf = try self.al().create(Form);
        nf.* = .{ .list = out };
        return nf;
    }

    fn makeDo(self: *Macro, body: []*Form) GrimoireLangError!*Form {
        var out = std.ArrayList(*Form).empty;
        const sym = try self.al().create(Form);
        sym.* = .{ .symbol = "do" };
        try out.append(self.al(), sym);
        for (body) |b| try out.append(self.al(), b);
        const nf = try self.al().create(Form);
        nf.* = .{ .list = out };
        return nf;
    }

    fn makeNil(self: *Macro) GrimoireLangError!*Form {
        const nf = try self.al().create(Form);
        nf.* = .{ .nil = {} };
        return nf;
    }
};

// ═════════════════════════════════════════════════════════════════════════════
// Emitter
// ═════════════════════════════════════════════════════════════════════════════

const Emit = struct {
    arena: *std.heap.ArenaAllocator,
    out: std.ArrayList(u8),
    ind: usize,
    label_id: usize,
    externs: std.StringHashMapUnmanaged(void),
    io: std.Io,
    src_dir: []const u8,
    out_dir: []const u8,

    fn init(arena: *std.heap.ArenaAllocator, io: std.Io, src_dir: []const u8, out_dir: []const u8) Emit {
        return .{ .arena = arena, .out = std.ArrayList(u8).empty, .ind = 0, .label_id = 0, .externs = std.StringHashMapUnmanaged(void).empty, .io = io, .src_dir = src_dir, .out_dir = out_dir };
    }

    fn freshLabel(self: *Emit) []const u8 {
        const n = self.label_id;
        self.label_id += 1;
        return std.fmt.allocPrint(self.al(), "gr__{d}", .{n}) catch "gr__err";
    }

    fn al(self: Emit) std.mem.Allocator { return self.arena.allocator(); }

    fn emitProg(self: *Emit, forms: []*Form) GrimoireLangError![]const u8 {
        try self.w("const std = @import(\"std\");\n");
        try self.w("const gr = @import(\"gr_runtime.zig\");\n\n");
        try self.w("var gr_arena_impl = std.heap.ArenaAllocator.init(std.heap.page_allocator);\n");
        try self.w("const gr_arena = gr_arena_impl.allocator();\n\n");
        for (forms) |f| {
            try self.emitTop(f);
            try self.w("\n");
        }
        return self.out.toOwnedSlice(self.al());
    }

    fn emitTop(self: *Emit, f: *Form) GrimoireLangError!void {
        if (f.* == .nil) return;
        if (f.* != .list or f.list.items.len == 0) return GrimoireLangError.BadForm;
        const head = f.list.items[0];
        if (head.* != .symbol) return GrimoireLangError.BadForm;
        const s = head.symbol;
        if (eql(s, "ns")) return self.emitNs(f);
        if (eql(s, "require")) return self.emitRequire(f);
        if (eql(s, "import")) return self.emitImport(f);
        if (eql(s, "def")) return self.emitDef(f);
        if (eql(s, "defn")) return self.emitDefn(f);
        if (eql(s, "zig/extern")) return self.emitZigExtern(f);
        if (eql(s, "c/import")) return self.emitCImport(f);
        if (eql(s, "zig/export")) return self.emitZigExport(f);
        return GrimoireLangError.BadForm;
    }

    fn emitNs(self: *Emit, f: *Form) GrimoireLangError!void {
        if (f.list.items.len != 2) return GrimoireLangError.BadForm;
        const name = f.list.items[1];
        if (name.* != .symbol) return GrimoireLangError.BadForm;
        try self.w("// namespace "); try self.w(name.symbol);
    }

    fn emitRequire(self: *Emit, f: *Form) GrimoireLangError!void {
        const items = f.list.items;
        if (items.len < 2) return GrimoireLangError.BadForm;
        var i: usize = 1;
        while (i < items.len) : (i += 1) {
            const spec = items[i];
            if (spec.* != .vector or spec.vector.items.len != 3) return GrimoireLangError.BadForm;
            const mod = spec.vector.items[0];
            const as_kw = spec.vector.items[1];
            const alias = spec.vector.items[2];
            if (mod.* != .symbol or as_kw.* != .keyword or !eql(as_kw.keyword, ":as") or alias.* != .symbol) return GrimoireLangError.BadForm;
            const zig_name = try std.fmt.allocPrint(self.al(), "{s}.zig", .{mod.symbol});
            const gr_name = try std.fmt.allocPrint(self.al(), "{s}.gr", .{mod.symbol});
            const gr_path = try std.fs.path.join(self.al(), &.{ self.src_dir, gr_name });
            const zig_path = try std.fs.path.join(self.al(), &.{ self.out_dir, zig_name });
            try compileFileWithDir(self.arena, self.io, gr_path, zig_path);
            try self.w("const "); try self.w(alias.symbol); try self.w(" = @import(\""); try self.w(zig_name); try self.w("\");\n");
        }
    }

    fn emitImport(self: *Emit, f: *Form) GrimoireLangError!void {
        const items = f.list.items;
        if (items.len < 2) return GrimoireLangError.BadForm;
        var i: usize = 1;
        while (i < items.len) : (i += 1) {
            const spec = items[i];
            if (spec.* != .vector or spec.vector.items.len != 3) return GrimoireLangError.BadForm;
            const mod = spec.vector.items[0];
            const as_kw = spec.vector.items[1];
            const alias = spec.vector.items[2];
            if (mod.* != .symbol or as_kw.* != .keyword or !eql(as_kw.keyword, ":as") or alias.* != .symbol) return GrimoireLangError.BadForm;
            try self.w("const "); try self.w(alias.symbol); try self.w(" = @import(\""); try self.w(mod.symbol); try self.w("\");\n");
        }
    }

    fn emitDef(self: *Emit, f: *Form) GrimoireLangError!void {
        if (f.list.items.len != 3) return GrimoireLangError.BadForm;
        const name = f.list.items[1];
        if (name.* != .symbol) return GrimoireLangError.BadForm;
        try self.w("pub const "); try self.w(try zigId(self.al(), name.symbol)); try self.w(" = ");
        try self.emitExpr(f.list.items[2]);
        try self.w(";");
    }

    fn emitDefn(self: *Emit, f: *Form) GrimoireLangError!void {
        if (f.list.items.len < 4) return GrimoireLangError.BadForm;
        const name = f.list.items[1];
        const params = f.list.items[2];
        if (name.* != .symbol or params.* != .vector) return GrimoireLangError.BadForm;
        const is_main = eql(name.symbol, "main");

        try self.w("pub fn "); try self.w(try zigId(self.al(), name.symbol)); try self.w("(");
        for (params.vector.items, 0..) |p, i| {
            if (i > 0) try self.w(", ");
            if (p.* != .symbol) return GrimoireLangError.BadForm;
            try self.w(try zigId(self.al(), p.symbol)); try self.w(": gr.Value");
        }
        if (is_main) try self.w(") void {\n") else try self.w(") gr.Value {\n");
        self.ind += 4;
        const body = f.list.items[3..];
        if (is_main) {
            for (body) |b| { try self.id(); try self.w("_ = "); try self.emitExpr(b); try self.w(";\n"); }
        } else {
            for (body[0..body.len-1]) |b| { try self.id(); try self.w("_ = "); try self.emitExpr(b); try self.w(";\n"); }
            try self.id(); try self.w("return "); try self.emitExpr(body[body.len-1]); try self.w(";\n");
        }
        self.ind -= 4;
        try self.w("}");
    }

    fn emitZigExtern(self: *Emit, f: *Form) GrimoireLangError!void {
        if (f.list.items.len != 3) return GrimoireLangError.BadForm;
        const sig = f.list.items[2];
        if (sig.* != .string) return GrimoireLangError.BadForm;
        const s = sig.string[1..sig.string.len-1];
        try self.w("extern "); try self.w(s); try self.w(";");
        const name = externName(s) orelse return;
        try self.externs.put(self.al(), name, {});
    }

    fn isExtern(self: *Emit, name: []const u8) bool {
        return self.externs.contains(name);
    }

    fn emitCImport(self: *Emit, f: *Form) GrimoireLangError!void {
        if (f.list.items.len != 2) return GrimoireLangError.BadForm;
        const h = f.list.items[1];
        if (h.* != .string) return GrimoireLangError.BadForm;
        try self.w("// c/import "); try self.w(h.string[1..h.string.len-1]);
    }

    fn emitZigExport(self: *Emit, f: *Form) GrimoireLangError!void {
        if (f.list.items.len != 2) return GrimoireLangError.BadForm;
        try self.w("// export: "); try self.w(f.list.items[1].symbol);
    }

    fn emitExpr(self: *Emit, f: *Form) GrimoireLangError!void {
        switch (f.*) {
            .number => |s| { try self.w("gr.number("); try self.w(s); try self.w(")"); },
            .string => |s| { try self.w("gr.string("); try self.w(s); try self.w(")"); },
            .symbol => |s| {
                if (eql(s, "true") or eql(s, "false")) try self.w("gr.boolean(") else if (eql(s, "nil")) { try self.w("gr.nil"); return; }
                else { try self.w(try self.emitSymbol(s)); return; }
                try self.w(s); try self.w(")");
            },
            .keyword => |s| { try self.w("gr.keyword(\""); try self.w(s[1..]); try self.w("\")"); },
            .boolean => |b| { try self.w("gr.boolean("); try self.w(if (b) "true" else "false"); try self.w(")"); },
            .nil => try self.w("gr.nil"),
            .list => try self.emitList(f),
            .vector => try self.emitVec(f),
            .map => try self.emitMap(f),
            .quote => |inner| try self.emitLit(inner),
            .syntax_quote => |inner| { try self.w("(syntax-quote "); try self.emitExpr(inner); try self.w(")"); },
            .unquote => |inner| try self.emitExpr(inner),
            .unquote_splice => |inner| try self.emitExpr(inner),
            .deref => |inner| { try self.w("gr.deref("); try self.emitExpr(inner); try self.w(")"); },
            .meta => |inner| try self.emitExpr(inner),
        }
    }

    fn emitList(self: *Emit, f: *Form) GrimoireLangError!void {
        const items = f.list.items;
        if (items.len == 0) { try self.w(".{}"); return; }
        const head = items[0];
        if (head.* == .symbol) {
            const s = head.symbol;
            if (eql(s, "if")) return self.emitIf(f);
            if (eql(s, "let")) return self.emitLet(f);
            if (eql(s, "do")) return self.emitDo(f);
            if (eql(s, "fn")) return self.emitFn(f);
            if (eql(s, "quote")) { try self.emitLit(items[1]); return; }
            if (eql(s, "zig/comptime")) { try self.w("comptime ("); try self.emitExpr(items[1]); try self.w(")"); return; }
            if (eql(s, "list")) { try self.w("gr.listFrom(gr_arena, &.{"); for (items[1..], 0..) |a, i| { if (i > 0) try self.w(", "); try self.emitExpr(a); } try self.w("}) catch gr.nil"); return; }
            if (eql(s, "vector")) { try self.w("gr.vectorFrom(gr_arena, &.{"); for (items[1..], 0..) |a, i| { if (i > 0) try self.w(", "); try self.emitExpr(a); } try self.w("}) catch gr.nil"); return; }
            if (eql(s, "map")) { try self.w("gr.mapFrom(gr_arena, &.{"); var i: usize = 1; while (i < items.len) : (i += 2) { if (i > 1) try self.w(", "); try self.w(".{ .key = "); try self.emitExpr(items[i]); try self.w(", .val = "); try self.emitExpr(items[i+1]); try self.w(" }"); } try self.w("}) catch gr.nil"); return; }
            if (eql(s, "hash-set")) { try self.w("gr.setFrom(gr_arena, &.{"); for (items[1..], 0..) |a, i| { if (i > 0) try self.w(", "); try self.emitExpr(a); } try self.w("}) catch gr.nil"); return; }
            if (eql(s, "count")) { try self.w("gr.number(gr.count("); try self.emitExpr(items[1]); try self.w("))"); return; }
            if (eql(s, "first")) { try self.w("gr.first("); try self.emitExpr(items[1]); try self.w(")"); return; }
            if (eql(s, "rest")) { try self.w("gr.rest("); try self.emitExpr(items[1]); try self.w(", gr_arena)"); return; }
            if (eql(s, "next")) { try self.w("gr.rest("); try self.emitExpr(items[1]); try self.w(", gr_arena)"); return; }
            if (eql(s, "conj")) { try self.w("gr.conj("); try self.emitExpr(items[1]); try self.w(", gr_arena, "); try self.emitExpr(items[2]); try self.w(") catch gr.nil"); return; }
            if (eql(s, "concat")) { try self.w("gr.concat(gr_arena, "); try self.emitExpr(items[1]); try self.w(", "); try self.emitExpr(items[2]); try self.w(") catch gr.nil"); return; }
            if (eql(s, "get")) { try self.w("gr.get("); try self.emitExpr(items[1]); try self.w(", "); try self.emitExpr(items[2]); try self.w(")"); return; }
            if (eql(s, "assoc")) { try self.w("gr.assoc("); try self.emitExpr(items[1]); try self.w(", gr_arena, "); try self.emitExpr(items[2]); try self.w(", "); try self.emitExpr(items[3]); try self.w(") catch gr.nil"); return; }
            if (eql(s, "contains?")) { try self.w("gr.boolean(gr.contains("); try self.emitExpr(items[1]); try self.w(", "); try self.emitExpr(items[2]); try self.w("))"); return; }
            const op = binOp(s);
            if (op) |o| return self.emitBin(o, items[1..]);
            if (eql(s, "print")) return self.emitPrint(items[1..]);
            return self.emitCall(s, items[1..]);
        }
        try self.w("("); try self.emitExpr(head); try self.w(")(");
        for (items[1..], 0..) |a, i| { if (i > 0) try self.w(", "); try self.emitExpr(a); }
        try self.w(")");
    }

    fn emitIf(self: *Emit, f: *Form) GrimoireLangError!void {
        const it = f.list.items;
        if (it.len < 3 or it.len > 4) return GrimoireLangError.BadForm;
        try self.w("if (gr.truthy("); try self.emitExpr(it[1]); try self.w(")) ");
        try self.emitExpr(it[2]);
        if (it.len == 4) {
            try self.w(" else ");
            try self.emitExpr(it[3]);
        }
    }

    fn emitLet(self: *Emit, f: *Form) GrimoireLangError!void {
        const it = f.list.items;
        if (it.len < 3) return GrimoireLangError.BadForm;
        const binds = it[1];
        if (binds.* != .vector) return GrimoireLangError.BadForm;
        const label = self.freshLabel();
        try self.w(label); try self.w(": {\n"); self.ind += 4;
        const ps = binds.vector.items;
        var i: usize = 0;
        while (i < ps.len) : (i += 2) {
            if (i + 1 >= ps.len) return GrimoireLangError.BadForm;
            try self.id(); try self.w("const "); try self.w(try zigId(self.al(), ps[i].symbol)); try self.w(" = ");
            try self.emitExpr(ps[i + 1]); try self.w(";\n");
        }
        const body = it[2..];
        for (body[0..body.len-1]) |b| { try self.id(); try self.w("_ = "); try self.emitExpr(b); try self.w(";\n"); }
        try self.id(); try self.w("break :"); try self.w(label); try self.w(" "); try self.emitExpr(body[body.len-1]); try self.w(";\n");
        self.ind -= 4; try self.id(); try self.w("}");
    }

    fn emitDo(self: *Emit, f: *Form) GrimoireLangError!void {
        const it = f.list.items;
        if (it.len == 1) { try self.w("{}"); return; }
        const label = self.freshLabel();
        try self.w(label); try self.w(": {\n"); self.ind += 4;
        const body = it[1..];
        for (body[0..body.len-1]) |b| { try self.id(); try self.w("_ = "); try self.emitExpr(b); try self.w(";\n"); }
        try self.id(); try self.w("break :"); try self.w(label); try self.w(" "); try self.emitExpr(body[body.len-1]); try self.w(";\n");
        self.ind -= 4; try self.id(); try self.w("}");
    }

    fn emitFn(self: *Emit, f: *Form) GrimoireLangError!void {
        const it = f.list.items;
        if (it.len < 3) return GrimoireLangError.BadForm;
        const params = it[1];
        if (params.* != .vector) return GrimoireLangError.BadForm;
        try self.w("struct {\n"); self.ind += 4;
        try self.id(); try self.w("pub fn call(self: @This(), ");
        for (params.vector.items, 0..) |p, i| {
            if (i > 0) try self.w(", ");
            try self.w(try zigId(self.al(), p.symbol)); try self.w(": gr.Value");
        }
        try self.w(") gr.Value {\n"); self.ind += 4;
        const body = it[2..];
        for (body[0..body.len-1]) |b| { try self.id(); try self.w("_ = "); try self.emitExpr(b); try self.w(";\n"); }
        try self.id(); try self.w("return "); try self.emitExpr(body[body.len-1]); try self.w(";\n");
        self.ind -= 4; try self.id(); try self.w("}\n"); self.ind -= 4; try self.id(); try self.w("}{}");
    }

    fn emitBin(self: *Emit, op: []const u8, args: []*Form) GrimoireLangError!void {
        if (args.len == 0) { try self.w("gr.number(0)"); return; }
        if (args.len == 1) {
            if (eql(op, "not")) {
                try self.w("gr.boolean(!gr.truthy("); try self.emitExpr(args[0]); try self.w("))");
            } else {
                try self.w("gr."); try self.w(op); try self.w("("); try self.emitExpr(args[0]); try self.w(")");
            }
            return;
        }
        if (eql(op, "equal")) {
            try self.w("gr.equal("); try self.emitExpr(args[0]); try self.w(", "); try self.emitExpr(args[1]); try self.w(")");
            return;
        }
        if (eql(op, "not_equal")) {
            try self.w("gr.boolean(!gr.equal("); try self.emitExpr(args[0]); try self.w(", "); try self.emitExpr(args[1]); try self.w("))");
            return;
        }
        if (eql(op, "and") or eql(op, "or")) {
            try self.w("gr.boolean((gr.truthy("); try self.emitExpr(args[0]);
            try self.w(") "); try self.w(op); try self.w(" gr.truthy("); try self.emitExpr(args[1]); try self.w(")))");
            return;
        }
        if (args.len == 2) {
            try self.w("gr."); try self.w(op); try self.w("("); try self.emitExpr(args[0]); try self.w(", "); try self.emitExpr(args[1]); try self.w(")");
        } else {
            try self.w("gr."); try self.w(op); try self.w("(");
            try self.emitBin(op, args[0 .. args.len - 1]);
            try self.w(", "); try self.emitExpr(args[args.len - 1]); try self.w(")");
        }
    }

    fn emitPrint(self: *Emit, args: []*Form) GrimoireLangError!void {
        if (args.len == 0) { try self.w("gr.nil"); return; }
        if (args.len == 1) {
            try self.w("gr.grPrint("); try self.emitExpr(args[0]); try self.w(")");
            return;
        }
        const label = self.freshLabel();
        try self.w(label); try self.w(": {\n"); self.ind += 4;
        for (args) |a| { try self.id(); try self.w("_ = gr.grPrint("); try self.emitExpr(a); try self.w(");\n"); }
        try self.id(); try self.w("break :"); try self.w(label); try self.w(" gr.nil;\n"); self.ind -= 4; try self.id(); try self.w("}");
    }

    fn emitCall(self: *Emit, name: []const u8, args: []*Form) GrimoireLangError!void {
        // c/printf -> printf (strip c/ for FFI calls)
        // ns/f -> ns.f
        const callee = if (std.mem.startsWith(u8, name, "c/")) name[2..] else name;
        const slash = std.mem.indexOf(u8, callee, "/");
        if (slash) |s| {
            try self.w(try zigId(self.al(), callee[0..s])); try self.w("."); try self.w(try zigId(self.al(), callee[s+1..]));
        } else {
            try self.w(try zigId(self.al(), callee));
        }
        try self.w("(");
        const is_extern = self.isExtern(if (slash) |s| callee[0..s] else callee);
        for (args, 0..) |a, i| {
            if (i > 0) try self.w(", ");
            if (is_extern) try self.emitExternArg(a) else try self.emitExpr(a);
        }
        try self.w(")");
    }

    fn emitSymbol(self: *Emit, s: []const u8) GrimoireLangError![]const u8 {
        if (std.mem.startsWith(u8, s, "c/")) return zigId(self.al(), s[2..]);
        const slash = std.mem.indexOf(u8, s, "/");
        if (slash) |i| {
            const alias = try zigId(self.al(), s[0..i]);
            const name = try zigId(self.al(), s[i + 1..]);
            return std.fmt.allocPrint(self.al(), "{s}.{s}", .{ alias, name }) catch GrimoireLangError.OutOfMemory;
        }
        return zigId(self.al(), s);
    }

    fn emitExternArg(self: *Emit, a: *Form) GrimoireLangError!void {
        switch (a.*) {
            .string => |s| try self.w(s),
            .number => |s| try self.w(s),
            .boolean => |b| try self.w(if (b) "true" else "false"),
            .nil => try self.w("null"),
            else => try self.emitExpr(a),
        }
    }

    fn emitVec(self: *Emit, f: *Form) GrimoireLangError!void {
        try self.w("gr.vectorFrom(gr_arena, &.{");
        for (f.vector.items, 0..) |it, i| { if (i > 0) try self.w(", "); try self.emitExpr(it); }
        try self.w("}) catch gr.nil");
    }

    fn emitMap(self: *Emit, f: *Form) GrimoireLangError!void {
        try self.w("gr.mapFrom(gr_arena, &.{");
        var i: usize = 0;
        while (i < f.map.items.len) : (i += 2) {
            if (i > 0) try self.w(", ");
            try self.w(".{ .key = "); try self.emitExpr(f.map.items[i]); try self.w(", .val = "); try self.emitExpr(f.map.items[i+1]); try self.w(" }");
        }
        try self.w("}) catch gr.nil");
    }

    fn emitLit(self: *Emit, f: *Form) GrimoireLangError!void {
        switch (f.*) {
            .number, .string, .boolean, .nil, .keyword, .symbol => try self.emitExpr(f),
            .vector => { try self.w("gr.vectorFrom(gr_arena, &.{"); for (f.vector.items, 0..) |it, i| { if (i > 0) try self.w(", "); try self.emitLit(it); } try self.w("}) catch gr.nil"); },
            .list => { try self.w("gr.listFrom(gr_arena, &.{"); for (f.list.items, 0..) |it, i| { if (i > 0) try self.w(", "); try self.emitLit(it); } try self.w("}) catch gr.nil"); },
            .map => { try self.w("gr.mapFrom(gr_arena, &.{"); var i: usize = 0; while (i < f.map.items.len) : (i += 2) { if (i > 0) try self.w(", "); try self.w(".{ .key = "); try self.emitLit(f.map.items[i]); try self.w(", .val = "); try self.emitLit(f.map.items[i+1]); try self.w(" }"); } try self.w("}) catch gr.nil"); },
            else => try self.emitExpr(f),
        }
    }

    fn w(self: *Emit, s: []const u8) GrimoireLangError!void { try self.out.appendSlice(self.al(), s); }
    fn id(self: *Emit) GrimoireLangError!void { var i: usize = 0; while (i < self.ind) : (i += 1) try self.out.append(self.al(), ' '); }
};

fn eql(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }

fn zigId(al: std.mem.Allocator, s: []const u8) std.mem.Allocator.Error![]const u8 {
    var needs = false;
    for (s) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') {
            needs = true;
            break;
        }
    }
    if (!needs) return s;
    const out = try al.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        out[i] = if (std.ascii.isAlphanumeric(c) or c == '_') c else '_';
    }
    return out;
}

fn externName(sig: []const u8) ?[]const u8 {
    const prefix = "fn ";
    if (!std.mem.startsWith(u8, sig, prefix)) return null;
    const rest = sig[prefix.len..];
    const end = std.mem.indexOf(u8, rest, "(") orelse return null;
    return rest[0..end];
}

fn binOp(s: []const u8) ?[]const u8 {
    const ops = .{ .{"+","add"}, .{"-","sub"}, .{"*","mul"}, .{"/","div"}, .{"=","equal"}, .{"not=","not_equal"}, .{"<","lt"}, .{">","gt"}, .{"<=","le"}, .{">=","ge"}, .{"and","and"}, .{"or","or"}, .{"not","not"}, .{"mod","mod"} };
    inline for (ops) |op| { if (eql(s, op[0])) return op[1]; }
    return null;
}

// ═════════════════════════════════════════════════════════════════════════════
// Public API
// ═════════════════════════════════════════════════════════════════════════════

pub fn compile(arena: *std.heap.ArenaAllocator, io: std.Io, src: []const u8) GrimoireLangError![]const u8 {
    return compileWithDir(arena, io, src, "", "");
}

pub fn compileWithDir(arena: *std.heap.ArenaAllocator, io: std.Io, src: []const u8, src_dir: []const u8, out_dir: []const u8) GrimoireLangError![]const u8 {
    var r = try Read.init(arena, src);
    const forms = try r.readAll();
    var m = Macro.init(arena);
    const expanded = try m.expandAll(forms.items);
    var e = Emit.init(arena, io, src_dir, out_dir);
    return try e.emitProg(expanded);
}

pub fn compileFile(arena: *std.heap.ArenaAllocator, io: std.Io, src_path: []const u8, out_path: []const u8) !void {
    const src = try std.Io.Dir.cwd().readFileAlloc(io, src_path, arena.allocator(), .limited(10 * 1024 * 1024));
    const src_dir = std.fs.path.dirname(src_path) orelse "";
    const out_dir = std.fs.path.dirname(out_path) orelse ".";
    const out = try compileWithDir(arena, io, src, src_dir, out_dir);
    try writeRuntime(io, out_dir);
    const file = try std.Io.Dir.cwd().createFile(io, out_path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, out);
}

fn compileFileWithDir(arena: *std.heap.ArenaAllocator, io: std.Io, src_path: []const u8, out_path: []const u8) GrimoireLangError!void {
    const src = std.Io.Dir.cwd().readFileAlloc(io, src_path, arena.allocator(), .limited(10 * 1024 * 1024)) catch return GrimoireLangError.BadForm;
    const src_dir = std.fs.path.dirname(src_path) orelse "";
    const out_dir = std.fs.path.dirname(out_path) orelse ".";
    const out = try compileWithDir(arena, io, src, src_dir, out_dir);
    try writeRuntime(io, out_dir);
    const file = std.Io.Dir.cwd().createFile(io, out_path, .{}) catch return GrimoireLangError.BadForm;
    defer file.close(io);
    file.writeStreamingAll(io, out) catch return GrimoireLangError.BadForm;
}

fn writeRuntime(io: std.Io, out_dir: []const u8) GrimoireLangError!void {
    const rt_path = std.fs.path.join(std.heap.page_allocator, &.{ out_dir, "gr_runtime.zig" }) catch return GrimoireLangError.OutOfMemory;
    defer std.heap.page_allocator.free(rt_path);
    const file = std.Io.Dir.cwd().createFile(io, rt_path, .{}) catch return GrimoireLangError.BadForm;
    defer file.close(io);
    file.writeStreamingAll(io, runtime_src) catch return GrimoireLangError.BadForm;
}

pub fn hello() void {
    std.debug.print("hello grimoire-lang\n", .{});
}

// ═════════════════════════════════════════════════════════════════════════════
// CLI
// ═════════════════════════════════════════════════════════════════════════════

pub fn main(init: std.process.Init) !void {
    const al = init.gpa;
    const io = init.io;
    const args = init.minimal.args;

    var it = std.process.Args.Iterator.init(args);
    defer it.deinit();

    var count: usize = 0;
    var src_path: ?[]const u8 = null;
    var out_path: ?[]const u8 = null;
    while (it.next()) |arg| {
        if (count == 1) src_path = arg;
        if (count == 2) out_path = arg;
        count += 1;
    }

    if (src_path == null) {
        std.debug.print("Usage: grimoire-lang <file.gr> [output.zig]\n", .{});
        std.process.exit(1);
    }

    const out = out_path orelse blk: {
        const base = std.fs.path.basename(src_path.?);
        if (std.mem.endsWith(u8, base, ".gr")) {
            break :blk try std.fmt.allocPrint(al, "{s}.zig", .{base[0..base.len-4]});
        }
        break :blk try std.fmt.allocPrint(al, "{s}.zig", .{base});
    };
    defer if (out_path == null) al.free(out);

    var arena = std.heap.ArenaAllocator.init(al);
    defer arena.deinit();
    try compileFile(&arena, io, src_path.?, out);
}
