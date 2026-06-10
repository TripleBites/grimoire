# core.c Architecture Breakdown

> A comprehensive analysis of the core.c repository structure, with an eye toward rebuilding something similar in Rust with a clean, expandable architecture.

---

## 1. High-Level Philosophy

core.c follows a **dual-reference philosophy**:

1. **CPU reference** (`train_gpt2.c`): Clean, readable, naive-but-correct C with OpenMP. Every layer is explicit. This is the "source of truth."
2. **GPU production** (`train_gpt2.cu`): Heavily optimized CUDA, fused kernels, mixed precision, multi-GPU. Same model structure, same math, same checkpoint format.

This is the most important architectural decision: **you maintain two implementations of the same thing**. One is for understanding and correctness verification. The other is for speed. They converge on the same binary interface (checkpoints, data format, expected outputs).

### For a Rust Project

Mirror this:
- `src/cpu/` — A pure, readable CPU backend. Use `rayon` for parallelism.
- `src/gpu/` or `src/cuda/` / `src/wgpu/` — The optimized backend.
- Both share the same `ModelConfig`, checkpoint format, and test fixtures.

---

## 2. Repository Layout Architecture

The directory structure is deliberately layered. This is the secret sauce for keeping a high-performance project maintainable.

```
core.c/
├── train_gpt2.c              # CPU reference (1,182 lines) — THE SOURCE OF TRUTH
├── train_gpt2.cu             # GPU production (1,904 lines) — THE FAST PATH
├── train_gpt2_fp32.cu        # Frozen legacy checkpoint — useful for learning
├── train_gpt2.py             # PyTorch reference — writes .bin weights for C to load
├── train_llama3.py           # PyTorch reference for LLaMA 3.1
├── test_gpt2.c               # CPU integration test
├── test_gpt2.cu              # GPU integration test
├── profile_gpt2.cu           # Thin wrapper for NCU profiling
├── profile_gpt2cu.py         # Automates ncu, parses CSV, groups kernels by phase
├── Makefile                  # Cross-platform build system (Linux/macOS/Windows)
│
├── corec/                     # === THE SHARED LIBRARY ===
│   ├── utils.h               # Safe file I/O wrappers, path utils
│   ├── tokenizer.h           # GPT-2 tokenizer (decode only)
│   ├── dataloader.h          # Binary shard reader, distributed-aware
│   ├── rand.h                # MT19937, numerically identical to PyTorch
│   ├── schedulers.h          # LR warmup + cosine decay
│   ├── sampler.h             # xorshift RNG for inference sampling
│   ├── logger.h              # Stateless metrics logger (append-only)
│   ├── mfu.h                 # Model Flops Utilization calculator
│   ├── outlier_detector.h    # Sliding-window z-score anomaly detector
│   │
│   ├── cuda_common.h         # floatX precision typedef, error checking, NVTX
│   ├── cuda_utils.cuh        # Packed128 vectorized loads, warp reductions
│   ├── cublas_common.h       # cuBLASLt handle management
│   │
│   ├── encoder.cuh           # Token + position embedding kernels
│   ├── layernorm.cuh         # LayerNorm fwd/bwd, fused residual+LN
│   ├── matmul.cuh            # cuBLASLt GEMMs, GELU fusion, bias reduction
│   ├── attention.cuh         # Manual attention (permute→softmax→unpermute)
│   ├── cudnn_att.cpp/h       # Optional cuDNN flash attention
│   ├── fused_classifier.cuh  # Fused cross-entropy (never materializes full probs)
│   ├── gelu.cuh              # GeLU fwd/bwd
│   ├── global_norm.cuh       # Gradient clipping (global L2 norm)
│   ├── adamw.cuh             # AdamW kernel, stochastic rounding, master weights
│   └── zero.cuh              # NCCL multi-GPU, ZeRO-1 sharding
│
├── dev/                      # === DEVELOPMENT SCRATCH SPACE ===
│   ├── cuda/                 # Kernel development sandbox (~30 .cu files)
│   │   ├── layernorm_forward.cu    # 6+ versions of same kernel, benchmarked
│   │   ├── attention_forward.cu
│   │   ├── matmul_forward.cu
│   │   └── ...
│   ├── cpu/                  # CPU matmul experiments
│   ├── data/                 # Dataset preprocessing scripts
│   ├── eval/                 # Export to HuggingFace, eval runners
│   ├── test/                 # Standalone unit tests (dataloader, outlier detector)
│   └── download_starter_pack.sh
│
└── scripts/                  # === TRAINING RECIPES ===
    ├── run_gpt2_124M.sh
    ├── run_gpt2_350M.sh
    ├── run_gpt2_774M.sh
    ├── run_gpt2_1558M.sh
    ├── run_gpt3_125M.sh
    └── multi_node/           # SLURM/MPI launch scripts
```

