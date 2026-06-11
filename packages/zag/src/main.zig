const std = @import("std");
const zag = @import("zag");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var arg_count: usize = 0;
    var it = std.process.Args.Iterator.init(init.minimal.args);
    defer it.deinit();

    var arg_list = std.ArrayList([]const u8).empty;
    defer arg_list.deinit(allocator);

    while (it.next()) |arg| {
        try arg_list.append(allocator, arg);
        arg_count += 1;
    }

    if (arg_count < 2) {
        std.debug.print("Usage: zag <file.zag> [output.zig]\n", .{});
        std.process.exit(1);
    }

    const source_path = arg_list.items[1];
    const out_path = if (arg_count >= 3) arg_list.items[2] else blk: {
        const basename = std.fs.path.basename(source_path);
        if (std.mem.endsWith(u8, basename, ".zag")) {
            const stem = basename[0 .. basename.len - 4];
            break :blk try std.fmt.allocPrint(allocator, "{s}.zig", .{stem});
        }
        break :blk try std.fmt.allocPrint(allocator, "{s}.zig", .{basename});
    };
    defer if (arg_count < 3) allocator.free(out_path);

    try zag.compileFile(allocator, io, source_path, out_path);
}
