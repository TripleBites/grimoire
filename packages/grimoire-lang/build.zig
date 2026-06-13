const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module exposed to dependents
    _ = b.addModule("grimoire-lang", .{
        .root_source_file = b.path("src/grimoire_lang.zig"),
        .target = target,
        .optimize = optimize,
    });

    // CLI executable: grimoire-lang compiler (same root file, uses pub fn main)
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/grimoire_lang.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "grimoire-lang",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run the grimoire-lang compiler");
    run_step.dependOn(&run_cmd.step);

    // Tests: include unit tests in the compiler plus integration tests
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run all grimoire-lang tests");
    test_step.dependOn(&run_tests.step);
}
