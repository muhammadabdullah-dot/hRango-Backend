"""Expense claims, air tickets and requisitions: the form rules, approval through the flow, the
payroll records an approved claim makes (pay.opening_balance) and their removal on cancellation,
the requisition's fulfilment notice, and the events and inbox notifications the engine publishes."""
from datetime import date, timedelta

import pytest

from tests import factories, factories_requests as fr

TODAY = date.today()
THIS_MONTH = TODAY.replace(day=1)
NEXT_MONTH = (THIS_MONTH + timedelta(days=32)).replace(day=1)


@pytest.fixture
def org(db, client):
    o = fr.org(db, client)
    fr.grant_new_types(db, o.staff.user_id, o.staff2.user_id, o.other.user_id)
    return o


def post(client, who, slug, body):
    return client.post(f"/api/requests/{slug}", json=body, headers=who.headers)


def approve(client, who, req, **body):
    r = client.post(f"/api/requests/approvals/{req['id']}/approve", json={"rowVersion": req["rowVersion"], **body},
                    headers=who.headers)
    assert r.status_code == 200, r.text
    return r.json()["data"]


def category(client, org, name: str, **extra) -> dict:
    r = client.post("/api/requests/settings/expense-categories", json={"name": name, **extra},
                    headers=org.hr["headers"])
    assert r.status_code == 201, r.text
    return r.json()["data"]


def reimbursement(client, org, **body) -> dict:
    r = client.put("/api/requests/settings/reimbursement", json=body, headers=org.hr["headers"])
    assert r.status_code == 200, r.text
    return r.json()["data"]


def balances(db, employee_id: int) -> list[dict]:
    cur = db.conn.cursor()
    try:
        rows = cur.execute("SELECT id, balance_month, pay_item_id, amount, is_taxable, kind FROM pay.opening_balance "
                           "WHERE employee_id = ? ORDER BY id", employee_id).fetchall()
        return [{"id": r[0], "month": r[1], "pay_item_id": r[2], "amount": float(r[3]), "is_taxable": r[4],
                 "kind": r[5]} for r in rows]
    finally:
        cur.close()


