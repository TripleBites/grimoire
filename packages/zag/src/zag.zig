const std = @import("std");

pub const name = "zag";

pub fn hello() void {
    std.debug.print("  [zag] hello from the zag package!\n", .{});
}
