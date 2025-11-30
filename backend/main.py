from __future__ import annotations

from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.staticfiles import StaticFiles

from .db import Base, engine
from .routes import health as health_routes
from .routes import seats as seats_routes
from .routes import reports as reports_routes
from .routes import admin as admin_routes
from .scheduler import FloorRefreshScheduler
from .routes import auth as auth_routes


def create_app() -> FastAPI:
	app = FastAPI(title="Library Seat Backend", version="0.1.0")

	# CORS middleware for cross-origin requests (needed for mobile/Flutter apps)
	app.add_middleware(
		CORSMiddleware,
		allow_origins=["*"],  # Allow all origins for development
		allow_credentials=True,
		allow_methods=["*"],  # Allow all HTTP methods
		allow_headers=["*"],  # Allow all headers
	)

	# Include routers
	app.include_router(health_routes.router)
	app.include_router(auth_routes.router)
	app.include_router(seats_routes.router)
	app.include_router(reports_routes.router)
	app.include_router(admin_routes.router)

	# Static files for report images
	base_dir = Path(__file__).resolve().parents[1]
	report_dir = base_dir / "config" / "report"
	report_dir.mkdir(parents=True, exist_ok=True)
	app.mount("/report", StaticFiles(directory=report_dir.as_posix()), name="report")

	# Create tables on startup
	@app.on_event("startup")
	def on_startup():
		Base.metadata.create_all(bind=engine)
		# 创建调度器但不立即启动，等待用户登录
		app.state.scheduler = FloorRefreshScheduler()
		app.state.scheduler_started = False

	@app.on_event("shutdown")
	def on_shutdown():
		sched = getattr(app.state, "scheduler", None)
		if sched:
			sched.shutdown()

	return app


app = create_app()


