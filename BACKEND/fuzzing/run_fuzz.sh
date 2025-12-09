#!/bin/bash
# run_fuzz.sh - Convenience script to run Atheris fuzzing on macOS

# 1. Set the path to the Python executable in the 'fuzz-env' Conda environment
PYTHON_BIN="/opt/homebrew/Caskroom/miniconda/base/envs/fuzz-env/bin/python"

# 2. Set DYLD_LIBRARY_PATH to include Homebrew's LLVM libc++
# This is required because Atheris was compiled with Homebrew's Clang but runs in Conda
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/llvm/lib/c++:$DYLD_LIBRARY_PATH"

# 3. Get the directory where this script is located to reliably find the python script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if the Python environment exists
if [ ! -f "$PYTHON_BIN" ]; then
    echo "Error: Python executable not found at $PYTHON_BIN"
    echo "Please ensure the 'fuzz-env' conda environment is created."
    exit 1
fi

echo "Environment configured."
echo "Running fuzzer with: $PYTHON_BIN"
echo "Target script: $SCRIPT_DIR/fuzz_roi_config.py"
echo "---------------------------------------------------"

# 4. Run the fuzzer
# Always use 'fuzz_corpus' directory to persist interesting inputs
mkdir -p "$SCRIPT_DIR/fuzz_corpus"

echo "Using corpus directory: $SCRIPT_DIR/fuzz_corpus"

# Run the fuzzer script, passing the corpus directory FIRST, followed by any other arguments
"$PYTHON_BIN" "$SCRIPT_DIR/fuzz_roi_config.py" "$SCRIPT_DIR/fuzz_corpus" "$@"

