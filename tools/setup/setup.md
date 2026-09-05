# Grimoire Mobile Engineering Environment Setup

This document outlines the architecture, toolchain specifications, and setup procedure for the **Grimoire** AI coding agent and sandboxed execution system running natively on Android via Termux.

---

## 1. System Architecture Overview

The system is designed as a lightweight, high-performance hybrid AI development stack optimized for mobile hardware (ARM64 / 12GB RAM).

```
+-----------------------------------------------------------------------+
|                         JupyterLab Command Center                     |
|                   (Python 3.14 Venv via Astral uv)                   |
+-----------------------------------------------------------------------+
                                   |
        +--------------------------+--------------------------+
        |                                                     |
+-------v-------------------------+         +-----------------v---------+
|     Orchestration & Routing     |         |     Sandboxed Tooling     |
| (PydanticAI / Smolagents Stack) |         | (Zig 0.17.0 / WebAssembly)|
+---------------------------------+         +---------------------------+
        |                                                     |
        +--------+------------------+                         |
                 |                  |                         |
+----------------v--+    +----------v-------+       +---------v---------+
| DeepSeek Coder API |    | Kimi-2.7 Coder   |       | Local llama.cpp   |
| (Cloud Inference) |    | (Cloud Inference) |       | (Qwen2.5-Coder 7B)|
+-------------------+    +------------------+       +-------------------+
```

### Technical Stack Specifications

* **Host OS / Shell:** Android (aarch64) running Termux.
* **Orchestration Layer:** Python 3.14 managed by Astral's `uv` package manager.
* **Native Toolchain & Linking:** Zig compiler (`zig cc` / `zig c++`) acting as the unified C/C++ cross-compiler and Cargo linker to bypass Android NDK Bionic libc linking constraints (`libgcc` substitution).
* **Execution & Sandboxing Target:** `wasm32-freestanding` WebAssembly compiled by Zig and executed within Python using deterministic fuel/memory bounds (`wasmtime-py`).
* **Interactive Environment:** JupyterLab running locally on port 8888 with `no-browser` flags.
* **Inference Pipeline:** Dual-channel hybrid setup utilizing cloud API endpoints (DeepSeek Coder / Kimi 2.7) alongside an on-device `llama.cpp` server.

---

## 2. Startup Script Breakdown (`tools/setup/termux_phone.sh`)

The setup script handles system package provisioning, toolchain bootstrap, dynamic binary resolution, and virtual environment initialization.

### Step-by-Step Script Operation

1. **System Dependency Provisioning (`pkg`):**
   Installs core build utilities, shared libraries (`libzmq`), Rust compiler (`cargo`), and `jq` for JSON manipulation.

2. **Dynamic Zig Toolchain Fetching:**
   Queries `https://ziglang.org/download/index.json` using `jq` to dynamically fetch the official `aarch64-linux` tarball URL for Zig 0.17.0 (or fallback to nightly master) to prevent broken release links.

3. **Compiler Overrides (`CC`, `CXX`, `CARGO_LINKER`):**
   Sets `CC="zig cc"`, `CXX="zig c++"`, and `CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="zig cc"`. This forces Rust and C-extensions to link against Android's runtime cleanly without missing library errors.

4. **Cargo Build of `uv`:**
   Compiles Astral's `uv` tool natively inside Termux using Cargo linked by Zig.

5. **Python 3.14 & Virtual Environment Setup:**
   Executes `uv python install 3.14` and provisions a clean `.venv` within the `grimoire/` repository root.

6. **JupyterLab Deployment:**
   Installs `jupyterlab` directly into the `.venv` using `uv pip`.

---

## 3. Full Script Source Code

File Location: `./tools/setup/termux_phone.sh`

