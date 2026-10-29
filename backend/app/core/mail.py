"""Outgoing mail. Not set up yet (settings.mail_enabled is false): callers record what would be sent
and report the status "disabled". The SMTP sender will live here."""
from app.core.config import settings


def enabled() -> bool:
    return settings.mail_enabled