### Key Insight: The Three-Zone Layout

| Zone | Purpose | Stability |
|------|---------|-----------|
| **Root** (`train_gpt2.*`) | Mainline, readable, high-level flow | Very stable |
| **`corec/`** | Reusable kernels, utilities, shared abstractions | Stable APIs, evolving internals |
| **`dev/`** | Scratch space, experiments, benchmarks, data prep | Unstable, free-for-all |

This separation is critical. `dev/cuda/` is where you iterate on 6 versions of a LayerNorm kernel without polluting the main build. `corec/` only receives the winner.

### For a Rust Project

```
your-project/
├── src/
│   ├── main.rs               # CLI entry, training loop orchestration
│   ├── lib.rs                # Public API
│   ├── config.rs             # ModelConfig, TrainingConfig
│   ├── model.rs              # GPT struct, forward(), backward()
│   │
│   ├── backends/
│   │   ├── cpu/              # CPU reference backend
│   │   │   ├── mod.rs
│   │   │   ├── encoder.rs
│   │   │   ├── layernorm.rs
│   │   │   └── ...
│   │   └── gpu/              # GPU backend (CUDA/WGPU/HIP)
│   │       ├── mod.rs
│   │       ├── encoder.cuh   # or .rs with rust-gpu / inline CUDA
│   │       └── ...
│   │
│   ├── ops/                  # Shared operator traits / generic implementations
│   │   ├── mod.rs
│   │   ├── matmul.rs
│   │   ├── attention.rs
│   │   └── ...
│   │
│   ├── data/
│   │   ├── dataloader.rs
│   │   ├── tokenizer.rs
│   │   └── shard.rs
│   │
│   ├── optim/
│   │   ├── adamw.rs
│   │   └── scheduler.rs
│   │
│   ├── distributed/
│   │   └── zero.rs
│   │
│   └── utils/
│       ├── checkpoint.rs
│       ├── logger.rs
│       └── sampling.rs
│
├── dev/
│   ├── kernels/              # Kernel sandbox — benchmark scripts
│   ├── data_prep/            # Python scripts for tokenization
│   └── benches/              # Criterion benchmarks
│
├── scripts/
│   └── run_*.sh              # Training recipes
│
├── python/
│   ├── train_gpt2.py         # PyTorch reference (if you want one)
│   └── export_weights.py     # Writes .bin for Rust to load
│
└── Cargo.toml
```

---

## 3. Build System Architecture

The `Makefile` is ~290 lines and does a lot:

- **Compiler auto-detection**: `clang` on Linux/macOS, `cl` on Windows. Auto-detects `nvcc`.
- **GPU compute capability**: Queries `nvidia-smi` for the lowest available compute capability.
- **Precision selection**: `PRECISION ?= BF16` (compile-time flag: `-DENABLE_BF16`).
- **Optional features** (auto-detected):
  - OpenMP
  - cuDNN flash attention
  - NCCL / Multi-GPU
  - MPI bootstrap

