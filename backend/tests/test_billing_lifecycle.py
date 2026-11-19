"""Billing without a payment gateway (migration 0050, app/services/billing_service.py): renewal invoices, trials that
end, read-only and locked access for unpaid invoices, bank transfer proofs and their review, and the e-mails.

Each test runs the billing for its own organisation only (customer_id), on days of its choosing, so other tests'
organisations are never touched."""
import calendar
from datetime import date, timedelta

from app.services import billing_service
from tests import factories
from tests.test_platform import staff
from tests.test_platform_portal import OWNER_PASSWORD, org


def _next_month(d: date) -> date:
    """As SQL Server's DATEADD(MONTH, 1, d): the same day next month, or that month's last day."""
    y, m = (d.year + 1, 1) if d.month == 12 else (d.year, d.month + 1)
    return date(y, m, min(d.day, calendar.monthrange(y, m)[1]))


def _query(db, sql, *params):
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
        cols = [d[0] for d in cur.description] if cur.description else []
        return [dict(zip(cols, row)) for row in cur.fetchall()] if cols else []
    finally:
        cur.close()


def _paid_plan(client, headers, price=500):
    r = client.post("/api/platform/plans", headers=headers, json={
        "name": f"Billed {factories.tag()}", "priceMonthly": price, "priceAnnual": price * 10, "employeeLimit": 50})
    assert r.status_code == 201, r.text
    return r.json()["data"]


def _owner(client, body):
    r = client.post("/api/auth/login", json={"email": body["ownerEmail"], "password": OWNER_PASSWORD})
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    return {"Authorization": f"Bearer {data['token']}"}, int(data["user"]["companyId"])


def _subscription(db, customer_id):
    return _query(db, "SELECT TOP 1 * FROM plat.subscription WHERE customer_id = ? ORDER BY id DESC", customer_id)[0]


def _run(db, customer_id, today):
    return [n["kind"] for n in billing_service.run_daily(db, today=today, customer_id=customer_id)]


def _mail_kinds(db, to_address):
    return [r["kind"] for r in _query(db, "SELECT kind FROM core.mail_message WHERE to_address = ? ORDER BY id",
                                       to_address)]


def _hire(client, headers, branch):
    return client.post("/api/employees", headers=headers, json={
        "firstName": "Billing", "lastName": f"Person {factories.tag()}", "branchId": branch, "joiningDate": "2026-01-05"})


def _new_org(client, db, price=500):
    me = staff(db, client)
    plan = _paid_plan(client, me["headers"], price)
    customer, body = org(client, me["headers"], planId=int(plan["id"]))
    owner, company = _owner(client, body)
    return me, int(customer["id"]), body, owner, company


