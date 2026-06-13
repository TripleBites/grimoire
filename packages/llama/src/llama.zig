const std = @import("std");

// ═════════════════════════════════════════════════════════════════════════════
// Low-level C bindings for llama.cpp
// ═════════════════════════════════════════════════════════════════════════════

pub const llama_token = i32;
pub const llama_pos = i32;
pub const llama_seq_id = i32;

pub const llama_model = opaque {};
pub const llama_context = opaque {};
pub const llama_vocab = opaque {};
pub const llama_sampler = opaque {};
pub const ggml_backend_dev = opaque {};

pub const llama_progress_callback = ?*const fn (f32, ?*anyopaque) callconv(.c) bool;

pub const llama_split_mode = enum(c_int) {
    none = 0,
    layer = 1,
    row = 2,
    tensor = 3,
};

pub const llama_rope_scaling_type = enum(c_int) {
    unspecified = -1,
    none = 0,
    linear = 1,
    yarn = 2,
    longrope = 3,
};

pub const llama_pooling_type = enum(c_int) {
    unspecified = -1,
    none = 0,
    mean = 1,
    cls = 2,
    last = 3,
    rank = 4,
};

pub const llama_attention_type = enum(c_int) {
    unspecified = -1,
    causal = 0,
    non_causal = 1,
};

pub const llama_flash_attn_type = enum(c_int) {
    auto = -1,
    disabled = 0,
    enabled = 1,
};

pub const llama_model_params = extern struct {
    devices: ?[*]?*ggml_backend_dev = null,
    tensor_buft_overrides: ?*const anyopaque = null,
    n_gpu_layers: i32 = 0,
    split_mode: llama_split_mode = .none,
    main_gpu: i32 = 0,
    tensor_split: ?[*]const f32 = null,
    progress_callback: llama_progress_callback = null,
    progress_callback_user_data: ?*anyopaque = null,
    kv_overrides: ?*const anyopaque = null,
    vocab_only: bool = false,
    use_mmap: bool = true,
    use_direct_io: bool = false,
    use_mlock: bool = false,
    check_tensors: bool = false,
    use_extra_bufts: bool = false,
    no_host: bool = false,
    no_alloc: bool = false,
};

pub const llama_sampler_seq_config = extern struct {
    seq_id: llama_seq_id,
    sampler: ?*llama_sampler,
};

pub const llama_context_params = extern struct {
    n_ctx: u32 = 0,
    n_batch: u32 = 2048,
    n_ubatch: u32 = 512,
    n_seq_max: u32 = 1,
    n_threads: i32 = 0,
    n_threads_batch: i32 = 0,
    rope_scaling_type: llama_rope_scaling_type = .unspecified,
    pooling_type: llama_pooling_type = .unspecified,
    attention_type: llama_attention_type = .unspecified,
    flash_attn_type: llama_flash_attn_type = .auto,
    rope_freq_base: f32 = 0,
    rope_freq_scale: f32 = 0,
    yarn_ext_factor: f32 = -1,
    yarn_attn_factor: f32 = 1,
    yarn_beta_fast: f32 = 32,
    yarn_beta_slow: f32 = 1,
    yarn_orig_ctx: u32 = 0,
    defrag_thold: f32 = 0,
    cb_eval: ?*const anyopaque = null,
    cb_eval_user_data: ?*anyopaque = null,
    type_k: c_int = 0,
    type_v: c_int = 0,
    abort_callback: ?*const anyopaque = null,
    abort_callback_data: ?*anyopaque = null,
    embeddings: bool = false,
    offload_kqv: bool = true,
    no_perf: bool = true,
    op_offload: bool = true,
    swa_full: bool = true,
    kv_unified: bool = true,
    samplers: ?[*]llama_sampler_seq_config = null,
    n_samplers: usize = 0,
};

pub const llama_batch = extern struct {
    n_tokens: i32,
    token: ?[*]llama_token,
    embd: ?[*]f32,
    pos: ?[*]llama_pos,
    n_seq_id: ?[*]i32,
    seq_id: ?[*]?[*]llama_seq_id,
    logits: ?[*]i8,
};

pub const llama_chat_message = extern struct {
    role: [*:0]const u8,
    content: [*:0]const u8,
};

pub const llama_sampler_chain_params = extern struct {
    no_perf: bool = true,
};

pub const LLAMA_DEFAULT_SEED: u32 = 0xFFFFFFFF;
pub const LLAMA_TOKEN_NULL: llama_token = -1;

// Backend
pub extern "c" fn llama_backend_init() void;
pub extern "c" fn llama_backend_free() void;

