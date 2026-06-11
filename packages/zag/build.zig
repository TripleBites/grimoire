const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module exposed to dependents
    const zag_mod = b.addModule("zag", .{
        .root_source_file = b.path("src/zag.zig"),
        .target = target,
        .optimize = optimize,
    });

    // CLI executable: zag compiler
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("zag", zag_mod);
    const exe = b.addExecutable(.{
        .name = "zag",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run the zag compiler");
    run_step.dependOn(&run_cmd.step);

    // Tests: run through zag.zig so all imports resolve
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/zag.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run all zag tests");
    test_step.dependOn(&run_tests.step);
}
