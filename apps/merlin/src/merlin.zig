const std = @import("std");
const neuro = @import("neuro");
const grimoire_lang = @import("grimoire-lang");

pub fn main() void {
    std.debug.print("hello merlin\n", .{});
    neuro.hello();
    grimoire_lang.hello();
}
