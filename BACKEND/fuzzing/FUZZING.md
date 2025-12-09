# Fuzzing Test Guide

This document describes how to use Atheris to perform fuzzing tests on the backend ROI configuration validation logic.

## Test Types

We have **two types of fuzzing tests**:

1. **`fuzz_roi_config.py`** - Tests `validate_floor_config()` function
   - Tests validation logic only (in-memory data)
   - Faster, focuses on data validation rules
   - Run with: `./run_fuzz.sh`

2. **`fuzz_load_floor_config.py`** - Tests `load_floor_config()` function
   - Tests file I/O + JSON parsing + validation (complete workflow)
   - Tests file reading, encoding, and error handling
   - Run with: `./run_fuzz_load.sh`

## Prerequisites

Ensure you have set up the environment using the provided scripts.

- **Python Environment**: Managed automatically by `run_fuzz.sh` using the `fuzz-env` Conda environment.
- **Atheris**: Installed in the `fuzz-env` environment.
- **LibFuzzer**: Provided by the `llvm` package from Homebrew.

## Quick Start

### Test 1: Validation Logic Only (Recommended for Quick Tests)

The easiest way to run the fuzzing test is using the helper script located in the `BACKEND` directory.

#### 1. Basic Run (Recommended)

This command runs the fuzzer indefinitely until you stop it with `Ctrl+C`. It automatically uses the `fuzz_corpus` directory to save and load test cases, making the test smarter over time.

```bash
cd BACKEND
./run_fuzz.sh
```

### 2. Run for a Specific Number of Iterations

If you want to run the test for a fixed number of attempts (e.g., 100,000 runs) and then stop:

```bash
cd BACKEND
./run_fuzz.sh -runs=100000
```

### 3. Run for a Specific Time Duration

If you want the fuzzer to run for a specific amount of time (e.g., 1 hour) and then stop automatically:

```bash
cd BACKEND
# 3600 seconds = 1 hour
./run_fuzz.sh -max_total_time=3600
```

#### 4. Reproduce a Crash

If the fuzzer finds a crash, it will create a file named `crash-<hash>` in the `BACKEND` directory. To reproduce the crash and debug:

```bash
cd BACKEND
./run_fuzz.sh crash-<hash_of_the_crash_file>
```
*Example: `./run_fuzz.sh crash-7a8...`*

### Test 2: File I/O + Validation (Complete Workflow)

This test covers the complete workflow: file reading, JSON parsing, and validation.

#### 1. Basic Run

```bash
cd BACKEND
./run_fuzz_load.sh
```

#### 2. Run for Specific Duration

```bash
cd BACKEND
./run_fuzz_load.sh -max_total_time=3600  # 1 hour
```

**Note**: This test creates temporary files in `BACKEND/fuzz_temp_floors/` directory. These are automatically cleaned up during testing.

## Output Explanation

When the fuzzer runs, you will see output like this:

```text
INFO: Seed: 2688538608
#2      INITED cov: 10 ft: 10 corp: 1/1b ...
#21     NEW    cov: 14 ft: 14 ...
...
```

- **cov**: Code coverage (number of code blocks executed). Higher is better.
- **ft**: Features (paths/signals) covered.
- **corp**: Corpus size (number of saved interesting inputs).
- **NEW**: Indicates a new code path was discovered and the input was saved to `fuzz_corpus`.

## Project Files

### Test 1: Validation Logic
- **`BACKEND/run_fuzz.sh`**: Entry point script for validation logic testing.
- **`BACKEND/fuzz_roi_config.py`**: Fuzzing script that tests `validate_floor_config()` with in-memory data.
- **`BACKEND/fuzz_corpus/`**: Directory where interesting test cases are stored.

### Test 2: File I/O + Validation
- **`BACKEND/run_fuzz_load.sh`**: Entry point script for file I/O testing.
- **`BACKEND/fuzz_load_floor_config.py`**: Fuzzing script that tests `load_floor_config()` with file operations.
- **`BACKEND/fuzz_corpus_load/`**: Directory where interesting test cases are stored.
- **`BACKEND/fuzz_temp_floors/`**: Temporary directory for test files (auto-cleaned).

## Troubleshooting

- **Symbol not found errors**: If you see errors about missing symbols (e.g., `__sanitizer_...`), ensure you are running the test via `./run_fuzz.sh` and not directly with python, as the script sets up necessary library paths.
- **Environment not found**: If the script complains about missing python, run `conda create -n fuzz-env python=3.12` and reinstall dependencies as per the setup guide.