```bash
#!/usr/bin/env bash
set -e

echo "[*] Setting up Termux environment for Grimoire (Python 3.14, Zig, JupyterLab)..."

# 1. Update Termux and install system prerequisites
echo "[*] Installing system dependencies..."
pkg update -y
pkg install -y curl tar xz-utils clang binutils libzmq build-essential rust jq

# 2. Install Zig dynamically via official JSON index
echo "[*] Installing Zig for aarch64..."

mkdir -p "$HOME/.local/opt/zig"
mkdir -p "$HOME/.local/bin"

if [ ! -f "$HOME/.local/bin/zig" ]; then
    echo "Querying Zig release index..."
    ZIG_URL=$(curl -sL https://ziglang.org/download/index.json | jq -r '."0.17.0"."aarch64-linux".tarball')
    
    if [ "$ZIG_URL" == "null" ] || [ -z "$ZIG_URL" ]; then
        echo "[!] 0.17.0 standard tarball not found in release index. Fetching latest master build..."
        ZIG_URL=$(curl -sL https://ziglang.org/download/index.json | jq -r '.master."aarch64-linux".tarball')
    fi
    
    echo "Downloading from: $ZIG_URL"
    curl -fL "$ZIG_URL" -o zig.tar.xz
    
    tar -xf zig.tar.xz -C "$HOME/.local/opt/zig" --strip-components=1
    rm zig.tar.xz
    
    ln -sf "$HOME/.local/opt/zig/zig" "$HOME/.local/bin/zig"
    echo "[+] Zig installed successfully."
else
    echo "[+] Zig is already installed."
fi

export PATH="$HOME/.local/bin:$PATH"

# 3. Configure Compilers to use Zig
echo "[*] Configuring CC/CXX and Cargo to use Zig..."
export CC="zig cc"
export CXX="zig c++"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="zig cc"

# 4. Install Astral's uv via Cargo using Zig as the linker
echo "[*] Installing uv via Cargo (using Zig to compile)..."
if ! command -v uv &> /dev/null; then
    cargo install uv
    export PATH="$HOME/.cargo/bin:$PATH"
else
    echo "[+] uv is already installed."
fi

# 5. Use uv to install Python 3.14
echo "[*] Fetching Python 3.14 via uv..."
uv python install 3.14

# 6. Set up the project virtual environment
echo "[*] Initializing Grimoire environment..."
PROJECT_DIR="$HOME/grimoire"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

if [ ! -d ".venv" ]; then
    uv venv --python 3.14
fi

# 7. Install Jupyter Lab
echo "[*] Installing Jupyter Lab..."
source .venv/bin/activate
uv pip install jupyterlab

echo ""
echo "[+] Termux setup complete!"
echo "======================================================"
echo "To launch your Jupyter Lab environment, run:"
echo "  cd ~/grimoire"
echo "  source .venv/bin/activate"
echo "  export CC="zig cc" && export CXX="zig c++""
echo "  jupyter lab --ip=127.0.0.1 --port=8888 --no-browser"
echo "======================================================"
```

---

## 4. Execution & Launch Instructions

### Initial Setup Run
```bash
cd ~/grimoire
chmod +x ./tools/setup/termux_phone.sh
./tools/setup/termux_phone.sh
```

### Daily JupyterLab Launch Procedure
```bash
cd ~/grimoire
source .venv/bin/activate
export CC="zig cc"
export CXX="zig c++"
jupyter lab --ip=127.0.0.1 --port=8888 --no-browser
```
Access JupyterLab by opening `http://localhost:8888` in your device browser.

---

## 5. Integrating CLI Coding Agents & Live Debugging

To allow external CLI coding agents (e.g., DeepSeek Coder CLI or Aider) to inspect and debug the environment directly:

1. **Configure API Keys in Shell Session:**
   ```bash
   export DEEPSEEK_API_KEY="your_deepseek_token_here"
   export KIMI_API_KEY="your_kimi_token_here"
   ```

2. **Launch CLI Agent inside `grimoire/` Repo:**
   When running the CLI coding agent, instruct it to use the environment variables established by this document:
   * **Python Runtime:** `~/grimoire/.venv/bin/python`
   * **Compiler:** `~/.local/bin/zig`
   * **Setup Documentation:** Point the agent to read `setup.md` as its context anchor.

This ensures the agent understands that `zig cc` must remain the compiler/linker for native modules or WebAssembly generation on your phone.
