import sys
from pathlib import Path

# Ensure project root is on sys.path so `import backend` works even if CWD is tools/
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
	sys.path.insert(0, str(PROJECT_ROOT))

from backend.db import SessionLocal
from backend.services.rollover import export_daily_and_reset, export_monthly_and_reset_total
from datetime import datetime, timedelta
import time

db = SessionLocal()
now_ts = int(time.time())

yesterday = datetime.now() - timedelta(days=1)
export_daily_and_reset(db, yesterday, now_ts)

export_monthly_and_reset_total(db, datetime.now()) 

db.close()