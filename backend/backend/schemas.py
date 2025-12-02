from __future__ import annotations

from typing import List, Optional
from pydantic import BaseModel


class SeatOut(BaseModel):
	seat_id: str
	floor_id: str
	has_power: bool
	is_empty: bool
	is_reported: bool
	is_malicious: bool
	lock_until_ts: int
	seat_color: str
	admin_color: str

	class Config:
		from_attributes = True


class FloorSummary(BaseModel):
	floor_id: str
	empty_count: int
	total_count: int
	floor_color: str


class HealthOut(BaseModel):
	ok: bool
	version: str


class TokenOut(BaseModel):
	access_token: str
	token_type: str
	role: str
	user_id: int
	username: str


class ReportOut(BaseModel):
	id: int
	seat_id: str
	reporter_id: int
	text: Optional[str] = None
	images: List[str] = []
	status: str
	created_at: int

	class Config:
		from_attributes = True


class AnomalyOut(BaseModel):
	seat_id: str
	floor_id: str
	has_power: bool
	is_empty: bool
	is_reported: bool
	is_malicious: bool
	seat_color: str
	admin_color: str
	last_report_id: Optional[int] = None


class SeatStatsOut(BaseModel):
	seat_id: str
	daily_empty_seconds: int
	total_empty_seconds: int
	change_count: int
	last_update_ts: int
	last_state_is_empty: bool
	occupancy_start_ts: int
	object_only_occupy_seconds: int
	is_malicious: bool

