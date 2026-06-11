const std = @import("std");
const Form = @import("../reader/Form.zig").Form;
const FormType = @import("../reader/Form.zig").FormType;

pub const EmitError = error{
    InvalidForm,
    UnknownSymbol,
    NotImplemented,
    OutOfMemory,
};

pub const Emitter = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    indent: usize,

    pub fn init(allocator: std.mem.Allocator) Emitter {
        return .{
            .allocator = allocator,
            .output = std.ArrayList(u8).empty,
            .indent = 0,
        };
    }

    pub fn deinit(self: *Emitter) void {
        self.output.deinit(self.allocator);
    }

    pub fn emitProgram(self: *Emitter, forms: []*Form) EmitError![]const u8 {
        try self.write("const std = @import(\"std\");\n\n");
        for (forms) |form| {
            try self.emitTopLevel(form);
            try self.write("\n");
        }
        return self.output.toOwnedSlice(self.allocator);
    }

    fn emitTopLevel(self: *Emitter, form: *Form) EmitError!void {
        switch (form.type) {
            .list => {
                if (form.data.list.items.len == 0) return EmitError.InvalidForm;
                const first = form.data.list.items[0];
                if (first.type != .symbol) {
                    // Top-level expression — wrap in a `comptime` or ignore for now
                    // For MVP, only support def/defn at top level
                    return EmitError.InvalidForm;
                }
                const sym = first.data.symbol;
                if (std.mem.eql(u8, sym, "def")) {
                    try self.emitDef(form);
                } else if (std.mem.eql(u8, sym, "defn")) {
                    try self.emitDefn(form);
                } else if (std.mem.eql(u8, sym, "zig/export")) {
                    try self.emitZigExport(form);
                } else if (std.mem.eql(u8, sym, "c/import")) {
                    try self.emitCImport(form);
                } else if (std.mem.eql(u8, sym, "zig/extern")) {
                    try self.emitZigExtern(form);
                } else {
                    return EmitError.UnknownSymbol;
                }
            },
            else => return EmitError.InvalidForm,
        }
    }

    fn emitDef(self: *Emitter, form: *Form) EmitError!void {
        // (def name value)
        if (form.data.list.items.len != 3) return EmitError.InvalidForm;
        const name_form = form.data.list.items[1];
        const value_form = form.data.list.items[2];
        if (name_form.type != .symbol) return EmitError.InvalidForm;

        try self.write("const ");
        try self.write(name_form.data.symbol);
        try self.write(" = ");
        try self.emitExpr(value_form);
        try self.write(";");
    }

    fn emitDefn(self: *Emitter, form: *Form) EmitError!void {
        // (defn name [params...] body...)
        if (form.data.list.items.len < 4) return EmitError.InvalidForm;
        const name_form = form.data.list.items[1];
        const params_form = form.data.list.items[2];
        if (name_form.type != .symbol) return EmitError.InvalidForm;
        if (params_form.type != .vector) return EmitError.InvalidForm;

        const is_main = std.mem.eql(u8, name_form.data.symbol, "main");

        try self.write("pub fn ");
        try self.write(name_form.data.symbol);
        try self.write("(");

        const params = params_form.data.vector.items;
        for (params, 0..) |param, i| {
            if (i > 0) try self.write(", ");
            if (param.type != .symbol) return EmitError.InvalidForm;
            try self.write(param.data.symbol);
            try self.write(": i64"); // MVP: default to i64
        }
        if (is_main) {
            try self.write(") void {\n");
        } else {
            try self.write(") i64 {\n"); // MVP: default return type i64
        }

        self.indent += 4;

        // Body
        const body = form.data.list.items[3..];
        if (is_main) {
            // void function: no return statement
            for (body) |bf| {
                try self.writeIndent();
                try self.write("_ = ");
                try self.emitExpr(bf);
                try self.write(";\n");
            }
        } else if (body.len == 1) {
            try self.writeIndent();
            try self.write("return ");
            try self.emitExpr(body[0]);
            try self.write(";\n");
        } else {
            // Multiple body forms
            for (body[0 .. body.len - 1]) |bf| {
                try self.writeIndent();
                try self.emitExpr(bf);
                try self.write(";\n");
            }
            try self.writeIndent();
            try self.write("return ");
            try self.emitExpr(body[body.len - 1]);
            try self.write(";\n");
        }

        self.indent -= 4;
        try self.write("}");
    }

    fn emitZigExport(self: *Emitter, form: *Form) EmitError!void {
        // (zig/export name) — marks the following defn as exported
        // MVP: just write export keyword before the function
        // For now, we handle this by having the user write (zig/export fn-name)
        // and we emit: export fn fn-name(...)
        if (form.data.list.items.len != 2) return EmitError.InvalidForm;
        const name_form = form.data.list.items[1];
        if (name_form.type != .symbol) return EmitError.InvalidForm;
        // This is a declaration; the actual defn should follow.
        // For MVP, we'll just emit a comment and expect the user to use it with defn.
        try self.write("// export: ");
        try self.write(name_form.data.symbol);
    }

    fn emitCImport(self: *Emitter, form: *Form) EmitError!void {
        // (c/import "header.h")
        // MVP: @cImport is not available in Zig 0.17; use zig/extern instead
        if (form.data.list.items.len != 2) return EmitError.InvalidForm;
        const header_form = form.data.list.items[1];
        if (header_form.type != .string) return EmitError.InvalidForm;
        const header = header_form.data.string;
        // Remove quotes from string
        const inner = header[1 .. header.len - 1];
        try self.write("// C import from ");
        try self.write(inner);
        try self.write(" (use zig/extern for declarations)");
    }

    fn emitZigExtern(self: *Emitter, form: *Form) EmitError!void {
        // (zig/extern name "signature")
        if (form.data.list.items.len != 3) return EmitError.InvalidForm;
        const name_form = form.data.list.items[1];
        const sig_form = form.data.list.items[2];
        if (name_form.type != .symbol) return EmitError.InvalidForm;
        if (sig_form.type != .string) return EmitError.InvalidForm;
        const sig = sig_form.data.string;
        // Remove quotes from signature string
        const inner = sig[1 .. sig.len - 1];
        try self.write("extern ");
        try self.write(inner);
        try self.write(";");
    }

    fn emitExpr(self: *Emitter, form: *Form) EmitError!void {
        switch (form.type) {
            .number => try self.write(form.data.number),
            .string => try self.write(form.data.string),
            .symbol => {
                // Check for special symbols
                const sym = form.data.symbol;
                if (std.mem.eql(u8, sym, "true")) {
                    try self.write("true");
                } else if (std.mem.eql(u8, sym, "false")) {
                    try self.write("false");
                } else if (std.mem.eql(u8, sym, "nil")) {
                    try self.write("null");
                } else {
                    try self.write(sym);
                }
            },
            .keyword => {
                // Keywords become string literals in Zig for MVP
                try self.write("\"");
                try self.write(form.data.keyword[1..]); // strip :
                try self.write("\"");
            },
            .boolean => try self.write(if (form.data.boolean) "true" else "false"),
            .nil => try self.write("null"),
            .list => try self.emitList(form),
            .vector => try self.emitVector(form),
            .map => try self.emitMap(form),
            .quote => try self.emitQuote(form),
            .syntax_quote => try self.emitSyntaxQuote(form),
            .unquote => try self.emitUnquote(form),
            .unquote_splice => try self.emitUnquoteSplice(form),
            .deref => try self.emitDeref(form),
            .meta => try self.emitMeta(form),
        }
    }

    fn emitList(self: *Emitter, form: *Form) EmitError!void {
        if (form.data.list.items.len == 0) {
            try self.write(".{}");
            return;
        }

        const first = form.data.list.items[0];
        if (first.type == .symbol) {
            const sym = first.data.symbol;

            // Special forms
            if (std.mem.eql(u8, sym, "if")) {
                try self.emitIf(form);
                return;
            }
            if (std.mem.eql(u8, sym, "let")) {
                try self.emitLet(form);
                return;
            }
            if (std.mem.eql(u8, sym, "do")) {
                try self.emitDo(form);
                return;
            }
            if (std.mem.eql(u8, sym, "fn")) {
                try self.emitFn(form);
                return;
            }
            if (std.mem.eql(u8, sym, "quote")) {
                try self.emitQuoteSpecial(form);
                return;
            }
            if (std.mem.eql(u8, sym, "zig/comptime")) {
                try self.emitComptime(form);
                return;
            }

            // Built-in operators / functions
            const op = try self.mapBuiltin(sym);
            if (op) |op_str| {
                try self.emitBinaryOp(op_str, form.data.list.items[1..]);
                return;
            }

            // Function call
            try self.emitCall(sym, form.data.list.items[1..]);
            return;
        }

        // Anonymous function call or other
        try self.write("(");
        try self.emitExpr(first);
        try self.write(")(");
        for (form.data.list.items[1..], 0..) |arg, i| {
            if (i > 0) try self.write(", ");
            try self.emitExpr(arg);
        }
        try self.write(")");
    }

    fn emitIf(self: *Emitter, form: *Form) EmitError!void {
        // (if cond then else?)
        const items = form.data.list.items;
        if (items.len < 3 or items.len > 4) return EmitError.InvalidForm;

        try self.write("(if (");
        try self.emitExpr(items[1]);
        try self.write(") ");
        try self.emitExpr(items[2]);
        if (items.len == 4) {
            try self.write(" else ");
            try self.emitExpr(items[3]);
        } else {
            try self.write(" else null");
        }
        try self.write(")");
    }

    fn emitLet(self: *Emitter, form: *Form) EmitError!void {
        // (let [bindings...] body...)
        const items = form.data.list.items;
        if (items.len < 3) return EmitError.InvalidForm;
        const bindings = items[1];
        if (bindings.type != .vector) return EmitError.InvalidForm;

        try self.write("blk: {\n");
        self.indent += 4;

        const pairs = bindings.data.vector.items;
        var i: usize = 0;
        while (i < pairs.len) : (i += 2) {
            if (i + 1 >= pairs.len) return EmitError.InvalidForm;
            const name = pairs[i];
            const val = pairs[i + 1];
            if (name.type != .symbol) return EmitError.InvalidForm;

            try self.writeIndent();
            try self.write("const ");
            try self.write(name.data.symbol);
            try self.write(" = ");
            try self.emitExpr(val);
            try self.write(";\n");
        }

        const body = items[2..];
        for (body[0 .. body.len - 1]) |bf| {
            try self.writeIndent();
            try self.emitExpr(bf);
            try self.write(";\n");
        }
        try self.writeIndent();
        try self.write("break :blk ");
        try self.emitExpr(body[body.len - 1]);
        try self.write(";\n");

        self.indent -= 4;
        try self.writeIndent();
        try self.write("}");
    }

    fn emitDo(self: *Emitter, form: *Form) EmitError!void {
        const items = form.data.list.items;
        if (items.len == 1) {
            try self.write("{}");
            return;
        }

        try self.write("blk: {\n");
        self.indent += 4;

        const body = items[1..];
        for (body[0 .. body.len - 1]) |bf| {
            try self.writeIndent();
            try self.emitExpr(bf);
            try self.write(";\n");
        }
        try self.writeIndent();
        try self.write("break :blk ");
        try self.emitExpr(body[body.len - 1]);
        try self.write(";\n");

        self.indent -= 4;
        try self.writeIndent();
        try self.write("}");
    }

    fn emitFn(self: *Emitter, form: *Form) EmitError!void {
        // (fn [params...] body...)
        const items = form.data.list.items;
        if (items.len < 3) return EmitError.InvalidForm;
        const params = items[1];
        if (params.type != .vector) return EmitError.InvalidForm;

        try self.write("struct {\n");
        self.indent += 4;
        try self.writeIndent();
        try self.write("pub fn call(self: @This(), ");

        const pitems = params.data.vector.items;
        for (pitems, 0..) |param, i| {
            if (i > 0) try self.write(", ");
            if (param.type != .symbol) return EmitError.InvalidForm;
            try self.write(param.data.symbol);
            try self.write(": i64");
        }
        try self.write(") i64 {\n");
        self.indent += 4;

        const body = items[2..];
        for (body[0 .. body.len - 1]) |bf| {
            try self.writeIndent();
            try self.emitExpr(bf);
            try self.write(";\n");
        }
        try self.writeIndent();
        try self.write("return ");
        try self.emitExpr(body[body.len - 1]);
        try self.write(";\n");

        self.indent -= 4;
        try self.writeIndent();
        try self.write("}\n");
        self.indent -= 4;
        try self.writeIndent();
        try self.write("}{}");
    }

    fn emitQuoteSpecial(self: *Emitter, form: *Form) EmitError!void {
        // (quote x) -> literal x
        if (form.data.list.items.len != 2) return EmitError.InvalidForm;
        try self.emitLiteral(form.data.list.items[1]);
    }

    fn emitQuote(self: *Emitter, form: *Form) EmitError!void {
        try self.emitLiteral(form.data.quote);
    }

    fn emitSyntaxQuote(self: *Emitter, form: *Form) EmitError!void {
        // MVP: same as quote
        try self.emitLiteral(form.data.syntax_quote);
    }

    fn emitUnquote(self: *Emitter, form: *Form) EmitError!void {
        try self.emitExpr(form.data.unquote);
    }

    fn emitUnquoteSplice(self: *Emitter, form: *Form) EmitError!void {
        try self.emitExpr(form.data.unquote_splice);
    }

    fn emitDeref(self: *Emitter, form: *Form) EmitError!void {
        // @atom -> atom.*
        try self.write("(");
        try self.emitExpr(form.data.deref);
        try self.write(").*");
    }

    fn emitMeta(self: *Emitter, form: *Form) EmitError!void {
        // MVP: ignore metadata
        try self.emitExpr(form.data.meta);
    }

    fn emitLiteral(self: *Emitter, form: *Form) EmitError!void {
        // Emit a form as a compile-time literal
        switch (form.type) {
            .number, .string, .boolean, .nil => try self.emitExpr(form),
            .keyword => {
                try self.write("\"");
                try self.write(form.data.keyword[1..]);
                try self.write("\"");
            },
            .symbol => try self.write(form.data.symbol),
            .vector => {
                try self.write("&.{");
                for (form.data.vector.items, 0..) |item, i| {
                    if (i > 0) try self.write(", ");
                    try self.emitLiteral(item);
                }
                try self.write("}");
            },
            .list => {
                try self.write(".{");
                for (form.data.list.items, 0..) |item, i| {
                    if (i > 0) try self.write(", ");
                    try self.emitLiteral(item);
                }
                try self.write("}");
            },
            .map => {
                try self.write(".{");
                var i: usize = 0;
                while (i < form.data.map.items.len) : (i += 2) {
                    if (i > 0) try self.write(", ");
                    try self.emitLiteral(form.data.map.items[i]);
                    try self.write(" = ");
                    try self.emitLiteral(form.data.map.items[i + 1]);
                }
                try self.write("}");
            },
            else => try self.emitExpr(form),
        }
    }

    fn emitVector(self: *Emitter, form: *Form) EmitError!void {
        // Runtime vector -> array literal for MVP
        try self.write("&.{");
        for (form.data.vector.items, 0..) |item, i| {
            if (i > 0) try self.write(", ");
            try self.emitExpr(item);
        }
        try self.write("}");
    }

    fn emitMap(self: *Emitter, form: *Form) EmitError!void {
        // Runtime map -> anonymous struct literal for MVP
        try self.write(".{");
        var i: usize = 0;
        while (i < form.data.map.items.len) : (i += 2) {
            if (i > 0) try self.write(", ");
            try self.emitExpr(form.data.map.items[i]);
            try self.write(" = ");
            try self.emitExpr(form.data.map.items[i + 1]);
        }
        try self.write("}");
    }

    fn emitBinaryOp(self: *Emitter, op: []const u8, args: []*Form) EmitError!void {
        if (args.len == 0) {
            try self.write("0");
            return;
        }
        if (args.len == 1) {
            try self.write("(");
            try self.write(op);
            try self.write(" ");
            try self.emitExpr(args[0]);
            try self.write(")");
            return;
        }
        try self.write("(");
        for (args, 0..) |arg, i| {
            if (i > 0) {
                try self.write(" ");
                try self.write(op);
                try self.write(" ");
            }
            try self.emitExpr(arg);
        }
        try self.write(")");
    }

    fn emitCall(self: *Emitter, name: []const u8, args: []*Form) EmitError!void {
        // Check for special calls
        if (std.mem.eql(u8, name, "print")) {
            try self.write("std.debug.print(\"");
            for (args, 0..) |arg, i| {
                if (i > 0) try self.write(" \" ++ \"");
                if (arg.type == .string) {
                    try self.write("{s}");
                } else {
                    try self.write("{any}");
                }
            }
            try self.write("\\n\", .{");
            for (args, 0..) |arg, i| {
                if (i > 0) try self.write(", ");
                try self.emitExpr(arg);
            }
            try self.write("})");
            return;
        }

        if (std.mem.eql(u8, name, "str")) {
            try self.write("std.fmt.allocPrint(self.allocator, \"");
            for (args, 0..) |arg, i| {
                _ = arg;
                if (i > 0) try self.write(" \" ++ \"");
                try self.write("{}");
            }
            try self.write("\", .{");
            for (args, 0..) |arg, i| {
                if (i > 0) try self.write(", ");
                try self.emitExpr(arg);
            }
            try self.write("}) catch \"\"");
            return;
        }

        // Convert namespace separators: c/printf -> c.printf
        const zig_name = try self.allocator.dupe(u8, name);
        defer self.allocator.free(zig_name);
        for (zig_name) |*c| {
            if (c.* == '/') c.* = '.';
        }
        try self.write(zig_name);
        try self.write("(");
        for (args, 0..) |arg, i| {
            if (i > 0) try self.write(", ");
            try self.emitExpr(arg);
        }
        try self.write(")");
    }

    fn emitComptime(self: *Emitter, form: *Form) EmitError!void {
        // (zig/comptime expr)
        const items = form.data.list.items;
        if (items.len != 2) return EmitError.InvalidForm;
        try self.write("comptime (");
        try self.emitExpr(items[1]);
        try self.write(")");
    }

    fn mapBuiltin(self: *Emitter, sym: []const u8) EmitError!?[]const u8 {
        _ = self;
        const map = .{
            .{ "+", "+" },
            .{ "-", "-" },
            .{ "*", "*" },
            .{ "/", "/" },
            .{ "=", "==" },
            .{ "not=", "!=" },
            .{ "<", "<" },
            .{ ">", ">" },
            .{ "<=", "<=" },
            .{ ">=", ">=" },
            .{ "and", "and" },
            .{ "or", "or" },
            .{ "not", "!" },
            .{ "bit-and", "&" },
            .{ "bit-or", "|" },
            .{ "bit-xor", "^" },
            .{ "bit-not", "~" },
            .{ "bit-shift-left", "<<" },
            .{ "bit-shift-right", ">>" },
            .{ "mod", "%" },
        };
        inline for (map) |entry| {
            if (std.mem.eql(u8, sym, entry[0])) return entry[1];
        }
        return null;
    }

    fn write(self: *Emitter, s: []const u8) EmitError!void {
        try self.output.appendSlice(self.allocator, s);
    }

    fn writeIndent(self: *Emitter) EmitError!void {
        var i: usize = 0;
        while (i < self.indent) : (i += 1) {
            try self.output.append(self.allocator, ' ');
        }
    }
};

// ── Tests ───────────────────────────────────────────────────────────────────

test "emitter def and defn" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    const source = "(def x 42)\n(defn add [a b] (+ a b))";
    _ = @import("../lexer/Lexer.zig");
    var forms = std.ArrayList(*Form).empty;
    defer {
        for (forms.items) |f| f.destroy(allocator);
        forms.deinit(allocator);
    }

    var reader = try @import("../reader/Reader.zig").Reader.init(allocator, source);
    while (true) {
        const form = reader.readForm() catch break;
        try forms.append(form);
    }

    const result = try emitter.emitProgram(forms.items);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "const x = 42;") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "fn add(a: i64, b: i64) i64") != null);
}
