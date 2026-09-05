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
    # Attempt to grab 0.17.0, fallback to master if unreleased
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
echo "  export CC=\"zig cc\" && export CXX=\"zig c++\""
echo "  jupyter lab --ip=127.0.0.1 --port=8888 --no-browser"
echo "======================================================"
