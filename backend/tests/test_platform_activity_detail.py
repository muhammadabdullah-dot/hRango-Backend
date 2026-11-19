"""Test Run (18-19 Nov 2026) row 16.37: the platform Activity Log's Detail names what each staff action changed
(which organisation was suspended or reactivated, which invoice was paid, whose subscription, which lead, ticket
or staff member), instead of "—" or a bare status."""
from datetime import date, timedelta

from tests import factories
from tests.test_platform import staff
from tests.test_platform_portal import org, plan


def _details(client, headers, entity_type: str, ref) -> list[tuple[str, str | None]]:
    """(action, detail) of the log's entries for one record, newest first."""
    log = client.get("/api/platform/audit", params={"pageSize": 100}, headers=headers).json()["data"]
    return [(x["actionName"], x["detail"]) for x in log
            if x["entityType"] == entity_type and x["entityRef"] == str(ref)]


def test_activity_log_says_what_was_changed(client, db):
    me = staff(db, client)
    h = me["headers"]
    row, body = org(client, h)
    name = body["name"]

    row = client.patch(f"/api/platform/organisations/{row['id']}/status", headers=h,
                       json={"status": "suspended", "rowVersion": row["rowVersion"]}).json()["data"]
    client.patch(f"/api/platform/organisations/{row['id']}/status", headers=h,
                 json={"status": "active", "rowVersion": row["rowVersion"]})
    entries = dict(_details(client, h, "customer", row["id"]))
    assert entries["organisation_suspended"] == name and entries["organisation_active"] == name

    today = date.today()
    invoice = client.post("/api/platform/invoices", headers=h, json={
        "customerId": int(row["id"]), "issueDate": today.isoformat(),
        "dueDate": (today + timedelta(days=10)).isoformat(), "amount": 5000}).json()["data"]
    client.patch(f"/api/platform/invoices/{invoice['id']}/status", headers=h,
                 json={"status": "paid", "paymentReference": "BANK-7", "rowVersion": invoice["rowVersion"]})
    entries = dict(_details(client, h, "invoice", invoice["id"]))
    assert entries["invoice_issued"] == f"{invoice['number']} · {name}"
    assert entries["invoice_paid"] == f"{invoice['number']} · {name} · BANK-7"

    offer = plan(client, h)
    sub = client.post("/api/platform/subscriptions", headers=h, json={
        "customerId": int(row["id"]), "planId": int(offer["id"]), "billingCycle": "monthly", "status": "active",
        "startDate": today.isoformat()})
    assert sub.status_code == 201, sub.text
    assert dict(_details(client, h, "subscription", sub.json()["data"]["id"]))["subscription_added"] == \
        f"{name} · {offer['name']} · active"

    lead = client.post("/api/platform/leads", headers=h, json={
        "companyName": f"Lead {factories.tag()}", "stage": "proposal"}).json()["data"]
    assert dict(_details(client, h, "lead", lead["id"]))["lead_added"] == f"{lead['companyName']} · proposal"

    ticket = client.post("/api/platform/tickets", headers=h, json={
        "customerId": int(row["id"]), "subject": "Cannot sign in", "priority": "urgent"}).json()["data"]
    assert dict(_details(client, h, "ticket", ticket["id"]))["ticket_added"] == f"{name}: Cannot sign in · open"

    billing = staff(db, client, "billing")
    entries = dict(_details(client, h, "staff_account", billing["id"]))
    assert entries["staff_added"] == "Staff billing · billing"
    assert client.put(f"/api/platform/staff/{billing['id']}/password", headers=h,
                      json={"password": "Another-long-2026"}).status_code == 204
    assert dict(_details(client, h, "staff_account", billing["id"]))["staff_password_set"] == "Staff billing"
