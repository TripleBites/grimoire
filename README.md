```text                                       
 ▄▄▄▄ ▄▄▄▄  ▄▄ ▄▄   ▄▄  ▄▄▄  ▄▄ ▄▄▄▄  ▄▄▄▄▄ 
██ ▄▄ ██▄█▄ ██ ██▀▄▀██ ██▀██ ██ ██▄█▄ ██▄▄  
▀███▀ ██ ██ ██ ██   ██ ▀███▀ ██ ██ ██ ██▄▄▄ 
```

# What is this
Grimoire is a platform for building and testing ternary neural networks (TNNs): models whose weights and activations are all in {-1, 0, +1}. It is the workbench for the larger goal, **Merlin**: a multimodal machine learning model that runs, and is fully trainable, with ternary weights and activations. Merlin comes later; Grimoire comes first.

Grimoire embeds the [Janet](https://janet-lang.org) language, which we use for network layouts, configurations, saved model weights and training scripts. SDL3 is the platform and OS layer, which keeps the project cross-platform. ImGui is planned for visual tools later; it is not part of the MVP.

# Research Goals
1. Discover learning rules that train TNNs natively, without the floating-point math that gradient descent requires.
2. Discover learning rules that let a system learn, fine-tune itself and run inference in a single forward pass.

# The Big Question (Training)
How do we train these networks with fully ternary weights and activations?

**Existing methods:**
- Quantization-Aware Training (QAT) with the Straight-Through Estimator
- Threshold-based and sparsity-controlled quantization
- Continuous relaxation (annealing)
- Stochastic quantization
- Progressive/elastic quantization and distillation

**First experiment:** Top, a ternary variant of the Bop optimizer, on MNIST. See [SPEC.md](SPEC.md).

# Build and run
Requires CMake 3.15+, GCC or Clang, and SDL3 installed where CMake can find it. Run from the repo root:

```
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/grimoire src/scripts/hello.janet
```

# Layout
See SPEC.md section 4. Ternary arrays are stored as two bitplanes (a nonzero mask and a sign), padded to 64-bit words; see SPEC.md section 5.
