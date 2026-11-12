"""The staff portal: organisations, plans, subscriptions, invoices, the sales pipeline and support, and who may do what."""
from datetime import date, timedelta

from tests import factories
from tests.test_platform import staff

OWNER_PASSWORD = "Owner@2026"


def org(client, headers, **extra) -> tuple[dict, dict]:
    t = factories.tag()
    owner = {"ownerName": "Owner One", "ownerEmail": f"owner.{t}@org.test", "ownerPassword": OWNER_PASSWORD}
    body = {"name": f"Org {t}", "contactEmail": f"contact.{t}@org.test", **owner, **extra}
    r = client.post("/api/platform/organisations", headers=headers, json=body)
    assert r.status_code == 201, r.text
    return r.json()["data"], body


def plan(client, headers) -> dict:
    r = client.post("/api/platform/plans", headers=headers, json={
        "name": f"Plan {factories.tag()}", "priceMonthly": 1000, "priceAnnual": 12000, "employeeLimit": 10})
    assert r.status_code == 201, r.text
    return r.json()["data"]


def test_registering_makes_a_working_organisation(client, db):
    me = staff(db, client)
    offer = plan(client, me["headers"])
    row, body = org(client, me["headers"], planId=int(offer["id"]))
    assert row["status"] == "active" and row["companyCount"] == 1
    assert row["planName"] == offer["name"] and row["subscriptionStatus"] == "trial"

    login = client.post("/api/auth/login", json={"email": body["ownerEmail"], "password": OWNER_PASSWORD})
    assert login.status_code == 200, login.text
    who = client.get("/api/auth/me", headers={"Authorization": f"Bearer {login.json()['data']['token']}"}).json()["data"]
    assert who["role"] == "Account Owner" and who["companyName"] == body["name"]

    companies = client.get(f"/api/platform/organisations/{row['id']}/companies", headers=me["headers"]).json()["data"]
    assert [c["name"] for c in companies] == [body["name"]]


def test_registering_cannot_take_over_what_exists(client, db):
    me = staff(db, client)
    _, first = org(client, me["headers"])
    same_name = {**first, "ownerEmail": f"other.{factories.tag()}@org.test"}
    r = client.post("/api/platform/organisations", headers=me["headers"], json=same_name)
    assert r.status_code == 409 and r.json()["code"] == "CUSTOMER_DUPLICATE"

    same_owner = {**first, "name": f"Org {factories.tag()}", "ownerPassword": "Stolen@2026"}
    r = client.post("/api/platform/organisations", headers=me["headers"], json=same_owner)
    assert r.status_code == 409 and r.json()["code"] == "OWNER_EMAIL_TAKEN"
    # The first owner's password still works, and the refused company was not left behind.
    assert client.post("/api/auth/login", json={"email": first["ownerEmail"], "password": OWNER_PASSWORD}).status_code == 200
    assert client.post("/api/auth/login", json={"email": first["ownerEmail"], "password": "Stolen@2026"}).status_code == 401
    assert client.get("/api/platform/organisations", headers=me["headers"], params={"q": same_owner["name"]}).json()["data"] == []


def test_a_failed_registration_leaves_nothing_behind(client, db):
    me = staff(db, client)
    t = factories.tag()
    r = client.post("/api/platform/organisations", headers=me["headers"], json={
        "name": f"Org {t}", "contactEmail": f"c.{t}@org.test", "ownerName": "Owner", "ownerEmail": f"o.{t}@org.test",
        "ownerPassword": OWNER_PASSWORD, "planId": 999999999})
    assert r.status_code == 422
    assert db.call("plat.usp_customer_list", search=f"Org {t}", status=None, page=1, page_size=5) == [{"total": 0}]
    assert client.post("/api/auth/login", json={"email": f"o.{t}@org.test", "password": OWNER_PASSWORD}).status_code == 401


def test_suspending_stops_sign_in_and_open_sessions(client, db):
    me = staff(db, client)
    row, body = org(client, me["headers"])
    login = client.post("/api/auth/login", json={"email": body["ownerEmail"], "password": OWNER_PASSWORD})
    owner = {"Authorization": f"Bearer {login.json()['data']['token']}"}
    assert client.get("/api/auth/me", headers=owner).status_code == 200

    row = client.patch(f"/api/platform/organisations/{row['id']}/status", headers=me["headers"],
                       json={"status": "suspended", "rowVersion": row["rowVersion"]}).json()["data"]
    assert row["status"] == "suspended"
    assert client.get("/api/auth/me", headers=owner).status_code == 401
    r = client.post("/api/auth/login", json={"email": body["ownerEmail"], "password": OWNER_PASSWORD})
    assert r.status_code == 403 and r.json()["code"] == "ORGANISATION_SUSPENDED"

    client.patch(f"/api/platform/organisations/{row['id']}/status", headers=me["headers"],
                 json={"status": "active", "rowVersion": row["rowVersion"]})
    assert client.post("/api/auth/login", json={"email": body["ownerEmail"], "password": OWNER_PASSWORD}).status_code == 200


