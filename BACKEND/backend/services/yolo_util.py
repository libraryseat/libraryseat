from __future__ import annotations

# Helper to provide a stable relative import surface for YOLO util functions.
# Prefer package-relative import; fallback to path-based import for robustness.

try:
	# When package context is intact
	from ...yolov11.utils import util as _util  # type: ignore
except Exception:
	import sys
	from pathlib import Path

	BASE_DIR = Path(__file__).resolve().parents[2]  # -> library/
	YOLO_DIR = BASE_DIR / "yolov11"
	UTILS_DIR = YOLO_DIR / "utils"
	if UTILS_DIR.as_posix() not in sys.path:
		sys.path.insert(0, UTILS_DIR.as_posix())
	import util as _util  # type: ignore

util = _util


