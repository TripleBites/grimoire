# Mira — local AI chat CLI

Mira is a Zig CLI chat application that runs the **Ternary-Bonsai** model locally
through a custom [llama.cpp](https://github.com/ggml-org/llama.cpp) build.

It uses:

- `@packages/llama/src/llama.zig` — Zig bindings / wrapper around llama.cpp
- `@packages/llama/libs/llama.cpp/` — the custom llama.cpp source
- `@apps/mira/models/` — the local GGUF model files

## Quick start

From the workspace root:

```bash
# Build and run with an interactive chat loop
zig build run-mira

# Single-shot prompt
zig build run-mira -- -p "What is the capital of France?"

# Or use the installed binary after `zig build`
./zig-out/bin/mira -p "What is 2+2?"
```

The default model is:

```text
apps/mira/models/ternary-gguf/4B/Ternary-Bonsai-4B-Q2_0.gguf
```

Use `-m <path>` to point to a different GGUF file.

## Interactive commands

Inside the chat loop:

- `/clear` — clear conversation history
- `/quit` or `/exit` — exit
- `Ctrl+D` — exit

## Options

```text
-m, --model <path>      Path to GGUF model
-c, --ctx <n>           Context size (default: 4096)
-ngl, --gpu-layers <n>  GPU layers to offload (default: 0, CPU only)
-t, --threads <n>       CPU threads (default: auto)
--temp <f>              Temperature (default: 0.5)
--top-p <f>             Top-p (default: 0.85)
--top-k <n>             Top-k (default: 20)
--max-tokens <n>        Max tokens per response (default: 512)
-p, --prompt <text>     Single-shot prompt (non-interactive)
-h, --help              Show help
```

## Rebuilding llama.cpp

If the shared libraries in `packages/llama/libs/llama.cpp/build-cpu/bin/` are
missing or you want to rebuild from source:

```bash
cd packages/llama
zig build build-llama-cpp
```

The Zig build links against the resulting `libllama.so`, `libggml.so`,
`libggml-base.so`, and `libggml-cpu.so` and sets the rpath so the produced
`mira` binary finds them at runtime.
