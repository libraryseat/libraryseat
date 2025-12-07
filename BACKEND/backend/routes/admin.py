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
	# 修改查询条件：不仅包含被举报的，也包含被系统标记为恶意的，或者系统自动推送的
	q = db.query(Seat).filter(
		(Seat.is_reported == True) | 
		(Seat.is_malicious == True) |
		(Seat.is_system_reported == True)
	)
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

	# 确认异常（勾选）：
	# 场景：确实有人占座（异常），或者管理员判定这是个违规行为。
	# 动作：清理异常状态，将座位恢复为“空闲”状态（赶走占座者，让座位变回绿色/蓝色供他人使用）。
	#      同时标记举报为"confirmed"。
	#      
	# 注意：确认后，座位会从异常列表中消失（因为所有异常标记都被清除），
	#      这是正常行为，表示问题已处理完毕。
	
	seat.is_malicious = False
	seat.is_reported = False
	seat.is_system_reported = False # 清除系统推送标记
	seat.is_empty = True  # 恢复为空闲
	
	report.status = "confirmed"
	
	db.add(seat)
	db.add(report)
	db.commit()
	db.refresh(seat)
	
	# 返回更新后的座位信息（虽然它不再是异常，但前端需要这个响应来更新UI）
	return build_anomaly_out(seat, db)


@router.delete("/anomalies/{seat_id}", response_model=AnomalyOut)
def clear_anomaly(seat_id: str, db: Session = Depends(get_db)) -> AnomalyOut:
	seat = get_or_404(db, Seat, seat_id, id_field=Seat.seat_id)

	# 删除/驳回异常（叉掉）：
	# 场景：座位是正常的（比如人只是暂时离开或正常使用），被人误举报了。
	# 动作：清除举报标记，恢复座位原来的状态。
	#      注意：我们并不完全知道"原来"是什么状态，但通常：
	#      - 如果之前被标记为 malicious（黄色），说明管理员之前可能确认过，或者系统自动标记的。
	#        现在人工驳回，说明其实没问题。
	#      - 逻辑上，"没有异常" 意味着 "当前的使用状态是合法的"。
	#      - 如果有人坐（is_empty=False），那就保持有人坐。
	#      - 如果没人坐（is_empty=True），那就保持没人坐。
	#      
	#      *关键修改*：这里我们只清除 `is_reported` 和 `is_malicious` 标记，
	#      **不修改** `is_empty` 的状态。
	#      这样，如果它本身是空闲的，就还是空闲；如果本身是占用的，就还是占用。
	#      这就实现了"空闲就空闲，有人使用就有人使用"的效果。

	seat.is_reported = False
	seat.is_malicious = False
	seat.is_system_reported = False # 清除系统推送标记
	
	# 不修改 seat.is_empty，保持原状
	
	# 将相关的 pending 举报标记为 dismissed
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
