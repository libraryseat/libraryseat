from __future__ import annotations

import time
from pathlib import Path
from typing import List, Optional

from fastapi import APIRouter, Depends, Form, File, UploadFile, HTTPException, status
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Report, Seat
from ..schemas import ReportOut


router = APIRouter(prefix="", tags=["reports"])


def _save_report_images(report_id: int, files: Optional[List[UploadFile]]) -> List[str]:
	if not files:
		return []
	base_dir = Path(__file__).resolve().parents[1]
	report_root = base_dir / "config" / "report" / str(report_id)
	report_root.mkdir(parents=True, exist_ok=True)
	now = int(time.time())
	saved: List[str] = []
	for idx, f in enumerate(files):
		if not f.content_type or not f.content_type.startswith("image/"):
			raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Unsupported file type: {f.content_type}")
		ext = Path(f.filename or "").suffix or ".jpg"
		filename = f"{now}_{idx}{ext}"
		target_path = report_root / filename
		with target_path.open("wb") as out:
			out.write(f.file.read())
		# store as path relative to config/report for static serving via /report
		saved.append(f"report/{report_id}/{filename}")
	return saved


@router.post("/reports", response_model=ReportOut)
def create_report(
	seat_id: str = Form(...),
	reporter_id: str = Form(...),  # 改为 str，然后转换为 int
	text: Optional[str] = Form(default=None),
	images: Optional[List[UploadFile]] = File(default=None),
	db: Session = Depends(get_db),
) -> ReportOut:
	try:
		reporter_id_int = int(reporter_id)
	except (ValueError, TypeError):
		raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid reporter_id: must be an integer")
	seat = db.query(Seat).filter(Seat.seat_id == seat_id).first()
	if not seat:
		raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="seat_id not found")

	now = int(time.time())
	report = Report(
		seat_id=seat_id,
		reporter_id=reporter_id_int,  # 使用转换后的整数
		text=text,
		images=[],
		status="pending",
		created_at=now,
	)
	db.add(report)
	db.flush()  # to get report.id

	try:
		image_paths = _save_report_images(report.id, images)
	except HTTPException:
		db.rollback()
		raise

	report.images = image_paths
	seat.is_reported = True

	db.add(report)
	db.add(seat)
	db.commit()
	db.refresh(report)

	return ReportOut.model_validate(report)


