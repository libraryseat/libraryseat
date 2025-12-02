from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import List, Tuple, Dict, Any

import cv2
import numpy as np

# Optional YOLO overlay (guidance only)
def run_yolo_overlay(frame: np.ndarray):
	try:
		# Lazy import to avoid startup failures if torch is not ready
		from backend.services.yolo_service import YOLODetector
		det = YOLODetector()
		dets = det.detect_frame(frame)
		for d in dets:
			x1, y1, x2, y2 = map(int, (d.x1, d.y1, d.x2, d.y2))
			cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 255), 2)
			cv2.circle(frame, (int((x1 + x2) / 2), int((y1 + y2) / 2)), 3, (0, 0, 255), -1)
			cv2.putText(frame, d.cls_name, (x1, max(0, y1 - 5)), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
	except Exception:
		# YOLO overlay is optional; ignore errors
		pass


def annotate(video_path: str, show_yolo: bool, out_path: str | None, floor_id: str | None, stream_path: str | None):
	cap = cv2.VideoCapture(video_path)
	if not cap.isOpened():
		raise SystemExit(f"Failed to open video: {video_path}")
	ok, frame = cap.read()
	cap.release()
	if not ok or frame is None:
		raise SystemExit("Failed to read first frame")

	h, w = frame.shape[:2]
	base_img = frame.copy()
	if show_yolo:
		run_yolo_overlay(base_img)

	window = "ROI Annotator"
	cv2.namedWindow(window, cv2.WINDOW_NORMAL)
	cv2.resizeWindow(window, min(1280, w), min(720, h))

	points: List[Tuple[int, int]] = []
	seats: List[Dict[str, Any]] = []

	def redraw():
		canvas = base_img.copy()
		# draw existing seats
		for s in seats:
			pts = np.array(s["desk_roi"], dtype=np.int32)
			cv2.polylines(canvas, [pts], isClosed=True, color=(0, 200, 0), thickness=2)
			if "seat_id" in s:
				centroid = pts.mean(axis=0).astype(int)
				cv2.putText(canvas, s["seat_id"], tuple(centroid), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 200, 0), 2)
		# draw current polygon
		if len(points) > 0:
			for i, p in enumerate(points):
				cv2.circle(canvas, p, 3, (255, 0, 0), -1)
				if i > 0:
					cv2.line(canvas, points[i - 1], points[i], (255, 0, 0), 2)
		help1 = "LeftClick=add point, RightClick=undo, Enter=finish polygon, N=clear current, S=save JSON, Q=quit"
		cv2.putText(canvas, help1, (10, h - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (240, 240, 240), 1, cv2.LINE_AA)
		cv2.imshow(window, canvas)

	def on_mouse(event, x, y, flags, param):
		nonlocal points
		if event == cv2.EVENT_LBUTTONDOWN:
			points.append((x, y))
			redraw()
		elif event == cv2.EVENT_RBUTTONDOWN:
			if points:
				points.pop()
				redraw()

	cv2.setMouseCallback(window, on_mouse)
	redraw()

	while True:
		key = cv2.waitKey(50) & 0xFF
		if key == ord('q') or key == ord('Q'):
			break
		if key == ord('n') or key == ord('N'):
			points = []
			redraw()
		if key in (13, 10):  # Enter
			if len(points) < 3:
				print("Polygon needs at least 3 points")
				continue
			try:
				seat_id = input("seat_id (e.g. F1-01): ").strip()
				has_power_str = input("has_power (0/1): ").strip()
				has_power = 1 if has_power_str == "1" else 0
			except KeyboardInterrupt:
				print("\nCanceled.")
				continue
			seats.append({"seat_id": seat_id, "has_power": has_power, "desk_roi": [[int(x), int(y)] for (x, y) in points]})
			points = []
			redraw()
		if key == ord('s') or key == ord('S'):
			cfg: Dict[str, Any] = {
				"floor_id": floor_id or "F?",
				"stream_path": stream_path or os.fspath(Path(video_path)),
				"frame_size": [int(w), int(h)],
				"seats": seats,
			}
			text = json.dumps(cfg, ensure_ascii=False, indent=2)
			print("\n=== JSON BEGIN ===\n" + text + "\n=== JSON END ===\n")
			if out_path:
				out_file = Path(out_path)
				out_file.parent.mkdir(parents=True, exist_ok=True)
				out_file.write_text(text, encoding="utf-8")
				print(f"Wrote {out_file.as_posix()}")

	cv2.destroyAllWindows()


def main():
	parser = argparse.ArgumentParser(description="Annotate desk_roi polygons on first frame")
	parser.add_argument("--video", required=True, help="Path to video (e.g., library/yolov11/input/test/F1.mp4)")
	parser.add_argument("--floor-id", default=None, help="Floor id to embed into JSON (e.g., F1)")
	parser.add_argument("--stream-path", default=None, help="stream_path to embed into JSON; defaults to --video")
	parser.add_argument("--out", default=None, help="Output JSON path (e.g., config/floors/F1.json)")
	parser.add_argument("--yolo", action="store_true", help="Overlay YOLO detections on first frame for guidance")
	args = parser.parse_args()
	annotate(args.video, args.yolo, args.out, args.floor_id, args.stream_path)


if __name__ == "__main__":
	main()


