const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Expose "zag" so dependents can call dep.module("zag")
    _ = b.addModule("zag", .{
        .root_source_file = b.path("src/zag.zig"),
        .target = target,
        .optimize = optimize,
    });
}
