from __future__ import annotations

import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple, Any

import cv2
import numpy as np
import torch
from sqlalchemy.orm import Session

from ..models import Seat
from .rollover import perform_rollovers_if_needed

# Setup YOLOv11 import path
BASE_DIR = Path(__file__).resolve().parents[1]
YOLO_DIR = BASE_DIR / "yolov11"
if YOLO_DIR.as_posix() not in sys.path:
	sys.path.insert(0, YOLO_DIR.as_posix())

from utils import util  # type: ignore


OBJECT_NAMES_DEFAULT = {
	"backpack", "handbag", "suitcase", "book", "laptop", "cell phone",
	"mouse", "keyboard", "bottle", "cup", "umbrella"
}


@dataclass
class Detection:
	x1: float
	y1: float
	x2: float
	y2: float
	score: float
	cls_name: str

	@property
	def center(self) -> Tuple[float, float]:
		return (self.x1 + self.x2) / 2.0, (self.y1 + self.y2) / 2.0


class YOLODetector:
	def __init__(self) -> None:
		self.device = "cuda:0" if torch.cuda.is_available() else "cpu"
		weights_path = YOLO_DIR / "weights" / "v11_x.pt"
		ckpt = torch.load(weights_path.as_posix(), map_location=self.device)
		self.model = ckpt["model"].float().to(self.device)
		if self.device.startswith("cuda"):
			self.model.half()
		self.model.eval()
		# Load names from args.yaml
		import yaml
		with (YOLO_DIR / "utils" / "args.yaml").open("r", encoding="utf-8") as f:
			params = yaml.safe_load(f)
		self.names = params.get("names", {})
		self.person_name = "person"
		self.object_names = OBJECT_NAMES_DEFAULT

	@torch.no_grad()
	def detect_frame(self, frame: np.ndarray, conf_th: float = 0.15, iou_th: float = 0.2) -> List[Detection]:
		shape = frame.shape[:2]  # (h, w)
		image = frame.copy()

		# Resize short edge to <= inp_size (letterbox)
		inp_size = 640
		r = inp_size / max(shape[0], shape[1])
		if r != 1:
			resample = cv2.INTER_LINEAR if r > 1 else cv2.INTER_AREA
			image = cv2.resize(image, dsize=(int(shape[1] * r), int(shape[0] * r)), interpolation=resample)
		height, width = image.shape[:2]

		# Scale ratio (new / old)
		r = min(1.0, inp_size / height, inp_size / width)

		# Compute padding
		pad = int(round(width * r)), int(round(height * r))
		w = (inp_size - pad[0]) / 2
		h = (inp_size - pad[1]) / 2

		if (width, height) != pad:  # resize
			image = cv2.resize(image, pad, interpolation=cv2.INTER_LINEAR)
		top, bottom = int(round(h - 0.1)), int(round(h + 0.1))
		left, right = int(round(w - 0.1)), int(round(w + 0.1))
		image = cv2.copyMakeBorder(image, top, bottom, left, right, cv2.BORDER_CONSTANT)

		# To tensor
		x = image.transpose((2, 0, 1))[::-1]
		x = np.ascontiguousarray(x)
		x = torch.from_numpy(x).unsqueeze(0).to(self.device)
		if self.device.startswith("cuda"):
			x = x.half()
		else:
			x = x.float()
		x = x / 255

		# Inference + NMS
		outputs = self.model(x)
		outputs = util.non_max_suppression(outputs, conf_th, iou_th)[0]

		dets: List[Detection] = []
		if outputs is None or len(outputs) == 0:
			return dets

		# Undo padding and scaling to original shape
		outputs[:, [0, 2]] -= w
		outputs[:, [1, 3]] -= h
		outputs[:, :4] /= min(height / shape[0], width / shape[1])
		outputs[:, 0].clamp_(0, shape[1])
		outputs[:, 1].clamp_(0, shape[0])
		outputs[:, 2].clamp_(0, shape[1])
		outputs[:, 3].clamp_(0, shape[0])

		for box in outputs:
			x1, y1, x2, y2, score, index = box.tolist()
			idx = int(index)
			cls_name = self.names.get(idx, str(idx))
			dets.append(Detection(x1, y1, x2, y2, float(score), cls_name))
		return dets


_detector: YOLODetector | None = None


def get_detector() -> YOLODetector:
	global _detector
	if _detector is None:
		_detector = YOLODetector()
	return _detector


