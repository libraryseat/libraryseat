from __future__ import annotations

import argparse
import sys
from typing import Optional

from .db import Base, engine, SessionLocal
from .models import User
from .auth import get_password_hash


def ensure_tables():
	Base.metadata.create_all(bind=engine)


def cmd_create(username: str, password: str, role: str) -> int:
	if role not in ("student", "admin"):
		print("role must be 'student' or 'admin'")
		return 2
	db = SessionLocal()
	try:
		exists = db.query(User).filter(User.username == username).first()
		if exists:
			print(f"user '{username}' already exists")
			return 1
		user = User(username=username, pass_hash=get_password_hash(password), role=role)
		db.add(user)
		db.commit()
		print(f"created user '{username}' with role '{role}'")
		return 0
	finally:
		db.close()


def cmd_passwd(username: str, password: str) -> int:
	db = SessionLocal()
	try:
		user = db.query(User).filter(User.username == username).first()
		if not user:
			print(f"user '{username}' not found")
			return 1
		user.pass_hash = get_password_hash(password)
		db.add(user)
		db.commit()
		print(f"password updated for '{username}'")
		return 0
	finally:
		db.close()


def cmd_role(username: str, role: str) -> int:
	if role not in ("student", "admin"):
		print("role must be 'student' or 'admin'")
		return 2
	db = SessionLocal()
	try:
		user = db.query(User).filter(User.username == username).first()
		if not user:
			print(f"user '{username}' not found")
			return 1
		user.role = role
		db.add(user)
		db.commit()
		print(f"role of '{username}' set to '{role}'")
		return 0
	finally:
		db.close()


def cmd_list() -> int:
	db = SessionLocal()
	try:
		users = db.query(User).order_by(User.id.asc()).all()
		if not users:
			print("(no users)")
			return 0
		for u in users:
			print(f"{u.id}\t{u.username}\t{u.role}")
		return 0
	finally:
		db.close()


def main(argv: Optional[list[str]] = None) -> int:
	ensure_tables()
	parser = argparse.ArgumentParser(description="Manage users for Library Backend")
	sub = parser.add_subparsers(dest="cmd", required=True)

	p_create = sub.add_parser("create", help="create a new user")
	p_create.add_argument("--username", required=True)
	p_create.add_argument("--password", required=True)
	p_create.add_argument("--role", required=True, choices=["student", "admin"])

	p_pass = sub.add_parser("passwd", help="set/reset password")
	p_pass.add_argument("--username", required=True)
	p_pass.add_argument("--password", required=True)

	p_role = sub.add_parser("role", help="change role")
	p_role.add_argument("--username", required=True)
	p_role.add_argument("--role", required=True, choices=["student", "admin"])

	sub.add_parser("list", help="list users")

	args = parser.parse_args(argv)
	if args.cmd == "create":
		return cmd_create(args.username, args.password, args.role)
	if args.cmd == "passwd":
		return cmd_passwd(args.username, args.password)
	if args.cmd == "role":
		return cmd_role(args.username, args.role)
	if args.cmd == "list":
		return cmd_list()
	return 0


if __name__ == "__main__":
	sys.exit(main())

