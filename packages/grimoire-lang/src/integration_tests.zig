const std = @import("std");
const gl = @import("grimoire_lang.zig");

// Only scripts that define a `main` function can be compiled into a runnable
// Zig program. Library modules (level_a, level_b, math_lib) are exercised
// indirectly through level_c and use_math. c_ffi is skipped because the
// compiler currently emits only a comment for (c/import ...).
const test_files = [_][]const u8{
    "hello.gr",
    "calc.gr",
    "let_test.gr",
    "demo.gr",
    "level_c.gr",
    "use_math.gr",
    "zig_ffi.gr",
};

test "compile and run integration scripts" {
    const allocator = std.testing.allocator;
    const cwd = std.Io.Dir.cwd();
    const io = std.testing.io;

    // When run from the workspace root the test scripts are under
    // packages/grimoire-lang/test; when run from the package they are under test/.
    const test_dir = blk: {
        cwd.access(io, "test/hello.gr", .{}) catch {
            break :blk "packages/grimoire-lang/test";
        };
        break :blk "test";
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(tmp_path);

    for (test_files) |name| {
        const rel_path = try std.fs.path.join(allocator, &.{ test_dir, name });
        defer allocator.free(rel_path);
        const src = try cwd.readFileAlloc(io, rel_path, allocator, .limited(1024 * 1024));
        defer allocator.free(src);

        const src_dir = std.fs.path.dirname(rel_path) orelse ".";
        const stem = std.fs.path.stem(rel_path);
        const out_name = try std.fmt.allocPrint(allocator, "{s}.zig", .{stem});
        defer allocator.free(out_name);

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const compiled = try gl.compileWithDir(&arena, io, src, src_dir, tmp_path);

        try tmp.dir.writeFile(io, .{ .sub_path = out_name, .data = compiled });
        try tmp.dir.writeFile(io, .{ .sub_path = "gr_runtime.zig", .data = gl.runtime_src });

        const argv = &.{
            "zig", "run", out_name, "-lc",
        };

        var child = try std.process.spawn(io, .{
            .argv = argv,
            .cwd = .{ .path = tmp_path },
            .stdout = .ignore,
            .stderr = .ignore,
        });
        const result = try child.wait(io);
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result);
    }
}
