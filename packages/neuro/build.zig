const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Expose "neuro" so dependents can call dep.module("neuro")
    _ = b.addModule("neuro", .{
        .root_source_file = b.path("src/neuro.zig"),
        .target = target,
        .optimize = optimize,
    });
}
