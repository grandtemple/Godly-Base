"""Auth: operator login (JWT) and the agent service-token guard.

One operator today -- the CEO seat, in godly.operators (db/migrations/0010_auth.sql).
Client-facing logins, SSO, and per-deployment RBAC are explicitly out of
scope here -- see docs/ROADMAP.md Phase 2 and Phase 13.
"""
from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
import psycopg
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

JWT_ALGORITHM = "HS256"
JWT_EXPIRES_HOURS = 24

bearer_scheme = HTTPBearer(auto_error=False)


def _jwt_secret() -> str:
    secret = os.getenv("AUTH_JWT_SECRET")
    if not secret:
        raise HTTPException(status_code=503, detail="AUTH_JWT_SECRET is not set")
    return secret


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, password_hash: str) -> bool:
    return bcrypt.checkpw(password.encode(), password_hash.encode())


def create_access_token(operator_id: int, email: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(operator_id),
        "email": email,
        "iat": now,
        "exp": now + timedelta(hours=JWT_EXPIRES_HOURS),
    }
    return jwt.encode(payload, _jwt_secret(), algorithm=JWT_ALGORITHM)


def get_db_connection() -> psycopg.Connection:
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise HTTPException(status_code=503, detail="DATABASE_URL is not set")
    return psycopg.connect(database_url)


def authenticate_operator(email: str, password: str) -> dict | None:
    """Verify email+password against godly.operators. None on any failure --
    the caller doesn't get to distinguish 'no such email' from 'wrong
    password', which is the point."""
    with get_db_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT id, email, password_hash, display_name, is_active "
            "FROM godly.operators WHERE email = %s",
            (email,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        operator_id, operator_email, password_hash, display_name, is_active = row
        if not is_active or not verify_password(password, password_hash):
            return None
        cur.execute(
            "UPDATE godly.operators SET last_login_at = now() WHERE id = %s",
            (operator_id,),
        )
        conn.commit()
        return {"id": operator_id, "email": operator_email, "display_name": display_name}


def require_operator(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict:
    """FastAPI dependency: the caller must present a valid operator JWT."""
    if credentials is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    try:
        payload = jwt.decode(credentials.credentials, _jwt_secret(), algorithms=[JWT_ALGORITHM])
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return {"principal": "operator", "id": int(payload["sub"]), "email": payload["email"]}


def require_operator_or_agent(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict:
    """FastAPI dependency: accept either a valid operator JWT, or the shared
    agent service token (AGENT_SERVICE_TOKEN) for agent-originated calls.
    This is deliberately a single shared token, not per-agent credentials --
    proportionate to Phase 2/6's scope of one narrow capability, not the full
    21-agent roster. Revisit if/when that roster actually runs (Phase 9)."""
    if credentials is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    agent_token = os.getenv("AGENT_SERVICE_TOKEN")
    if agent_token and credentials.credentials == agent_token:
        return {"principal": "agent"}
    try:
        payload = jwt.decode(credentials.credentials, _jwt_secret(), algorithms=[JWT_ALGORITHM])
        return {"principal": "operator", "id": int(payload["sub"]), "email": payload["email"]}
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
