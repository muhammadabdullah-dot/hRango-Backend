"""Limits on failed sign-ins (BE-07): auth.usp_login_throttle_check decides, auth.usp_login_attempt_add
records. Shared by customer sign-in (realm "customer") and platform staff sign-in ("staff"). Kept in the
database, so every API worker and server sees the same counts."""
from app.core.db import Db
from app.core.errors import AppError


def check(db: Db, realm: str, email: str, ip_address: str | None) -> None:
    """Raises 429 TOO_MANY_ATTEMPTS, with Retry-After, while sign-in from here is paused."""
    row = db.call_one("auth.usp_login_throttle_check", realm=realm, email=email[:254], ip_address=ip_address)
    wait = int(row["retry_after_seconds"]) if row else 0
    if wait > 0:
        minutes = max(1, -(-wait // 60))
        raise AppError(429, "TOO_MANY_ATTEMPTS",
                       f"Too many failed sign-ins. Try again in {minutes} minute{'s' if minutes != 1 else ''}.",
                       headers={"Retry-After": str(wait)})


def record(db: Db, realm: str, email: str, ip_address: str | None, succeeded: bool) -> None:
    db.call("auth.usp_login_attempt_add", realm=realm, email=email[:254], ip_address=ip_address, succeeded=succeeded)
