from __future__ import annotations

import os
import time
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from .db import get_db
from .models import User


SECRET_KEY = os.getenv("JWT_SECRET_KEY", "dev-secret-change")
ALGORITHM = os.getenv("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("JWT_EXPIRE_MINUTES", "120"))

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def verify_password(plain_password: str, hashed_password: str) -> bool:
	return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
	return pwd_context.hash(password)


def create_access_token(subject: str, user_id: int, role: str, expires_delta_minutes: Optional[int] = None) -> str:
	expire_minutes = expires_delta_minutes or ACCESS_TOKEN_EXPIRE_MINUTES
	now = int(time.time())
	to_encode = {"sub": subject, "uid": user_id, "role": role, "iat": now, "exp": now + expire_minutes * 60}
	encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
	return encoded_jwt


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
	credentials_exception = HTTPException(
		status_code=status.HTTP_401_UNAUTHORIZED,
		detail="Could not validate credentials",
		headers={"WWW-Authenticate": "Bearer"},
	)
	try:
		payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
		username: str = payload.get("sub")
		if username is None:
			raise credentials_exception
	except JWTError:
		raise credentials_exception
	user = db.query(User).filter(User.username == username).first()
	if user is None:
		raise credentials_exception
	return user


def require_admin(user: User = Depends(get_current_user)) -> User:
	if user.role != "admin":
		raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin privileges required")
	return user


