#!/usr/bin/env bash

# Install System Dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install jupyterlab
sudo apt install python3 python3-pip python3-venv python3-dev -y

# Make sure python3-venv or python3-full is fully installed 
sudo apt update && sudo apt install python3-full -y

# Create a virtual environment named 'jupyter_env'
python3 -m venv jupyter_env

# Activate the virtual environment
source jupyter_env/bin/activate

pip install --upgrade pip
pip install jupyterlab