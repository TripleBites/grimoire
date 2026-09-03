# AI & ML Architecture Diagram Cheat Sheet

When reading machine learning architecture diagrams—such as the one in the file you referenced, **1788461054516.png**—you will frequently encounter a standardized set of mathematical and structural symbols. 

Here is a quick reference guide to help you decode them whenever you are looking at model documentation or papers.

## 1. The Circular Math Symbols

These are the most common symbols that usually trip people up. They generally represent **element-wise** operations, meaning the math is applied to the corresponding elements of two tensors (data arrays) of the exact same shape.

### ⊕ (Circle with a "+") : Element-wise Addition
* **What it means:** The two incoming tensors are added together, value by individual value.
* **Common usage:** **Residual Connections (Skip Connections)**. 
* **In practice:** In your reference image (1788461054516.png), you can see long arrows looping around the outside of the "Time Mixing" and "Channel Mixing" blocks. These arrows carry the original, unprocessed input and flow directly into a **⊕** symbol alongside the block's output. This adds the original input back to the processed data. It acts as a shortcut for the data, which prevents the "vanishing gradient" problem and helps deep networks learn much faster.

### ⊗ (Circle with an "x") : Element-wise Multiplication (Hadamard Product)
* **What it means:** The two incoming tensors are multiplied together, value by individual value. 
* **Common usage:** **Gating Mechanisms**. 
* **In practice:** This is used to filter, scale, or "gate" information. For example, if one input comes from a Sigmoid function (which squishes all values between 0 and 1), multiplying it by another tensor acts like a volume knob—determining exactly how much of the other tensor's data is allowed to pass through. You can see this happening in the reference image inside the mixing blocks, where the outputs of **σ** (sigmoid) or **R** (receptance) are combined with other data streams using the **⊗** symbol.
* *(Note: Sometimes you might also see **⊙ (a circle with a dot in the middle)** used for this exact same operation).*

---

## 2. Other Common Diagram Elements

### ➔ (Arrows) : Tensors (Data Flow)
* **What it means:** The arrows represent the flow of multi-dimensional data arrays (tensors) from one operation to the next.
* **Forking / Splitting Arrows:** When an arrow splits into two or more paths, it means the exact same tensor is being duplicated and sent to multiple operations at the exact same time. You see this heavily at the start of the "Channel Mixing" and "Time Mixing" blocks in your image.

### ▭ (Rectangles / Boxes) : Layers or Operations
* **What it means:** Boxes represent distinct transformations, neural network layers, or mathematical functions applied to the data. Colors are usually arbitrary and just used by the author to group similar concepts together.
* **Examples from your image (1788461054516.png):** 
    * **LayerNorm:** A normalization layer that scales the data to keep it stable during training.
    * **Softmax:** A function (usually at the very end of a model) that converts raw numerical scores into percentages/probabilities that sum to 1.
    * **Linear / Matrix blocks (R, K, V, Out):** These typically represent learned parameter matrices (weights) that the model trains over time.

### [ ] or || (Concatenation)
* **What it means:** Joining two tensors together along a specific dimension (like gluing two arrays side-by-side) rather than doing math on their values. 
* **Symbol:** While not explicitly explicitly shown as a unique symbol in your reference image, this is often represented by arrows merging into a box labeled "Concat", or a circle with two vertical lines `||`.

### Matrix Multiplication (Dot Product)
* **What it means:** Standard linear algebra matrix multiplication (combining rows and columns, rather than element-by-element).
* **Symbol:** It is rarely drawn as a circle symbol. Instead, it is usually implied when a tensor flows into a fully connected layer box, or it's sometimes represented by a standard `x` or `·` without the circle.

---

## Summary Walkthrough from "1788461054516.png"

To put it all together, if you trace the **Channel Mixing** block in your image from bottom to top:
1. The input tensor comes in from the bottom and **forks** into multiple paths.
2. The paths go through different transformations (like the **σ** box).
3. The paths are combined using **⊗ (Element-wise multiplication)** to filter/gate the data.
4. The heavily processed result exits the gray block and is added back to the original, unmodified input using **⊕ (Residual addition)**. 