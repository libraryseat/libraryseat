from __future__ import annotations

import time
from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from ..auth import require_admin
from ..db import get_db
from ..models import Report, Seat
from ..schemas import AnomalyOut, ReportOut, SeatOut
from ..services.response_builder import (
	build_anomaly_out,
	build_seat_out,
	get_or_404,
)

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
	return [build_anomaly_out(s, db) for s in seats]


@router.get("/reports/{report_id}", response_model=ReportOut)
def get_report(report_id: int, db: Session = Depends(get_db)) -> ReportOut:
	report = get_or_404(db, Report, report_id)
	return ReportOut.model_validate(report)


@router.post("/reports/{report_id}/confirm", response_model=AnomalyOut)
def confirm_toggle(report_id: int, db: Session = Depends(get_db)) -> AnomalyOut:
	report = get_or_404(db, Report, report_id)
	seat = get_or_404(db, Seat, report.seat_id, id_field=Seat.seat_id)

	# 确认异常的逻辑：
	# - 如果当前是恶意（黄色），确认后应该清除恶意标记，座位变为空闲（绿色/蓝色）
	# - 如果当前不是恶意，确认后标记为恶意（黄色）
	if seat.is_malicious:
		# 确认异常：清除恶意标记，座位变为空闲状态
		seat.is_malicious = False
		seat.is_reported = False  # 清除举报标记
		seat.is_empty = True  # 确认异常后，座位应该是空的
		report.status = "confirmed"
	else:
		# 标记为恶意
		seat.is_malicious = True
		report.status = "confirmed"
	
	db.add(seat)
	db.add(report)
	db.commit()
	db.refresh(seat)

	return build_anomaly_out(seat, db)


@router.delete("/anomalies/{seat_id}", response_model=AnomalyOut)
def clear_anomaly(seat_id: str, db: Session = Depends(get_db)) -> AnomalyOut:
	seat = get_or_404(db, Seat, seat_id, id_field=Seat.seat_id)

	# 删除异常：说明有人正在坐，恢复为占用状态（灰色）
	seat.is_reported = False
	seat.is_malicious = False
	seat.is_empty = False  # 删除异常说明有人正在坐，所以是占用状态
	# optional: set all pending reports to dismissed
	db.query(Report).filter(Report.seat_id == seat_id, Report.status == "pending").update({"status": "dismissed"})
	db.add(seat)
	db.commit()
	db.refresh(seat)

	return build_anomaly_out(seat, db)


@router.post("/seats/{seat_id}/lock", response_model=SeatOut)
def lock_seat(seat_id: str, minutes: int = 5, db: Session = Depends(get_db)) -> SeatOut:
	seat = get_or_404(db, Seat, seat_id, id_field=Seat.seat_id)
	
	now = int(time.time())
	if minutes < 0:
		minutes = 0
	seat.lock_until_ts = now + minutes * 60 if minutes > 0 else now
	db.add(seat)
	db.commit()
	db.refresh(seat)

	return build_seat_out(seat)
