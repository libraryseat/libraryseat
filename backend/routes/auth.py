from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from ..auth import create_access_token, verify_password, get_current_user
from ..db import get_db
from ..models import User
from ..schemas import TokenOut


router = APIRouter(prefix="/auth", tags=["auth"])


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


