from __future__ import annotations


SEAT_GREEN = "#60D937"
SEAT_BLUE = "#00A1FF"
SEAT_GRAY = "#929292"
ADMIN_YELLOW = "#FEAE03"
SEAT_RED = "#FF5252"
FLOOR_RED = "#FF0000"


def compute_seat_color(is_empty: bool, has_power: bool, is_reported: bool = False) -> str:
	if is_reported:
		return ADMIN_YELLOW
	if not is_empty:
		return SEAT_GRAY
	return SEAT_BLUE if has_power else SEAT_GREEN


def compute_admin_color(base_color: str, is_malicious: bool, is_empty: bool = True, has_power: bool = False) -> str:
	if is_malicious:
		# 反色逻辑：原本空的 -> 变占用(灰色)；原本占用的 -> 变空(绿/蓝)
		if is_empty:
			return SEAT_GRAY
		else:
			return SEAT_BLUE if has_power else SEAT_GREEN
	return base_color


def compute_floor_color(empty_count: int, total_count: int) -> str:
	if total_count == 0:
		return FLOOR_RED
	ratio = empty_count / float(total_count)
	if ratio == 0:
		return FLOOR_RED
	if ratio > 0.5:
		return SEAT_GREEN
	return ADMIN_YELLOW