### Build Targets

| Target | Source | Notes |
|--------|--------|-------|
| `train_gpt2` | `train_gpt2.c` | CPU only |
| `train_gpt2cu` | `train_gpt2.cu` | Main GPU build |
| `test_gpt2cu` | `test_gpt2.cu` | Integration test |
| `profile_gpt2cu` | `profile_gpt2.cu` | With `-lineinfo` for NCU |

### For a Rust Project

Cargo handles the Rust side. For GPU kernels, you have options:

1. **CUDA via `rustacuda` / `cust`**: Write `.cu` files, compile with `nvcc` in a `build.rs`, link the PTX/static lib.
2. **WGPU / WebGPU**: Pure Rust compute shaders. Portable but less mature for core-scale GEMMs.
3. **`cudarc`**: Popular Rust CUDA wrapper. You can write CUDA kernels in `.cu` and call them from Rust.
4. ** candle / burn backends**: If you want to lean on existing frameworks.

**Recommended approach for a clean expandable architecture:**

Use a `build.rs` that:
- Detects `nvcc` at compile time.
- Sets `--gpu-architecture` based on the local GPU (or env override).
- Compiles `.cu` files to a static library if CUDA is present.
- Sets `cfg` flags (`has_cuda`, `has_cudnn`) so the Rust code can conditionally compile backends.

```rust
// build.rs sketch
fn main() {
    if let Ok(cuda) = detect_cuda() {
        println!("cargo:rustc-cfg=has_cuda");
        compile_cuda_kernels(&cuda);
    }
}
```

---

## 4. Model & Tensor Architecture

### Configuration

```c
typedef struct {
    int max_seq_len;       // e.g. 1024
    int vocab_size;        // 50257
    int padded_vocab_size; // 50304 (padded to 128 for CUDA)
    int num_layers;        // e.g. 12
    int num_heads;         // e.g. 12
    int channels;          // e.g. 768
} GPT2Config;
```

### Parameter Tensors

There are **16 parameter tensors**. The key pattern: **one big allocation, pointer-sliced.**

```c
typedef struct {
    floatX* wte;       // (Vp, C)
    floatX* wpe;       // (maxT, C)
    floatX* ln1w;      // (L, C)
    floatX* ln1b;      // (L, C)
    floatX* qkvw;      // (L, 3*C, C)
    floatX* qkvb;      // (L, 3*C)
    floatX* attprojw;  // (L, C, C)
    floatX* attprojb;  // (L, C)
    floatX* ln2w;      // (L, C)
    floatX* ln2b;      // (L, C)
    floatX* fcw;       // (L, 4*C, C)
    floatX* fcb;       // (L, 4*C)
    floatX* fcprojw;   // (L, C, 4*C)
    floatX* fcprojb;   // (L, C)
    floatX* lnfw;      // (C)
    floatX* lnfb;      // (C)
} ParameterTensors;
```

All parameters live in a single `cudaMalloc` blob. `malloc_and_point_parameters()` slices it.

**Why this matters:**
- One `cudaMalloc` = one contiguous block = better memory coherence.
- Easy to save/load: just fwrite/fread the whole blob.
- Easy to calculate total parameter count.
- Gradients use the exact same struct and slicing logic.

### Activation Tensors

21 activation tensors, also single-blob allocated. Some key design choices:
- `output` buffer is **triple-purposed**: logits during forward → gradient scratch during backward → general workspace during block processing.
- `lnf` (final layernorm) buffer is reused for **all** layernorms when recomputation is enabled.
- `att` is either `(L, B, NH, T, T)` for manual attention, or `(L, B, NH, T)` stats for cuDNN.

### For a Rust Project

You want a **typed tensor view system** over a single `Vec` or `DeviceBuffer`.

