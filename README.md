# Library Seat Management System

A full-stack application for managing library seats with real-time detection, reporting, and admin management features.

## Project Structure

```
libraryseat/
├── README.md                 # Project documentation
├── start_frontend.sh         # Frontend startup script
├── start_backend.sh          # Backend startup script
├── FRONTEND/                 # Flutter frontend application
│   ├── lib/                  # Flutter source code
│   │   ├── config/           # Configuration (API config)
│   │   ├── models/           # Data models
│   │   ├── pages/            # UI pages
│   │   ├── services/         # API services
│   │   └── utils/            # Utilities (translations)
│   ├── android/              # Android native code
│   ├── ios/                  # iOS native code
│   └── pubspec.yaml          # Flutter dependencies
└── BACKEND/                  # FastAPI backend service
    ├── backend/              # Backend source code
    │   ├── routes/           # API routes
    │   ├── services/         # Business logic services
    │   ├── models.py         # Database models
    │   ├── schemas.py        # Pydantic schemas
    │   └── main.py           # Application entry point
    ├── config/               # Configuration files
    │   ├── floors/           # Floor ROI configuration
    │   ├── report/           # Report image storage
    │   └── roi.schema.json   # ROI schema definition
    ├── yolov11/              # YOLOv11 model code and weights
    ├── tools/                # Utility scripts
    │   ├── annotate_roi.py   # ROI annotation tool
    │   └── export.py         # Data export tool
    └── outputs/              # Exported data
        ├── YYYY-MM-DD/       # Daily exports
        └── monthly/          # Monthly exports
```

## Quick Start

### Prerequisites

1. Python 3.9+ and Conda
2. Flutter SDK
3. YOLOv11 weights file (downloaded to `BACKEND/yolov11/weights/yolo11x.pt`)

### Using Startup Scripts (Recommended)

We provide convenient startup scripts for both backend and frontend.

**Backend:**

```bash
./start_backend.sh
```

This script will automatically:
- Check for Conda environment (creates `YOLO` environment if missing)
- Install dependencies
- Check for port conflicts
- Start the FastAPI server

**Frontend:**

```bash
./start_frontend.sh
```

This script will:
- Check for Flutter installation
- Install dependencies (including `image_picker` for photo uploads)
- Start the Flutter application

### Manual Setup

#### Backend

```bash
# 1. Navigate to backend directory
cd BACKEND

# 2. Create and activate Conda environment
conda create -n YOLO python=3.9 -y
conda activate YOLO

# 3. Install dependencies
pip install -r requirements.txt

# 4. Download YOLOv11 weights
# Visit: https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11x.pt
# Save to: yolov11/weights/yolo11x.pt

# 5. Create test users
python -m backend.manage_users create --username admin --password 123456 --role admin
python -m backend.manage_users create --username user --password 123456 --role student

# 6.start server
python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000

restart server
python -m uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
```

Note: Use `python -m uvicorn` instead of `uvicorn` directly. Run from the `BACKEND` directory.

Server starts at `http://localhost:8000`. API documentation available at `http://localhost:8000/docs`.

#### Frontend

```bash
# 1. Navigate to frontend directory
cd FRONTEND

# 2. Install dependencies
flutter pub get

# 3. Run application
flutter run
```

**Important for iOS**: If you are running on a physical iOS device, ensure `FRONTEND/ios/Runner/Info.plist` contains the necessary `NSPhotoLibraryUsageDescription` and `NSCameraUsageDescription` keys (already configured in the repository).

Note: Ensure backend server is running before starting the frontend.

## Features

### User Features
- User login and registration
- Floor map visualization
- Real-time seat status viewing
- **Seat reporting with Photo Upload** (Camera & Gallery support)
- Multi-language support (English / Simplified Chinese / Traditional Chinese)
- Responsive layout (mobile and desktop)

### Admin Features
- Anomaly seat list management
- Report detail viewing (text, images)
- Confirm/clear anomaly seats
- Seat locking (5 minutes)
- Floor refresh functionality
- Suspicious seat marking (admin only)

### Backend Features
- YOLOv11 real-time seat detection
- **System Auto-Alarm**: Automatically flags seats as "System Reported" if malicious status persists > 30 seconds.
- Automatic scheduled refresh (default 8 seconds)
- Daily/monthly data export
- JWT authentication
- RESTful API
- CORS support

## Color Rules

