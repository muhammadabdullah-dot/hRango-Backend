"""Webhooks: subscriptions, the outbox, signed delivery, retries and redelivery."""
import hashlib
import hmac
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from app.core import outbound
from app.core.config import settings
from app.services.webhook_dispatcher import dispatch_once
from tests import factories


class Receiver:
    """A local HTTP endpoint that records what it is sent and answers with `status`."""

    def __init__(self):
        self.received: list[dict] = []
        self.status = 200
        self.location = ""
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                body = self.rfile.read(int(self.headers["Content-Length"]))
                outer.received.append({"headers": {k.lower(): v for k, v in self.headers.items()}, "body": body})
                self.send_response(outer.status)
                if outer.location:
                    self.send_header("Location", outer.location)
                self.end_headers()
                self.wfile.write(b"internal secret page")

            def log_message(self, *args):
                pass

        self.server = HTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}/hook"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self, db) -> None:
        """Stops listening and switches off the webhooks that point here. Left on, every later notification in
        the shared test company would queue a delivery to a dead port, and any later flush would wait on them."""
        self.server.shutdown()
        self.server.server_close()
        switch_off_webhooks(db, self.url)


def switch_off_webhooks(db, url_pattern: str) -> None:
    cur = db.conn.cursor()
    try:
        cur.execute("UPDATE core.webhook SET is_active = 0 WHERE url LIKE ? AND is_active = 1", url_pattern)
    finally:
        cur.close()


@pytest.fixture()
def receiver(monkeypatch, db):
    # The receiver listens on 127.0.0.1, which webhooks may only call with WEBHOOK_ALLOW_PRIVATE (development).
    monkeypatch.setattr(settings, "webhook_allow_private", True)
    r = Receiver()
    yield r
    r.close(db)


def _flush(db) -> int:
    total = 0
    while n := dispatch_once(db):
        total += n
    return total


def test_notification_reaches_webhook_signed(client, db, company, admin, receiver):
    h = admin["headers"]
    created = client.post("/api/integrations/webhooks", json={"name": f"Chat {factories.tag()}", "url": receiver.url,
                                                              "events": ["notification.*"]}, headers=h)
    assert created.status_code == 201, created.text
    hook = created.json()["data"]
    secret = hook["secret"]
    assert secret.startswith("whsec_") and hook["secretHint"].endswith(secret[-4:])
    assert "secret" not in client.get(f"/api/integrations/webhooks/{hook['id']}", headers=h).json()["data"]

    emp = factories.employee(db, company, first_name="Sana")
    factories.user(db, company, employee_id=emp)
    db.call("core.usp_notification_add_employee", company_id=company, employee_id=emp, title="Leave approved",
            body="Your leave for 3 days was approved.", notification_type="request", link="/requests/leave/7")
    _flush(db)

    assert len(receiver.received) == 1
    got = receiver.received[0]
    event = json.loads(got["body"])
    assert got["headers"]["x-hrango-event"] == "notification.created"
    assert event["type"] == "notification.created" and event["data"]["title"] == "Leave approved"
    assert event["data"]["employeeId"] == str(emp) and event["companyId"] == str(company)
    expected = hmac.new(secret.encode(), got["headers"]["x-hrango-timestamp"].encode() + b"." + got["body"],
                        hashlib.sha256).hexdigest()
    assert got["headers"]["x-hrango-signature"] == f"sha256={expected}"

    deliveries = client.get(f"/api/integrations/webhooks/{hook['id']}/deliveries", headers=h).json()
    assert deliveries["data"][0]["status"] == "delivered" and deliveries["data"][0]["responseCode"] == 200


def test_failures_retry_and_redeliver(client, db, admin, receiver):
    h = admin["headers"]
    hook = client.post("/api/integrations/webhooks", json={"name": f"Flaky {factories.tag()}", "url": receiver.url,
                                                           "events": ["webhook.ping"]}, headers=h).json()["data"]
    receiver.status = 500
    ping = client.post(f"/api/integrations/webhooks/{hook['id']}/ping", headers=h)
    assert ping.status_code == 202
    _flush(db)
    d = client.get(f"/api/integrations/webhooks/{hook['id']}/deliveries", headers=h).json()["data"][0]
    assert d["status"] == "pending" and d["attempts"] == 1 and d["responseCode"] == 500 and d["nextAttemptAt"]
    assert client.get(f"/api/integrations/webhooks/{hook['id']}", headers=h).json()["data"]["failureCount"] == 1

    receiver.status = 200
    assert client.post(f"/api/integrations/webhooks/deliveries/{d['id']}/redeliver", headers=h).status_code == 202
    _flush(db)
    d = client.get(f"/api/integrations/webhooks/{hook['id']}/deliveries", headers=h).json()["data"][0]
    assert d["status"] == "delivered"
    assert len(receiver.received) == 2