```rust
// Single contiguous buffer, typed views
pub struct TensorArena {
    data: Vec<f32>, // or DeviceBuffer<f32> for GPU
}

pub struct ParameterTensors<'a> {
    pub wte: TensorView<'a, f32>,      // (Vp, C)
    pub wpe: TensorView<'a, f32>,      // (maxT, C)
    pub ln1w: TensorView<'a, f32>,     // (L, C)
    // ... etc
}

pub struct TensorView<'a, T> {
    data: &'a mut [T],
    shape: Vec<usize>,
    strides: Vec<usize>,
}
```

Or use an existing crate like `ndarray` for CPU, but for GPU you'll likely want your own thin wrapper around `cudarc::driver::DevicePtr`.

**Critical pattern to preserve:** The `ParameterTensors` struct should be a **plain bag of views** with no vtable indirection. In Rust, this means no `Box<dyn Layer>` in the hot path. Use generics or static dispatch.

---

## 5. Layer / Kernel Architecture

Each layer type lives in its own header file in `corec/`. The pattern is:

1. `__global__` kernel(s) — the actual CUDA device code.
2. Host launcher function — sets up grid/block dims, calls the kernel.
3. Often multiple kernel versions (e.g., `layernorm_forward_kernel3` vs `kernel6`), with the launcher picking the best one.

Example from `corec/layernorm.cuh`:

```c
// Device code
__global__ void layernorm_forward_kernel3(floatX* out, float* mean, float* rstd, ...);
__global__ void layernorm_forward_kernel6(floatX* out, float* mean, float* rstd, ...);

// Host launcher
void layernorm_forward(floatX* out, float* mean, float* rstd,
                       const floatX* inp, const floatX* weight, const floatX* bias,
                       int B, int T, int C, cudaStream_t stream) {
    // pick kernel6 if conditions met, else kernel3
    // set up grid, launch
}
```

### Precision Abstraction

All kernels are typed against `floatX`, which is a compile-time typedef:

```c
#if defined(ENABLE_FP32)
    typedef float floatX;
#elif defined(ENABLE_FP16)
    typedef half floatX;
#else
    typedef __nv_bfloat16 floatX;  // default
#endif
```

Internal accumulation is almost always **FP32** for numerical stability, even when `floatX` is BF16/FP16.

### Vectorized Memory Access

`corec/cuda_utils.cuh` defines `Packed128<ElementType>` — forces 128-bit LDG/STS instructions. This is crucial for kernel performance.

```c
using x128 = Packed128<floatX>;
x128 data = load128cs(ptr + offset);
store128(ptr + offset, data);
```

### For a Rust Project

In Rust, you'd define a `Backend` trait:

```rust
pub trait Backend {
    type DeviceBuffer<T>;
    
    fn encoder_forward(&self, out: &mut TensorView<Self::Float>, ...);
    fn layernorm_forward(&self, out: &mut TensorView<Self::Float>, ...);
    fn matmul_forward(&self, out: &mut TensorView<Self::Float>, ...);
    fn attention_forward(&self, out: &mut TensorView<Self::Float>, ...);
    // ...
}

pub struct CpuBackend;
pub struct CudaBackend;

impl Backend for CpuBackend { ... }
impl Backend for CudaBackend { ... }
```

**But beware:** Trait method dispatch in the hot loop has overhead. core.c avoids all dynamic dispatch. In Rust, you can avoid it too by:

1. Making the model generic over `B: Backend` — monomorphization at compile time.
2. Or using `#[inline]` + static dispatch via `impl Backend` in function signatures.

```rust
pub fn gpt2_forward<B: Backend>(backend: &B, model: &mut GPT2<B>, ...) {
    // monomorphized — zero overhead
}
```

---

## 6. Forward & Backward Pass Data Flow

### CPU Forward (exact flow from `train_gpt2.c`)

