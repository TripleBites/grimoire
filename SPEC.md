# Grimoire MVP spec: Top (ternary Bop) on MNIST

## 1. Goal

Answer one question: **does Top, a ternary variant of the Bop optimizer, train a fully ternary MLP on MNIST?**

Everything else in this spec is the minimum scaffolding needed to ask that
question from a Janet script. The owner will extend the project by hand
afterwards, so the code must be small enough to read in one sitting.

Reference: Helwegen et al., "Latent Weights Do Not Exist: Rethinking Binarized
Neural Network Optimization", https://arxiv.org/abs/1906.02107 (Algorithm 2).

## 2. Not in scope

Do not build any of these, even if they would improve accuracy:

- Batch norm, biases, learned thresholds, latent weights, Adam, learning-rate
  or hyperparameter schedules, dropout, data augmentation, shuffling.
- Convolutions, any layer type other than dense.
- SIMD intrinsics, threads, GPU code.
- A CLI argument parser, config system, logging framework, or test framework.
- Binary weight-file encodings, checkpoints of optimizer state.
- A Janet DSL for building networks (a spec is a plain struct, see section 8).
- MNIST downloading or gzip decoding. The owner places the four uncompressed
  IDX files in `data/mnist/`.

If a result looks bad, report it (section 10). Do not add machinery to fix it.

## 3. Stack

- C++11, built with CMake. Target compilers: GCC and Clang.
- Janet, vendored as the single-file amalgamation (`janet.c`, `janet.h`).
- SDL3 as the platform layer, found with `find_package(SDL3 REQUIRED CONFIG)`.
  If it is not found, stop and tell the owner. Do not vendor or fetch it.
- No other dependencies.

## 4. Layout

Files marked with a milestone do not exist yet; that milestone creates them.

```
CMakeLists.txt                  sources are listed by hand, no globs
src/core/main.cpp               entry point, --selftest (M2), SDL and Janet init
src/core/platform.hpp     (M2)  plat_alloc / plat_free (64-byte aligned), over SDL3
src/core/bind.cpp         (M3)  all Janet natives
src/core/mnist.hpp        (M3)  Mnist, IDX loader
src/core/viz.hpp          (M6)  debug window
src/core/tnn/trit.hpp     (M2)  Trits
src/core/tnn/tnn.hpp      (M3)  Net, Layer, forward pass
src/core/tnn/optimizer.hpp (M4) Top
src/lib/grimoire/hello.janet      M1 import check
src/lib/grimoire/tnn.janet  (M5)  save and load
src/nets/mnist-mlp.janet        network spec
src/scripts/hello.janet         M1 boot check
src/scripts/train-mnist.janet   the experiment
src/vendor/janet/               janet.c, janet.h (built as a separate library)
data/mnist/                     the four IDX files
ckpt/                           saved networks (git-ignored)
```

Everything runs from the repo root. `src/lib/` is Janet's module root, so
`(import grimoire/tnn)` loads `src/lib/grimoire/tnn.janet`.

- **Budget: under 1,000 lines of C++ and under 100 lines of Janet in total**,
  excluding `vendor/`. If a milestone would break the budget, stop and say so.

## 5. Trits: the ternary array

Two bitplanes, one row per vector, each row padded to whole 64-bit words.

```cpp
class Trits {
public:
    Trits() {}
    ~Trits() { free(); }
    Trits(const Trits &) = delete;
    Trits &operator=(const Trits &) = delete;

    bool init(uint32_t rows, uint32_t cols);   // zeroed, 64-byte aligned
    void free();                               // safe to call twice
    int  get(uint32_t r, uint32_t c) const;    // returns -1, 0 or +1
    void set(uint32_t r, uint32_t c, int v);
    int  dot(uint32_t ra, const Trits &b, uint32_t rb) const;

    uint64_t *mask = nullptr;  // bit = 1: trit is nonzero
    uint64_t *sign = nullptr;  // bit = 1: trit is -1 (only where mask = 1)
    uint32_t  rows = 0, cols = 0;
    uint32_t  stride = 0;      // 64-bit words per row = (cols + 63) / 64
};
```

