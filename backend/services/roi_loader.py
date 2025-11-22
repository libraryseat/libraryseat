from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List


BASE_DIR = Path(__file__).resolve().parents[2]
FLOORS_DIR = BASE_DIR / "config" / "floors"


def _is_number(x: Any) -> bool:
	return isinstance(x, (int, float)) and not isinstance(x, bool)


def _polygon_area(poly: List[List[float]]) -> float:
	area = 0.0
	n = len(poly)
	for i in range(n):
		x1, y1 = poly[i]
		x2, y2 = poly[(i + 1) % n]
		area += x1 * y2 - x2 * y1
	return abs(area) * 0.5


def validate_floor_config(data: Dict[str, Any]) -> None:
	if not isinstance(data, dict):
		raise ValueError("config must be an object")
	if "floor_id" not in data or not isinstance(data["floor_id"], str) or not data["floor_id"]:
		raise ValueError("floor_id must be a non-empty string")
	if "stream_path" not in data or not isinstance(data["stream_path"], str) or not data["stream_path"]:
		raise ValueError("stream_path must be a non-empty string")

	if "frame_size" in data:
		fs = data["frame_size"]
		if not isinstance(fs, list) or len(fs) != 2 or not all(isinstance(v, int) and v > 0 for v in fs):
			raise ValueError("frame_size must be [width, height] with positive integers")
		width, height = fs
	else:
		width = height = None

	seats = data.get("seats")
	if not isinstance(seats, list) or len(seats) == 0:
		raise ValueError("seats must be a non-empty array")

	for i, s in enumerate(seats):
		if not isinstance(s, dict):
			raise ValueError(f"seats[{i}] must be an object")
		if "seat_id" not in s or not isinstance(s["seat_id"], str) or not s["seat_id"]:
			raise ValueError(f"seats[{i}].seat_id must be a non-empty string")
		if "has_power" not in s or not isinstance(s["has_power"], (bool, int)):
			raise ValueError(f"seats[{i}].has_power must be boolean or 0/1")
		if "desk_roi" not in s or not isinstance(s["desk_roi"], list) or len(s["desk_roi"]) < 3:
			raise ValueError(f"seats[{i}].desk_roi must be an array of >=3 points")
		for j, pt in enumerate(s["desk_roi"]):
			if not isinstance(pt, list) or len(pt) != 2 or not all(_is_number(v) for v in pt):
				raise ValueError(f"seats[{i}].desk_roi[{j}] must be [x, y] numbers")
			if width is not None and (pt[0] < 0 or pt[0] > width):
				raise ValueError(f"seats[{i}].desk_roi[{j}].x out of bounds 0..{width}")
			if height is not None and (pt[1] < 0 or pt[1] > height):
				raise ValueError(f"seats[{i}].desk_roi[{j}].y out of bounds 0..{height}")
		if _polygon_area(s["desk_roi"]) <= 0.0:
			raise ValueError(f"seats[{i}].desk_roi polygon area must be > 0")


def load_floor_config(floor_id: str) -> Dict[str, Any]:
	"""
	Load and validate floor ROI config JSON from config/floors/{floor_id}.json
	"""
	path = FLOORS_DIR / f"{floor_id}.json"
	if not path.exists():
		raise FileNotFoundError(f"Floor config not found: {path.as_posix()}")
	with path.open("r", encoding="utf-8") as f:
		data = json.load(f)
	if "floor_id" not in data:
		data["floor_id"] = floor_id
	validate_floor_config(data)
	return data


def list_floor_ids() -> list[str]:
	"""
	List floor ids by scanning config/floors/*.json
	"""
	if not FLOORS_DIR.exists():
		return []
	return sorted([p.stem for p in FLOORS_DIR.glob("*.json")])