```
encoded = wte[x] + wpe[t]
for layer in 0..L:
    ln1     = layernorm(residual)
    qkv     = matmul(ln1, qkvw) + qkvb
    atty    = attention(qkv)               // causal softmax
    attproj = matmul(atty, attprojw) + attprojb
    res2    = residual + attproj           // residual
    ln2     = layernorm(res2)
    fch     = matmul(ln2, fcw) + fcb
    fch     = gelu(fch)
    fcproj  = matmul(fch, fcprojw) + fcprojb
    res3    = res2 + fcproj                // residual
lnf     = layernorm(last_residual)
logits  = matmul(lnf, wte)                 // weight tying!
probs   = softmax(logits)
loss    = cross_entropy(probs, targets)
```

### GPU Forward Optimizations

- `encoder_forward` — fused token+position lookup kernel.
- `fused_residual_forward5` — **fuses residual add + LayerNorm into one kernel**.
- `matmul_forward_cublaslt` — all GEMMs via cuBLASLt, with optional **GELU fusion** via epilogues.
- `fused_classifier` — never materializes full `(B, T, V)` probability matrix. Computes per-row softmax + loss + gradient all in one kernel.
- Cross-layer fusion: The residual+LN of layer `l+1` is fused with the output of layer `l`, reducing kernel launches.

### GPU Backward Flow

```
fused_classifier_backward          // overwrites logits with dlogits in-place
matmul_backward(classifier)        // dlnf, dwte
layernorm_backward(final_ln)

for layer in (L-1)..0:
    // recompute GELU if recompute >= 1
    matmul_backward(fcproj)        // dfch_gelu, dfcprojw, dfcprojb
    layernorm_backward(ln2)
    matmul_backward(fcw)           // dln2, dfcw, dfcb
    matmul_backward(attproj)       // datty, dattprojw, dattprojb
    attention_backward             // dqkvr
    matmul_backward(qkvw)          // dln1, dqkvw, dqkvb
    layernorm_backward(ln1)
    // gradient reduction across GPUs (last micro-step only)

encoder_backward                   // dwte, dwpe
```

### Memory Reuse Patterns

| Buffer | Forward Use | Backward Use |
|--------|-------------|--------------|
| `output` | logits | dlogits (in-place) |
| `att` | attention matrix | scratch for attention backward |
| `dresidual` | — | reused across all layers |
| `scratch_btc` | — | general scratch |
| `scratch_bt4c` | — | general scratch |

**Key insight:** The backward pass aggressively reuses buffers to avoid peak memory blowup. This is hand-managed — there is no automatic memory pool.

### For a Rust Project

In Rust, you could model this with explicit lifecycle tracking:

```rust
pub struct Activations {
    encoded: TensorView<f32>,
    ln1: TensorView<f32>,
    ln1_mean: TensorView<f32>,
    ln1_rstd: TensorView<f32>,
    // ...
}

// Or use a typed arena with named offsets
pub struct ActivationArena {
    buffer: Vec<f32>,
    offsets: ActivationOffsets,
}
```

Since Rust has ownership, you could potentially enforce at compile time that a buffer isn't double-used. But in practice, the C-style "careful manual reuse" is probably simpler and more performant for this use case.

---

## 7. Data Loading Architecture

### Binary Shard Format

```
[Header: 256 x int32]
  [0] = magic: 20240520
  [1] = version: 1
  [2] = num_tokens
[Data: uint16_t tokens...]
```

### DataLoader Features

- **Distributed-aware**: Each process reads a different slice of the global batch.
- **Shuffling**: Both inter-shard and intra-shard shuffle via MT19937.
- **Resumption**: Can restart from exact shard index and sample index for crash recovery.
- **Batch construction**: Reads `B*T+1` consecutive tokens, splits into `inputs[i] = buffer[i]`, `targets[i] = buffer[i+1]`.

### EvalLoader

- For multiple-choice eval (HellaSwag).
- Variable-length examples packed into `(B, T)` with delimiters.
- Computes average loss per completion to determine accuracy.

### For a Rust Project

This maps very cleanly:

