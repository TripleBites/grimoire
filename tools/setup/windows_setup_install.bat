@echo off
echo 🪟 Setting up Jupyter host for Windows 11...

REM Check if Python is installed and accessible
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Python is not installed or not in your system PATH. 
    echo Please install Python from the Microsoft Store or python.org and run this again.
    pause
    exit /b 1
)

REM Install Astral's uv package manager via PowerShell
echo ⬇️ Installing uv package manager...
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

REM Add uv to the path for the current terminal session
set "PATH=%USERPROFILE%\.cargo\bin;%USERPROFILE%\.local\bin;%PATH%"

echo ✅ Setup complete! You can now run:
echo python jupyter_run.py
pause