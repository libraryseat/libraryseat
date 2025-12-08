from __future__ import annotations

from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, Text, Index
from sqlalchemy.dialects.sqlite import JSON as SQLITE_JSON
from sqlalchemy.orm import relationship

from .db import Base


class User(Base):
	__tablename__ = "users"

	id = Column(Integer, primary_key=True, index=True)
	username = Column(String(64), unique=True, nullable=False, index=True)
	pass_hash = Column(String(256), nullable=False)
	role = Column(String(16), nullable=False, default="student")  # student/admin


class Seat(Base):
	__tablename__ = "seats"

	seat_id = Column(String(32), primary_key=True)
	floor_id = Column(String(8), index=True, nullable=False)
	has_power = Column(Boolean, default=False, nullable=False)

	is_empty = Column(Boolean, default=True, nullable=False)
	is_reported = Column(Boolean, default=False, nullable=False)
	is_malicious = Column(Boolean, default=False, nullable=False)

	lock_until_ts = Column(Integer, default=0, nullable=False)

	last_update_ts = Column(Integer, default=0, nullable=False)
	last_state_is_empty = Column(Boolean, default=True, nullable=False)
	daily_empty_seconds = Column(Integer, default=0, nullable=False)
	total_empty_seconds = Column(Integer, default=0, nullable=False)
	change_count = Column(Integer, default=0, nullable=False)
	occupancy_start_ts = Column(Integer, default=0, nullable=False)

	reports = relationship("Report", back_populates="seat", cascade="all, delete-orphan")

	__table_args__ = (
		Index("idx_seats_floor_id", "floor_id"),
	)


class Report(Base):
	__tablename__ = "reports"

	id = Column(Integer, primary_key=True)
	seat_id = Column(String(32), ForeignKey("seats.seat_id"), nullable=False, index=True)
	reporter_id = Column(Integer, ForeignKey("users.id"), nullable=False)
	text = Column(Text, nullable=True)
	images = Column(SQLITE_JSON, nullable=True)  # list of relative paths under config/report/{id}/
	status = Column(String(16), default="pending", nullable=False)  # pending/confirmed/dismissed
	created_at = Column(Integer, nullable=False)  # epoch seconds

	seat = relationship("Seat", back_populates="reports")


