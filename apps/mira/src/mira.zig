const std = @import("std");
const llama = @import("llama");

// ═════════════════════════════════════════════════════════════════════════════
// Mira — AI chat CLI built on llama.cpp
//
// Usage:
//   zig build run-mira -- [options]
//   ./zig-out/bin/mira [options]
//
// Options:
//   -m, --model <path>     Path to GGUF model (default: models/ternary-gguf/4B/...)
//   -c, --ctx <n>          Context size (default: 4096)
//   -ngl, --gpu-layers <n> GPU layers to offload (default: 0)
//   -t, --threads <n>      CPU threads (default: auto)
//   --temp <f>             Temperature (default: 0.5)
//   --top-p <f>            Top-p (default: 0.85)
//   --top-k <n>            Top-k (default: 20)
//   --max-tokens <n>       Max tokens per response (default: 512)
//   -p, --prompt <text>    Single-shot prompt (non-interactive)
//   -h, --help             Show this help
// ═════════════════════════════════════════════════════════════════════════════

const default_model = "apps/mira/models/ternary-gguf/4B/Ternary-Bonsai-4B-Q2_0.gguf";

const Args = struct {
    model: []const u8 = default_model,
    n_ctx: u32 = 4096,
    n_gpu_layers: i32 = 0,
    n_threads: i32 = 0,
    temperature: f32 = 0.5,
    top_p: f32 = 0.85,
    top_k: i32 = 20,
    max_tokens: u32 = 512,
    prompt: ?[]const u8 = null,
    help: bool = false,

    pub fn deinit(self: Args, allocator: std.mem.Allocator) void {
        if (self.model.ptr != default_model.ptr) allocator.free(self.model);
        if (self.prompt) |p| allocator.free(p);
    }
};

const system_prompt = "You are Mira, a helpful AI assistant. Answer concisely and accurately.";

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    const args = try parseArgs(allocator, init.minimal.args);
    defer args.deinit(allocator);

    if (args.help) {
        try printHelp(stdout);
        return;
    }

    llama.initBackend();
    defer llama.freeBackend();

    std.debug.print("\n{s}Mira{s} — local AI chat\n", .{ ansi(.cyan), ansi(.reset) });
    std.debug.print("Model: {s}\n", .{args.model});
    std.debug.print("Backend: {s}\n\n", .{llama.systemInfo()});

    var session = llama.Session.init(allocator, .{
        .model_path = args.model,
        .n_ctx = args.n_ctx,
        .n_gpu_layers = args.n_gpu_layers,
        .n_threads = args.n_threads,
        .temperature = args.temperature,
        .top_p = args.top_p,
        .top_k = args.top_k,
    }) catch |err| {
        std.debug.print("{s}Error:{s} failed to load model '{s}': {s}\n", .{ ansi(.red), ansi(.reset), args.model, @errorName(err) });
        std.process.exit(1);
    };
    defer session.deinit();

    const desc = try session.modelDesc();
    defer allocator.free(desc);
    std.debug.print("Loaded: {s}\n", .{desc});
    std.debug.print("Context: {d} tokens | Threads: {d}\n\n", .{ session.n_ctx, session.n_threads });

    if (args.prompt) |single_prompt| {
        try generateSingleShot(allocator, &session, single_prompt, stdout);
        return;
    }

    try runInteractiveChat(allocator, init.io, &session);
}

fn generateSingleShot(allocator: std.mem.Allocator, session: *llama.Session, user_prompt: []const u8, stdout: *std.Io.Writer) !void {
    const messages = try buildMessages(allocator, &[_]ChatTurn{}, user_prompt);
    defer allocator.free(messages);

    const prompt = try buildPrompt(allocator, session, messages);
    defer allocator.free(prompt);

    std.debug.print("{s}Mira:{s} ", .{ ansi(.green), ansi(.reset) });
    try session.generate(prompt, stdout, 512);
    try stdout.writeAll("\n");
    try stdout.flush();
}

const ChatTurn = struct {
    user: []const u8,
    assistant: []const u8,
};

