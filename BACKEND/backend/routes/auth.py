from __future__ import annotations

import threading
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from ..auth import create_access_token, verify_password, get_current_user, get_password_hash
from ..db import get_db
from ..models import User
from ..schemas import TokenOut, UserCreate


router = APIRouter(prefix="/auth", tags=["auth"])

# 线程安全的活跃用户跟踪
_active_users: set[int] = set()
_active_users_lock = threading.Lock()


def _start_scheduler_if_needed(request: Request) -> None:
	"""在用户登录成功后启动 YOLO 检测调度器（如果尚未启动）"""
	scheduler = getattr(request.app.state, "scheduler", None)
	if scheduler:
		with _active_users_lock:
			if not scheduler.started:
				scheduler.start()


def _stop_scheduler_if_no_users(request: Request) -> None:
	"""当所有用户登出后停止 YOLO 检测调度器"""
	scheduler = getattr(request.app.state, "scheduler", None)
	if scheduler:
		with _active_users_lock:
			if scheduler.started and len(_active_users) == 0:
				scheduler.shutdown()


@router.post("/register", response_model=TokenOut)
def register(user_in: UserCreate, db: Session = Depends(get_db), request: Request = None) -> TokenOut:
	if db.query(User).filter(User.username == user_in.username).first():
		raise HTTPException(status_code=400, detail="Username already registered")
	
	hashed_password = get_password_hash(user_in.password)
	user = User(
		username=user_in.username,
		pass_hash=hashed_password,
		role="student",  # default role
	)
	db.add(user)
	db.commit()
	db.refresh(user)
	
	# 记录活跃用户
	with _active_users_lock:
		_active_users.add(user.id)
		was_empty = len(_active_users) == 1
	
	# 注册成功后，启动 YOLO 检测调度器（如果尚未启动）
	if was_empty and request:
		_start_scheduler_if_needed(request)
	
	token = create_access_token(subject=user.username, user_id=user.id, role=user.role)
	return TokenOut(access_token=token, token_type="bearer", role=user.role, user_id=user.id, username=user.username)


@router.post("/login", response_model=TokenOut)
def login(
	form_data: OAuth2PasswordRequestForm = Depends(), 
	db: Session = Depends(get_db),
	request: Request = None
) -> TokenOut:
	user = db.query(User).filter(User.username == form_data.username).first()
	if not user or not verify_password(form_data.password, user.pass_hash):
		raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect username or password")
	
	# 记录活跃用户
	with _active_users_lock:
		_active_users.add(user.id)
		was_empty = len(_active_users) == 1
	
	# 登录成功后，启动 YOLO 检测调度器（如果尚未启动）
	if was_empty and request:
		_start_scheduler_if_needed(request)
	
	token = create_access_token(subject=user.username, user_id=user.id, role=user.role)
	return TokenOut(access_token=token, token_type="bearer", role=user.role, user_id=user.id, username=user.username)


@router.post("/logout")
def logout(user: User = Depends(get_current_user), request: Request = None):
	"""用户登出接口"""
	with _active_users_lock:
		_active_users.discard(user.id)  # 移除用户，如果不存在也不报错
		is_empty = len(_active_users) == 0
	
	# 如果所有用户都登出了，停止 YOLO 检测调度器
	if is_empty and request:
		_stop_scheduler_if_no_users(request)
	
	return {"message": "Logged out successfully"}


@router.get("/me")
def me(user: User = Depends(get_current_user)):
	return {"id": user.id, "username": user.username, "role": user.role}


