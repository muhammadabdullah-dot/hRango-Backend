"""Password reset and invitations by e-mail (roadmap 1.5).

- Forgot password: anyone may ask; the answer is the same whether or not the email has an account, and
  asking is limited like signing in (app/core/login_throttle.py, realm "password_reset").
- Invitations: an administrator adds a user without typing a password and the user sets their own.
- Links carry a random token after "#" (the browser never sends that part to a server, so it stays out of
  logs and Referer headers). Only the token's SHA-256 is stored. Reset links last an hour, invitations a
  week; a newer link replaces an older one; using a link ends every open session of the account.
"""
import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from typing import Any

from app.core import login_throttle, mail
from app.core.config import settings
from app.core.db import Db
from app.core.errors import AppError, invalid
from app.core.mail_templates import Button, render
from app.core.security import hash_password, password_problem
from app.middlewares.auth import RequestContext

RESET_MINUTES = 60
INVITE_DAYS = 7
# Not an scrypt hash, so no password matches it: an invited account cannot sign in until it is accepted.
UNUSABLE_PASSWORD = "!invited"

_MAIL_OFF = AppError(503, "MAIL_UNAVAILABLE",
                     "E-mail is not set up on this server, so links cannot be sent. Ask your administrator to set "
                     "a password for you.")


def _new_token() -> tuple[str, str]:
    token = secrets.token_urlsafe(32)
    return token, digest_of(token)


def digest_of(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _link(path: str, token: str) -> str:
    return f"{settings.app_public_url.rstrip('/')}{path}#token={token}"


def _refuse(state: str) -> AppError:
    if state == "used":
        return AppError(410, "LINK_USED", "This link has already been used. Ask for a new one.")
    if state == "expired":
        return AppError(410, "LINK_EXPIRED", "This link has expired. Ask for a new one.")
    return AppError(404, "LINK_NOT_FOUND", "This link is not valid. Ask for a new one.")


# ---------------------------------------------------------------- forgot password

def request_reset(db: Db, email: str, ip_address: str | None) -> None:
    if not mail.enabled():
        raise _MAIL_OFF
    email = email.strip().lower()
    if settings.login_throttle:
        login_throttle.check(db, "password_reset", email, ip_address)
        login_throttle.record(db, "password_reset", email, ip_address, False)
    token, digest = _new_token()
    row = db.call_one("auth.usp_password_reset_request", email=email, token_hash=digest, minutes=RESET_MINUTES)
    if row is None:
        return  # same answer as for a real account
    html, text = render(
        title="Reset your password",
        paragraphs=[f"Hello {row['name']},",
                    f"Someone asked to reset the password of your {row['company_name']} account on hRango. "
                    "If it was you, choose a new password with the button below."],
        button=Button("Choose a new password", _link("/reset-password", token)),
        after=[f"The link works once, for {RESET_MINUTES} minutes.",
               "If you did not ask for this, ignore this e-mail: your password stays as it is."],
        company_name=row["company_name"])
    mail.queue(db, kind="password_reset", to_address=row["email"], to_name=row["name"],
               subject="Reset your hRango password", body_html=html, body_text=text, company_id=row["company_id"],
               actor_id=row["user_id"])


def reset_password(db: Db, token: str, password: str) -> str:
    """Sets the password from a reset link; returns the account's email (the sign-in page fills it in)."""
    return _use(db, token, "password_reset", password)


# ---------------------------------------------------------------- invitations

def invite(db: Db, ctx: RequestContext, user_id: int) -> dict[str, Any]:
    if not mail.enabled():
        raise _MAIL_OFF
    token, digest = _new_token()
    row = db.call_one("auth.usp_invite_create", company_id=ctx.company_id, actor_user_id=ctx.user_id, id=user_id,
                      token_hash=digest, days=INVITE_DAYS)
    html, text = render(
        title=f"You're invited to {row['company_name']}",
        paragraphs=[f"Hello {row['name']},",
                    f"{row['invited_by']} has given you an account for {row['company_name']} on hRango, where you "
                    "can see your attendance, leave, requests and pay slips.",
                    f"You sign in with this e-mail address: {row['email']}. Choose your password to start."],
        button=Button("Choose your password", _link("/accept-invite", token)),
        after=[f"The invitation is valid for {INVITE_DAYS} days and works once."],
        company_name=row["company_name"])
    queued = mail.queue(db, kind="invite", to_address=row["email"], to_name=row["name"],
                        subject=f"Your {row['company_name']} account on hRango", body_html=html, body_text=text,
                        company_id=ctx.company_id, actor_id=ctx.user_id)
    return {"sent_to": row["email"], "expires_at": datetime.now(UTC).replace(microsecond=0) + timedelta(days=INVITE_DAYS),
            "status": queued["status"]}


def accept_invite(db: Db, token: str, password: str) -> str:
    return _use(db, token, "invite", password)


# ---------------------------------------------------------------- shared

def inspect(db: Db, token: str) -> dict[str, Any]:
    row = db.call_one("auth.usp_user_token_inspect", token_hash=digest_of(token))
    if row is None or row["state"] != "ok":
        raise _refuse(row["state"] if row else "not_found")
    return {"purpose": row["purpose"], "email": row["email"], "company_name": row["company_name"],
            "expires_at": row["expires_at"]}


def _use(db: Db, token: str, purpose: str, password: str) -> str:
    problem = password_problem(password)
    if problem:
        raise invalid(problem, "password")
    row = db.call_one("auth.usp_user_token_use", token_hash=digest_of(token), purpose=purpose,
                      password_hash=hash_password(password))
    if row is None or row["state"] != "ok":
        raise _refuse(row["state"] if row else "not_found")
    return row["email"]