```rust
pub struct DataLoader {
    shard_pattern: String,
    shards: Vec<PathBuf>,
    current_shard: usize,
    current_sample: usize,
    buffer: Vec<u16>,
    inputs: Vec<i32>,
    targets: Vec<i32>,
    rng: Mt19937,
    process_rank: usize,
    num_processes: usize,
    // ...
}

impl DataLoader {
    pub fn next_batch(&mut self) -> (&[i32], &[i32]);
    pub fn reset(&mut self);
    pub fn save_state(&self) -> DataLoaderState;
    pub fn load_state(&mut self, state: DataLoaderState);
}
```

Use `memmap2` for memory-mapped file I/O instead of explicit `fread`. This is often faster and cleaner in Rust.

---

## 8. Training Loop Architecture

```c
for step in 0..num_batches:
    // periodic: validation, HellaSwag eval, sampling, checkpointing
    
    // gradient accumulation
    for micro_step in 0..grad_accum_steps:
        dataloader_next_batch()
        gpt2_forward(model, inputs, B, T)
        gpt2_backward_and_reduce(model, inputs, targets, grad_accum_steps, micro_step)
    
    grad_norm = gpt2_calculate_grad_norm(model)
    grad_scale = (grad_norm > 1.0f) ? 1.0f / grad_norm : 1.0f
    
    gpt2_update(model, lr, beta1, beta2, eps, weight_decay, grad_scale, step, multi_gpu)
```

### Features in the Loop

- **Learning rate scheduling**: Warmup + cosine decay + final fraction.
- **Gradient clipping**: Global L2 norm scaling.
- **Outlier detection**: Skip updates if loss/grad_norm z-score exceeds threshold.
- **MFU estimation**: Queries GPU specs via NVML.
- **Checkpointing**: Saves model weights + optimizer state + dataloader state + RNG state. Bit-perfect resumption.
- **Multi-GPU**: NCCL DDP with ZeRO-1 optimizer sharding.
- **Activation recomputation**: Trades compute for memory (`recompute=0,1,2`).

### AdamW Optimizer

- Hand-written CUDA kernel with **stochastic rounding** when writing FP32 master weights back to BF16/FP16.
- Optional FP32 master weights (default on for mixed precision).
- ZeRO-1: Each GPU holds `1/N` of `m` and `v` states.

### For a Rust Project

```rust
pub struct Trainer<B: Backend> {
    model: GPT2<B>,
    optimizer: AdamW,
    dataloader: DataLoader,
    scheduler: LRScheduler,
    outlier_detector: OutlierDetector,
    multi_gpu: Option<MultiGpuConfig>,
    grad_accum_steps: usize,
    // ...
}

impl<B: Backend> Trainer<B> {
    pub fn train_step(&mut self) -> StepMetrics {
        // gradient accumulation loop
        // forward + backward
        // grad norm + clip
        // optimizer step
        // logging
    }
}
```

---

## 9. Testing & Correctness Architecture

This is one of the strongest parts of core.c.

### Integration Tests

**`test_gpt2.cu`** loads `gpt2_124M_debug_state.bin` (generated by `train_gpt2.py`) and:

1. Runs forward pass, compares logits against expected.
2. Runs 1 backward pass, compares all 16 parameter gradients against PyTorch reference.
3. Trains 10 steps, verifies loss sequence matches exactly.
4. Saves checkpoint, reloads, trains 10 more steps, verifies token-by-token match.

**Per-tensor tolerances**: FP32 gets strict tolerance. BF16/FP16 get looser tolerance.

### Unit Tests

- `dev/test/test_dataloader.c`
- `dev/test/test_outlier_detector.c`

### CI

- CPU builds on Ubuntu/macOS/Windows.
- CUDA builds in containers (FP32, BF16, FP16, cuDNN).
- **Actual GPU tests** on Ubicloud runners.
- PTX/SASS dumps archived for A100 (sm80) and H100 (sm90).
- Loss validation via `dev/loss_checker_ci.py`.

