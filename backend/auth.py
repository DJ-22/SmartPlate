import os
from datetime import datetime, timedelta
from typing import Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from passlib.context import CryptContext

SECRET_KEY = os.getenv("JWT_SECRET")
if not SECRET_KEY:
    raise RuntimeError("JWT_SECRET environment variable must be set (see .env.example)")
ALGORITHM  = "HS256"
TOKEN_EXP_HOURS = 24

pwd_ctx   = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer    = HTTPBearer()

def hash_password(plain: str) -> str:
    return pwd_ctx.hash(plain)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_ctx.verify(plain, hashed)

def create_token(user_id: int, role: str, supplier_id: int = 0) -> str:
    payload = {
        "user_id":     user_id,
        "role":        role,
        "supplier_id": supplier_id,
        "exp":         datetime.utcnow() + timedelta(hours=TOKEN_EXP_HOURS),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)

def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")

def get_current_user(creds: HTTPAuthorizationCredentials = Depends(bearer)) -> dict:
    return decode_token(creds.credentials)

def require_role(*roles: str):
    # NOTE: managers bypass all role checks by design (superuser for this project).
    # If you need stricter separation, remove the first branch below.
    def dependency(user: dict = Depends(get_current_user)) -> dict:
        if user["role"] == "manager":
            return user
        if user["role"] in roles:
            return user
        raise HTTPException(status_code=403, detail="Forbidden")
    return dependency
