#!/bin/bash
# run_fuzz_load.sh - Run fuzzing test for load_floor_config (file I/O testing)

# 1. Set the path to the Python executable in the 'fuzz-env' Conda environment
PYTHON_BIN="/opt/homebrew/Caskroom/miniconda/base/envs/fuzz-env/bin/python"

# 2. Set DYLD_LIBRARY_PATH to include Homebrew's LLVM libc++
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/llvm/lib/c++:$DYLD_LIBRARY_PATH"

# 3. Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if the Python environment exists
if [ ! -f "$PYTHON_BIN" ]; then
    echo "Error: Python executable not found at $PYTHON_BIN"
    echo "Please ensure the 'fuzz-env' conda environment is created."
    exit 1
fi

echo "Environment configured."
echo "Running file I/O fuzzer with: $PYTHON_BIN"
echo "Target script: $SCRIPT_DIR/fuzz_load_floor_config.py"
echo "This tests load_floor_config (file reading + validation)"
echo "---------------------------------------------------"

# 4. Run the fuzzer
# Use a separate corpus directory for file I/O tests
mkdir -p "$SCRIPT_DIR/fuzz_corpus_load"

echo "Using corpus directory: $SCRIPT_DIR/fuzz_corpus_load"

# Run the fuzzer script, passing the corpus directory FIRST, followed by any other arguments
"$PYTHON_BIN" "$SCRIPT_DIR/fuzz_load_floor_config.py" "$SCRIPT_DIR/fuzz_corpus_load" "$@"

