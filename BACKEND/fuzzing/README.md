# Fuzzing Tests Directory

This directory contains all fuzzing test related files for the library seat management system.

## Directory Structure

```
fuzzing/
├── README.md                          # This file
├── FUZZING.md                         # Fuzzing test usage guide
├── FUZZING_REPORT.md                  # English test report
│
├── fuzz_roi_config.py                 # Validation logic test script
├── fuzz_load_floor_config.py          # File I/O test script
├── generate_comprehensive_report.py    # Report generation script
│
├── run_fuzz.sh                        # Run validation logic test
├── run_fuzz_load.sh                   # Run file I/O test
│
├── comprehensive_fuzzing_report.html   # Comprehensive test report (HTML)
│
├── fuzz_corpus/                       # Validation test corpus
├── fuzz_corpus_load/                  # File I/O test corpus
└── fuzz_temp_floors/                  # Temporary files for file I/O tests
```

## Quick Start

### Test 1: Validation Logic Only
```bash
cd fuzzing
./run_fuzz.sh
```

### Test 2: File I/O + Validation
```bash
cd fuzzing
./run_fuzz_load.sh
```

### Generate Report
```bash
cd fuzzing
/opt/homebrew/Caskroom/miniconda/base/envs/fuzz-env/bin/python generate_comprehensive_report.py
```

## Files Description

- **Test Scripts**: Generate random test data and feed to validation functions
- **Run Scripts**: Convenience scripts that set up environment and run tests
- **Corpus Directories**: Store interesting test cases discovered by fuzzer
- **Report**: HTML report showing test results and analysis

For detailed usage, see `FUZZING.md`.

