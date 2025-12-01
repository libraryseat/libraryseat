from __future__ import annotations

from typing import List, Dict
from fastapi import APIRouter, Depends, Query, HTTPException, status
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Seat
from ..schemas import SeatOut, FloorSummary, SeatStatsOut
from ..services.color import compute_seat_color, compute_admin_color, compute_floor_color
from ..services.roi_loader import load_floor_config
from ..services.yolo_service import refresh_floor
import time


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
	out: List[SeatOut] = []
	for s in seats:
		base_color = compute_seat_color(s.is_empty, s.has_power)
		admin_color = compute_admin_color(base_color, s.is_malicious)
		out.append(
			SeatOut(
				seat_id=s.seat_id,
				floor_id=s.floor_id,
				has_power=s.has_power,
				is_empty=s.is_empty,
				is_reported=s.is_reported,
				is_malicious=s.is_malicious,
				lock_until_ts=s.lock_until_ts,
				seat_color=base_color,
				admin_color=admin_color,
			)
		)
	return out


@router.get("/seats/{seat_id}", response_model=SeatOut)
def get_seat(
	seat_id: str,
	db: Session = Depends(get_db),
) -> SeatOut:
	s = db.query(Seat).filter(Seat.seat_id == seat_id).first()
	if not s:
		raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="seat not found")
	base_color = compute_seat_color(s.is_empty, s.has_power)
	admin_color = compute_admin_color(base_color, s.is_malicious)
	return SeatOut(
		seat_id=s.seat_id,
		floor_id=s.floor_id,
		has_power=s.has_power,
		is_empty=s.is_empty,
		is_reported=s.is_reported,
		is_malicious=s.is_malicious,
		lock_until_ts=s.lock_until_ts,
		seat_color=base_color,
		admin_color=admin_color,
	)


@router.get("/floors", response_model=List[FloorSummary])
def list_floors(db: Session = Depends(get_db)) -> List[FloorSummary]:
	seats = db.query(Seat).all()
	by_floor: Dict[str, Dict[str, int]] = {}
	for s in seats:
		stats = by_floor.setdefault(s.floor_id, {"empty": 0, "total": 0})
		stats["total"] += 1
		if s.is_empty:
			stats["empty"] += 1
	out: List[FloorSummary] = []
	for floor_id, stats in sorted(by_floor.items()):
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
	out: List[SeatOut] = []
	for s in seats:
		if s.floor_id != floor:
			continue
		base_color = compute_seat_color(s.is_empty, s.has_power)
		admin_color = compute_admin_color(base_color, s.is_malicious)
		out.append(
			SeatOut(
				seat_id=s.seat_id,
				floor_id=s.floor_id,
				has_power=s.has_power,
				is_empty=s.is_empty,
				is_reported=s.is_reported,
				is_malicious=s.is_malicious,
				lock_until_ts=s.lock_until_ts,
				seat_color=base_color,
				admin_color=admin_color,
			)
		)
	return out


@router.get("/stats/seats/{seat_id}", response_model=SeatStatsOut)
def get_seat_stats(seat_id: str, db: Session = Depends(get_db)) -> SeatStatsOut:
	s = db.query(Seat).filter(Seat.seat_id == seat_id).first()
	if not s:
		raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="seat not found")
	now = int(time.time())
	object_only_sec = 0
	if s.occupancy_start_ts and not s.is_empty:
		object_only_sec = max(0, now - s.occupancy_start_ts)
	return SeatStatsOut(
		seat_id=s.seat_id,
		daily_empty_seconds=s.daily_empty_seconds,
		total_empty_seconds=s.total_empty_seconds,
		change_count=s.change_count,
		last_update_ts=s.last_update_ts,
		last_state_is_empty=s.last_state_is_empty,
		occupancy_start_ts=s.occupancy_start_ts,
		object_only_occupy_seconds=object_only_sec,
		is_malicious=s.is_malicious,
	)

