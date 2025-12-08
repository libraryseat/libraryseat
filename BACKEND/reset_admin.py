
import sys
import os
from pathlib import Path
from sqlalchemy.orm import Session

# Add the current directory to sys.path so we can import from backend
sys.path.append(os.getcwd())

from backend.db import SessionLocal, engine
from backend.models import User, Base
from backend.auth import get_password_hash

def reset_admin_password():
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.username == "admin").first()
        if not user:
            print("Admin user not found, creating one...")
            user = User(username="admin", role="admin")
            db.add(user)
        
        new_password = "123456"
        hashed = get_password_hash(new_password)
        user.pass_hash = hashed
        
        db.commit()
        print(f"Successfully reset password for user 'admin' to '{new_password}'")
        print(f"New Hash: {hashed}")
    except Exception as e:
        print(f"Error: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    reset_admin_password()

