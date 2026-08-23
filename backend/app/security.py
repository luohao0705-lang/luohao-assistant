from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from pwdlib import PasswordHash

from .config import get_settings

password_hash = PasswordHash.recommended()
bearer = HTTPBearer(auto_error=False)


def verify_password(password: str) -> bool:
    configured = get_settings().app_password
    if configured.startswith("$argon2"):
        return password_hash.verify(password, configured)
    # Development convenience only. Production must use an Argon2 hash.
    return password == configured


def create_access_token() -> str:
    payload = {"sub": "owner", "exp": datetime.now(timezone.utc) + timedelta(days=get_settings().jwt_expiry_days)}
    return jwt.encode(payload, get_settings().jwt_secret, algorithm="HS256")


def require_auth(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)) -> str:
    if not credentials:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="登录已失效")
    try:
        payload = jwt.decode(credentials.credentials, get_settings().jwt_secret, algorithms=["HS256"])
        if payload.get("sub") != "owner":
            raise ValueError("invalid subject")
        return "owner"
    except (JWTError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="登录已失效")