### For a Rust Project

Mirror this exactly:

1. Write a Python PyTorch script that exports:
   - Model weights → `model.bin`
   - A single forward/backward debug state → `debug_state.bin`
   - Expected losses for N steps → `expected_losses.json`

2. Rust integration tests load these and compare.

3. Use `approx` crate for floating-point comparisons with per-tensor tolerances.

```rust
#[test]
fn test_forward_matches_pytorch() {
    let model = GPT2::from_checkpoint("gpt2_124M_debug_state.bin");
    let (inputs, expected_logits) = load_debug_state();
    model.forward(&inputs);
    assert_relative_eq!(model.logits, expected_logits, epsilon = 1e-3);
}
```

---

## 10. Multi-GPU / Distributed Architecture

### `corec/zero.cuh`

```c
typedef struct {
    int process_rank;
    int num_processes;
    int local_device_idx;
    int zero_stage;
    size_t shard_num_parameters;
    ncclComm_t nccl_comm;
    cudaStream_t nccl_stream;
} MultiGpuConfig;
```

### ZeRO Stages

| Stage | What it does |
|-------|--------------|
| **0 (DDP)** | Standard data parallelism. `ncclAllReduce` on gradients. |
| **1 (ZeRO-1)** | Shard optimizer states. `reduceScatter` grads → local AdamW → `allGather` updated params. |
| **2/3** | Structure exists, noted as future work. |

### Bootstrap Methods

1. **MPI**: `mpirun` launches, MPI used only to bootstrap NCCL.
2. **TCP socket**: Rank 0 opens a socket, broadcasts NCCL ID.
3. **Filesystem**: Write NCCL ID to a shared file.

### Gradient Reduction

`multi_gpu_async_reduce_gradient` launches `ncclGroupStart/End` on a **dedicated NCCL stream**. The main compute stream is synchronized via `cudaEvent_t`. This overlaps communication with the remaining backward compute.

### For a Rust Project

Rust has `nccl-rs` bindings, or you can use `cudarc`'s NCCL support. Alternatively, for a first version, you could use `tokio` + gRPC for a pure-Rust distributed setup, but NCCL is the performance standard.

For a clean architecture:

```rust
pub trait DistributedBackend {
    fn all_reduce(&self, buffer: &mut [f32]);
    fn reduce_scatter(&self, sendbuf: &[f32], recvbuf: &mut [f32]);
    fn all_gather(&self, sendbuf: &[f32], recvbuf: &mut [f32]);
}

pub struct NcclBackend { ... }
pub struct DummyBackend; // single-GPU no-op
```

---

## 11. Profiling Architecture

`profile_gpt2cu.py` is a gem:

1. Builds `profile_gpt2cu` with `NO_MULTI_GPU=1 USE_CUDNN=1`.
2. Runs `ncu --set full --import-source yes`.
3. Parses CSV for: `gpu__time_duration`, `dram__bytes_read/write`, L2 traffic, tensor core utilization.
4. **Groups kernels by phase**: `enc`, `fwd`, `cls`, `bwd`, `opt`.
5. Multiplies non-classifier times by `N_LAYERS` to estimate full-model cost.
6. Computes aggregate efficiency relative to peak DRAM BW and tensor throughput.

### For a Rust Project

Use `nvtx` ranges (via `cudarc` or raw bindings) to mark phases. Then write a Python script to automate `ncu` and parse results, just like core.c does. Or use `tracy` / `tokio-console` for CPU-side profiling.

---

## 12. Rust Translation: Recommended Clean Architecture

Based on all of the above, here's how I'd structure a Rust port that preserves core.c's virtues while being idiomatic and expandable:

### Core Principles

