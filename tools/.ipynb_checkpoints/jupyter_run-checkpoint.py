#!/usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path

def main():
    print("🚀 Initializing Jupyter environment...")
    
    # 1. Verify uv is available
    try:
        subprocess.run(["uv", "--version"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ 'uv' is missing. Please run the setup script for your platform first.")
        sys.exit(1)

    # 2. Scaffold virtual environment
    venv_dir = Path(".venv")
    if not venv_dir.exists():
        print("📦 Scaffolding isolated virtual environment with uv...")
        subprocess.run(["uv", "venv"], check=True)
    else:
        print("✅ Virtual environment found.")
    
    # 3. Determine the correct Python executable path for the OS
    bin_dir = "Scripts" if os.name == "nt" else "bin"
    python_exe = venv_dir / bin_dir / ("python.exe" if os.name == "nt" else "python")
    
    # 4. Install Jupyter if missing
    try:
        # Check if the module is available inside the venv
        subprocess.run([str(python_exe), "-c", "import notebook"], capture_output=True, check=True)
        print("✅ Jupyter is installed.")
    except subprocess.CalledProcessError:
        print("⬇️ Installing Jupyter Notebook...")
        subprocess.run(["uv", "pip", "install", "jupyter", "notebook"], check=True)

    # 5. Launch the server using the venv's Python executable
    print("🌐 Launching Jupyter server on 0.0.0.0...")
    cmd = [
        str(python_exe), 
        "-m", "jupyter", "notebook", 
        "--ip=0.0.0.0", 
        "--port=8888", 
        "--no-browser"
    ]
    
    try:
        subprocess.run(cmd)
    except KeyboardInterrupt:
        print("\n🛑 Jupyter server stopped.")

if __name__ == "__main__":
    main()