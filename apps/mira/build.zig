const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const neuro_dep = b.dependency("neuro", .{ .target = target, .optimize = optimize });
    const zag_dep = b.dependency("zag", .{ .target = target, .optimize = optimize });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/mira.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("neuro", neuro_dep.module("neuro"));
    exe_mod.addImport("zag", zag_dep.module("zag"));

    const exe = b.addExecutable(.{
        .name = "mira",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (@hasField(std.Build, "args")) {
        if (b.args) |args| run.addArgs(args);
    } else {
        run.addPassthruArgs();
    }
    const run_step = b.step("run", "Run mira");
    run_step.dependOn(&run.step);
}
