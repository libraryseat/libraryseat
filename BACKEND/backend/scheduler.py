from __future__ import annotations

import os
import logging
from typing import Optional
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.cron import CronTrigger

from .db import SessionLocal
from .services.roi_loader import list_floor_ids, load_floor_config
from .services.yolo_service import refresh_floor
from .services.rollover import perform_rollovers_if_needed, export_daily_and_reset, export_monthly_and_reset_total, _date_from_ts, is_first_day


logger = logging.getLogger("scheduler")


class FloorRefreshScheduler:
	def __init__(self, interval_seconds: Optional[int] = None) -> None:
		self.interval_seconds = interval_seconds or int(os.getenv("REFRESH_INTERVAL_SECONDS", "5"))###
		self.scheduler = BackgroundScheduler()
		self.started = False

	def _refresh_job(self, floor_id: str) -> None:
		db = SessionLocal()
		try:
			cfg = load_floor_config(floor_id)
			refresh_floor(db, cfg)
		except Exception as e:
			logger.exception("Error refreshing floor %s: %s", floor_id, e)
			# 如果刷新失败，不要阻塞后续任务
		finally:
			try:
				db.close()
			except Exception:
				pass

	def start(self) -> None:
		if self.started:
			# 检查调度器是否仍在运行
			try:
				if self.scheduler.running:
					return  # 已经在运行，不需要重新启动
				else:
					# 调度器已停止但标记为 started，重置状态
					self.started = False
			except Exception:
				# 调度器可能已经 shutdown，重新创建
				self.scheduler = BackgroundScheduler()
				self.started = False
		
		floors = list_floor_ids()
		for floor_id in floors:
			self.scheduler.add_job(
				func=self._refresh_job,
				args=[floor_id],
				trigger=IntervalTrigger(seconds=self.interval_seconds),
				id=f"refresh_{floor_id}",
				max_instances=1,
				coalesce=True,
				misfire_grace_time=30,
				replace_existing=True,
			)
		# Daily midnight job (00:00:00 local time)
		self.scheduler.add_job(
			func=self._daily_rollover_job,
			trigger=CronTrigger(hour=0, minute=0, second=0),
			id="daily_rollover",
			max_instances=1,
			coalesce=True,
			replace_existing=True,
		)
		
		# 只有在调度器未运行时才启动
		if not self.scheduler.running:
			self.scheduler.start()
		self.started = True

	def shutdown(self) -> None:
		if self.started:
			try:
				self.scheduler.shutdown(wait=False)
			except Exception:
				pass  # 如果已经 shutdown，忽略错误
			# shutdown 后重新创建调度器实例，以便下次可以重新启动
			self.scheduler = BackgroundScheduler()
			self.started = False

	def _daily_rollover_job(self) -> None:
		db = SessionLocal()
		try:
			now_ts = int(__import__("time").time())
			# Offline safety (if missed days)
			try:
				perform_rollovers_if_needed(db, now_ts)
			except Exception:
				logger.exception("perform_rollovers_if_needed failed")
			# Now run today's 00:00 rollover for yesterday's daily
			now_dt = _date_from_ts(now_ts)
			yesterday = now_dt.replace(hour=0, minute=0, second=0, microsecond=0) - __import__("datetime").timedelta(days=1)
			try:
				export_daily_and_reset(db, yesterday, now_ts)
			except Exception:
				logger.exception("export_daily_and_reset failed")
			# Monthly export if first day of month (meaning we just rolled over)
			if is_first_day(now_dt):
				prev_month = (now_dt.replace(day=1) - __import__("datetime").timedelta(days=1))
				try:
					export_monthly_and_reset_total(db, prev_month)
				except Exception:
					logger.exception("export_monthly_and_reset_total failed")
		finally:
			db.close()


