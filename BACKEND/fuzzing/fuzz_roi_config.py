import sys
import os
import json
import atheris

# Add the parent directory (BACKEND) to sys.path so we can import backend
script_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(script_dir)  # Go up one level to BACKEND
sys.path.append(parent_dir)

try:
    from backend.services.roi_loader import validate_floor_config
except ImportError as e:
    print(f"Error: Could not import backend.services.roi_loader: {e}")
    sys.exit(1)

def TestOneInput(data):
    """
    Fuzzing entry point using FuzzedDataProvider to generate structured data.
    """
    fdp = atheris.FuzzedDataProvider(data)
    
    try:
        # Construct a dictionary that mimics the expected structure
        # This allows us to reach deeper into the validation logic
        
        # Helper to generate random seat objects
        def generate_seat():
            return {
                "seat_id": fdp.ConsumeString(10),
                "has_power": fdp.ConsumeBool(),
                # Generate a polygon of 3-5 points
                "desk_roi": [
                    [fdp.ConsumeFloatInRange(0.0, 1000.0), fdp.ConsumeFloatInRange(0.0, 1000.0)]
                    for _ in range(fdp.ConsumeIntInRange(0, 5))
                ]
            }

        # Main config object
        config = {
            "floor_id": fdp.ConsumeString(10),
            "stream_path": fdp.ConsumeString(20),
            "frame_size": [fdp.ConsumeIntInRange(0, 2000), fdp.ConsumeIntInRange(0, 2000)],
            # Generate 0-10 seats
            "seats": [generate_seat() for _ in range(fdp.ConsumeIntInRange(0, 10))]
        }
        
        # Also consume some remaining bytes to randomly corrupt keys or values 
        # to test unexpected structures (optional, but good for robustness)
        if fdp.ConsumeBool():
             config["random_field"] = fdp.ConsumeString(5)

        # Validate logic
        validate_floor_config(config)
        
    except (ValueError, json.JSONDecodeError, AttributeError, TypeError, IndexError):
        # Catch expected validation errors
        return
    except Exception as e:
        # Any other exception is a potential bug/crash
        raise e

def main():
    print("Initializing Atheris...")
    atheris.instrument_all()
    atheris.Setup(sys.argv, TestOneInput)
    print("Starting fuzzing...")
    atheris.Fuzz()

if __name__ == "__main__":
    main()
