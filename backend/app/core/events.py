"""The event catalogue: every event type modules publish (core.usp_event_publish), gathered from the
EVENTS lists in app/catalogue/<module>.py. Webhooks subscribe to an exact type, "module.*" or "*".

Payload sent to a webhook (POST, JSON):
  {"id": "<event id>", "type": "request.approved", "occurredAt": "...Z", "companyId": "1",
   "entityType": "req.request", "entityId": "42", "data": {...}}
Headers: X-HRango-Event, X-HRango-Delivery, X-HRango-Timestamp, and
X-HRango-Signature: "sha256=" + hex HMAC-SHA256(secret, "<timestamp>.<raw body>").
"""
from importlib import import_module

from app.core.permissions import MODULES


def catalogue() -> list[dict[str, str]]:
    out = []
    for module in MODULES:
        for event_type, description in getattr(import_module(f"app.catalogue.{module}"), "EVENTS", []):
            out.append({"type": event_type, "module": event_type.split(".", 1)[0], "description": description})
    return out


def valid_subscription(pattern: str) -> bool:
    types = {e["type"] for e in catalogue()}
    if pattern == "*" or pattern in types:
        return True
    return pattern.endswith(".*") and any(t.startswith(pattern[:-1]) for t in types)