// Default params
pub extern "c" fn llama_model_default_params() llama_model_params;
pub extern "c" fn llama_context_default_params() llama_context_params;
pub extern "c" fn llama_sampler_chain_default_params() llama_sampler_chain_params;

// Model
pub extern "c" fn llama_model_load_from_file(path_model: [*:0]const u8, params: llama_model_params) ?*llama_model;
pub extern "c" fn llama_model_free(model: *llama_model) void;
pub extern "c" fn llama_model_get_vocab(model: *const llama_model) *const llama_vocab;
pub extern "c" fn llama_model_n_ctx_train(model: *const llama_model) i32;
pub extern "c" fn llama_model_desc(model: *const llama_model, buf: [*]u8, buf_size: usize) i32;
pub extern "c" fn llama_model_chat_template(model: *const llama_model, name: ?[*:0]const u8) ?[*:0]const u8;

// Context
pub extern "c" fn llama_init_from_model(model: *llama_model, params: llama_context_params) ?*llama_context;
pub extern "c" fn llama_free(ctx: *llama_context) void;
pub extern "c" fn llama_n_ctx(ctx: *const llama_context) u32;
pub extern "c" fn llama_set_n_threads(ctx: *llama_context, n_threads: i32, n_threads_batch: i32) void;

// Vocab
pub extern "c" fn llama_vocab_n_tokens(vocab: *const llama_vocab) i32;
pub extern "c" fn llama_vocab_is_eog(vocab: *const llama_vocab, token: llama_token) bool;
pub extern "c" fn llama_vocab_bos(vocab: *const llama_vocab) llama_token;
pub extern "c" fn llama_vocab_eos(vocab: *const llama_vocab) llama_token;

// Tokenize / detokenize
pub extern "c" fn llama_tokenize(
    vocab: *const llama_vocab,
    text: [*]const u8,
    text_len: i32,
    tokens: ?[*]llama_token,
    n_tokens_max: i32,
    add_special: bool,
    parse_special: bool,
) i32;

pub extern "c" fn llama_token_to_piece(
    vocab: *const llama_vocab,
    token: llama_token,
    buf: [*]u8,
    length: i32,
    lstrip: i32,
    special: bool,
) i32;

pub extern "c" fn llama_detokenize(
    vocab: *const llama_vocab,
    tokens: [*]const llama_token,
    n_tokens: i32,
    text: [*]u8,
    text_len_max: i32,
    remove_special: bool,
    unparse_special: bool,
) i32;

// Chat template
pub extern "c" fn llama_chat_apply_template(
    tmpl: ?[*:0]const u8,
    chat: [*]const llama_chat_message,
    n_msg: usize,
    add_ass: bool,
    buf: [*]u8,
    length: i32,
) i32;

// Batch / decode
pub extern "c" fn llama_batch_get_one(tokens: [*]llama_token, n_tokens: i32) llama_batch;
pub extern "c" fn llama_decode(ctx: *llama_context, batch: llama_batch) i32;
pub extern "c" fn llama_synchronize(ctx: *llama_context) void;

// Sampler
pub extern "c" fn llama_sampler_chain_init(params: llama_sampler_chain_params) ?*llama_sampler;
pub extern "c" fn llama_sampler_chain_add(chain: *llama_sampler, smpl: *llama_sampler) void;
pub extern "c" fn llama_sampler_free(smpl: *llama_sampler) void;
pub extern "c" fn llama_sampler_accept(smpl: *llama_sampler, token: llama_token) void;
pub extern "c" fn llama_sampler_sample(smpl: *llama_sampler, ctx: *llama_context, idx: i32) llama_token;

pub extern "c" fn llama_sampler_init_greedy() ?*llama_sampler;
pub extern "c" fn llama_sampler_init_dist(seed: u32) ?*llama_sampler;
pub extern "c" fn llama_sampler_init_top_k(k: i32) ?*llama_sampler;
pub extern "c" fn llama_sampler_init_top_p(p: f32, min_keep: usize) ?*llama_sampler;
pub extern "c" fn llama_sampler_init_min_p(p: f32, min_keep: usize) ?*llama_sampler;
pub extern "c" fn llama_sampler_init_temp(t: f32) ?*llama_sampler;

// Info
pub extern "c" fn llama_print_system_info() [*:0]const u8;
pub extern "c" fn llama_supports_gpu_offload() bool;

// Logging
pub const ggml_log_level = enum(c_int) {
    none = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,
    cont = 5,
};

pub const ggml_log_callback = ?*const fn (level: ggml_log_level, text: [*:0]const u8, user_data: ?*anyopaque) callconv(.c) void;

pub extern "c" fn llama_log_set(callback: ggml_log_callback, user_data: ?*anyopaque) void;

