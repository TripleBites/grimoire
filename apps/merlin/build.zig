const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const neuro_dep = b.dependency("neuro", .{ .target = target, .optimize = optimize });
    const grimoire_lang_dep = b.dependency("grimoire_lang", .{ .target = target, .optimize = optimize });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/merlin.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("neuro", neuro_dep.module("neuro"));
    exe_mod.addImport("grimoire-lang", grimoire_lang_dep.module("grimoire-lang"));

    const exe = b.addExecutable(.{
        .name = "merlin",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (@hasField(std.Build, "args")) {
        if (b.args) |args| run.addArgs(args);
    } else {
        run.addPassthruArgs();
    }
    const run_step = b.step("run", "Run merlin");
    run_step.dependOn(&run.step);
}
