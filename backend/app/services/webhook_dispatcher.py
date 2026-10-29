"""Sends webhook deliveries: takes due ones (core.usp_webhook_due), POSTs the signed event, and records
the result (core.usp_webhook_delivery_result), which schedules retries. Runs in a background thread of
the API (settings.webhook_worker) or as its own service (scripts/webhooks.py).

The same loop sends due project reminders to the inbox once a minute (REMINDER_SECONDS); each one
becomes a notification.created event, which the next pass delivers."""
import hashlib
import hmac
import json
import logging
import threading
import time
import urllib.error
import urllib.request
from datetime import UTC, datetime

from app.core.config import settings
from app.core.db import Db, connect

log = logging.getLogger("hrango")
TIMEOUT_SECONDS = 10
REMINDER_SECONDS = 60
USER_AGENT = "HRango-Webhooks/1"


def _iso(value: datetime) -> str:
    return value.replace(tzinfo=UTC).isoformat().replace("+00:00", "Z")


def body_of(row: dict) -> bytes:
    event = {"id": str(row["event_id"]), "type": row["event_type"], "occurredAt": _iso(row["occurred_at"]),
             "companyId": str(row["company_id"]), "entityType": row["entity_type"],
             "entityId": None if row["entity_id"] is None else str(row["entity_id"]),
             "data": json.loads(row["payload"] or "{}")}
    return json.dumps(event, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def signature(secret: str, timestamp: str, body: bytes) -> str:
    mac = hmac.new(secret.encode("utf-8"), timestamp.encode("ascii") + b"." + body, hashlib.sha256)
    return "sha256=" + mac.hexdigest()


def send(row: dict) -> tuple[bool, int | None, str | None, str | None]:
    """(ok, status code, response body, error). Any 2xx is success."""
    body = body_of(row)
    timestamp = str(int(time.time()))
    req = urllib.request.Request(row["url"], data=body, method="POST", headers={
        "Content-Type": "application/json", "User-Agent": USER_AGENT, "X-HRango-Event": row["event_type"],
        "X-HRango-Delivery": str(row["id"]), "X-HRango-Timestamp": timestamp,
        "X-HRango-Signature": signature(row["secret"], timestamp, body)})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
            text = resp.read(2000).decode("utf-8", "replace")
            return 200 <= resp.status < 300, resp.status, text, None
    except urllib.error.HTTPError as exc:
        return False, exc.code, exc.read(2000).decode("utf-8", "replace"), None
    except Exception as exc:  # timeouts, refused connections, bad hosts
        return False, None, None, f"{type(exc).__name__}: {exc}"[:1000]


def dispatch_once(db: Db, batch: int = 20) -> int:
    """Sends what is due now. Returns how many deliveries were attempted."""
    rows = db.call("core.usp_webhook_due", batch=batch)
    for row in rows:
        ok, code, text, error = send(row)
        db.call("core.usp_webhook_delivery_result", id=row["id"], ok=ok, response_code=code, response_body=text,
                error=error)
        if not ok:
            log.warning("webhook %s delivery %s failed (%s %s)", row["webhook_id"], row["id"], code, error or "")
    return len(rows)


def remind_once(db: Db) -> int:
    """Sends the project reminders that are due (Project Management -> Remind Me)."""
    from app.services.projects_collab_service import deliver_due_reminders

    return deliver_due_reminders(db)


def run_forever(stop: threading.Event, poll_seconds: int) -> None:
    last_reminders = 0.0
    while not stop.is_set():
        try:
            conn = connect()
            try:
                db = Db(conn)
                if time.monotonic() - last_reminders >= REMINDER_SECONDS:
                    last_reminders = time.monotonic()
                    try:
                        remind_once(db)
                    except Exception:
                        log.exception("project reminders pass failed")
                while dispatch_once(db) and not stop.is_set():
                    pass
            finally:
                conn.close()
        except Exception:
            log.exception("webhook worker pass failed")
        stop.wait(poll_seconds)


class Worker:
    """The background thread the API starts when settings.webhook_worker is on."""

    def __init__(self) -> None:
        self.stop = threading.Event()
        self.thread = threading.Thread(target=run_forever, args=(self.stop, settings.webhook_poll_seconds),
                                       name="webhook-worker", daemon=True)

    def start(self) -> None:
        self.thread.start()

    def close(self) -> None:
        self.stop.set()
        self.thread.join(timeout=TIMEOUT_SECONDS + 2)
