from __future__ import annotations

import calendar
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Tuple

from sqlalchemy.orm import Session

from ..models import Seat


BASE_DIR = Path(__file__).resolve().parents[2]
OUTPUTS_DIR = BASE_DIR / "outputs"


def _fmt_hms(seconds: int) -> str:
	seconds = max(0, int(seconds))
	h = seconds // 3600
	m = (seconds % 3600) // 60
	s = seconds % 60
	return f"{h:02d}h{m:02d}min{s:02d}s"


def _group_by_floor(rows: List[Seat], value_func) -> Dict[str, List[Tuple[str, int]]]:
	group: Dict[str, List[Tuple[str, int]]] = {}
	for seat in rows:
		group.setdefault(seat.floor_id, []).append((seat.seat_id, int(value_func(seat))))
	# Sort seats by seat_id within each floor
	for floor_id in group:
		group[floor_id].sort(key=lambda x: x[0])
	return dict(sorted(group.items(), key=lambda kv: kv[0]))


def _write_grouped_txt(
	path: Path,
	grouped: Dict[str, List[Tuple[str, int]]],
	floor_rates: Dict[str, float],
	library_rate: float,
) -> None:
	path.parent.mkdir(parents=True, exist_ok=True)
	lines: List[str] = []
	# First line: Library total empty rate
	lines.append(f"图书馆总空座率: {library_rate:.2%}")
	lines.append("")
	for floor_id, items in grouped.items():
		rate = floor_rates.get(floor_id, 0.0)
		lines.append(f"{floor_id} 空座率: {rate:.2%}")
		for seat_id, secs in items:
			lines.append(f"{seat_id} {_fmt_hms(secs)}")
		lines.append("")  # blank line between floors
	content = "\n".join(lines).rstrip() + "\n"
	path.write_text(content, encoding="utf-8")


def export_daily_and_reset(db: Session, target_date: datetime, now_ts: int) -> None:
	"""
	Export daily_empty_seconds grouped by floor to outputs/YYYY-MM-DD/daily_empty.txt
	and reset daily fields and state for the new day as per requirements.
	Also clear is_reported, is_malicious, lock_until_ts, occupancy_start_ts.
	Set is_empty=True, last_state_is_empty=True, last_update_ts=now.
	"""
	date_str = target_date.strftime("%Y-%m-%d")
	target_dir = OUTPUTS_DIR / date_str
	target_file = target_dir / "daily_empty.txt"

	seats = db.query(Seat).all()
	grouped = _group_by_floor(seats, lambda s: s.daily_empty_seconds)
	# Compute rates: per floor and library
	seconds_per_seat = 24 * 3600
	# floor seat counts
	floor_counts: Dict[str, int] = {}
	for s in seats:
		floor_counts[s.floor_id] = floor_counts.get(s.floor_id, 0) + 1
	# per-floor numerator
	floor_sums: Dict[str, int] = {floor_id: sum(secs for _, secs in items) for floor_id, items in grouped.items()}
	floor_rates: Dict[str, float] = {}
	for floor_id, total_secs in floor_sums.items():
		den = max(1, floor_counts.get(floor_id, 0)) * seconds_per_seat
		floor_rates[floor_id] = (total_secs / den) if den > 0 else 0.0
	# library rate
	total_secs_all = sum(floor_sums.values())
	total_seats = sum(floor_counts.values())
	library_den = max(1, total_seats) * seconds_per_seat
	library_rate = (total_secs_all / library_den) if library_den > 0 else 0.0
	_write_grouped_txt(target_file, grouped, floor_rates, library_rate)

	# Reset per-day stats and flags
	for seat in seats:
		seat.daily_empty_seconds = 0
		seat.is_reported = False
		seat.is_malicious = False
		seat.lock_until_ts = 0
		seat.occupancy_start_ts = 0
		seat.is_empty = True
		seat.last_state_is_empty = True
		seat.last_update_ts = now_ts
		db.add(seat)
	db.commit()


def export_monthly_and_reset_total(db: Session, month_of: datetime) -> None:
	"""
	Export total_empty_seconds grouped by floor to outputs/monthly/YYYY-MM.txt
	and reset total_empty_seconds=0 for all seats.
	"""
	ym_str = month_of.strftime("%Y-%m")
	target_dir = OUTPUTS_DIR / "monthly"
	target_file = target_dir / f"{ym_str}.txt"

	seats = db.query(Seat).all()
	grouped = _group_by_floor(seats, lambda s: s.total_empty_seconds)
	# Compute monthly rates
	days = calendar.monthrange(month_of.year, month_of.month)[1]
	seconds_per_seat = days * 24 * 3600
	floor_counts: Dict[str, int] = {}
	for s in seats:
		floor_counts[s.floor_id] = floor_counts.get(s.floor_id, 0) + 1
	floor_sums: Dict[str, int] = {floor_id: sum(secs for _, secs in items) for floor_id, items in grouped.items()}
	floor_rates: Dict[str, float] = {}
	for floor_id, total_secs in floor_sums.items():
		den = max(1, floor_counts.get(floor_id, 0)) * seconds_per_seat
		floor_rates[floor_id] = (total_secs / den) if den > 0 else 0.0
	total_secs_all = sum(floor_sums.values())
	total_seats = sum(floor_counts.values())
	library_den = max(1, total_seats) * seconds_per_seat
	library_rate = (total_secs_all / library_den) if library_den > 0 else 0.0
	_write_grouped_txt(target_file, grouped, floor_rates, library_rate)

	for seat in seats:
		seat.total_empty_seconds = 0
		db.add(seat)
	db.commit()


def _date_from_ts(ts: int) -> datetime:
	return datetime.fromtimestamp(ts, tz=timezone.utc).astimezone()


def _at_local_midnight(dt: datetime) -> datetime:
	return dt.replace(hour=0, minute=0, second=0, microsecond=0)


def is_first_day(dt: datetime) -> bool:
	return dt.day == 1


def last_day_of_month(dt: datetime) -> int:
	return calendar.monthrange(dt.year, dt.month)[1]


def perform_rollovers_if_needed(db: Session, now_ts: int) -> None:
	"""
	Offline handling: if current date != last_update_date across seats, run daily export for last date,
	and if month changed, run monthly export for the previous month.
	We base the check on the minimum non-zero last_update_ts among seats; if none, do nothing.
	"""
	seats = db.query(Seat).all()
	last_ts_vals = [s.last_update_ts for s in seats if s.last_update_ts and s.last_update_ts > 0]
	if not last_ts_vals:
		return
	last_ts = min(last_ts_vals)
	now_dt = _date_from_ts(now_ts)
	last_dt = _date_from_ts(last_ts)

	# Monthly rollover if month changed
	if (now_dt.year, now_dt.month) != (last_dt.year, last_dt.month):
		# export for the month of last_dt
		export_monthly_and_reset_total(db, last_dt)

	# Daily rollover if date changed
	if (now_dt.date() != last_dt.date()):
		# export for the date of last_dt
		export_daily_and_reset(db, last_dt, now_ts)


