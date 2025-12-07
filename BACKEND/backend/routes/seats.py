from __future__ import annotations

from typing import Dict, List

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Seat
from ..schemas import FloorSummary, SeatOut, SeatStatsOut
from ..services.color import compute_floor_color
from ..services.response_builder import (
	build_seat_out,
	build_seat_stats_out,
	get_or_404,
)
from ..services.roi_loader import load_floor_config
from ..services.yolo_service import refresh_floor

router = APIRouter(prefix="", tags=["seats"])


@router.get("/seats", response_model=List[SeatOut])
def list_seats(
	floor: str | None = Query(default=None, alias="floor"),
	db: Session = Depends(get_db),
) -> List[SeatOut]:
	q = db.query(Seat)
	if floor:
		q = q.filter(Seat.floor_id == floor)
	seats = q.all()
	
	# Mock Data Logic for Demo
	if floor == "F3":
		# F3 默认为全占用（灰色，0个空座位）
		for s in seats:
			s.is_empty = False
			s.is_reported = False
			s.is_malicious = False
			s.has_power = False # 假设无电插座
	elif floor == "test":
		# test 楼层显示红色（全占用）
		for s in seats:
			s.is_empty = False
			s.is_reported = False
			s.is_malicious = False
			s.has_power = False
			
	return [build_seat_out(s) for s in seats]


@router.get("/seats/{seat_id}", response_model=SeatOut)
def get_seat(
	seat_id: str,
	db: Session = Depends(get_db),
) -> SeatOut:
	seat = get_or_404(db, Seat, seat_id, id_field=Seat.seat_id)
	return build_seat_out(seat)


@router.get("/floors", response_model=List[FloorSummary])
def list_floors(db: Session = Depends(get_db)) -> List[FloorSummary]:
	seats = db.query(Seat).all()
	
	# Apply mock data logic to summary as well
	for s in seats:
		if s.floor_id == "F3":
			s.is_empty = False  # F3全占用
		elif s.floor_id == "test":
			s.is_empty = False

	by_floor: Dict[str, Dict[str, int]] = {}
	for s in seats:
		stats = by_floor.setdefault(s.floor_id, {"empty": 0, "total": 0})
		stats["total"] += 1
		if s.is_empty:
			stats["empty"] += 1
	
	# 确保 F3 楼层有数据，如果没有座位数据，创建默认统计
	if "F3" not in by_floor:
		# 如果 F3 没有座位数据，创建一个全占用的统计
		by_floor["F3"] = {"empty": 0, "total": 1}  # 至少有一个座位，0个空座位
			
	out: List[FloorSummary] = []
	for floor_id, stats in sorted(by_floor.items()):
		# 特殊处理 F3：强制设置为全占用（红色）
		if floor_id == "F3":
			stats["empty"] = 0
			if stats["total"] == 0:
				stats["total"] = 1  # 确保至少有一个座位
		
		color = compute_floor_color(stats["empty"], stats["total"])
		out.append(
			FloorSummary(
				floor_id=floor_id,
				empty_count=stats["empty"],
				total_count=stats["total"],
				floor_color=color,
			)
		)
	return out


@router.post("/floors/{floor}/refresh", response_model=List[SeatOut])
def refresh_floor_endpoint(
	floor: str,
	db: Session = Depends(get_db),
) -> List[SeatOut]:
	cfg = load_floor_config(floor)
	seats = refresh_floor(db, cfg)
	return [build_seat_out(s) for s in seats if s.floor_id == floor]


@router.get("/stats/seats/{seat_id}", response_model=SeatStatsOut)
def get_seat_stats(seat_id: str, db: Session = Depends(get_db)) -> SeatStatsOut:
	seat = get_or_404(db, Seat, seat_id, id_field=Seat.seat_id)
	return build_seat_stats_out(seat)