Data members are public: the optimizer and the selftest read the bitplanes
directly, and getters would only add lines.

Invariants, checked by the selftest:

1. Where a `mask` bit is 0, the `sign` bit is 0.
2. Padding bits past `cols` are 0 in both planes.

`Trits::dot` over the words of the two rows:

```
nz   = a.mask & b.mask
sum += popcount(nz) - 2 * popcount(nz & (a.sign ^ b.sign))
```

Use one inline `popcount64` wrapper around `__builtin_popcountll`
(`std::popcount` is C++20 and not available). "SIMD friendly" here means the
layout only: aligned, contiguous, branch-free word loops. No intrinsics.

A vector is a `Trits` with `rows = 1`. A weight matrix has one row per output
neuron. The MNIST images are one `Trits` with one row per image.

## 6. Network

A stack of dense layers. All weights and all hidden activations are ternary.
No bias.

```cpp
struct Layer {
    Trits w;       // rows = out, cols = in
    float scale;   // s = sqrt(in)
    float theta;   // activation threshold in units of s (hidden layers only)
    int   delta;   // integer threshold = round(theta * s)
};
class Net {
public:
    // same rules as Trits: empty constructor, bool init(...), free(),
    // destructor calls free(), copying deleted
    Layer   *layers = nullptr;
    uint32_t n_layers = 0, n_in = 0;
    // plus the z / x scratch buffers and forward() / predict()
};
```

`Layer` stays a plain struct: it owns nothing beyond its `Trits`, which frees
itself. Allocate the layer array with `plat_alloc` and placement `new`, and
call `~Layer()` before `plat_free`.

Input encoding (in the MNIST loader): pixel >= 128 becomes +1, otherwise -1.

Forward pass for one sample, integers only:

```
x[0] = input row
for each layer l:
    z[j] = W_l.dot(j, x[l-1], 0)
    hidden layer:  x[l][j] = +1 if z[j] >  delta
                             -1 if z[j] < -delta
                              0 otherwise
    last layer:    no activation; z is the output
prediction = argmax z   (ties: lowest index)
```

Initial weights: each trit uniformly from {-1, 0, +1}, from a seeded
xorshift64 generator written inline (do not use `<random>`).

Scratch buffers for `z` and `x` are allocated once per network, not per sample.

## 7. Top: the optimizer

### 7.1 Gradient (floats, backward pass)

Per sample, with `s_l` the scale of layer `l` and `L` the last layer:

```
logits = z_L / s_L
p      = softmax(logits)                 loss = -log p[label]
d_L[k] = (p[k] - onehot[k]) / s_L

for hidden layers, going backward:
    e[j]   = sum over k of W_{l+1}[k][j] * d_{l+1}[k]
    d_l[j] = e[j] / s_l   if |z_l[j]| <= s_l
             0            otherwise

G_l[j][i] += d_l[j] * x[l-1][i]
```

The window `|z| <= s` is the straight-through surrogate for the ternary
activation. `G` is a float array, `out * in` per layer, accumulated over a batch.

### 7.2 Update (once per batch of B samples)

```
g = G / B
m = (1 - gamma) * m + gamma * g          per weight, m starts at 0

if      m >  tau_l and w > -1:  w -= 1;  m = 0;  flips_l++
else if m < -tau_l and w < +1:  w += 1;  m = 0;  flips_l++

G = 0
```

This is Bop with three changes, all deliberate:

1. **Step through zero.** A weight moves one step per update: -1, 0, +1.
2. **Momentum resets on a step.** Without the reset, `m` is still past `tau`
   on the next batch, so a weight leaving +1 would land on 0 and move on to -1
   immediately, and 0 would never be a resting state.
3. **`tau` is per layer.** There is no batch norm to equalize gradient scale
   between layers.