def test_a_trial_that_ends_unpaid_turns_read_only_then_locked_and_a_bank_transfer_restores_it(client, db):
    me, customer, body, owner, company = _new_org(client, db)
    sub = _subscription(db, customer)
    assert sub["status"] == "trial" and sub["access"] == "full"
    end = sub["renews_on"]
    branch = factories.branch(db, company)

    # A week before the trial ends: its invoice, and the "ends in 7 days" e-mail (not a separate invoice e-mail).
    assert _run(db, customer, end - timedelta(days=7)) == ["trial_7"]
    assert _run(db, customer, end - timedelta(days=7)) == []
    invoices = client.get("/api/billing/invoices", headers=owner).json()["data"]
    assert len(invoices) == 1
    invoice = invoices[0]
    assert invoice["source"] == "renewal" and invoice["status"] == "issued" and invoice["amount"] == 500
    assert invoice["periodStart"] == end.isoformat() and invoice["dueDate"] == end.isoformat()
    me_now = client.get("/api/auth/me", headers=owner).json()["data"]
    assert me_now["isAccountOwner"] is True and me_now["billing"]["status"] == "trial"
    assert me_now["billing"]["access"] == "full"

    assert _run(db, customer, end - timedelta(days=3)) == ["trial_3"]
    assert _run(db, customer, end) == ["due_today"]

    # The day after: expired and read-only. Reading works, changing does not, Billing still does.
    assert _run(db, customer, end + timedelta(days=1)) == ["trial_ended"]
    sub = _subscription(db, customer)
    assert sub["status"] == "expired" and sub["access"] == "read_only"
    assert client.get("/api/employees", headers=owner).status_code == 200
    blocked = _hire(client, owner, branch)
    assert blocked.status_code == 403 and blocked.json()["code"] == "READ_ONLY"
    details = client.put("/api/billing/details", headers=owner, json={
        "billingName": "Billed Org (Pvt) Ltd", "billingEmail": f"accounts.{factories.tag()}@org.test",
        "billingAddress": "1 Mall Road, Lahore", "taxNumber": "1234567-8"})
    assert details.status_code == 200, details.text
    assert details.json()["data"]["details"]["billingName"] == "Billed Org (Pvt) Ltd"
    billing_email = details.json()["data"]["details"]["billingEmail"]

    # A week later: locked. Only Billing (and sign-in) answers the Account Owner.
    assert _run(db, customer, end + timedelta(days=8)) == ["locked"]
    assert _subscription(db, customer)["access"] == "locked"
    locked = client.get("/api/employees", headers=owner)
    assert locked.status_code == 403 and locked.json()["code"] == "BILLING_LOCKED"
    assert client.get("/api/auth/me", headers=owner).json()["data"]["billing"]["access"] == "locked"
    overview = client.get("/api/billing", headers=owner).json()["data"]
    assert overview["access"] == "locked" and overview["nextInvoice"]["number"] == invoice["number"]
    assert overview["openAmount"] == 500

    # The owner sends a bank transfer proof; one at a time.
    proof = factories.upload(client, owner, name="slip.pdf", module="billing")
    sent = client.post(f"/api/billing/invoices/{invoice['id']}/payments", headers=owner, json={
        "reference": "TRX-778812", "paidOn": date.today().isoformat(), "amount": 500, "fileId": proof["id"],
        "note": "Paid from Meezan Bank"})
    assert sent.status_code == 201, sent.text
    assert sent.json()["data"]["proof"]["status"] == "pending"
    assert client.get("/api/billing", headers=owner).json()["data"]["nextInvoice"]["proofPending"] is True
    again = client.post(f"/api/billing/invoices/{invoice['id']}/payments", headers=owner, json={
        "reference": "TRX-778812", "paidOn": date.today().isoformat(), "amount": 500})
    assert again.status_code == 409 and again.json()["code"] == "PAYMENT_PENDING"

    # Staff see it with its proof, and accept it: paid, active for the next month, access back, receipt e-mailed.
    waiting = client.get("/api/platform/payments", headers=me["headers"], params={"status": "pending"}).json()["data"]
    mine = next(p for p in waiting if p["invoiceId"] == invoice["id"])
    assert mine["reference"] == "TRX-778812" and mine["fileUrl"] and mine["fileName"] == "slip.pdf"
    accepted = client.patch(f"/api/platform/payments/{mine['id']}", headers=me["headers"],
                            json={"decision": "accept", "rowVersion": mine["rowVersion"]})
    assert accepted.status_code == 200, accepted.text
    sub = _subscription(db, customer)
    assert sub["status"] == "active" and sub["access"] == "full"
    assert sub["renews_on"] == _next_month(end)
    paid = client.get(f"/api/billing/invoices/{invoice['id']}", headers=owner).json()["data"]
    assert paid["status"] == "paid" and paid["paymentReference"] == "TRX-778812"
    assert paid["billTo"]["name"] == "Billed Org (Pvt) Ltd" and paid["billTo"]["taxNumber"] == "1234567-8"
    assert _hire(client, owner, branch).status_code == 201
    kinds = _mail_kinds(db, billing_email)
    assert "billing_locked" in kinds and kinds[-1] == "billing_payment_received"


def test_a_paying_customer_has_two_weeks_then_read_only_then_locked(client, db):
    me, customer, body, owner, company = _new_org(client, db)
    # Make it a paying customer: active, renewing in 20 days.
    renews = date.today() + timedelta(days=20)
    sub = _subscription(db, customer)
    r = client.put(f"/api/platform/subscriptions/{sub['id']}", headers=me["headers"], json={
        "customerId": customer, "planId": sub["plan_id"], "billingCycle": "monthly", "status": "active",
        "startDate": date.today().isoformat(), "renewsOn": renews.isoformat(),
        "rowVersion": _rv(client, me, customer)})
    assert r.status_code == 200, r.text

    assert _run(db, customer, renews - timedelta(days=7)) == ["invoice_issued"]
    assert _run(db, customer, renews + timedelta(days=1)) == []
    sub = _subscription(db, customer)
    assert sub["status"] == "past_due" and sub["access"] == "full"
    assert _run(db, customer, renews + timedelta(days=3)) == ["overdue_3"]
    assert _run(db, customer, renews + timedelta(days=14)) == ["read_only"]
    assert _subscription(db, customer)["access"] == "read_only"
    assert _run(db, customer, renews + timedelta(days=30)) == ["locked"]

    # Staff mark the invoice paid by hand: the same as a payment.
    invoice = client.get("/api/platform/invoices", headers=me["headers"],
                         params={"customerId": customer}).json()["data"][0]
    # The list works "overdue" out from today's real date, which is before the due date of this run.
    assert invoice["source"] == "renewal" and invoice["status"] == "issued"
    paid = client.patch(f"/api/platform/invoices/{invoice['id']}/status", headers=me["headers"], json={
        "status": "paid", "paymentReference": "Cheque 4471", "rowVersion": invoice["rowVersion"]})
    assert paid.status_code == 200, paid.text
    sub = _subscription(db, customer)
    assert sub["status"] == "active" and sub["access"] == "full" and sub["renews_on"] > renews
    assert client.get("/api/employees", headers=owner).status_code == 200