### Seat Colors (Student View)
- Green (#60D937): Available seat (no power)
- Blue (#00A1FF): Available seat (with power)
- Gray (#929292): Occupied
- Yellow (#FEAE03): Suspicious (admin only, students see previous status)

### Floor Colors
- Green: Empty seat rate > 50%
- Yellow: Empty seat rate 0-50%
- Red: Empty seat rate = 0%

## API Endpoints

### Authentication
- `POST /auth/login` - User login
- `POST /auth/register` - User registration
- `GET /auth/me` - Get current user info

### Seats and Floors
- `GET /seats` - Get seat list (optional floor filter)
- `GET /seats/{seatId}` - Get single seat info
- `GET /floors` - Get floor summary
- `POST /floors/{floor}/refresh` - Manual floor refresh

### Reports
- `POST /reports` - Submit seat report (supports text and images)

### Admin (requires admin role)
- `GET /admin/anomalies` - Get anomaly seat list
- `GET /admin/reports/{report_id}` - Get report details
- `POST /admin/reports/{report_id}/confirm` - Confirm/cancel anomaly
- `DELETE /admin/anomalies/{seat_id}` - Clear anomaly
- `POST /admin/seats/{seat_id}/lock` - Lock seat

### Others
- `GET /health` - Health check
- `GET /health/scheduler` - Scheduler status
- `GET /stats/seats/{seatId}` - Seat statistics

Full API documentation: `http://localhost:8000/docs` (Swagger UI)

## Demo Tips (MVP)

### System Auto-Alarm Demo
To demonstrate the system automatically flagging a seat as suspicious (Yellow -> Red Alarm):
1. Go to `BACKEND/backend/services/yolo_service.py` line ~333.
2. Change the threshold `7200` (2 hours) to a small value like `10` (seconds).
3. Place an object on a seat.
4. Wait ~10 seconds -> Seat turns Yellow (Malicious).
5. Wait another ~30 seconds -> System Auto-Alarm triggers (appears in Admin Anomaly List).

### Frontend Mock Data
- Floors F3 and F4 use mock data for demonstration purposes.
- F3 is configured to be fully occupied (Grey).
- F4 shows a variety of statuses including suspicious seats.

## Tools

### ROI Annotation Tool
Annotate seat ROI (Region of Interest):

```bash
cd BACKEND
conda activate YOLO
python -m tools.annotate_roi --video {video_path} --floor-id F1 --out config/floors/F1.json
```

**Controls**:
- Left click: Add point
- Right click: Remove last point
- Enter: Finish polygon and enter seat info
- N: Clear current polygon
- S: Save as JSON
- Q: Quit

### Data Export Tool
Manually generate daily/monthly statistics:

```bash
cd BACKEND
conda activate YOLO
python tools/export.py
```

## Configuration

### Environment Variables
- `REFRESH_INTERVAL_SECONDS`: Floor refresh interval in seconds (default: 8)
- `CORS_ORIGINS`: Allowed CORS origins, comma-separated (default: "*" for development)
- `JWT_SECRET_KEY`: JWT signing key (default: `dev-secret-change`)
- `JWT_ALGORITHM`: JWT algorithm (default: `HS256`)
- `JWT_EXPIRE_MINUTES`: Token expiration in minutes (default: 120)

### Directory Structure
- `config/floors/`: Floor ROI JSON configuration files
- `config/report/`: Report image storage directory
- `outputs/`: Data export directory
- `yolov11/weights/`: YOLO model weight files

## Frontend Configuration

Frontend API configuration is located at `FRONTEND/lib/config/api_config.dart`:

```dart
class ApiConfig {
  // Local development
  static const String baseUrl = 'http://localhost:8000';
  
  // Device testing (use Mac's local network IP)
  // static const String baseUrl = 'http://192.168.1.109:8000';
}
```

## User Management

Database is automatically created on first run. Use CLI to manage users:

```bash
cd BACKEND
conda activate YOLO

# Create user
python -m backend.manage_users create --username admin --password 123456 --role admin

# Reset password
python -m backend.manage_users passwd --username admin --password 654321

# Change role
python -m backend.manage_users role --username user --role student

# List all users
python -m backend.manage_users list
```

## Scheduled Tasks

- Floor refresh: Automatically refreshes every 8 seconds (configurable via environment variable)
- **Alarm Check**: Checks every 5 seconds for seats that have been suspicious for >30 seconds.
- Daily export: Automatically exports data and resets counters at 00:00 daily
- Monthly export: Exports previous month data and resets monthly counters on the first day of each month at 00:00
- Offline handling: Checks for missed days/months on startup and performs corresponding exports

## Documentation

For detailed documentation, please refer to the README files in each subdirectory:
- `BACKEND/README.md` - Backend documentation
- `FRONTEND/README.md` - Frontend documentation

## Test Accounts

Default test accounts:
- Admin: `admin` / `123456`
- User: `user` / `123456`

## Tech Stack

### Backend
- FastAPI - Web framework
- SQLAlchemy - ORM
- YOLOv11 - Object detection
- SQLite - Database
- APScheduler - Scheduled tasks

### Frontend
- Flutter - Cross-platform framework
- Dio - HTTP client
- SharedPreferences - Local storage
- **image_picker** - Photo capture and selection

## API Usage Examples

### Login
```bash
curl -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin&password=123456" \
  http://localhost:8000/auth/login
```

### Get Seat List
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:8000/seats?floor=F1
```

### Submit Report
```bash
curl -X POST \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "seat_id=F1-01" \
  -F "reporter_id=1" \
  -F "text=Seat Occupied" \
  -F "images=@/path/to/image.jpg" \
  http://localhost:8000/reports
```

## License

This project is a team project. All rights reserved by the libraryseat organization.

---

**Note**: Before first run, ensure:
1. Python 3.9+ and Conda are installed
2. YOLOv11 weights file is downloaded
3. At least one admin account is created
4. Floor ROI files are configured (if needed)
