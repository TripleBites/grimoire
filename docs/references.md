# References

### 1. Conceptual & Architectural Deep Dives (BitNet & Ternary Weights)

* **[The Myth of 1-bit LLMs | Quantization-Aware Training](https://www.youtube.com/watch?v=WBm0nyDkVYM&utm_source=gemini) — Julia Turc**
* **Length:** ~25 min
* **Focus:** A deep dive into how ternary models work in practice. Explains the transition from binary to 1.58-bit ternary ($\{-1, 0, 1\}$), why adding zero acts as a crucial feature filter, and how Quantization-Aware Training (QAT) with Straight-Through Estimators (STE) allows gradient flow through discrete operations.


* **[How 1 Bit LLMs Work](https://www.youtube.com/watch?v=MXWlB9nDAFU&utm_source=gemini) — Oxen.ai**
* **Length:** ~47 min
* **Focus:** A detailed paper walkthrough of Microsoft's BitNet b1.58 paper. Breaks down the `BitLinear` transformation, absmean scaling, and how matrix multiplication reduces to pure integer additions and subtractions.


* **[The Era of 1-bit LLMs: All Large Language Models are in 1.58 Bits](https://www.youtube.com/watch?v=wN07Wwtp6LE&utm_source=gemini) — Krish Naik**
* **Length:** ~17 min
* **Focus:** High-level architectural overview covering why ternary weights eliminate floating-point multiplications, reducing memory bandwidth requirements and energy consumption.



---

### 2. Practical Training & PyTorch QAT Implementations

* **[Quantization Explained with PyTorch: Post-Training & Quantization-Aware Training](https://www.youtube.com/watch?v=0VdNflU08yA&utm_source=gemini) — Umar Jamil**
* **Length:** ~51 min
* **Focus:** One of the clearest step-by-step code tutorials on quantization mechanics. Walks through building custom quantization operators in PyTorch, setting up scale/zero-point calculations, and implementing the training loop required for Quantization-Aware Training.


* **[Neural Network Quantization with Brevitas (TVMCon Tutorial)](https://www.youtube.com/watch?v=wsXx3Hr5kZs&utm_source=gemini) — AMD / Xilinx Research**
* **Length:** ~25 min
* **Focus:** Explores Brevitas (the primary PyTorch library used for ultra-low precision QAT, including sub-2-bit and ternary models). Demonstrates how to write custom quantized building blocks and control low-bit datapaths during training.



---

### 3. Academic Lectures & Foundational Theory

* **[MIT 6.S965 / 6.5940: Quantization (Lecture 05)](https://www.youtube.com/watch?v=AlASZb93rrc&utm_source=gemini) — Prof. Song Han (MIT HAN Lab)**
* **Length:** ~50 min
* **Focus:** Comprehensive university lecture covering the mathematical foundations of low-precision neural networks, linear quantization formulas, clamping, and handling non-differentiable step functions.



---

### 4. Podcast Episodes & Audio Overviews

* **[1-bit LLMs & BitNet b1.58 Overview](https://www.youtube.com/watch?v=3QbzMHCZvjY&utm_source=gemini)**
* **Length:** ~15 min (Audio / Podcast format)
* **Focus:** Discusses the systems-level impact of ternary computing, CPU-side kernel acceleration (`bitnet.cpp`), and why hardware hardware-software co-design makes ternary models significantly faster than standard INT8 or FP16 models.