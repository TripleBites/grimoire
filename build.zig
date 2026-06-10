const std = @import("std");

// ─────────────────────────────────────────────────────────────────────────────
// Top-level build entry point
//
//  zig build                     → native grimoire + sandbox (install)
//  zig build run-grimoire        → run native grimoire
//  zig build run-sandbox         → run native sandbox
//  zig build cross               → cross-compile all apps for ARM + WASM
// ─────────────────────────────────────────────────────────────────────────────
pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // ── Native (host) ────────────────────────────────────────────────────────
    const native_target = b.standardTargetOptions(.{});
    addApps(b, native_target, optimize, null);

    // ── ARM Linux (Cortex-A hard-float; covers i.MX6, RPi, etc.) ────────────
    const arm_target = b.resolveTargetQuery(.{
        .cpu_arch = .arm,
        .os_tag = .linux,
        .abi = .musleabihf, // musl + hard-float ABI
    });

    // ── WebAssembly / WASI ───────────────────────────────────────────────────
    // WASI gives us a proper stdout so std.debug.print works.
    // Run the output with: wasmtime zig-out/bin/grimoire-wasm.wasm
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });

    // Collect cross-compile artifacts under a single "cross" step so the
    // default `zig build` stays fast (native only).
    const cross_step = b.step("cross", "Cross-compile all apps for ARM + WASM");

    addCrossApps(b, arm_target, optimize, "arm", cross_step);
    addCrossApps(b, wasm_target, optimize, "wasm", cross_step);
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Adds both apps for *native* target: installs them and wires up run-<name>
/// steps.
fn addApps(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// null  → native (no suffix, run-<name> steps registered)
    tag: ?[]const u8,
) void {
    const neuro_dep = b.dependency("neuro", .{ .target = target, .optimize = optimize });
    const zag_dep = b.dependency("zag", .{ .target = target, .optimize = optimize });

    addApp(b, target, optimize, tag, "grimoire", "apps/grimoire/grimoire.zig", neuro_dep, zag_dep);
    addApp(b, target, optimize, tag, "sandbox", "apps/sandbox/sandbox.zig", neuro_dep, zag_dep);
}

/// Adds both apps for a *cross* target; each installed artifact is also
/// wired into `cross_step` so `zig build cross` triggers everything.
fn addCrossApps(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    tag: []const u8,
    cross_step: *std.Build.Step,
) void {
    const neuro_dep = b.dependency("neuro", .{ .target = target, .optimize = optimize });
    const zag_dep = b.dependency("zag", .{ .target = target, .optimize = optimize });

    const apps = [_]struct { name: []const u8, src: []const u8 }{
        .{ .name = "grimoire", .src = "apps/grimoire/grimoire.zig" },
        .{ .name = "sandbox", .src = "apps/sandbox/sandbox.zig" },
    };

    for (apps) |app| {
        const exe = buildExe(b, target, optimize, tag, app.name, app.src, neuro_dep, zag_dep);
        // Attach the install step to cross_step rather than the default install
        const install = b.addInstallArtifact(exe, .{});
        cross_step.dependOn(&install.step);
    }
}

/// Builds one executable, adding it to the default install and (for native
/// builds) registering a `run-<name>` step.
fn addApp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    tag: ?[]const u8,
    name: []const u8,
    src: []const u8,
    neuro_dep: *std.Build.Dependency,
    zag_dep: *std.Build.Dependency,
) void {
    const exe = buildExe(b, target, optimize, tag, name, src, neuro_dep, zag_dep);
    b.installArtifact(exe);

    if (tag == null) {
        const run = b.addRunArtifact(exe);
        if (b.args) |args| run.addArgs(args);
        const run_step = b.step(
            b.fmt("run-{s}", .{name}),
            b.fmt("Run the {s} app", .{name}),
        );
        run_step.dependOn(&run.step);
    }
}

/// Constructs the Compile step; shared by native and cross paths.
fn buildExe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    tag: ?[]const u8,
    name: []const u8,
    src: []const u8,
    neuro_dep: *std.Build.Dependency,
    zag_dep: *std.Build.Dependency,
) *std.Build.Step.Compile {
    const full_name = if (tag) |t|
        b.fmt("{s}-{s}", .{ name, t })
    else
        name;

    const exe = b.addExecutable(.{
        .name = full_name,
        .root_source_file = b.path(src),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("neuro", neuro_dep.module("neuro"));
    exe.root_module.addImport("zag", zag_dep.module("zag"));
    return exe;
}
