const std = @import("std");
const Io = std.Io;
const Reader = @import("../reader/Reader.zig").Reader;
const ReaderError = @import("../reader/Reader.zig").ReaderError;
const Form = @import("../reader/Form.zig").Form;
const Emitter = @import("Emitter.zig").Emitter;
const EmitError = @import("Emitter.zig").EmitError;

pub const CompileError = error{
    ReadError,
    EmitError,
    OutOfMemory,
    IoError,
} || ReaderError || EmitError;

pub fn compile(allocator: std.mem.Allocator, source: []const u8) CompileError![]const u8 {
    var forms = std.ArrayList(*Form).empty;
    defer {
        for (forms.items) |f| f.destroy(allocator);
        forms.deinit(allocator);
    }

    var reader = try Reader.init(allocator, source);
    while (true) {
        const form = reader.readForm() catch |err| switch (err) {
            ReaderError.EmptyInput => break,
            else => return err,
        };
        try forms.append(allocator, form);
    }

    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    return try emitter.emitProgram(forms.items);
}

pub fn compileFile(
    allocator: std.mem.Allocator,
    io: Io,
    source_path: []const u8,
    out_path: []const u8,
) CompileError!void {
    const source = Io.Dir.cwd().readFileAlloc(io, source_path, allocator, .limited(10 * 1024 * 1024)) catch |err| {
        std.log.err("Failed to read {s}: {}", .{ source_path, err });
        return CompileError.IoError;
    };
    defer allocator.free(source);

    const output = try compile(allocator, source);
    defer allocator.free(output);

    const file = Io.Dir.cwd().createFile(io, out_path, .{}) catch |err| {
        std.log.err("Failed to create {s}: {}", .{ out_path, err });
        return CompileError.IoError;
    };
    defer file.close(io);

    file.writeStreamingAll(io, output) catch |err| {
        std.log.err("Failed to write {s}: {}", .{ out_path, err });
        return CompileError.IoError;
    };

    std.log.info("Compiled {s} -> {s}", .{ source_path, out_path });
}
