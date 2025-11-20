Library Backend
================

FastAPI backend for Library Seat Management with YOLOv11 integration, ROI-based seat mapping, reports, admin anomaly handling, statistics, and daily/monthly rollovers.

Project structure
-----------------
- library/backend: FastAPI application, routes, services, database models, scheduler
- library/config
  - floors: per-floor ROI JSON files to be provided
  - report: uploaded report images directory
  - db.sqlite3: SQLite database (auto-created on first run)
- library/yolov11: YOLOv11 model code and weights
- library/outputs
  - YYYY-MM-DD/daily_empty.txt: daily export
  - monthly/YYYY-MM.txt: monthly export

Requirements
------------
- Python 3.10+
- PyTorch with CUDA if available (CPU supported but slower)

Install
-------
1. Install dependencies:
   pip install -r library/requirements.txt
2. Ensure YOLO weights exist:
   - library/yolov11/weights/v11_x.pt (provided)

Run
---
Start the server:
  uvicorn library.backend.main:app --reload

On startup:
- Creates SQLite tables if missing
- Mounts static report directory at /report
- Starts per-floor periodic refresh (default every 60s)
- Registers daily midnight rollover

Configuration
-------------
Environment variables:
- REFRESH_INTERVAL_SECONDS: per-floor refresh interval in seconds, default 60
- JWT_SECRET_KEY: secret for JWT signing, default dev-secret-change
- JWT_ALGORITHM: default HS256
- JWT_EXPIRE_MINUTES: default 120

Directories:
- library/config/floors: floor ROI JSON files, one per floor, for example F4.json
- library/config/report: reports image uploads (served under /report)
- library/outputs: daily and monthly exports

User management
---------------
The database is auto-created on first run. Use the CLI to manage users.

Create user:
  python -m library.backend.manage_users create --username admin --password 123456 --role admin

Reset password:
  python -m library.backend.manage_users passwd --username admin --password 654321

Change role:
  python -m library.backend.manage_users role --username alice --role student

List users:
  python -m library.backend.manage_users list

ROI JSON format
---------------
File location: library/config/floors/<FLOOR_ID>.json

Example:
{
  "floor_id": "F4",
  "stream_path": "library/yolov11/input/per10s.mp4",
  "frame_size": [1920, 1080],
  "seats": [
    {
      "seat_id": "F4-16",
      "has_power": 1,
      "desk_roi": [[510,260],[620,260],[620,330],[510,330]]
    }
  ]
}

Notes:
- frame_size is optional and used for validation only
- desk_roi is a polygon defined by at least three [x, y] points, in pixels for the original stream resolution
- The application validates ROI JSON on load and will raise informative errors if invalid

YOLO integration and detection logic
------------------------------------
- YOLOv11 model loaded once and reused across refreshes
- Sampling N frames per refresh (default 16)
- For each seat, consider detection box center points that fall inside the seat desk_roi
- Categories:
  - person: considered occupied
  - object categories: backpack, handbag, suitcase, book, laptop, cell phone, mouse, keyboard, bottle, cup, umbrella (treated as object)
- Presence threshold:
  - Ratio of frames with hit >= 0.3 marks presence for that category
- Seat state:
  - Occupied if person or object present, otherwise empty
- Malicious occupancy:
  - If only object present without person for at least 7200 seconds, mark seat is_malicious=1 (admin view shows yellow)
- Lock behavior:
  - If now < lock_until_ts, statistics are updated but visible state is not changed

Statistics and rollovers
------------------------
- Accumulation:
  - On each refresh, if previous state was empty, add delta seconds to daily_empty_seconds and total_empty_seconds
  - If state changes, increment change_count
- Daily rollover:
  - At 00:00 local time export daily_empty_seconds grouped by floor to library/outputs/YYYY-MM-DD/daily_empty.txt
  - File format:
    - First line: library total empty rate
    - Each floor header line includes floor empty rate
    - Each seat line: seat_id and time formatted as XXhXXminXXs
  - After export:
    - Reset daily_empty_seconds to 0
    - Clear is_reported, is_malicious, lock_until_ts, occupancy_start_ts
    - Set is_empty=True, last_state_is_empty=True, last_update_ts=now
- Monthly rollover:
  - On the first day of the month at 00:00 export previous month total_empty_seconds to library/outputs/monthly/YYYY-MM.txt
  - Header includes library monthly empty rate and per-floor rates
  - Reset total_empty_seconds to 0
- Offline compensation:
  - On startup and before each refresh, if current date or month differs from the earliest nonzero last_update_ts across seats:
    - Run previous date daily export and reset
    - If month changed, also run previous month export and reset

API reference
-------------
Authentication
- POST /auth/login
  - OAuth2 password login, returns JWT token and user info
- GET /auth/me
  - Get current user info, requires Bearer token

Health
- GET /health
  - Health check of the service

Seats and floors
- GET /seats
  - Query parameters: floor optional
  - List seats with colors and current states
- GET /seats/{seatId}
  - Get a single seat state and colors
- GET /floors
  - List floor summaries with empty counts and floor color
- POST /floors/{floor}/refresh
  - Trigger a one-time YOLO refresh for the floor and return updated seats
