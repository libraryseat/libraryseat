Floor ROI JSON Spec
===================

One file per floor, provided by you. Video resolution is fixed; `frame_size` is optional and only used for sanity checks.

Example (F4.json):
{
  "floor_id": "F4",
  "stream_path": "YOLOv11/input/per10s.mp4",
  "frame_size": [1920, 1080],
  "seats": [
    {
      "seat_id": "F4-16",
      "has_power": 1,
      "desk_roi": [[510,260],[620,260],[620,330],[510,330]]
    }
  ]
}

Fields
------
- floor_id: string like "F1"/"F2"/"F3"/"F4"
- stream_path: path to video/stream
- frame_size: [width, height] (optional; for validation only)
- seats: array of:
  - seat_id: "F4-16"
  - has_power: 0/1
  - desk_roi: polygon array of [x,y] points in pixel coordinates


