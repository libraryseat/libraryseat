import sys
import os
import json
import atheris
import tempfile
import shutil
from pathlib import Path

# Add the parent directory (BACKEND) to sys.path so we can import backend
script_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(script_dir)  # Go up one level to BACKEND
sys.path.append(parent_dir)

try:
    from backend.services.roi_loader import load_floor_config
    from backend.services.roi_loader import FLOORS_DIR
except ImportError as e:
    print(f"Error: Could not import backend.services.roi_loader: {e}")
    sys.exit(1)

# Create a temporary directory for fuzzing test files
FUZZ_TEMP_DIR = Path(__file__).parent / "fuzz_temp_floors"
FUZZ_TEMP_DIR.mkdir(exist_ok=True)

def TestOneInput(data):
    """
    Fuzzing entry point for load_floor_config.
    Tests file reading, JSON parsing, and validation logic together.
    """
    fdp = atheris.FuzzedDataProvider(data)
    
    try:
        # 1. Generate a random floor_id (filename)
        floor_id = fdp.ConsumeString(20).replace('/', '_').replace('\\', '_')  # Sanitize for filesystem
        if not floor_id:
            floor_id = "test_floor"
        
        # 2. Generate random JSON content
        def generate_seat():
            return {
                "seat_id": fdp.ConsumeString(10),
                "has_power": fdp.ConsumeBool(),
                "desk_roi": [
                    [fdp.ConsumeFloatInRange(0.0, 1000.0), fdp.ConsumeFloatInRange(0.0, 1000.0)]
                    for _ in range(fdp.ConsumeIntInRange(0, 5))
                ]
            }

        config_data = {
            "floor_id": floor_id,
            "stream_path": fdp.ConsumeString(50),
            "frame_size": [fdp.ConsumeIntInRange(0, 2000), fdp.ConsumeIntInRange(0, 2000)],
            "seats": [generate_seat() for _ in range(fdp.ConsumeIntInRange(0, 10))]
        }
        
        # 3. Write to temporary file
        temp_file = FUZZ_TEMP_DIR / f"{floor_id}.json"
        
        # Sometimes generate invalid JSON to test error handling
        if fdp.ConsumeBool() and fdp.ConsumeProbability() < 0.1:  # 10% chance of invalid JSON
            # Write invalid JSON
            with temp_file.open('w', encoding='utf-8') as f:
                f.write(fdp.ConsumeString(100))  # Random string, likely invalid JSON
        else:
            # Write valid JSON structure
            with temp_file.open('w', encoding='utf-8') as f:
                json.dump(config_data, f)
        
        # 4. Temporarily override FLOORS_DIR to point to our temp directory
        # We need to monkey-patch the module
        import backend.services.roi_loader as roi_module
        original_floors_dir = roi_module.FLOORS_DIR
        
        # Patch the module-level FLOORS_DIR
        roi_module.FLOORS_DIR = Path(FUZZ_TEMP_DIR)
        
        try:
            # 5. Call load_floor_config (this will read file, parse JSON, and validate)
            result = load_floor_config(floor_id)
            
            # If we get here, the file was successfully loaded and validated
            # This is expected for valid configurations
            
        except (ValueError, FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError, KeyError):
            # Expected errors: validation failure, file not found, invalid JSON, encoding issues
            pass
        except Exception as e:
            # Unexpected errors might indicate bugs
            raise e
        finally:
            # Restore original FLOORS_DIR
            roi_module.FLOORS_DIR = original_floors_dir
            
            # Clean up temp file
            if temp_file.exists():
                try:
                    temp_file.unlink()
                except:
                    pass
        
    except (ValueError, json.JSONDecodeError, AttributeError, TypeError, IndexError, OSError, UnicodeEncodeError):
        # Catch expected errors during file operations
        return
    except Exception as e:
        # Any other exception is a potential bug/crash
        raise e

def main():
    print("Initializing Atheris for load_floor_config fuzzing...")
    print(f"Using temporary directory: {FUZZ_TEMP_DIR}")
    
    # Ensure temp directory exists and is clean
    if FUZZ_TEMP_DIR.exists():
        shutil.rmtree(FUZZ_TEMP_DIR)
    FUZZ_TEMP_DIR.mkdir(exist_ok=True)
    
    atheris.instrument_all()
    atheris.Setup(sys.argv, TestOneInput)
    print("Starting fuzzing...")
    atheris.Fuzz()

if __name__ == "__main__":
    main()