1. **Zero-cost abstractions**: Monomorphize over backend and precision. No `Box<dyn>` in the hot loop.
2. **Explicit is better than implicit**: Every tensor shape is visible. Every allocation is deliberate.
3. **Reference + fast path**: Keep a CPU reference backend that shares tests with the GPU backend.
4. **Single-blob allocation**: Use arenas for parameters, gradients, and activations.
5. **Binary bridge to PyTorch**: Export/import `.bin` files for correctness verification.

### Module Structure

```rust
// src/lib.rs
pub mod config;
pub mod model;
pub mod backends;
pub mod ops;
pub mod data;
pub mod optim;
pub mod distributed;
pub mod utils;

// src/backends/mod.rs
pub trait Backend {
    type Float: Float;
    fn device_name(&self) -> &str;
}

pub struct CpuBackend;
pub struct CudaBackend;

// src/model.rs
pub struct GPT2<B: Backend> {
    config: GPT2Config,
    params: ParameterTensors<B>,
    grads: ParameterTensors<B>,
    acts: ActivationTensors<B>,
    // ...
}

impl<B: Backend> GPT2<B> {
    pub fn forward(&mut self, inputs: &[i32]);
    pub fn backward(&mut self, targets: &[i32]);
}

// src/ops/mod.rs — generic ops, backend-specific implementations
pub mod encoder;
pub mod layernorm;
pub mod matmul;
pub mod attention;
```

### Precision Generic

```rust
pub trait Float: Copy + 'static {
    fn zero() -> Self;
    fn from_f32(v: f32) -> Self;
    fn to_f32(self) -> f32;
}

impl Float for f32 { ... }
impl Float for half::f16 { ... }
impl Float for half::bf16 { ... }
```

Then:

```rust
pub fn layernorm_forward<B: Backend>(
    backend: &B,
    out: &mut TensorView<B::Float>,
    mean: &mut TensorView<f32>,
    rstd: &mut TensorView<f32>,
    inp: &TensorView<B::Float>,
    weight: &TensorView<B::Float>,
    bias: &TensorView<B::Float>,
);
```

### Checkpoint Format

Keep the exact same binary format as core.c so you can:
- Load core.c checkpoints into your Rust code.
- Generate debug states with `train_gpt2.py` and test against them.

```rust
pub struct Checkpoint {
    header: [i32; 256],
    params: Vec<u8>, // raw blob
}
```

---

## 13. What to Copy vs. What to Reimagine

| Copy Exactly | Reimagine for Rust |
|--------------|-------------------|
| Binary checkpoint format | Use `memmap2` for I/O |
| Debug state testing strategy | Use `approx` + `serde_json` for expected values |
| Single-blob allocation | Use `bumpalo` or custom arena |
| `dev/` scratch space pattern | Use `criterion` for kernel benchmarking |
| Precision-generic `floatX` | Use Rust generics + `Float` trait |
| Manual attention kernel | Could use `flash-attn` crate if available |
| Makefile feature flags | Use `build.rs` + `cfg` flags |
| ZeRO-1 NCCL pattern | Use `cudarc` NCCL bindings |
| `corec/` header organization | Use Rust modules + traits |

---

## 14. Summary of Key Patterns

| Pattern | Why It Matters |
|---------|----------------|
| **Single-blob params/grads/acts** | Fewer allocations, cache-friendly, easy serialize |
| **Pointer-slice structs** | Zero-overhead tensor naming |
| **Kernel + launcher pairs** | Separation of device logic from host orchestration |
| **Compile-time precision** | No runtime branching on dtype; kernels are monomorphic |
| **In-place buffer reuse** | Peak memory is the bottleneck for core training |
| **Fused ops** | Kernel launch overhead matters; fuse everything you can |
| **CPU reference + GPU fast path** | Correctness verification without doubt |
| **PyTorch bridge via binary files** | No FFI/bindings complexity; just files |
| **Deterministic training** | Bucket-sort for embedding grads, deterministic seeds |
| **Async NCCL on separate stream** | Overlap communication with compute |

---

*Document generated from analysis of the core.c repository (commit around June 2026).*