// ═════════════════════════════════════════════════════════════════════════════
// High-level Zig wrapper
// ═════════════════════════════════════════════════════════════════════════════

pub const ChatMessage = struct {
    role: []const u8,
    content: []const u8,
};

pub const SessionOptions = struct {
    model_path: []const u8,
    n_ctx: u32 = 4096,
    n_gpu_layers: i32 = 0,
    n_threads: i32 = 0,
    seed: u32 = LLAMA_DEFAULT_SEED,
    temperature: f32 = 0.5,
    top_p: f32 = 0.85,
    top_k: i32 = 20,
    min_p: f32 = 0.0,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    model: *llama_model,
    ctx: *llama_context,
    vocab: *const llama_vocab,
    sampler: *llama_sampler,
    n_ctx: u32,
    n_threads: i32,

    pub const Error = error{
        ModelLoadFailed,
        ContextInitFailed,
        SamplerInitFailed,
        TokenizeFailed,
        DecodeFailed,
        OutOfMemory,
    };

    pub fn init(allocator: std.mem.Allocator, opts: SessionOptions) Error!Session {
        var mparams = llama_model_default_params();
        mparams.n_gpu_layers = opts.n_gpu_layers;
        mparams.use_mmap = true;
        mparams.use_mlock = false;

        const model_path_z = allocator.dupeSentinel(u8, opts.model_path, 0) catch return error.OutOfMemory;
        defer allocator.free(model_path_z);

        const model = llama_model_load_from_file(model_path_z.ptr, mparams) orelse return error.ModelLoadFailed;
        errdefer llama_model_free(model);

        const vocab = llama_model_get_vocab(model);

        var cparams = llama_context_default_params();
        cparams.n_ctx = opts.n_ctx;
        cparams.n_batch = 2048;
        cparams.n_ubatch = 512;
        cparams.n_threads = if (opts.n_threads > 0) opts.n_threads else @intCast(std.Thread.getCpuCount() catch 4);
        cparams.n_threads_batch = cparams.n_threads;
        cparams.no_perf = true;

        const ctx = llama_init_from_model(model, cparams) orelse return error.ContextInitFailed;
        errdefer llama_free(ctx);

        const n_ctx = llama_n_ctx(ctx);
        const n_threads = cparams.n_threads;

        const sampler = createSampler(opts) orelse return error.SamplerInitFailed;
        errdefer llama_sampler_free(sampler);

        return Session{
            .allocator = allocator,
            .model = model,
            .ctx = ctx,
            .vocab = vocab,
            .sampler = sampler,
            .n_ctx = n_ctx,
            .n_threads = n_threads,
        };
    }

    pub fn deinit(self: *Session) void {
        llama_sampler_free(self.sampler);
        llama_free(self.ctx);
        llama_model_free(self.model);
    }

    pub fn modelDesc(self: *Session) error{OutOfMemory}![]const u8 {
        var buf: [256]u8 = undefined;
        const len = llama_model_desc(self.model, &buf, buf.len);
        if (len <= 0) return self.allocator.dupe(u8, "unknown") catch return error.OutOfMemory;
        return self.allocator.dupe(u8, buf[0..@intCast(len)]) catch return error.OutOfMemory;
    }

    pub fn tokenize(self: *Session, text: []const u8, add_special: bool) Error!std.ArrayList(llama_token) {
        const text_len: i32 = @intCast(text.len);
        const size_query = llama_tokenize(self.vocab, text.ptr, text_len, null, 0, add_special, true);
        // llama_tokenize returns the negative of the needed count when the
        // output buffer is too small (including the size-query case).
        const n_needed = @abs(size_query);
        if (n_needed == 0) return error.TokenizeFailed;

        var tokens: std.ArrayList(llama_token) = .empty;
        errdefer tokens.deinit(self.allocator);

        try tokens.resize(self.allocator, @intCast(n_needed));
        const n_actual = llama_tokenize(self.vocab, text.ptr, text_len, tokens.items.ptr, @intCast(n_needed), add_special, true);
        if (n_actual < 0) {
            std.debug.print("tokenize failed: n_actual={d}\n", .{n_actual});
            return error.TokenizeFailed;
        }

        tokens.shrinkAndFree(self.allocator, @intCast(n_actual));
        return tokens;
    }

    pub fn tokenToPiece(self: *Session, token: llama_token, buf: []u8, special: bool) i32 {
        return llama_token_to_piece(self.vocab, token, buf.ptr, @intCast(buf.len), 0, special);
    }

    pub fn generate(self: *Session, prompt: []const u8, writer: anytype, max_tokens: u32) !void {
        var tokens = try self.tokenize(prompt, false);
        defer tokens.deinit(self.allocator);

        if (tokens.items.len >= self.n_ctx) {
            return error.DecodeFailed;
        }

        // Decode prompt
        var batch = llama_batch_get_one(tokens.items.ptr, @intCast(tokens.items.len));
        var decode_result = llama_decode(self.ctx, batch);
        if (decode_result != 0) {
            return error.DecodeFailed;
        }

        var n_gen: u32 = 0;
        var piece_buf: [256]u8 = undefined;

        while (n_gen < max_tokens) {
            var token = llama_sampler_sample(self.sampler, self.ctx, -1);

            if (llama_vocab_is_eog(self.vocab, token)) {
                break;
            }

            llama_sampler_accept(self.sampler, token);

            const n_piece = llama_token_to_piece(self.vocab, token, &piece_buf, piece_buf.len, 0, false);
            if (n_piece > 0) {
                try writer.writeAll(piece_buf[0..@intCast(n_piece)]);
            }

            batch = llama_batch_get_one(@ptrCast(&token), 1);
            decode_result = llama_decode(self.ctx, batch);
            if (decode_result != 0) {
                return error.DecodeFailed;
            }

            n_gen += 1;
        }
    }

    pub fn applyChatTemplate(
        self: *Session,
        messages: []const ChatMessage,
        add_assistant_turn: bool,
    ) Error!?[]u8 {
        const tmpl = llama_model_chat_template(self.model, null);
        if (tmpl == null) return null;

        const msgs = self.allocator.alloc(llama_chat_message, messages.len) catch return error.OutOfMemory;
        defer self.allocator.free(msgs);

        const role_bufs = self.allocator.alloc([:0]u8, messages.len) catch return error.OutOfMemory;
        defer self.allocator.free(role_bufs);
        const content_bufs = self.allocator.alloc([:0]u8, messages.len) catch return error.OutOfMemory;
        defer self.allocator.free(content_bufs);

        for (messages, 0..) |msg, i| {
            role_bufs[i] = self.allocator.dupeSentinel(u8, msg.role, 0) catch return error.OutOfMemory;
            content_bufs[i] = self.allocator.dupeSentinel(u8, msg.content, 0) catch return error.OutOfMemory;
            msgs[i] = .{
                .role = role_bufs[i].ptr,
                .content = content_bufs[i].ptr,
            };
        }
        defer {
            for (role_bufs) |b| self.allocator.free(b);
            for (content_bufs) |b| self.allocator.free(b);
        }

        var buf: [4096]u8 = undefined;
        const len = llama_chat_apply_template(tmpl, msgs.ptr, msgs.len, add_assistant_turn, &buf, buf.len);
        if (len < 0) return null; // template not supported
        if (len > buf.len) {
            const big = self.allocator.alloc(u8, @intCast(len + 1)) catch return error.OutOfMemory;
            const len2 = llama_chat_apply_template(tmpl, msgs.ptr, msgs.len, add_assistant_turn, big.ptr, @intCast(len + 1));
            if (len2 < 0) {
                self.allocator.free(big);
                return error.OutOfMemory;
            }
            big[@intCast(len2)] = 0;
            return big[0..@intCast(len2) :0];
        }

        const result = self.allocator.dupe(u8, std.mem.trimEnd(u8, buf[0..@intCast(len)], "\x00")) catch return error.OutOfMemory;
        return result;
    }
};

