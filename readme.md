```text
 ██████   ██████                    ████   ███            
░░██████ ██████                    ░░███  ░░░             
 ░███░█████░███   ██████  ████████  ░███  ████  ████████  
 ░███░░███ ░███  ███░░███░░███░░███ ░███ ░░███ ░░███░░███ 
 ░███ ░░░  ░███ ░███████  ░███ ░░░  ░███  ░███  ░███ ░███ 
 ░███      ░███ ░███░░░   ░███      ░███  ░███  ░███ ░███ 
 █████     █████░░██████  █████     █████ █████ ████ █████
░░░░░     ░░░░░  ░░░░░░  ░░░░░     ░░░░░ ░░░░░ ░░░░ ░░░░░
```

# What is this
This is my attempt to build a fully multimodel machine learning model that operates, and is fully trainable using ternary weights and activations. {-1,0,1}. These are abbreviated to TNN's

# Research Goals
1. Discover new learning / training rules that allow us to train TNN's natively without the floating point math that gradient decent requires.
2. Discover new learning / training rules  that let a system learn, fine tune itself, and run inference in a single forward pass.

# The Big Question (Training)
We need to figure out a way to train these neural networks in full ternary ternary weights and activations.

**Existing Methods:***
- Quantization-Aware Training (QAT) with the Straight-Through Estimator
- Threshold-Based and Sparsity-Controlled Quantization
- Continuous Relaxation (Annealing)
- Stochastic Quantization
- Progressive/Elastic Quantization and Distillation

# Memory Layout


