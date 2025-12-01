from __future__ import annotations

from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Seat, Report
from ..schemas import AnomalyOut, ReportOut, SeatOut
from ..services.color import compute_seat_color, compute_admin_color
import time
from ..auth import require_admin


router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin)])


@router.get("/anomalies", response_model=List[AnomalyOut])
def list_anomalies(
	floor: Optional[str] = Query(default=None),
	db: Session = Depends(get_db),
) -> List[AnomalyOut]:
	q = db.query(Seat).filter((Seat.is_reported == True) | (Seat.is_malicious == True))
	if floor:
		q = q.filter(Seat.floor_id == floor)
	seats = q.all()
	out: List[AnomalyOut] = []
	for s in seats:
		last_report = (
			db.query(Report)
			.filter(Report.seat_id == s.seat_id)
			.order_by(Report.created_at.desc())
			.first()
		)
		base_color = compute_seat_color(s.is_empty, s.has_power)
		admin_color = compute_admin_color(base_color, s.is_malicious)
		out.append(
			AnomalyOut(
				seat_id=s.seat_id,
				floor_id=s.floor_id,
				has_power=s.has_power,
				is_empty=s.is_empty,
				is_reported=s.is_reported,
				is_malicious=s.is_malicious,
				seat_color=base_color,
				admin_color=admin_color,
				last_report_id=last_report.id if last_report else None,
			)
		)
	return out


@router.get("/reports/{report_id}", response_model=ReportOut)
def get_report(report_id: int, db: Session = Depends(get_db)) -> ReportOut:
	r = db.query(Report).filter(Report.id == report_id).first()
	if not r:
		raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="report not found")
	return ReportOut.model_validate(r)


@router.post("/reports/{report_id}/confirm", response_model=AnomalyOut)
def confirm_toggle(report_id: int, db: Session = Depends(get_db)) -> AnomalyOut:
	r = db.query(Report).filter(Report.id == report_id).first()
	if not r:
		raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="report not found")
	seat = db.query(Seat).filter(Seat.seat_id == r.seat_id).first()
	if not seat:
		raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="seat not found")

	# 取对色：若当前(管理员端)非黄 -> 标黄；若已黄 -> 变回底色（清黄）
	new_is_malicious = not seat.is_malicious
	seat.is_malicious = new_is_malicious
	r.status = "confirmed" if new_is_malicious else "dismissed"
	db.add(seat)
	db.add(r)
	db.commit()
	db.refresh(seat)

	base_color = compute_seat_color(seat.is_empty, seat.has_power)
	admin_color = compute_admin_color(base_color, seat.is_malicious)
	last_report = (
		db.query(Report)
		.filter(Report.seat_id == seat.seat_id)
		.order_by(Report.created_at.desc())
		.first()
	)
	return AnomalyOut(
		seat_id=seat.seat_id,
		floor_id=seat.floor_id,
		has_power=seat.has_power,
		is_empty=seat.is_empty,
		is_reported=seat.is_reported,
		is_malicious=seat.is_malicious,
		seat_color=base_color,
		admin_color=admin_color,
		last_report_id=last_report.id if last_report else None,
	)


@router.delete("/anomalies/{seat_id}", response_model=AnomalyOut)
def clear_anomaly(seat_id: str, db: Session = Depends(get_db)) -> AnomalyOut:
	seat = db.query(Seat).filter(Seat.seat_id == seat_id).first()
	if not seat:
		raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="seat not found")

	seat.is_reported = False
	seat.is_malicious = False
	# optional: set all pending reports to dismissed
	db.query(Report).filter(Report.seat_id == seat_id, Report.status == "pending").update({"status": "dismissed"})
	db.add(seat)
	db.commit()
	db.refresh(seat)

	base_color = compute_seat_color(seat.is_empty, seat.has_power)
	admin_color = compute_admin_color(base_color, seat.is_malicious)
	last_report = (
		db.query(Report)
		.filter(Report.seat_id == seat.seat_id)
		.order_by(Report.created_at.desc())
		.first()
	)
	return AnomalyOut(
		seat_id=seat.seat_id,
		floor_id=seat.floor_id,
		has_power=seat.has_power,
		is_empty=seat.is_empty,
		is_reported=seat.is_reported,
		is_malicious=seat.is_malicious,
		seat_color=base_color,
		admin_color=admin_color,
		last_report_id=last_report.id if last_report else None,
	)


@router.post("/seats/{seat_id}/lock", response_model=SeatOut)
def lock_seat(seat_id: str, minutes: int = 5, db: Session = Depends(get_db)) -> SeatOut:
	seat = db.query(Seat).filter(Seat.seat_id == seat_id).first()
	if not seat:
		raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="seat not found")
	now = int(time.time())
	if minutes < 0:
		minutes = 0
	seat.lock_until_ts = now + minutes * 60 if minutes > 0 else now
	db.add(seat)
	db.commit()
	db.refresh(seat)

	base_color = compute_seat_color(seat.is_empty, seat.has_power)
	admin_color = compute_admin_color(base_color, seat.is_malicious)
	return SeatOut(
		seat_id=seat.seat_id,
		floor_id=seat.floor_id,
		has_power=seat.has_power,
		is_empty=seat.is_empty,
		is_reported=seat.is_reported,
		is_malicious=seat.is_malicious,
		lock_until_ts=seat.lock_until_ts,
		seat_color=base_color,
		admin_color=admin_color,
	)


