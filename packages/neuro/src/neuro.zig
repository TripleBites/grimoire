const std = @import("std");

pub const name = "neuro";

pub fn hello() void {
    std.debug.print("  [neuro] hello from the neuro package!\n", .{});
}
