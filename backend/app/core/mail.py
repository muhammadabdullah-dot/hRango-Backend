"""Outgoing mail (roadmap 1.4).

Callers queue a message (`queue`); the worker (the API's background thread or scripts/webhooks.py, see
app/services/webhook_dispatcher.py) sends what is due (`deliver_due`) and retries failures. Nothing is sent
inside a web request, so a slow mail server never slows the app.

Two backends (settings.mail_backend):
- smtp: any provider (Amazon SES, SendGrid, Mailgun, Microsoft 365 and Gmail all speak SMTP), STARTTLS on
  587 or TLS on 465.
- file: each message is written as an .eml file to settings.mail_file_dir (development and tests), with an .html
  copy beside it that a browser opens with working links.

With mail off (settings.mail_enabled false) a message is recorded as "disabled" and never sent.
"""
import html
import logging
import smtplib
import ssl
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from email.message import EmailMessage
from email.utils import formataddr, format_datetime, make_msgid, parseaddr
from pathlib import Path

from app.core.config import settings
from app.core.db import Db

log = logging.getLogger("hrango")


def enabled() -> bool:
    return settings.mail_enabled


@dataclass
class Message:
    to_address: str
    subject: str
    body_html: str
    body_text: str | None = None
    to_name: str | None = None
    id: int | None = None


def queue(db: Db, *, kind: str, to_address: str, subject: str, body_html: str, body_text: str | None = None,
          to_name: str | None = None, company_id: int | None = None, actor_id: int | None = None) -> dict:
    """Records a message for the worker to send: {"id", "status"} with status "queued", or "disabled" when
    mail is off."""
    return db.call_one("core.usp_mail_queue", company_id=company_id, kind=kind, to_address=to_address,
                       to_name=to_name, subject=subject, body_html=body_html, body_text=body_text,
                       status="queued" if enabled() else "disabled", actor_id=actor_id)


def build(message: Message) -> EmailMessage:
    mail = EmailMessage()
    sender_name, sender_address = parseaddr(settings.mail_from)
    mail["From"] = formataddr((sender_name, sender_address)) if sender_name else sender_address
    mail["To"] = formataddr((message.to_name, message.to_address)) if message.to_name else message.to_address
    if settings.mail_reply_to:
        mail["Reply-To"] = settings.mail_reply_to
    mail["Subject"] = message.subject
    mail["Date"] = format_datetime(datetime.now(UTC))
    mail["Message-ID"] = make_msgid(domain=(sender_address.split("@", 1)[-1] or "hrango.local"))
    # Transactional mail: tell auto-responders not to answer.
    mail["Auto-Submitted"] = "auto-generated"
    mail.set_content(message.body_text or "Open this message in a mail program that shows HTML.")
    mail.add_alternative(message.body_html, subtype="html")
    return mail


def _as_page(mail: EmailMessage, message: Message) -> str:
    """The file backend's .html copy: who it is to, the subject and date, then the message's own HTML."""
    head = "".join(
        f"<div><b>{label}:</b> {html.escape(str(mail[label] or ''))}</div>" for label in ("To", "Subject", "Date")
    )
    return (
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        f"<title>{html.escape(message.subject)}</title></head><body>"
        '<div style="font:13px/1.6 system-ui,sans-serif;color:#334155;background:#f1f5f9;padding:12px 16px;'
        f'border-bottom:1px solid #cbd5e1">{head}</div>'
        f"{message.body_html}</body></html>"
    )


def send(message: Message) -> None:
    """Sends one message now through the configured backend; raises on failure."""
    mail = build(message)
    if settings.mail_backend == "file":
        folder = Path(settings.mail_file_dir or Path(__file__).resolve().parents[2] / "mail-outbox")
        folder.mkdir(parents=True, exist_ok=True)
        stem = f"{datetime.now(UTC).strftime('%Y%m%dT%H%M%S')}-{message.id or uuid.uuid4().hex[:8]}"
        (folder / f"{stem}.eml").write_bytes(bytes(mail))
        # The same message as a page a browser opens: an .eml keeps long lines encoded, so a link copied out of it
        # breaks; this page's links work as they would in a mail program.
        (folder / f"{stem}.html").write_text(_as_page(mail, message), encoding="utf-8")
        return
    context = ssl.create_default_context()
    timeout = settings.smtp_timeout_seconds
    if settings.smtp_ssl:
        server: smtplib.SMTP = smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, timeout=timeout, context=context)
    else:
        server = smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=timeout)
    with server:
        server.ehlo()
        if settings.smtp_starttls and not settings.smtp_ssl:
            server.starttls(context=context)
            server.ehlo()
        if settings.smtp_username:
            server.login(settings.smtp_username, settings.smtp_password)
        server.send_message(mail)


def _error_text(exc: Exception) -> str:
    if isinstance(exc, smtplib.SMTPRecipientsRefused):
        return "The mail server refused the recipient address."
    if isinstance(exc, smtplib.SMTPAuthenticationError):
        return "The mail server refused the sign-in (check SMTP_USERNAME and SMTP_PASSWORD)."
    if isinstance(exc, smtplib.SMTPResponseException):
        return f"The mail server answered {exc.smtp_code}."
    if isinstance(exc, (TimeoutError, OSError)):
        return "The mail server could not be reached."
    return type(exc).__name__


def deliver_due(db: Db, batch: int = 20) -> int:
    """Sends what is due now; returns how many were attempted. Does nothing while mail is off."""
    if not enabled():
        return 0
    rows = db.call("core.usp_mail_due", batch=batch)
    for row in rows:
        try:
            send(Message(id=row["id"], to_address=row["to_address"], to_name=row["to_name"], subject=row["subject"],
                         body_html=row["body_html"] or "", body_text=row["body_text"]))
            db.call("core.usp_mail_result", id=row["id"], ok=True, error=None)
        except Exception as exc:  # noqa: BLE001 - every failure is recorded and retried
            log.warning("mail %s to %s failed: %s", row["id"], row["to_address"], exc)
            db.call("core.usp_mail_result", id=row["id"], ok=False, error=_error_text(exc))
        _tell_owner(db, row)
    return len(rows)


# Modules that keep their own record of a message's state: kind -> procedure taking @mail_message_id, called after
# each result. Payroll: pay.mail_outbox and the run's close e-mail (app/services/payroll_mail_service.py).
RESULT_OWNERS = {"payroll_close": "pay.usp_mail_outbox_result", "salary_revision": "pay.usp_mail_outbox_result"}


def _tell_owner(db: Db, row: dict) -> None:
    proc = RESULT_OWNERS.get(row["kind"])
    if proc is None:
        return
    try:
        db.call(proc, mail_message_id=row["id"])
    except Exception:  # noqa: BLE001 - the message's own state is recorded; the owner's copy must not stop the pass
        log.exception("mail %s: %s failed", row["id"], proc)