def _rv(client, me, customer):
    rows = client.get("/api/platform/subscriptions", headers=me["headers"], params={"customerId": customer}).json()
    return rows["data"][0]["rowVersion"]


def test_staff_extend_a_trial_and_reject_a_proof_with_a_reason(client, db):
    me, customer, body, owner, company = _new_org(client, db)
    end = _subscription(db, customer)["renews_on"]
    _run(db, customer, end - timedelta(days=7))
    _run(db, customer, end + timedelta(days=1))
    assert _subscription(db, customer)["access"] == "read_only"

    # A proof that does not match: rejected with a reason, which the organisation is told.
    invoice = client.get("/api/billing/invoices", headers=owner).json()["data"][0]
    sent = client.post(f"/api/billing/invoices/{invoice['id']}/payments", headers=owner, json={
        "reference": "WRONG-1", "paidOn": date.today().isoformat(), "amount": 50})
    assert sent.status_code == 201, sent.text
    pending = next(p for p in client.get("/api/platform/payments", headers=me["headers"]).json()["data"]
                   if p["invoiceId"] == invoice["id"])
    no_reason = client.patch(f"/api/platform/payments/{pending['id']}", headers=me["headers"],
                             json={"decision": "reject", "rowVersion": pending["rowVersion"]})
    assert no_reason.status_code == 422
    rejected = client.patch(f"/api/platform/payments/{pending['id']}", headers=me["headers"], json={
        "decision": "reject", "note": "No transfer of 50 found.", "rowVersion": pending["rowVersion"]})
    assert rejected.status_code == 200 and rejected.json()["data"]["status"] == "rejected"
    listed = client.get("/api/billing/invoices", headers=owner).json()["data"][0]
    assert listed["proof"]["status"] == "rejected" and listed["proof"]["reviewNote"] == "No transfer of 50 found."
    assert _mail_kinds(db, body["contactEmail"])[-1] == "billing_payment_rejected"

    # Ten more days: a trial again, full access, and the old invoice voided.
    extended = client.post(f"/api/platform/subscriptions/{_subscription(db, customer)['id']}/extend-trial",
                           headers=me["headers"], json={"days": 10, "rowVersion": _rv(client, me, customer)})
    assert extended.status_code == 200, extended.text
    data = extended.json()["data"]
    assert data["status"] == "trial" and data["access"] == "full"
    assert data["renewsOn"] == (end + timedelta(days=10)).isoformat()
    assert client.get(f"/api/billing/invoices/{invoice['id']}", headers=owner).json()["data"]["status"] == "void"


def test_an_organisation_sees_only_its_own_invoices(client, db):
    _, customer_a, _, owner_a, _ = _new_org(client, db)
    _, customer_b, _, owner_b, _ = _new_org(client, db)
    end = _subscription(db, customer_b)["renews_on"]
    _run(db, customer_b, end - timedelta(days=7))
    theirs = client.get("/api/billing/invoices", headers=owner_b).json()["data"][0]
    assert client.get(f"/api/billing/invoices/{theirs['id']}", headers=owner_a).status_code == 404
    pay = client.post(f"/api/billing/invoices/{theirs['id']}/payments", headers=owner_a, json={
        "reference": "X", "paidOn": date.today().isoformat(), "amount": 1})
    assert pay.status_code == 404
    assert client.get("/api/billing/invoices", headers=owner_a).json()["data"] == []


def test_a_free_plan_is_never_billed_or_restricted(client, db):
    _, customer, _, owner, _ = _new_org(client, db, price=0)
    end = _subscription(db, customer)["renews_on"]
    assert _run(db, customer, end - timedelta(days=7)) == []
    assert _run(db, customer, end + timedelta(days=40)) == []
    sub = _subscription(db, customer)
    assert sub["status"] == "active" and sub["access"] == "full" and sub["renews_on"] is None
    assert client.get("/api/billing/invoices", headers=owner).json()["data"] == []


def test_billing_is_for_administrators_not_hr(client, db, company):
    # The default HR Manager role holds no billing permission; a Company Administrator does.
    rows = _query(db, """
        SELECT r.code FROM auth.role r JOIN auth.role_permission rp ON rp.role_id = r.id
        JOIN auth.permission p ON p.id = rp.permission_id
        WHERE r.company_id = ? AND p.code = 'billing.subscription.view'""", company)
    codes = {r["code"] for r in rows}
    assert "company_admin" in codes and "hr_manager" not in codes and "hr_officer" not in codes
