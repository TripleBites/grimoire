const std = @import("std");

// ─────────────────────────────────────────────────────────────────────────────
// Top-level build entry point
//
//  zig build                     → install merlin + grimoire-lang CLI
//  zig build run-merlin          → run the merlin test-bed app
//  zig build test                → run all package tests
//  zig build cross               → cross-compile merlin for ARM + WASM
// ─────────────────────────────────────────────────────────────────────────────
pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // ── Native (host) ────────────────────────────────────────────────────────
    const native_target = b.standardTargetOptions(.{});
    addPackagesAndApp(b, native_target, optimize, null);
    addMiraApp(b, native_target, optimize);

    // ── ARM Linux (Cortex-A hard-float; covers i.MX6, RPi, etc.) ────────────
    const arm_target = b.resolveTargetQuery(.{
        .cpu_arch = .arm,
        .os_tag = .linux,
        .abi = .musleabihf, // musl + hard-float ABI
    });

    // ── WebAssembly / WASI ───────────────────────────────────────────────────
    // WASI gives us a proper stdout so std.debug.print works.
    // Run the output with: wasmtime zig-out/bin/merlin-wasm.wasm
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });

    // Collect cross-compile artifacts under a single "cross" step so the
    // default `zig build` stays fast (native only).
    const cross_step = b.step("cross", "Cross-compile merlin for ARM + WASM");

    addCrossApp(b, arm_target, optimize, "arm", cross_step);
    addCrossApp(b, wasm_target, optimize, "wasm", cross_step);
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Adds the merlin app for *native* target: installs it and wires up run-merlin
/// step. Also registers package test steps.
fn addPackagesAndApp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// null  → native (no suffix, run-merlin step registered)
    tag: ?[]const u8,
) void {
    const neuro_dep = b.dependency("neuro", .{ .target = target, .optimize = optimize });
    const grimoire_lang_dep = b.dependency("grimoire_lang", .{ .target = target, .optimize = optimize });

    // Package tests (grimoire-lang has integration tests; neuro has none yet)
    const test_step = b.step("test", "Run all package tests");
    if (grimoire_lang_dep.builder.top_level_steps.get("test")) |tl| {
        test_step.dependOn(&tl.step);
    }
    if (neuro_dep.builder.top_level_steps.get("test")) |tl| {
        test_step.dependOn(&tl.step);
    }

    // grimoire-lang CLI (also install it from the root build)
    const grimoire_lang_exe = grimoire_lang_dep.artifact("grimoire-lang");
    b.installArtifact(grimoire_lang_exe);

    // Merlin app as the package test bed
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("apps/merlin/src/merlin.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("neuro", neuro_dep.module("neuro"));
    exe_mod.addImport("grimoire-lang", grimoire_lang_dep.module("grimoire-lang"));

    const full_name = if (tag) |t| b.fmt("merlin-{s}", .{t}) else "merlin";
    const exe = b.addExecutable(.{
        .name = full_name,
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    if (tag == null) {
        const run = b.addRunArtifact(exe);
        if (@hasField(std.Build, "args")) {
            if (b.args) |args| run.addArgs(args);
        } else {
            run.addPassthruArgs();
        }
        const run_step = b.step("run-merlin", "Run the merlin app");
        run_step.dependOn(&run.step);
    }
}

/// Adds the Mira AI chat CLI app for the native target.
fn addMiraApp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const llama_dep = b.dependency("llama", .{ .target = target, .optimize = optimize });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("apps/mira/src/mira.zig"),
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
    const run_step = b.step("run-mira", "Run the Mira AI chat CLI");
    run_step.dependOn(&run.step);
}

/// Adds merlin for a *cross* target; the installed artifact is wired into
/// `cross_step` so `zig build cross` triggers everything.
fn addCrossApp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    tag: []const u8,
    cross_step: *std.Build.Step,
) void {
    const neuro_dep = b.dependency("neuro", .{ .target = target, .optimize = optimize });
    const grimoire_lang_dep = b.dependency("grimoire_lang", .{ .target = target, .optimize = optimize });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("apps/merlin/src/merlin.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("neuro", neuro_dep.module("neuro"));
    exe_mod.addImport("grimoire-lang", grimoire_lang_dep.module("grimoire-lang"));

    const exe = b.addExecutable(.{
        .name = b.fmt("merlin-{s}", .{tag}),
        .root_module = exe_mod,
    });
    const install = b.addInstallArtifact(exe, .{});
    cross_step.dependOn(&install.step);
}
