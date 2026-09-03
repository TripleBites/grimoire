#!/bin/bash
echo "🍓 Setting up Jupyter host for Raspberry Pi..."

# Install required system dependencies (compilers and networking libraries)
sudo apt update
sudo apt install -y python3 python3-venv python3-pip build-essential libffi-dev libzmq3-dev

# Install Astral's uv package manager if it's missing
if ! command -v uv &> /dev/null; then
    echo "⬇️ Installing uv package manager..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    
    # Source the environment so uv is available immediately without a reboot
    source $HOME/.local/bin/env
fi

echo "✅ Setup complete! You can now run:"
echo "python3 jupyter_run.py"