- GET /stats/seats/{seatId}
  - Seat statistics including daily_empty_seconds, total_empty_seconds, change_count, last_update_ts, last_state_is_empty, occupancy_start_ts, object_only_occupy_seconds, is_malicious

Reports and anomalies
- POST /reports
  - Multipart form with fields: seat_id, reporter_id, text optional, images[] optional
  - Saves images under config/report/{report_id} and sets seat is_reported=1

Admin endpoints
Note: All admin endpoints require Bearer token and admin role.
- GET /admin/anomalies
  - Query parameters: floor optional
  - List seats that are reported or marked malicious, include last_report_id if present
- GET /admin/reports/{report_id}
  - Get a report details including text and image paths
- POST /admin/reports/{report_id}/confirm
  - Toggle malicious flag for the report seat following the color pairing rule, update report status to confirmed or dismissed
- DELETE /admin/anomalies/{seat_id}
  - Clear anomalies for the seat, reset is_reported and is_malicious
- POST /admin/seats/{seat_id}/lock
  - Query parameters: minutes default 5
  - Lock the seat until now plus minutes

Static files
- /report
  - Serves files from library/config/report so images can be accessed by clients

Color rules
-----------
Seat color for students:
- Empty with power: #00A1FF
- Empty without power: #60D937
- Occupied: #929292

Admin overlay:
- If is_malicious=1: #FEAE03

Floor color:
- Empty ratio greater than 50 percent: #60D937
- Empty ratio between 0 and 50 percent: #FEAE03
- Empty ratio equals 0: #FF0000

Notes
-----
- Ensure floor ROI JSON matches the camera view and resolution
- Configure environment variables in production, especially JWT_SECRET_KEY
- Large models and OpenCV can be CPU intensive without GPU


Windows and Conda setup
-----------------------
Option A: Pip and Python already installed
  python -m venv .venv
  .venv\Scripts\activate
  pip install -r library/requirements.txt

Option B: Conda example
  conda create -n YOLO python=3.9 -y
  conda activate YOLO
  pip install -r library/requirements.txt
If you want GPU acceleration, install PyTorch following the official selector for your CUDA version, then install the remaining requirements.

Environment variables examples
------------------------------
PowerShell (current session):
  $env:REFRESH_INTERVAL_SECONDS="60"
  $env:JWT_SECRET_KEY="please-change-me"
  $env:JWT_ALGORITHM="HS256"
  $env:JWT_EXPIRE_MINUTES="120"

Linux or macOS:
  export REFRESH_INTERVAL_SECONDS=60
  export JWT_SECRET_KEY=please-change-me
  export JWT_ALGORITHM=HS256
  export JWT_EXPIRE_MINUTES=120

API usage examples
------------------
Login and token
  curl -X POST ^
    -H "Content-Type: application/x-www-form-urlencoded" ^
    -d "username=admin&password=123456" ^
    http://localhost:8000/auth/login
Use the returned access_token in header:
  -H "Authorization: Bearer YOUR_TOKEN"

Health
  curl http://localhost:8000/health

Seats and floors
  curl http://localhost:8000/seats
  curl "http://localhost:8000/seats?floor=F4"
  curl http://localhost:8000/seats/F4-16
  curl http://localhost:8000/floors

Manual refresh a floor
  curl -X POST http://localhost:8000/floors/F4/refresh

Seat statistics
  curl http://localhost:8000/stats/seats/F4-16

Submit a report with images
  curl -X POST http://localhost:8000/reports ^
    -F "seat_id=F4-16" ^
    -F "reporter_id=1" ^
    -F "text=占座" ^
    -F "images=@C:\path\to\image1.jpg" ^
    -F "images=@C:\path\to\image2.jpg"
Images are accessible under /report for example:
  http://localhost:8000/report/12/1699999999_0.jpg

Admin anomalies and actions
All admin endpoints require the Authorization header with a token for role admin.
List anomalies:
  curl -H "Authorization: Bearer YOUR_TOKEN" ^
    "http://localhost:8000/admin/anomalies?floor=F4"
Get a report:
  curl -H "Authorization: Bearer YOUR_TOKEN" ^
    http://localhost:8000/admin/reports/12
Confirm or dismiss by toggling:
  curl -X POST -H "Authorization: Bearer YOUR_TOKEN" ^
    http://localhost:8000/admin/reports/12/confirm
Clear a seat anomaly:
  curl -X DELETE -H "Authorization: Bearer YOUR_TOKEN" ^
    http://localhost:8000/admin/anomalies/F4-16
Lock a seat for 5 minutes:
  curl -X POST -H "Authorization: Bearer YOUR_TOKEN" ^
    "http://localhost:8000/admin/seats/F4-16/lock?minutes=5"

Scheduling, rollovers and offline handling summary
--------------------------------------------------
- A background scheduler refreshes each floor every REFRESH_INTERVAL_SECONDS seconds. Default is 60.
- At local 00:00 the service exports daily results and resets daily counters and flags according to the specification.
- On the first day of a new month at 00:00 the service exports the previous month total and resets the monthly total counter.
- On startup and before each refresh the service checks if a day or month boundary was crossed while the service was offline and runs the corresponding export and reset for the previous day or month.