fn runInteractiveChat(allocator: std.mem.Allocator, io: std.Io, session: *llama.Session) !void {
    var history: std.ArrayList(ChatTurn) = .empty;
    defer {
        for (history.items) |turn| {
            allocator.free(turn.user);
            allocator.free(turn.assistant);
        }
        history.deinit(allocator);
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stdin_buffer: [4096]u8 = undefined;
    var stdin_file_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
    const stdin = &stdin_file_reader.interface;

    std.debug.print("{s}Interactive chat started. Type /quit, /exit, or press Ctrl+D to quit.{s}\n\n", .{ ansi(.dim), ansi(.reset) });

    while (true) {
        std.debug.print("{s}You:{s} ", .{ ansi(.yellow), ansi(.reset) });

        const maybe_line = stdin.takeDelimiter('\n') catch |err| {
            std.debug.print("\n{s}Error:{s} reading input: {s}\n", .{ ansi(.red), ansi(.reset), @errorName(err) });
            break;
        };
        const line = maybe_line orelse {
            std.debug.print("\n", .{});
            break;
        };

        const input = std.mem.trim(u8, line, " \r\t");
        if (input.len == 0) continue;
        if (std.mem.eql(u8, input, "/quit") or std.mem.eql(u8, input, "/exit")) break;
        if (std.mem.eql(u8, input, "/clear")) {
            for (history.items) |turn| {
                allocator.free(turn.user);
                allocator.free(turn.assistant);
            }
            history.clearRetainingCapacity();
            std.debug.print("{s}Chat history cleared.{s}\n\n", .{ ansi(.dim), ansi(.reset) });
            continue;
        }

        const messages = try buildMessages(allocator, history.items, input);
        defer allocator.free(messages);

        const prompt = try buildPrompt(allocator, session, messages);
        defer allocator.free(prompt);

        std.debug.print("{s}Mira:{s} ", .{ ansi(.green), ansi(.reset) });

        var response: std.ArrayList(u8) = .empty;
        defer response.deinit(allocator);
        var response_writer = std.Io.Writer.Allocating.fromArrayList(allocator, &response);

        try session.generate(prompt, &response_writer.writer, 512);
        response = response_writer.toArrayList();

        try stdout.writeAll(response.items);
        try stdout.writeAll("\n\n");
        try stdout.flush();

        const turn = ChatTurn{
            .user = try allocator.dupe(u8, input),
            .assistant = try allocator.dupe(u8, response.items),
        };
        try history.append(allocator, turn);

        // Keep history from exceeding context by dropping oldest turns
        while (history.items.len > 16) {
            const oldest = history.orderedRemove(0);
            allocator.free(oldest.user);
            allocator.free(oldest.assistant);
        }
    }

    std.debug.print("{s}Goodbye!{s}\n", .{ ansi(.cyan), ansi(.reset) });
}

fn buildMessages(allocator: std.mem.Allocator, history: []const ChatTurn, user_input: []const u8) ![]const llama.ChatMessage {
    var messages: std.ArrayList(llama.ChatMessage) = .empty;
    errdefer messages.deinit(allocator);

    try messages.append(allocator, .{ .role = "system", .content = system_prompt });

    for (history) |turn| {
        try messages.append(allocator, .{ .role = "user", .content = turn.user });
        try messages.append(allocator, .{ .role = "assistant", .content = turn.assistant });
    }

    try messages.append(allocator, .{ .role = "user", .content = user_input });

    return messages.toOwnedSlice(allocator);
}

fn buildPrompt(allocator: std.mem.Allocator, session: *llama.Session, messages: []const llama.ChatMessage) ![]u8 {
    // Try the model's built-in chat template first
    if (try session.applyChatTemplate(messages, true)) |tmpl| {
        return tmpl;
    }

    // Fall back to a Qwen-style template (works for Bonsai/Ternary-Bonsai)
    var parts: std.ArrayList(u8) = .empty;
    errdefer parts.deinit(allocator);

    for (messages) |msg| {
        try parts.appendSlice(allocator, "<|im_start|>");
        try parts.appendSlice(allocator, msg.role);
        try parts.appendSlice(allocator, "\n");
        try parts.appendSlice(allocator, msg.content);
        try parts.appendSlice(allocator, "<|im_end|>\n");
    }
    try parts.appendSlice(allocator, "<|im_start|>assistant\n");

    return parts.toOwnedSlice(allocator);
}

fn printHelp(stdout: *std.Io.Writer) !void {
    const help =
        \\Mira — local AI chat CLI
        \\
        \\Usage:
        \\  mira [options]
        \\
        \\Options:
        \\  -m, --model <path>      Path to GGUF model
        \\  -c, --ctx <n>           Context size (default: 4096)
        \\  -ngl, --gpu-layers <n>  GPU layers to offload (default: 0)
        \\  -t, --threads <n>       CPU threads (default: auto)
        \\  --temp <f>              Temperature (default: 0.5)
        \\  --top-p <f>             Top-p (default: 0.85)
        \\  --top-k <n>             Top-k (default: 20)
        \\  --max-tokens <n>        Max tokens per response (default: 512)
        \\  -p, --prompt <text>     Single-shot prompt (non-interactive)
        \\  -h, --help              Show this help
        \\
        \\Interactive commands:
        \\  /clear                  Clear chat history
        \\  /quit, /exit            Exit the chat
        \\
    ;
    try stdout.writeAll(help);
    try stdout.flush();
}

fn parseArgs(allocator: std.mem.Allocator, args_in: std.process.Args) !Args {
    var args = Args{};
    var it = args_in.iterate();

    _ = it.next(); // skip executable name

    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            args.help = true;
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--model")) {
            const val = it.next() orelse fatal("expected value after {s}", .{arg});
            args.model = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--ctx")) {
            const val = it.next() orelse fatal("expected value after {s}", .{arg});
            args.n_ctx = std.fmt.parseInt(u32, val, 10) catch fatal("invalid context size: {s}", .{val});
        } else if (std.mem.eql(u8, arg, "-ngl") or std.mem.eql(u8, arg, "--gpu-layers")) {
            const val = it.next() orelse fatal("expected value after {s}", .{arg});
            args.n_gpu_layers = std.fmt.parseInt(i32, val, 10) catch fatal("invalid gpu layers: {s}", .{val});
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--threads")) {
            const val = it.next() orelse fatal("expected value after {s}", .{arg});
            args.n_threads = std.fmt.parseInt(i32, val, 10) catch fatal("invalid thread count: {s}", .{val});
        } else if (std.mem.eql(u8, arg, "--temp")) {
            const val = it.next() orelse fatal("expected value after {s}", .{arg});
            args.temperature = std.fmt.parseFloat(f32, val) catch fatal("invalid temperature: {s}", .{val});
        } else if (std.mem.eql(u8, arg, "--top-p")) {
            const val = it.next() orelse fatal("expected value after {s}", .{arg});
            args.top_p = std.fmt.parseFloat(f32, val) catch fatal("invalid top-p: {s}", .{val});
        } else if (std.mem.eql(u8, arg, "--top-k")) {
            const val = it.next() orelse fatal("expected value after {s}", .{arg});
            args.top_k = std.fmt.parseInt(i32, val, 10) catch fatal("invalid top-k: {s}", .{val});
        } else if (std.mem.eql(u8, arg, "--max-tokens")) {
            const val = it.next() orelse fatal("expected value after {s}", .{arg});
            args.max_tokens = std.fmt.parseInt(u32, val, 10) catch fatal("invalid max-tokens: {s}", .{val});
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--prompt")) {
            const val = it.next() orelse fatal("expected value after {s}", .{arg});
            args.prompt = try allocator.dupe(u8, val);
        } else {
            std.debug.print("{s}Warning:{s} unknown argument '{s}'\n", .{ ansi(.yellow), ansi(.reset), arg });
        }
    }

    return args;
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("{s}Error:{s} " ++ fmt ++ "\n", .{ ansi(.red), ansi(.reset) } ++ args);
    std.process.exit(1);
}

fn ansi(style: enum { reset, red, green, yellow, cyan, dim }) []const u8 {
    return switch (style) {
        .reset => "\x1b[0m",
        .red => "\x1b[31m",
        .green => "\x1b[32m",
        .yellow => "\x1b[33m",
        .cyan => "\x1b[36m",
        .dim => "\x1b[90m",
    };
}
