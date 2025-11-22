from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..auth import create_access_token, verify_password, get_current_user, get_password_hash
from ..db import get_db
from ..models import User
from ..schemas import TokenOut


router = APIRouter(prefix="/auth", tags=["auth"])


class RegisterRequest(BaseModel):
	username: str
	password: str


@router.post("/register", response_model=TokenOut)
def register(request: RegisterRequest, db: Session = Depends(get_db)) -> TokenOut:
	# 检查用户名是否已存在
	existing_user = db.query(User).filter(User.username == request.username).first()
	if existing_user:
		raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Username already exists")
	
	# 验证用户名和密码
	if not request.username or len(request.username.strip()) == 0:
		raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Username cannot be empty")
	if len(request.password) < 6:
		raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password must be at least 6 characters")
	
	# 创建新用户（默认角色为 student）
	new_user = User(
		username=request.username.strip(),
		pass_hash=get_password_hash(request.password),
		role="student"
	)
	db.add(new_user)
	db.commit()
	db.refresh(new_user)
	
	# 自动登录，返回 token
	token = create_access_token(subject=new_user.username, user_id=new_user.id, role=new_user.role)
	return TokenOut(access_token=token, token_type="bearer", role=new_user.role, user_id=new_user.id, username=new_user.username)


@router.post("/login", response_model=TokenOut)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)) -> TokenOut:
	user = db.query(User).filter(User.username == form_data.username).first()
	if not user or not verify_password(form_data.password, user.pass_hash):
		raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect username or password")
	token = create_access_token(subject=user.username, user_id=user.id, role=user.role)
	return TokenOut(access_token=token, token_type="bearer", role=user.role, user_id=user.id, username=user.username)


@router.get("/me")
def me(user: User = Depends(get_current_user)):
	return {"id": user.id, "username": user.username, "role": user.role}


