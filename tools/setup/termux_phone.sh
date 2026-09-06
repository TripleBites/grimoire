#!/usr/bin/env bash

# Install System Dependencies
pkg update -y
pkg install -y python clang binutils libzmq zig

# Install Jupyter Lab & C++ Kernel
pip install jupyterlab jupyter-cpp-kernel
install_cpp_kernel