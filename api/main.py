"""Local cloud server entrypoint."""

import os

import resend
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel, EmailStr

from . import auth

load_dotenv()

RESEND_API_KEY = os.getenv("RESEND_API_KEY")
if RESEND_API_KEY:
    resend.api_key = RESEND_API_KEY

app = FastAPI(title="Godly-Base local cloud server")


class EmailRequest(BaseModel):
    to: EmailStr
    subject: str
    html: str
    sender: str = "onboarding@resend.dev"


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "resend_configured": bool(RESEND_API_KEY)}


@app.post("/auth/login")
def login(req: LoginRequest) -> dict:
    operator = auth.authenticate_operator(req.email, req.password)
    if operator is None:
        raise HTTPException(status_code=401, detail="Invalid email or password")
    token = auth.create_access_token(operator["id"], operator["email"])
    return {"access_token": token, "token_type": "bearer", "operator": operator}


@app.get("/auth/me")
def me(principal: dict = Depends(auth.require_operator)) -> dict:
    return principal


@app.post("/send-email")
def send_email(
    req: EmailRequest, principal: dict = Depends(auth.require_operator_or_agent)
) -> dict:
    if not RESEND_API_KEY:
        raise HTTPException(status_code=503, detail="RESEND_API_KEY is not set")
    result = resend.Emails.send(
        {
            "from": req.sender,
            "to": req.to,
            "subject": req.subject,
            "html": req.html,
        }
    )
    return {"sent": True, "id": result.get("id")}