Hyperparameters and starting values:

| Name | Start | Meaning |
|---|---|---|
| `gamma` | 1e-3 | adaptivity rate of the moving average |
| `tau` | [1e-5, 1e-4] | step threshold, one per layer |
| `batch` | 64 | samples per update |
| `theta` | 0.5 | hidden activation threshold, in the net spec |

These values are back-of-envelope estimates and have never been run. Expect to
tune them (section 9, milestone 4).

### 7.3 Interface

`Mnist` and `Top` follow the same class rules as `Trits`.

```cpp
struct TrainStats { double loss_sum; uint32_t correct; uint32_t n; uint32_t *flips; };
class Mnist {                  // in mnist.hpp
public:
    bool load(const char *images_path, const char *labels_path);
    void free();
    Trits    images;           // one row per image
    uint8_t *labels = nullptr;
    uint32_t n = 0;
};
class Top {                    // in optimizer.hpp
public:
    bool init(Net *net, float gamma, const float *tau, uint32_t batch);
    void free();
    void train(const Mnist &data, uint32_t first, uint32_t count, TrainStats *out);
    Net     *net = nullptr;    // not owned
    float    gamma = 0;
    float   *tau = nullptr;    // one per layer
    uint32_t batch = 0;
    float  **G = nullptr;      // per layer, out * in
    float  **m = nullptr;      // per layer, out * in, starts at 0
};
```

`Top::train` trains on samples `[first, first + count)` in order, clamped to the end of the
dataset. The last batch may be short. No shuffling.

Write the obvious loops first. One permitted shortcut: unpack the input row
into an `int8_t` buffer once per sample before the `G` update. Aim for one
epoch in about a minute in a Release build; if it is far slower, report it and
wait.

## 8. Janet API

`main.cpp`: `grimoire <script.janet>` runs the script; `grimoire --selftest` runs
the checks. It initializes SDL and Janet, calls `grimoire_register` (from M3),
sets Janet's `:syspath` to `src/lib` so `(import grimoire/tnn)` resolves to
`src/lib/grimoire/tnn.janet` (run from the repo root), and runs the script
through Janet's own `dofile` so relative imports work.

Natives, all in `bind.cpp`:

| Call | Returns |
|---|---|
| `(mnist/load images-path labels-path)` | dataset |
| `(mnist/count data)` | number of samples |
| `(tnn/build spec seed)` | net |
| `(tnn/layers net)` | tuple of `{:in n :out n :theta x}` |
| `(tnn/row net layer i)` | neuron `i`'s weights as a string of `+`, `0`, `-` |
| `(tnn/set-row net layer i str)` | nil |
| `(tnn/stats net layer)` | `{:neg n :zero n :pos n}` |
| `(tnn/evaluate net data)` | fraction correct |
| `(top/new net {:gamma g :tau [t0 t1] :batch b})` | optimizer |
| `(top/train opt data first count)` | `{:loss mean :acc fraction :flips [n0 n1]}` |

Binding rules:

- Net, dataset and optimizer are Janet abstract types. The object lives in
  the abstract's memory, constructed with placement `new`; the `gc`
  finalizer calls its destructor.
- The optimizer holds a pointer to its net and must mark it in `gcmark`.
- Janet panics are `longjmp`. The argument getters panic on bad input, so read
  and validate every argument before allocating anything.
- Natives use the prefixes `mnist/`, `tnn/`, `top/`. The Janet module
  `grimoire/tnn` also imports as `tnn/`; do not reuse a name on both sides.

The network spec, `src/nets/mnist-mlp.janet`. The last layer is always the linear
output; every other layer is ternary.

```janet
(def spec
  {:input 784
   :layers [{:out 512 :theta 0.5}
            {:out 10}]})
```

Save and load live in `src/lib/grimoire/tnn.janet`, built from `tnn/layers`,
`tnn/row` and `tnn/set-row`. `load` uses `parse`, never `eval`. File format:

```janet
{:format :tnn :version 1
 :input 784
 :layers [{:out 512 :theta 0.5 :rows ["+0-0..." "..."]}
          {:out 10 :rows ["..."]}]}
```

The experiment, `src/scripts/train-mnist.janet`, should read close to this:

```janet
(import grimoire/tnn)
(import ../nets/mnist-mlp :as arch)

(def train (mnist/load "data/mnist/train-images-idx3-ubyte" "data/mnist/train-labels-idx1-ubyte"))
(def test  (mnist/load "data/mnist/t10k-images-idx3-ubyte"  "data/mnist/t10k-labels-idx1-ubyte"))
(def net   (tnn/build arch/spec 42))
(def opt   (top/new net {:gamma 1e-3 :tau [1e-5 1e-4] :batch 64}))

(for epoch 0 10
  (loop [first :range [0 (mnist/count train) 6400]]
    (def r (top/train opt train first 6400))
    (printf "  %5d  loss %.4f  acc %.4f  flips %j" first (r :loss) (r :acc) (r :flips)))
  (printf "epoch %d  test acc %.4f  layer0 %j"
          epoch (tnn/evaluate net test) (tnn/stats net 0)))

(tnn/save net "ckpt/mnist-mlp.tnn.janet")
```

## 9. Milestones

Do one milestone per request, then stop and report.

**M0. Read and plan.** Read the existing files. Report what is there, what you
would keep, and anything in this spec that conflicts with it. Write no code.

**M1. Build and boot.** CMake builds Janet, links SDL3, produces `grimoire`.
`src/scripts/hello.janet` prints a line and imports a one-function module,
`src/lib/grimoire/hello.janet`.
*Check:* the script's output.

**M2. Trits.** `trit.hpp`, `platform.hpp`, and `grimoire --selftest`.
*Check:* `Trits::dot` matches a naive per-element loop on random rows for
`cols` in {1, 63, 64, 65, 784}; get/set round-trips; both invariants hold.

**M3. Data and forward pass.** `mnist.hpp`, `tnn.hpp`, and the natives
`mnist/*`, `tnn/build`, `tnn/stats`, `tnn/evaluate`.
*Check:* an untrained net scores near 10% on the test set, and `tnn/stats`
shows roughly one third each of -1, 0, +1.

**M4. Top.** `optimizer.hpp`, `top/new`, `top/train`.
*Checks, in order:*
1. Selftest for the update rule: all six cases of (w, sign of m past tau),
   including the momentum reset.
2. Overfit: train repeatedly on the first 256 samples. Training accuracy
   should climb toward 100%. If it does not, that is a bug or a broken rule;
   find out which before going on.
3. Full run: 10 epochs with `src/scripts/train-mnist.janet`.

Target for the full run: 90% test accuracy or better. This is a research
question, so the target may not be reachable. You may tune only `gamma`,
`tau`, `theta` and `batch`, in the Janet files, for at most 10 runs. Use the
flip counts as the guide: a layer that steps more than about 1% of its weights
per batch is following noise (raise its `tau`); a layer with no steps is frozen
(lower it). Report every run in a table.

**M5. Save and load.** `tnn/layers`, `tnn/row`, `tnn/set-row`, and
`src/lib/grimoire/tnn.janet`.
*Check:* save, load into a fresh net, and get the identical test accuracy;
saving the loaded net produces a byte-identical file.

**M6. Debug window. Only when the owner asks.** `viz.hpp` plus `(viz/open)`
and `(viz/frame net)`, which pumps SDL events, draws the first 64 neurons of
layer 0 as 28x28 tiles (-1 blue, 0 black, +1 orange), and returns false once
the window is closed. Called from the script's loop; under 100 lines.

## 10. Report format

End every milestone with:

1. Files added or changed, with line counts, and the running total against the
   budget.
2. The exact commands you ran and their real output. Never describe a result
   you did not observe.
3. Every place you deviated from this spec, and why.
4. Open questions for the owner.