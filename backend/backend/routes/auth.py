from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel
from sqlalchemy.orm import Session
from starlette.requests import Request

from ..auth import create_access_token, verify_password, get_current_user, get_password_hash
from ..db import get_db
from ..models import User
from ..schemas import TokenOut


router = APIRouter(prefix="/auth", tags=["auth"])


class RegisterRequest(BaseModel):
	username: str
	password: str


@router.post("/register", response_model=TokenOut)
def register(register_request: RegisterRequest, http_request: Request, db: Session = Depends(get_db)) -> TokenOut:
	# 检查用户名是否已存在
	existing_user = db.query(User).filter(User.username == register_request.username).first()
	if existing_user:
		raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Username already exists")
	
	# 验证用户名和密码
	if not register_request.username or len(register_request.username.strip()) == 0:
		raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Username cannot be empty")
	if len(register_request.password) < 6:
		raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password must be at least 6 characters")
	
	# 创建新用户（默认角色为 student）
	new_user = User(
		username=register_request.username.strip(),
		pass_hash=get_password_hash(register_request.password),
		role="student"
	)
	db.add(new_user)
	db.commit()
	db.refresh(new_user)
	
	# 启动 YOLO 调度器（如果尚未启动）
	_start_scheduler_if_needed(http_request.app)
	
	# 自动登录，返回 token
	token = create_access_token(subject=new_user.username, user_id=new_user.id, role=new_user.role)
	return TokenOut(access_token=token, token_type="bearer", role=new_user.role, user_id=new_user.id, username=new_user.username)


@router.post("/login", response_model=TokenOut)
def login(http_request: Request, form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)) -> TokenOut:
	user = db.query(User).filter(User.username == form_data.username).first()
	if not user or not verify_password(form_data.password, user.pass_hash):
		raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect username or password")
	
	# 启动 YOLO 调度器（如果尚未启动）
	if http_request:
		_start_scheduler_if_needed(http_request.app)
	
	token = create_access_token(subject=user.username, user_id=user.id, role=user.role)
	return TokenOut(access_token=token, token_type="bearer", role=user.role, user_id=user.id, username=user.username)


@router.get("/me")
def me(user: User = Depends(get_current_user)):
	return {"id": user.id, "username": user.username, "role": user.role}


def _start_scheduler_if_needed(app) -> None:
	"""如果调度器尚未启动，则启动它"""
	if not getattr(app.state, "scheduler_started", False):
		scheduler = getattr(app.state, "scheduler", None)
		if scheduler and not scheduler.started:
			scheduler.start()
			app.state.scheduler_started = True