def test_an_organisation_has_one_live_subscription(client, db):
    me = staff(db, client)
    offer = plan(client, me["headers"])
    row, _ = org(client, me["headers"])
    today = date.today().isoformat()
    body = {"customerId": int(row["id"]), "planId": int(offer["id"]), "billingCycle": "annual", "status": "active",
            "startDate": today}
    first = client.post("/api/platform/subscriptions", headers=me["headers"], json=body)
    assert first.status_code == 201 and first.json()["data"]["amount"] == 12000
    second = client.post("/api/platform/subscriptions", headers=me["headers"], json=body)
    assert second.status_code == 409 and second.json()["code"] == "SUBSCRIPTION_EXISTS"

    data = first.json()["data"]
    done = client.put(f"/api/platform/subscriptions/{data['id']}", headers=me["headers"], json={
        **body, "status": "cancelled", "rowVersion": data["rowVersion"]})
    assert done.status_code == 200 and done.json()["data"]["cancelledOn"] == today
    assert client.post("/api/platform/subscriptions", headers=me["headers"], json=body).status_code == 201


def test_invoices_go_overdue_and_close_once(client, db):
    me = staff(db, client)
    row, _ = org(client, me["headers"])
    today = date.today()
    r = client.post("/api/platform/invoices", headers=me["headers"], json={
        "customerId": int(row["id"]), "issueDate": (today - timedelta(days=40)).isoformat(),
        "dueDate": (today - timedelta(days=10)).isoformat(), "amount": 5000})
    assert r.status_code == 201, r.text
    invoice = r.json()["data"]
    assert invoice["status"] == "overdue" and invoice["number"].startswith("INV-")

    listed = client.get("/api/platform/invoices", headers=me["headers"],
                        params={"status": "overdue", "customerId": row["id"]}).json()["data"]
    assert [i["id"] for i in listed] == [invoice["id"]]

    paid = client.patch(f"/api/platform/invoices/{invoice['id']}/status", headers=me["headers"], json={
        "status": "paid", "paymentReference": "BANK-1", "rowVersion": invoice["rowVersion"]}).json()["data"]
    assert paid["status"] == "paid" and paid["paidOn"] == today.isoformat()
    again = client.patch(f"/api/platform/invoices/{invoice['id']}/status", headers=me["headers"], json={
        "status": "void", "rowVersion": paid["rowVersion"]})
    assert again.status_code == 409 and again.json()["code"] == "INVOICE_CLOSED"


def test_a_won_lead_becomes_an_organisation(client, db):
    me = staff(db, client, "sales")
    lead = client.post("/api/platform/leads", headers=me["headers"], json={
        "companyName": f"Lead {factories.tag()}", "stage": "proposal", "expectedMonthly": 2000}).json()["data"]
    row, _ = org(client, me["headers"], leadId=int(lead["id"]))
    leads = client.get("/api/platform/leads", headers=me["headers"], params={"q": lead["companyName"]}).json()["data"]
    assert leads[0]["stage"] == "won" and leads[0]["customerId"] == row["id"]


def test_tickets_record_when_they_were_resolved(client, db):
    me = staff(db, client, "support")
    admin = staff(db, client)
    row, _ = org(client, admin["headers"])
    body = {"customerId": int(row["id"]), "subject": "Cannot sign in", "priority": "urgent", "assigneeStaffId": me["id"]}
    ticket = client.post("/api/platform/tickets", headers=me["headers"], json=body).json()["data"]
    assert ticket["status"] == "open" and ticket["resolvedAt"] is None and ticket["customerName"] == row["name"]
    done = client.put(f"/api/platform/tickets/{ticket['id']}", headers=me["headers"], json={
        **body, "status": "resolved", "rowVersion": ticket["rowVersion"]}).json()["data"]
    assert done["resolvedAt"] is not None


def test_each_role_works_only_in_its_own_area(client, db):
    support = staff(db, client, "support")["headers"]
    billing = staff(db, client, "billing")["headers"]
    sales = staff(db, client, "sales")["headers"]
    admin = staff(db, client, "admin")["headers"]

    assert client.get("/api/platform/invoices", headers=support).status_code == 403
    assert client.get("/api/platform/subscriptions", headers=sales).status_code == 403
    assert client.get("/api/platform/leads", headers=billing).status_code == 403
    assert client.get("/api/platform/tickets", headers=billing).status_code == 403
    assert client.get("/api/platform/tickets", headers=sales).status_code == 403
    assert client.get("/api/platform/organisations", headers=support).status_code == 200
    assert client.get("/api/platform/plans", headers=support).status_code == 200
    assert client.post("/api/platform/organisations", headers=billing, json={
        "name": "X", "contactEmail": "x@org.test", "ownerName": "X", "ownerEmail": "y@org.test",
        "ownerPassword": OWNER_PASSWORD}).status_code == 403
    assert client.post("/api/platform/plans", headers=sales, json={
        "name": "X", "priceMonthly": 1, "priceAnnual": 1}).status_code == 403
    assert client.get("/api/platform/invoices", headers=admin).status_code == 200
    assert client.get("/api/platform/leads", headers=admin).status_code == 200


def test_the_dashboard_keeps_money_to_those_who_work_with_it(client, db):
    def figures(role: str) -> dict:
        return client.get("/api/platform/dashboard", headers=staff(db, client, role)["headers"]).json()["data"]["figures"]

    assert figures("admin")["monthlyRevenue"] is not None and figures("billing")["monthlyRevenue"] is not None
    support = figures("support")
    assert support["organisations"] >= 0
    assert support["monthlyRevenue"] is None and support["overdueAmount"] is None and support["pipelineMonthly"] is None
    sales = figures("sales")
    assert sales["monthlyRevenue"] is None and sales["pipelineMonthly"] is not None
