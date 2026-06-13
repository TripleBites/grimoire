const std = @import("std");

// Standalone build for the Mira AI chat CLI.
//
// When working inside the grimoire workspace, this file is not used directly;
// the root build.zig builds Mira from apps/mira/src/mira.zig.  This file lets
// you build Mira on its own with:
//
//   cd apps/mira
//   zig build
//
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const llama_dep = b.dependency("llama", .{ .target = target, .optimize = optimize });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/mira.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("llama", llama_dep.module("llama"));

    const exe = b.addExecutable(.{
        .name = "mira",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    const run_step = b.step("run", "Run the Mira AI chat CLI");
    run_step.dependOn(&run.step);
}
