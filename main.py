"""Local cloud server entrypoint."""

import os

import resend
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, EmailStr

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


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "resend_configured": bool(RESEND_API_KEY)}


@app.post("/send-email")
def send_email(req: EmailRequest) -> dict:
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
