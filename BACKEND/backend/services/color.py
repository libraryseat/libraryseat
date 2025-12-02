from __future__ import annotations


SEAT_GREEN = "#60D937"
SEAT_BLUE = "#00A1FF"
SEAT_GRAY = "#929292"
ADMIN_YELLOW = "#FEAE03"
FLOOR_RED = "#FF0000"


def compute_seat_color(is_empty: bool, has_power: bool) -> str:
	if not is_empty:
		return SEAT_GRAY
	return SEAT_BLUE if has_power else SEAT_GREEN


def compute_admin_color(base_color: str, is_malicious: bool, is_reported: bool = False) -> str:
	# 如果被举报或标记为恶意，显示黄色
	if is_malicious or is_reported:
		return ADMIN_YELLOW
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