def test_subscriptions_and_edits(client, db, company, admin, receiver):
    h = admin["headers"]
    bad = client.post("/api/integrations/webhooks", json={"name": "x", "url": receiver.url, "events": ["no.such"]},
                      headers=h)
    assert bad.status_code == 422 and "events" in bad.json()["fieldErrors"]
    assert client.post("/api/integrations/webhooks", json={"name": "x", "url": "ftp://x", "events": ["*"]},
                       headers=h).status_code == 422
    hook = client.post("/api/integrations/webhooks", json={"name": f"Off {factories.tag()}", "url": receiver.url,
                                                           "events": ["*"], "isActive": False}, headers=h).json()["data"]
    db.call("core.usp_event_publish", company_id=company, event_type="notification.created", payload="{}")
    _flush(db)
    assert receiver.received == []  # an inactive webhook gets nothing

    rotated = client.post(f"/api/integrations/webhooks/{hook['id']}/rotate-secret",
                          json={"rowVersion": hook["rowVersion"]}, headers=h).json()["data"]
    assert rotated["secret"] != hook["secret"]
    assert client.put(f"/api/integrations/webhooks/{hook['id']}", json={"name": "x", "url": receiver.url,
                      "events": ["*"], "rowVersion": hook["rowVersion"]}, headers=h).status_code == 409
    assert client.delete(f"/api/integrations/webhooks/{hook['id']}", params={"rowVersion": rotated["rowVersion"]},
                         headers=h).status_code == 204
    types = {e["type"] for e in client.get("/api/integrations/events", headers=h).json()["data"]}
    assert {"notification.created", "webhook.ping"} <= types


def test_only_administrators(client, db, company):
    hr = factories.login_as(db, client, company, role_codes="hr_manager")
    assert client.get("/api/integrations/webhooks", headers=hr["headers"]).status_code == 403


# ---------------------------------------------------------------- BE-03: no requests into private networks

@pytest.mark.parametrize("url", [
    "http://127.0.0.1:8000/hook",
    "http://10.0.0.5/hook",
    "http://172.20.0.1/hook",
    "http://192.168.0.10/hook",
    "http://169.254.169.254/latest/meta-data",
    "http://100.64.0.1/hook",
    "http://[::1]/hook",
    "http://[::ffff:127.0.0.1]/hook",
    "http://[fd00::1]/hook",
    "http://0.0.0.0/hook",
    "http://localhost/hook",
])
def test_internal_addresses_are_blocked(url):
    with pytest.raises(outbound.BlockedAddress):
        outbound.check_url(url)


@pytest.mark.parametrize("url, words", [
    ("ftp://93.184.215.14/x", "http:// or https://"),
    ("https://user:pass@93.184.215.14/x", "credentials"),
    ("https:///nohost", "host name"),
    ("http://93.184.215.14/x", "https://"),
])
def test_malformed_or_unsafe_urls_are_refused(url, words):
    with pytest.raises(outbound.BlockedAddress) as refused:
        outbound.check_url(url, require_https=True)
    assert words in str(refused.value)


def test_public_addresses_are_allowed():
    assert outbound.check_url("https://93.184.215.14/hook").hostname == "93.184.215.14"


def test_saving_a_private_address_is_refused(client, admin):
    r = client.post("/api/integrations/webhooks", json={"name": f"Inside {factories.tag()}",
                    "url": "http://169.254.169.254/latest/meta-data", "events": ["*"]}, headers=admin["headers"])
    assert r.status_code == 422
    assert "private or internal" in r.json()["fieldErrors"]["url"]


def test_delivery_is_checked_again_when_sent(client, db, admin, receiver, monkeypatch):
    """A URL that was fine when saved is refused at delivery time once it points inside (DNS rebinding)."""
    h = admin["headers"]
    hook = client.post("/api/integrations/webhooks", json={"name": f"Rebind {factories.tag()}", "url": receiver.url,
                                                           "events": ["webhook.ping"]}, headers=h).json()["data"]
    monkeypatch.setattr(settings, "webhook_allow_private", False)
    client.post(f"/api/integrations/webhooks/{hook['id']}/ping", headers=h)
    _flush(db)
    assert receiver.received == []
    d = client.get(f"/api/integrations/webhooks/{hook['id']}/deliveries", headers=h).json()["data"][0]
    assert d["responseCode"] is None and d["error"].startswith("Blocked:")


def test_redirects_are_not_followed_and_replies_not_kept(client, db, admin, receiver):
    h = admin["headers"]
    hook = client.post("/api/integrations/webhooks", json={"name": f"Hop {factories.tag()}", "url": receiver.url,
                                                           "events": ["webhook.ping"]}, headers=h).json()["data"]
    receiver.status, receiver.location = 302, "http://169.254.169.254/latest/meta-data"
    client.post(f"/api/integrations/webhooks/{hook['id']}/ping", headers=h)
    _flush(db)
    assert len(receiver.received) == 1  # sent once, the redirect was not followed
    d = client.get(f"/api/integrations/webhooks/{hook['id']}/deliveries", headers=h).json()["data"][0]
    assert d["status"] == "pending" and d["responseCode"] == 302 and "Redirects are not followed" in d["error"]
    assert "responseBody" not in d
    cur = db.conn.cursor()
    try:
        stored = cur.execute("SELECT response_body FROM core.webhook_delivery WHERE id = ?", int(d["id"])).fetchval()
    finally:
        cur.close()
    assert stored is None  # "internal secret page" was not kept


def test_unreachable_receiver_error_is_coarse(client, db, admin, receiver):
    h = admin["headers"]
    port = receiver.server.server_address[1]
    receiver.server.shutdown()
    receiver.server.server_close()
    hook = client.post("/api/integrations/webhooks", json={"name": f"Gone {factories.tag()}",
                       "url": f"http://127.0.0.1:{port}/hook", "events": ["webhook.ping"]}, headers=h).json()["data"]
    client.post(f"/api/integrations/webhooks/{hook['id']}/ping", headers=h)
    _flush(db)
    d = client.get(f"/api/integrations/webhooks/{hook['id']}/deliveries", headers=h).json()["data"][0]
    assert d["error"] in ("The receiver refused the connection.", "The receiver could not be reached.",
                          "No answer within the time limit.")
