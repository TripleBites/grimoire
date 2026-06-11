const std = @import("std");

pub const FormType = enum {
    number,
    string,
    symbol,
    keyword,
    boolean,
    nil,
    list,
    vector,
    map,
    quote,
    syntax_quote,
    unquote,
    unquote_splice,
    deref,
    meta,
};

pub const Form = struct {
    type: FormType,
    data: Data,
    line: u32,
    col: u32,

    pub const Data = union(FormType) {
        number: []const u8, // raw text, parsed later
        string: []const u8,
        symbol: []const u8,
        keyword: []const u8,
        boolean: bool,
        nil: void,
        list: std.ArrayList(*Form),
        vector: std.ArrayList(*Form),
        map: std.ArrayList(*Form), // flat key/value pairs
        quote: *Form,
        syntax_quote: *Form,
        unquote: *Form,
        unquote_splice: *Form,
        deref: *Form,
        meta: *Form,
    };

    pub fn create(allocator: std.mem.Allocator, ftype: FormType, line: u32, col: u32) !*Form {
        const form = try allocator.create(Form);
        form.* = .{
            .type = ftype,
            .data = undefined,
            .line = line,
            .col = col,
        };
        return form;
    }

    pub fn destroy(self: *Form, allocator: std.mem.Allocator) void {
        switch (self.data) {
            .list, .vector, .map => |*items| {
                for (items.items) |item| {
                    item.destroy(allocator);
                }
                items.deinit(allocator);
            },
            .quote, .syntax_quote, .unquote, .unquote_splice, .deref, .meta => |inner| {
                inner.destroy(allocator);
            },
            else => {},
        }
        allocator.destroy(self);
    }

    pub fn format(
        self: Form,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self.data) {
            .number => |s| try writer.print("{s}", .{s}),
            .string => |s| try writer.print("{s}", .{s}),
            .symbol => |s| try writer.print("{s}", .{s}),
            .keyword => |s| try writer.print("{s}", .{s}),
            .boolean => |b| try writer.print("{}", .{b}),
            .nil => try writer.print("nil", .{}),
            .list => |items| {
                try writer.print("(", .{});
                for (items.items, 0..) |item, i| {
                    if (i > 0) try writer.print(" ", .{});
                    try writer.print("{}", .{item.*});
                }
                try writer.print(")", .{});
            },
            .vector => |items| {
                try writer.print("[", .{});
                for (items.items, 0..) |item, i| {
                    if (i > 0) try writer.print(" ", .{});
                    try writer.print("{}", .{item.*});
                }
                try writer.print("]", .{});
            },
            .map => |items| {
                try writer.print("{{", .{});
                var i: usize = 0;
                while (i < items.items.len) : (i += 2) {
                    if (i > 0) try writer.print(", ", .{});
                    try writer.print("{} {}", .{ items.items[i].*, items.items[i + 1].* });
                }
                try writer.print("}}", .{});
            },
            .quote => |inner| try writer.print("(quote {})", .{inner.*}),
            .syntax_quote => |inner| try writer.print("(syntax-quote {})", .{inner.*}),
            .unquote => |inner| try writer.print("(unquote {})", .{inner.*}),
            .unquote_splice => |inner| try writer.print("(unquote-splice {})", .{inner.*}),
            .deref => |inner| try writer.print("(deref {})", .{inner.*}),
            .meta => |inner| try writer.print("(meta {})", .{inner.*}),
        }
    }
};