fn createSampler(opts: SessionOptions) ?*llama_sampler {
    const sparams = llama_sampler_chain_default_params();
    const smpl = llama_sampler_chain_init(sparams) orelse return null;

    if (opts.temperature <= 0.0) {
        llama_sampler_chain_add(smpl, llama_sampler_init_greedy() orelse return null);
    } else {
        llama_sampler_chain_add(smpl, llama_sampler_init_top_k(opts.top_k) orelse return null);
        llama_sampler_chain_add(smpl, llama_sampler_init_top_p(opts.top_p, 1) orelse return null);
        if (opts.min_p > 0.0) {
            llama_sampler_chain_add(smpl, llama_sampler_init_min_p(opts.min_p, 1) orelse return null);
        }
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(opts.temperature) orelse return null);
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(opts.seed) orelse return null);
    }

    return smpl;
}

fn noopLogCallback(_: ggml_log_level, _: [*:0]const u8, _: ?*anyopaque) callconv(.c) void {}

pub fn initBackend() void {
    llama_backend_init();
    llama_log_set(noopLogCallback, null);
}

pub fn initBackendWithLogs() void {
    llama_backend_init();
}

pub fn freeBackend() void {
    llama_backend_free();
}

pub fn supportsGpuOffload() bool {
    return llama_supports_gpu_offload();
}

pub fn systemInfo() [:0]const u8 {
    return std.mem.span(llama_print_system_info());
}