def test_expense_settings(client, db, org):
    h = org.hr["headers"]
    earning = fr.pay_item(db, org.company_id, "earning")
    r = client.post("/api/requests/settings/expense-categories", json={"name": "Travel Fee", "payItemId": earning},
                    headers=h)
    assert r.status_code == 422 and "payItemId" in r.json()["fieldErrors"]
    item = fr.pay_item(db, org.company_id, "reimbursement")
    travel = category(client, org, "Travel Fee", payItemId=item, maxAmount=5000, receiptRequired=True)
    assert travel["payItemId"] == str(item) and float(travel["maxAmount"]) == 5000 and travel["receiptRequired"] is True
    dup = client.post("/api/requests/settings/expense-categories", json={"name": "Travel Fee"}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "EXPENSE_CATEGORY_DUPLICATE"
    old = category(client, org, "Venue Rental")
    off = client.put(f"/api/requests/settings/expense-categories/{old['id']}",
                     json={"name": "Venue Rental", "isActive": False, "rowVersion": old["rowVersion"]}, headers=h)
    assert off.status_code == 200 and off.json()["data"]["isActive"] is False

    # The form's dropdown: active categories, for whoever may claim.
    names = [c["name"] for c in client.get("/api/requests/expense/categories", headers=org.staff.headers).json()["data"]]
    assert names == ["Travel Fee"]
    assert client.get("/api/requests/settings/expense-categories", headers=org.staff.headers).status_code == 403
    assert client.get("/api/requests/settings/reimbursement", headers=org.staff.headers).status_code == 403

    empty = client.get("/api/requests/settings/reimbursement", headers=h).json()["data"]
    assert empty["expensePayItemId"] is None and empty["airTicketPayItemId"] is None
    bad = client.put("/api/requests/settings/reimbursement", json={"airTicketPayItemId": earning}, headers=h)
    assert bad.status_code == 422 and "airTicketPayItemId" in bad.json()["fieldErrors"]
    saved = reimbursement(client, org, expensePayItemId=item, airTicketPayItemId=item)
    assert saved["expensePayItemId"] == str(item) and saved["airTicketPayItemName"]

    deleted = client.delete(f"/api/requests/settings/expense-categories/{old['id']}",
                            params={"rowVersion": off.json()["data"]["rowVersion"]}, headers=h)
    assert deleted.status_code == 204


def test_expense_claims_reach_payroll_and_leave_it_on_cancel(client, db, org):
    travel_item = fr.pay_item(db, org.company_id, "reimbursement")
    default_item = fr.pay_item(db, org.company_id, "reimbursement")
    travel = category(client, org, "Travel Fee", payItemId=travel_item, maxAmount=5000, receiptRequired=True)
    software = category(client, org, "Software")

    receipt = factories.upload(client, org.staff.headers, name="taxi.pdf", module="requests")
    invoice = factories.upload(client, org.staff.headers, name="licence.png", content=factories.PNG_BYTES,
                               module="requests")
    taxi = {"title": "Taxi to client", "claimDate": str(TODAY - timedelta(days=2)), "expenseCategoryId": travel["id"],
            "amount": 1200, "description": "Airport to client office", "fileId": receipt["id"]}
    licence = {"title": "Design tool", "expenseCategoryId": software["id"], "amount": 800,
               "description": "Monthly licence", "fileId": invoice["id"]}

    # No pay item for Software claims yet: refused at submit, not at the last approval.
    r = post(client, org.staff, "expense", {"details": {"lines": [taxi, licence]}})
    assert r.status_code == 422 and r.json()["code"] == "EXPENSE_NOT_PAYABLE"
    reimbursement(client, org, expensePayItemId=default_item)

    no_receipt = post(client, org.staff, "expense", {"details": {"lines": [{**taxi, "fileId": None}]}})
    assert no_receipt.status_code == 422 and no_receipt.json()["code"] == "EXPENSE_RECEIPT_REQUIRED"
    over = post(client, org.staff, "expense", {"details": {"lines": [{**taxi, "amount": 6000}]}})
    assert over.status_code == 422 and over.json()["code"] == "EXPENSE_OVER_LIMIT"
    future = post(client, org.staff, "expense", {"details": {"lines": [{**taxi, "claimDate": str(TODAY + timedelta(days=1))}]}})
    assert future.status_code == 422
    stranger = fr.org(db, client)
    theirs = factories.upload(client, stranger.staff.headers, name="theirs.pdf")
    r = post(client, org.staff, "expense", {"details": {"lines": [{**taxi, "fileId": theirs["id"]}]}})
    assert r.status_code == 422 and "lines" in r.json()["fieldErrors"]

    # Two claims sent together ("Submit All").
    r = post(client, org.staff, "expense", {"details": {"lines": [taxi, licence]}})
    assert r.status_code == 201, r.text
    req = r.json()["data"]
    d = req["details"]
    assert req["code"].startswith("RQ-EXP-") and d["totalAmount"] == 2000 and d["currency"] == "PKR"
    assert [(x["lineNo"], x["title"], x["expenseCategoryName"]) for x in d["lines"]] == [
        (1, "Taxi to client", "Travel Fee"), (2, "Design tool", "Software")]
    assert d["lines"][1]["claimDate"] == str(TODAY) and d["lines"][0]["fileName"] == "taxi.pdf"
    assert client.get(d["lines"][0]["fileUrl"]).content == factories.PDF_BYTES
    assert req["fromDate"] == str(TODAY - timedelta(days=2)) and req["toDate"] == str(TODAY)
    again = post(client, org.staff, "expense", {"details": {"lines": [taxi]}})
    assert again.status_code == 409 and again.json()["code"] == "EXPENSE_DUPLICATE"

    # Manager: Approve & Forward, lowering the licence claim.
    lines = d["lines"]
    too_much = client.post(f"/api/requests/approvals/{req['id']}/approve",
                           json={"rowVersion": req["rowVersion"],
                                 "details": {"lines": [{"id": lines[1]["id"], "approvedAmount": 900}]}},
                           headers=org.manager.headers)
    assert too_much.status_code == 422
    req = approve(client, org.manager, req, details={"lines": [{"id": lines[1]["id"], "approvedAmount": 500}]})
    assert req["status"] == "pending" and req["nextApproverName"].startswith("Farah")
    assert balances(db, org.staff.employee_id) == []
    req = approve(client, org.fa, req)
    assert req["status"] == "approved"
    assert [x["approvedAmount"] for x in req["details"]["lines"]] == [1200, 500]
    assert req["details"]["approvedAmount"] == 1700

    # Payroll: one opening balance per claim, under the category's pay item or the default, this month.
    paid = balances(db, org.staff.employee_id)
    assert [(b["pay_item_id"], b["amount"], b["kind"], b["is_taxable"]) for b in paid] == [
        (travel_item, 1200, "reimbursement", False), (default_item, 500, "reimbursement", False)]
    assert all(b["month"] == THIS_MONTH for b in paid)
    assert all(x["paidInMonth"] == str(THIS_MONTH) for x in req["details"]["lines"])
    assert all(x["openingBalanceId"] for x in req["details"]["lines"])

    # Cancelling the approved request walks the cancellation flow; its approval removes the payroll records.
    r = client.post(f"/api/requests/expense/{req['id']}/cancel", json={"reason": "Paid by the client",
                                                                     "rowVersion": req["rowVersion"]},
                    headers=org.staff.headers)
    assert r.status_code == 200 and r.json()["data"]["status"] == "cancelling"
    req = approve(client, org.manager, r.json()["data"])
    req = approve(client, org.fa, req)
    assert req["status"] == "cancelled" and balances(db, org.staff.employee_id) == []

    assert fr.events(db, int(req["id"])) == [
        "requests.submitted", "requests.step_decided", "requests.approved", "requests.cancellation_requested",
        "requests.step_decided", "requests.cancelled"]
    to_manager = fr.notifications(db, org.manager.user_id, int(req["id"]))
    assert [n["type"] for n in to_manager] == ["request_approval", "request_approval"]
    assert to_manager[0]["link"] == f"/requests/approvals/{req['id']}" and "waiting for your approval" in to_manager[0]["title"]
    assert "cancellation" in to_manager[1]["title"]
    to_staff = fr.notifications(db, org.staff.user_id, int(req["id"]))
    assert [n["title"].rsplit(" ", 1)[-1] for n in to_staff] == ["approved", "cancelled"]
    assert to_staff[0]["link"] == f"/requests/expense/{req['id']}"
    # The inbox shows them too.
    inbox = fr.notifications(db, org.fa.user_id, int(req["id"]))
    assert len(inbox) == 2


def test_air_ticket_is_paid_in_the_first_open_month_and_cannot_be_cancelled_once_paid(client, db, org):
    body = {"details": {"title": "Lahore to Karachi", "travelDate": str(TODAY + timedelta(days=10)),
                        "fromPlace": "LHE", "toPlace": "KHI", "amount": 30000}}
    r = post(client, org.staff, "air-ticket", body)
    assert r.status_code == 422 and r.json()["code"] == "AIR_TICKET_NOT_PAYABLE"
    item = fr.pay_item(db, org.company_id, "reimbursement")
    reimbursement(client, org, airTicketPayItemId=item)

    ticket = factories.upload(client, org.staff.headers, name="eticket.pdf", module="requests")
    r = post(client, org.staff, "air-ticket", {"details": {**body["details"], "fileId": ticket["id"]}})
    assert r.status_code == 201, r.text
    req = r.json()["data"]
    assert req["code"].startswith("RQ-AIR-") and req["details"]["amount"] == 30000
    assert req["details"]["fileName"] == "eticket.pdf" and req["details"]["fileUrl"]
    dup = post(client, org.staff, "air-ticket", body)
    assert dup.status_code == 409 and dup.json()["code"] == "AIR_TICKET_DUPLICATE"

    # This month's payroll has already paid the person, so the claim goes to next month.
    fr.closed_payslip(db, org.company_id, org.staff.employee_id, THIS_MONTH)
    req = approve(client, org.manager, req, details={"approvedAmount": 28000})
    req = approve(client, org.fa, req)
    assert req["status"] == "approved" and req["details"]["approvedAmount"] == 28000
    paid = balances(db, org.staff.employee_id)
    assert [(b["pay_item_id"], b["amount"], b["month"]) for b in paid] == [(item, 28000, NEXT_MONTH)]

    # Once that month is closed too, cancelling is refused at the cancellation's final approval.
    fr.closed_payslip(db, org.company_id, org.staff.employee_id, NEXT_MONTH)
    r = client.post(f"/api/requests/air-ticket/{req['id']}/cancel",
                    json={"reason": "Trip cancelled", "rowVersion": req["rowVersion"]}, headers=org.staff.headers)
    req = approve(client, org.manager, r.json()["data"])
    refused = client.post(f"/api/requests/approvals/{req['id']}/approve", json={"rowVersion": req["rowVersion"]},
                          headers=org.fa.headers)
    assert refused.status_code == 409 and "paid through payroll" in refused.json()["message"]
    assert len(balances(db, org.staff.employee_id)) == 1


def test_requisition_is_approved_and_handed_to_whoever_fulfils_it(client, db, org):
    body = {"reason": "New joiners next week", "details": {
        "title": "Stationery for new joiners", "requisitionType": "stationery",
        "neededByDate": str(TODAY + timedelta(days=7)), "deliveryLocation": "Floor 2",
        "lines": [{"itemName": "Notebook", "quantity": 10, "unit": "pcs", "estimatedUnitCost": 150},
                  {"itemName": "Pens (box)", "quantity": 2, "estimatedUnitCost": 600}]}}
    assert post(client, org.staff, "requisition", {**body, "reason": ""}).status_code == 422
    past = post(client, org.staff, "requisition",
                {**body, "details": {**body["details"], "neededByDate": str(TODAY - timedelta(days=1))}})
    assert past.status_code == 422 and "neededByDate" in past.json()["fieldErrors"]

    # The Admin Manager authority fulfils requisitions (Request Settings -> Authorities).
    r = client.post("/api/requests/settings/authorities",
                    json={"authority": "admin_manager", "employeeId": org.other_manager.employee_id},
                    headers=org.hr["headers"])
    assert r.status_code == 201, r.text

    r = post(client, org.staff, "requisition", body)
    assert r.status_code == 201, r.text
    req = r.json()["data"]
    assert req["code"].startswith("RQ-RQN-") and req["details"]["estimatedAmount"] == 2700
    assert [x["itemName"] for x in req["details"]["lines"]] == ["Notebook", "Pens (box)"]
    req = approve(client, org.manager, req)
    req = approve(client, org.fa, req)
    assert req["status"] == "approved"
    fulfil = fr.notifications(db, org.other_manager.user_id, int(req["id"]))
    assert [n["type"] for n in fulfil] == ["request_fulfil"] and "Stationery for new joiners" in fulfil[0]["title"]
    assert fr.events(db, int(req["id"]))[-1] == "requests.approved"

    # A rejection ends it and tells the requester.
    second = post(client, org.staff, "requisition",
                  {**body, "details": {**body["details"], "title": "Chairs", "requisitionType": "furniture"}}).json()["data"]
    r = client.post(f"/api/requests/approvals/{second['id']}/reject",
                    json={"rowVersion": second["rowVersion"], "remarks": "Budget is closed"}, headers=org.manager.headers)
    assert r.status_code == 200 and r.json()["data"]["status"] == "rejected"
    assert fr.events(db, int(second["id"])) == ["requests.submitted", "requests.rejected"]
    told = fr.notifications(db, org.staff.user_id, int(second["id"]))
    assert len(told) == 1 and told[0]["title"].endswith("was rejected")


def test_forward_and_withdraw_publish_and_notify(client, db, org):
    r = client.post("/api/requests/travel", json=fr.travel_body(TODAY + timedelta(days=50)), headers=org.staff.headers)
    req = r.json()["data"]
    r = client.post(f"/api/requests/approvals/{req['id']}/forward",
                    json={"employeeId": org.other_manager.employee_id, "rowVersion": req["rowVersion"]},
                    headers=org.manager.headers)
    assert r.status_code == 200, r.text
    assert [n["type"] for n in fr.notifications(db, org.other_manager.user_id, int(req["id"]))] == ["request_approval"]
    req = r.json()["data"]
    r = client.post(f"/api/requests/travel/{req['id']}/cancel", json={"reason": "Not needed",
                                                                    "rowVersion": req["rowVersion"]},
                    headers=org.staff.headers)
    assert r.status_code == 200 and r.json()["data"]["status"] == "cancelled"
    assert fr.events(db, int(req["id"])) == ["requests.submitted", "requests.forwarded", "requests.cancelled"]
    # Withdrawn by the requester: nobody needs telling.
    assert fr.notifications(db, org.staff.user_id, int(req["id"])) == []
    cur = db.conn.cursor()
    payload = cur.execute("SELECT TOP 1 payload FROM core.outbox_event WHERE entity_type = N'req.request' AND entity_id = ? "
                          "AND event_type = N'requests.forwarded'", int(req["id"])).fetchval()
    cur.close()
    assert '"currentStep"' in payload and f'"approverId":"{org.other_manager.employee_id}"' in payload
    assert '"type":"travel"' in payload and f'"requestId":"{req["id"]}"' in payload
