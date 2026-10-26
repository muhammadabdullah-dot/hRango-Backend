"""Webhooks: subscriptions, the outbox, signed delivery, retries and redelivery."""
import hashlib
import hmac
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from app.services.webhook_dispatcher import dispatch_once
from tests import factories


class Receiver:
    """A local HTTP endpoint that records what it is sent and answers with `status`."""

    def __init__(self):
        self.received: list[dict] = []
        self.status = 200
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                body = self.rfile.read(int(self.headers["Content-Length"]))
                outer.received.append({"headers": {k.lower(): v for k, v in self.headers.items()}, "body": body})
                self.send_response(outer.status)
                self.end_headers()
                self.wfile.write(b"ok")

            def log_message(self, *args):
                pass

        self.server = HTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}/hook"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()


@pytest.fixture()
def receiver():
    r = Receiver()
    yield r
    r.server.shutdown()


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
