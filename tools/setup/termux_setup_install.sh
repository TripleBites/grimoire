#!/bin/bash

pkg update
pkg install python rust libffi clang make cmake libzmq binutils
pip install uv