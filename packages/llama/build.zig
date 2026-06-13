const std = @import("std");

// ═════════════════════════════════════════════════════════════════════════════
// llama.cpp Zig package build
//
// Wraps the custom llama.cpp source in libs/llama.cpp/ and exposes a clean
// Zig module under the name "llama".
//
// The package links against the llama.cpp shared libraries produced by the
// CMake build in libs/llama.cpp/build-cpu/.  If the libraries are missing,
// run:
//     zig build build-llama-cpp
// inside this package (or from the workspace root).
// ═════════════════════════════════════════════════════════════════════════════

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const llama_cpp_src = b.path("libs/llama.cpp");
    const llama_bin_path = b.path("libs/llama.cpp/build-cpu/bin");

    // Absolute paths for the CMake invocation
    const llama_cpp_root_abs = b.root.joinString(b.allocator, "libs/llama.cpp") catch @panic("OOM");
    defer b.allocator.free(llama_cpp_root_abs);
    const llama_cpp_build_abs = b.root.joinString(b.allocator, "libs/llama.cpp/build-cpu") catch @panic("OOM");
    defer b.allocator.free(llama_cpp_build_abs);

    // ── Optional: rebuild llama.cpp from source ─────────────────────────────
    const configure = b.addSystemCommand(&.{
        "cmake",
        "-S",
        llama_cpp_root_abs,
        "-B",
        llama_cpp_build_abs,
        "-DCMAKE_BUILD_TYPE=Release",
        "-DBUILD_SHARED_LIBS=ON",
        "-DGGML_NATIVE=ON",
    });

    const build_llama = b.addSystemCommand(&.{
        "cmake",
        "--build",
        llama_cpp_build_abs,
        "--target",
        "llama",
        "ggml",
        "ggml-base",
        "ggml-cpu",
        "--",
        "-j",
        "4",
    });
    build_llama.step.dependOn(&configure.step);

    const build_llama_cpp_step = b.step("build-llama-cpp", "Build llama.cpp shared libraries from source");
    build_llama_cpp_step.dependOn(&build_llama.step);

    // ── Expose the "llama" module ───────────────────────────────────────────
    const llama_mod = b.addModule("llama", .{
        .root_source_file = b.path("src/llama.zig"),
        .target = target,
        .optimize = optimize,
    });

    llama_mod.link_libc = true;
    llama_mod.link_libcpp = true;

    // Headers
    llama_mod.addIncludePath(llama_cpp_src.path(b, "include"));
    llama_mod.addIncludePath(llama_cpp_src.path(b, "ggml/include"));

    // Shared libraries
    llama_mod.addLibraryPath(llama_bin_path);
    llama_mod.linkSystemLibrary("llama", .{ .needed = true });
    llama_mod.linkSystemLibrary("ggml", .{ .needed = true });
    llama_mod.linkSystemLibrary("ggml-base", .{ .needed = true });
    llama_mod.linkSystemLibrary("ggml-cpu", .{ .needed = true });

    // rpath so the produced executable can find the shared libraries at runtime
    const bin_abs = b.root.joinString(b.allocator, "libs/llama.cpp/build-cpu/bin") catch @panic("OOM");
    defer b.allocator.free(bin_abs);
    llama_mod.addRPath(.{ .cwd_relative = bin_abs });
}
