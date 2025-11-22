### Library Backend
================

FastAPI backend for Library Seat Management with YOLOv11 integration, ROI-based seat mapping, reports, admin anomaly handling, statistics, and daily/monthly rollovers.

### Project structure
-----------------
- backend: FastAPI application, routes, services, database models, scheduler
- config
  - floors: per-floor ROI JSON files to be provided
  - report: uploaded report images directory
  - db.sqlite3: SQLite database (auto-created on first run)
- yolov11: YOLOv11 model code and weights
- outputs
  - YYYY-MM-DD/daily_empty.txt: daily export
  - monthly/YYYY-MM.txt: monthly export

### Install
-------
1. Install dependencies:
```
conda create -n YOLO python=3.9 -y
conda activate YOLO
pip install -r requirements.txt
```
2. Ensure YOLO weights exist:
   - yolov11/weights/yolo11x.pt (https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11x.pt)

### Run
---

Start the server:
```
python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```
restart the server:
```
uvicorn backend.main:app --reload
```

On startup:
- Creates SQLite tables if missing
- Mounts static report directory at /report
- Starts per-floor periodic refresh (default every 60s)
- Registers daily midnight rollover

### Tools
---
In tools folder
annatate_roi.py is used to mark the desk_roi
  - Operation keys:
    - Left mouse button: Add a point
    - Right mouse button: Remove the last added point
    - Enter: End the current polygon and input seat_id and has_power in the console
    - N: Clear the current polygon and start marking again
    - S: Print and save as JSON
    - Q: Exit
```
python -m tools.annotate_roi --video {video_path} --floor-id F1 --out config/floors/F1.json
```

export.py is used to manually generate daily/monthly seat statistics files and save them in the "outputs" folder.
```
python tools/export.py 
```
---

### Color rules
-----------
Seat color for students:
- Empty with power (blue): #00A1FF
- Empty without power (green): #60D937
- Occupied: #929292

Admin overlay:
- If is_malicious=1(yellow): #FEAE03

Floor color:
- Empty ratio greater than 50 percent(green): #60D937
- Empty ratio between 0 and 50 percent(yellow): #FEAE03
- Empty ratio equals 0(red): #FF0000

### Configuration
-------------
Environment variables:
- REFRESH_INTERVAL_SECONDS: per-floor refresh interval in seconds, default 60
- JWT_SECRET_KEY: secret for JWT signing, default dev-secret-change
- JWT_ALGORITHM: default HS256
- JWT_EXPIRE_MINUTES: default 120

Directories:
- config/floors: floor ROI JSON files, one per floor, for example F4.json
- config/report: reports image uploads (served under /report)
- outputs: daily and monthly exports


### API reference
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
  - Serves files from config/report so images can be accessed by clients

### API usage examples
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

### Scheduling, rollovers and offline handling summary
--------------------------------------------------
- A background scheduler refreshes each floor every REFRESH_INTERVAL_SECONDS seconds. Default is 60.
- At local 00:00 the service exports daily results and resets daily counters and flags according to the specification.
- On the first day of a new month at 00:00 the service exports the previous month total and resets the monthly total counter.
- On startup and before each refresh the service checks if a day or month boundary was crossed while the service was offline and runs the corresponding export and reset for the previous day or month.


### Test:User management
---------------
The database is auto-created on first run. Use the CLI to manage users.
```
Create user:
python -m backend.manage_users create --username admin --password 123456 --role admin

Reset password:
python -m backend.manage_users passwd --username admin --password 654321

Change role:
python -m backend.manage_users role --username alice --role student

List users:
python -m backend.manage_users list
```

