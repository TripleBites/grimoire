const std = @import("std");

pub const lexer = @import("lexer/Lexer.zig");
pub const reader = @import("reader/Reader.zig");
pub const compiler = @import("compiler/Compiler.zig");
pub const Compiler = compiler;

pub fn compile(allocator: std.mem.Allocator, source: []const u8) compiler.CompileError![]const u8 {
    return compiler.compile(allocator, source);
}

pub fn compileFile(allocator: std.mem.Allocator, io: std.Io, source_path: []const u8, out_path: []const u8) compiler.CompileError!void {
    return compiler.compileFile(allocator, io, source_path, out_path);
}

pub fn hello() void {
    std.debug.print("hello zag\n", .{});
}
