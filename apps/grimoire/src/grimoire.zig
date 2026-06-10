const std = @import("std");
const neuro = @import("neuro");
const zag = @import("zag");

pub fn main() void {
    std.debug.print("Hello from grimoire!\n", .{});
    neuro.hello();
    zag.hello();
}