def point_in_polygon(pt: Tuple[float, float], poly: List[List[float]]) -> bool:
	"""
	Ray casting algorithm for point-in-polygon
	"""
	x, y = pt
	inside = False
	n = len(poly)
	for i in range(n):
		x1, y1 = poly[i]
		x2, y2 = poly[(i + 1) % n]
		intersect = ((y1 > y) != (y2 > y)) and (x < (x2 - x1) * (y - y1) / (y2 - y1 + 1e-9) + x1)
		if intersect:
			inside = not inside
	return inside


def refresh_floor(db: Session, floor_cfg: Dict[str, Any], sample_frames: int = 16) -> List[Seat]:
	"""
	Run YOLO on a short clip from stream_path, update DB seats for this floor,
	and return updated Seat rows.
	"""
	# Offline rollover handling
	now_ts = int(time.time())
	try:
		perform_rollovers_if_needed(db, now_ts)
	except Exception:
		# best-effort; don't block detection
		pass
	floor_id = floor_cfg["floor_id"]
	stream_path = floor_cfg["stream_path"]
	seats_cfg = floor_cfg["seats"]

	# Ensure all seats exist in DB
	existing = {s.seat_id: s for s in db.query(Seat).filter(Seat.floor_id == floor_id).all()}
	for s in seats_cfg:
		if s["seat_id"] not in existing:
			db.add(Seat(
				seat_id=s["seat_id"],
				floor_id=floor_id,
				has_power=bool(s.get("has_power", 0)),
				is_empty=True,
				is_reported=False,
				is_malicious=False,
				lock_until_ts=0,
				last_update_ts=0,
				last_state_is_empty=True,
				total_empty_seconds=0,
				change_count=0,
				occupancy_start_ts=0,
			))
	db.commit()
	existing = {s.seat_id: s for s in db.query(Seat).filter(Seat.floor_id == floor_id).all()}

	# Initialize counters
	counters: Dict[str, Dict[str, int]] = {s["seat_id"]: {"person": 0, "object": 0, "frames": 0} for s in seats_cfg}

	cap = cv2.VideoCapture(stream_path)
	if not cap.isOpened():
		# If stream can't open, do nothing
		return list(existing.values())

	detector = get_detector()

	read_frames = 0
	while read_frames < sample_frames:
		ret, frame = cap.read()
		if not ret:
			break
		read_frames += 1
		dets = detector.detect_frame(frame)

		# For quicker mapping, build per-category points list
		person_pts = [d.center for d in dets if d.cls_name == detector.person_name]
		object_pts = [d.center for d in dets if d.cls_name in detector.object_names]

		for s in seats_cfg:
			seat_id = s["seat_id"]
			roi = s["desk_roi"]
			hit_person = any(point_in_polygon(pt, roi) for pt in person_pts)
			hit_object = any(point_in_polygon(pt, roi) for pt in object_pts)
			if hit_person:
				counters[seat_id]["person"] += 1
			if hit_object:
				counters[seat_id]["object"] += 1
			counters[seat_id]["frames"] += 1

	cap.release()

	# Apply thresholds
	now = now_ts
	for s in seats_cfg:
		seat = existing[s["seat_id"]]
		stats = counters[seat.seat_id]
		frames = max(1, stats["frames"])
		person_ratio = stats["person"] / frames
		object_ratio = stats["object"] / frames
		person_present = person_ratio >= 0.3
		object_present = object_ratio >= 0.3
		new_observed_is_empty = not (person_present or object_present)

		# Update statistics regardless of lock
		if seat.last_update_ts > 0:
			delta = now - seat.last_update_ts
			# accumulate based on LAST state being empty
			if seat.last_state_is_empty and delta > 0:
				seat.daily_empty_seconds += delta
				seat.total_empty_seconds += delta
			if seat.last_state_is_empty != new_observed_is_empty:
				seat.change_count += 1
		seat.last_state_is_empty = new_observed_is_empty
		seat.last_update_ts = now

		# Update occupancy timer for malicious detection (object only)
		if object_present and not person_present:
			if seat.occupancy_start_ts == 0:
				seat.occupancy_start_ts = now
		else:
			seat.occupancy_start_ts = 0

		# Apply visual state only if not locked
		if now >= seat.lock_until_ts:
			seat.is_empty = new_observed_is_empty
			# Malicious after 2h (7200s)
			if seat.occupancy_start_ts and (now - seat.occupancy_start_ts) >= 7200:
				seat.is_malicious = True

		db.add(seat)

	db.commit()
	return list(existing.values())


