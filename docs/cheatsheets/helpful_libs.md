# Helpful libs 

### Minimal Autograd & Educational Frameworks
Instead of jumping into PyTorch, these lightweight frameworks let you study how automatic differentiation and neural network backpropagation work under the hood.

- **micrograd:** A tiny scalar autograd engine written by Andrej Karpathy.

- **tinygrad:** A minimal deep learning framework designed to be simple, readable, and hackable. It acts as an approachable bridge between basic math and modern framework logic without the multi-gigabyte bloat of PyTorch.

### Fundamental Math & Benchmark Tools
- **scipy:** The natural expansion to NumPy. It adds specialized linear algebra routines, optimization algorithms (scipy.optimize is great for studying gradient-free vs. gradient-based optimization), and signal processing routines.

- **scikit-learn:** The industry standard for classical ML (decision trees, clustering, PCA, support vector machines). Having this installed gives you a reliable baseline to test your custom NumPy algorithms against.

- **sympy:** A pure Python library for symbolic mathematics. It is fantastic in Jupyter Notebooks for deriving exact analytical derivatives, simplifying loss functions, and verifying equations before writing their vectorized NumPy equivalents.

### Visualization & Notebook Utilities
- **matplotlib:** Essential for plotting loss curves, decision boundaries, visual activation functions, and tracking convergence directly in your Jupyter notebooks on mobile or desktop.

- **tqdm:** A lightweight, pure-Python progress bar wrapper that works in terminal sessions and Jupyter notebooks without adding overhead to training loops.

## For Grimoire Specifically
- LangGraph
- Langchain
- wasmtime-py
- pywasm
- RestrictedPython