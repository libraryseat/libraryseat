from __future__ import annotations

import time
from typing import Any, Type, TypeVar

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from ..models import Report, Seat
from ..schemas import AnomalyOut, SeatOut, SeatStatsOut
from .color import compute_admin_color, compute_seat_color

T = TypeVar("T")


def get_or_404(db: Session, model: Type[T], id_value: Any, id_field: Any = None) -> T:
	"""
	Generic helper to get a database object by ID or raise 404.
	"""
	if id_field is None:
		# Default to 'id' attribute if not specified, but for Seat it's 'seat_id' usually passed as id_field
		if hasattr(model, "id"):
			id_field = model.id
		else:
			raise ValueError("id_field must be provided if model has no 'id' attribute")

	obj = db.query(model).filter(id_field == id_value).first()
	if not obj:
		name = model.__name__.lower()
		raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"{name} not found")
	return obj


def build_seat_out(seat: Seat) -> SeatOut:
	"""
	Construct SeatOut schema from Seat model, computing colors.
	"""
	base_color = compute_seat_color(seat.is_empty, seat.has_power)
	admin_color = compute_admin_color(base_color, seat.is_malicious, seat.is_reported)
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


def build_anomaly_out(seat: Seat, db: Session) -> AnomalyOut:
	"""
	Construct AnomalyOut schema from Seat model.
	"""
	# Re-use build_seat_out logic to avoid duplication
	seat_out = build_seat_out(seat)
	
	last_report = (
		db.query(Report)
		.filter(Report.seat_id == seat.seat_id)
		.order_by(Report.created_at.desc())
		.first()
	)
	
	return AnomalyOut(
		seat_id=seat_out.seat_id,
		floor_id=seat_out.floor_id,
		has_power=seat_out.has_power,
		is_empty=seat_out.is_empty,
		is_reported=seat_out.is_reported,
		is_malicious=seat_out.is_malicious,
		seat_color=seat_out.seat_color,
		admin_color=seat_out.admin_color,
		last_report_id=last_report.id if last_report else None,
	)


def build_seat_stats_out(seat: Seat) -> SeatStatsOut:
	"""
	Construct SeatStatsOut schema from Seat model.
	"""
	now = int(time.time())
	object_only_sec = 0
	if seat.occupancy_start_ts and not seat.is_empty:
		object_only_sec = max(0, now - seat.occupancy_start_ts)

	return SeatStatsOut(
		seat_id=seat.seat_id,
		daily_empty_seconds=seat.daily_empty_seconds,
		total_empty_seconds=seat.total_empty_seconds,
		change_count=seat.change_count,
		last_update_ts=seat.last_update_ts,
		last_state_is_empty=seat.last_state_is_empty,
		occupancy_start_ts=seat.occupancy_start_ts,
		object_only_occupy_seconds=object_only_sec,
		is_malicious=seat.is_malicious,
	)

