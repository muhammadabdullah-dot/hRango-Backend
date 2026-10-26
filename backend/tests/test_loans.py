"""Loans: types and categories, eligibility on the loan request, the approver's fields, the loan
and its installment schedule made on final approval, and the cancellation that removes it."""
from datetime import date, timedelta

import pytest

from tests import factories_requests as fr

REPAY = date.today().replace(day=1) + timedelta(days=62)


@pytest.fixture
def org(db, client):
    return fr.org(db, client)


def loan_type(client, org, db, **extra):
    body = {"name": f"Car loan {fr.factories.tag()}", "guarantorRequired": True, "minExperienceMonths": 6,
            "installments": 3, "gapBetweenInstallmentsMonths": 1, "deductionPayItemId": fr.pay_item(db, org.company_id),
            "employmentTypeIds": [fr.employment_type(db, org.company_id)], **extra}
    r = client.post("/api/loans/types", json=body, headers=org.admin["headers"])
    assert r.status_code == 201, r.text
    return r.json()["data"]


def test_loan_settings(client, db, org):
    h = org.admin["headers"]
    base = {"name": "Laptop advance", "minExperienceMonths": 0, "installments": 2,
            "employmentTypeIds": [fr.employment_type(db, org.company_id)]}
    r = client.post("/api/loans/types", json=base, headers=h)
    assert r.status_code == 422 and "deductionPayItemId" in r.json()["fieldErrors"]
    r = client.post("/api/loans/types", json={**base, "employmentTypeIds": []}, headers=h)
    assert r.status_code == 422
    r = client.post("/api/loans/types", json={**base, "nonPayable": True}, headers=h)
    assert r.status_code == 201, r.text
    t = r.json()["data"]
    assert t["nonPayable"] is True and len(t["employmentTypes"]) == 1
    assert client.post("/api/loans/types", json={**base, "nonPayable": True}, headers=h).status_code == 409
    off = client.put(f"/api/loans/types/{t['id']}", json={**base, "nonPayable": True, "isActive": False,
                                                          "rowVersion": t["rowVersion"]}, headers=h)
    assert off.status_code == 200 and off.json()["data"]["isActive"] is False
    stale = client.put(f"/api/loans/types/{t['id']}", json={**base, "nonPayable": True, "rowVersion": t["rowVersion"]},
                       headers=h)
    assert stale.status_code == 409

    c = client.post("/api/loans/categories", json={"name": "Personal"}, headers=h)
    assert c.status_code == 201
    assert client.post("/api/loans/categories", json={"name": "Personal"}, headers=h).status_code == 409
    listed = client.get("/api/loans/categories", headers=h).json()
    assert listed["meta"]["total"] == 1
    cat = c.json()["data"]
    assert client.delete(f"/api/loans/categories/{cat['id']}", params={"rowVersion": cat["rowVersion"]},
                         headers=h).status_code == 204
    # Staff cannot change settings.
    assert client.get("/api/loans/types", headers=org.staff.headers).status_code == 403


def test_loan_request_to_schedule_and_back(client, db, org):
    t = loan_type(client, org, db)
    body = {"reason": "Car", "details": {"loanTypeId": t["id"], "amountRequested": 100000,
                                         "requiredDate": str(REPAY)}}
    # The staff member's contract type is not one the type is offered to.
    r = client.post("/api/requests/loan", json=body, headers=org.staff.headers)
    assert r.status_code == 422 and r.json()["code"] == "LOAN_NOT_ELIGIBLE"
    fr.execute(db, "UPDATE hr.employee SET employment_type_id = ? WHERE id = ?",
               int(t["employmentTypes"][0]["id"]), org.staff.employee_id)
    r = client.post("/api/requests/loan", json=body, headers=org.staff.headers)
    assert r.status_code == 422 and "guarantors" in r.json()["fieldErrors"]
    cnic_copy = fr.factories.upload(client, org.staff.headers, name="cnic.pdf", module="requests")
    guarantor = {"name": "Ali Raza", "cnic": "35202-1234567-1", "knownSince": "2015-01-01", "relationship": "Cousin",
                 "fileId": cnic_copy["id"]}
    r = client.post("/api/requests/loan", json={**body, "details": {**body["details"], "guarantors": [guarantor]}},
                    headers=org.staff.headers)
    assert r.status_code == 201, r.text
    req = r.json()["data"]
    assert req["details"]["guarantors"][0]["cnic"] == "35202-1234567-1" and req["code"].startswith("RQ-LA-")
    g = req["details"]["guarantors"][0]
    assert g["fileId"] == cnic_copy["id"] and g["fileName"] == "cnic.pdf" and client.get(g["fileUrl"]).status_code == 200
    # Empty guarantor fields come as null, so the shape is stable.
    assert "extensionNo" in g and g["extensionNo"] is None and "description" in g
    dup = client.post("/api/requests/loan", json={**body, "details": {**body["details"], "guarantors": [guarantor]}},
                      headers=org.staff.headers)
    assert dup.status_code == 409 and dup.json()["code"] == "LOAN_PENDING"

    too_much = client.post(f"/api/requests/approvals/{req['id']}/approve",
                           json={"rowVersion": req["rowVersion"], "details": {"approvedAmount": 150000}},
                           headers=org.manager.headers)
    assert too_much.status_code == 422
    req = client.post(f"/api/requests/approvals/{req['id']}/approve",
                      json={"rowVersion": req["rowVersion"], "details": {"approvedAmount": 90000}},
                      headers=org.manager.headers).json()["data"]
    missing = client.post(f"/api/requests/approvals/{req['id']}/approve", json={"rowVersion": req["rowVersion"]},
                          headers=org.fa.headers)
    assert missing.status_code == 422 and "approvedAmount" in missing.json()["fieldErrors"]
    done = client.post(f"/api/requests/approvals/{req['id']}/approve",
                       json={"rowVersion": req["rowVersion"], "details": {
                           "approvedAmount": 100000, "paymentMethod": "bank", "repaymentDate": str(REPAY)}},
                       headers=org.fa.headers)
    assert done.status_code == 200, done.text
    req = done.json()["data"]
    assert req["status"] == "approved" and req["details"]["approvedAmount"] == 100000
    assert req["details"]["currency"] == "PKR"

    mine = client.get("/api/loans", params={"view": "my"}, headers=org.staff.headers).json()
    assert mine["meta"]["total"] == 1
    loan = client.get(f"/api/loans/{mine['data'][0]['id']}", headers=org.staff.headers).json()["data"]
    amounts = [float(i["amount"]) for i in loan["schedule"]]
    assert amounts == [33333.33, 33333.33, 33333.34] and loan["guarantors"][0]["name"] == "Ali Raza"
    assert loan["guarantors"][0]["fileName"] == "cnic.pdf" and loan["guarantors"][0]["fileUrl"]
    months = [i["dueMonth"] for i in loan["schedule"]]
    assert months[0] == str(REPAY.replace(day=1)) and months[1] > months[0]
    # Loan figures are sensitive (ACC-9): HR reads them; a line manager does not until open question E6 says so.
    summary = client.get("/api/loans/summary", params={"employeeId": org.staff.employee_id},
                         headers=org.hr["headers"]).json()["data"]
    assert float(summary["totalApproved"]) == 100000 and float(summary["totalRemaining"]) == 100000
    assert client.get("/api/loans", params={"view": "all"}, headers=org.hr["headers"]).json()["meta"]["total"] >= 1
    # The manager's own-scope loan permission shows only their own loans, so the report's loan is not there.
    assert client.get("/api/loans", params={"view": "all"}, headers=org.manager.headers).json()["meta"]["total"] == 0
    assert client.get("/api/loans", params={"view": "all"}, headers=org.other_manager.headers).json()["meta"]["total"] == 0
    reps = client.get("/api/loans/installments", headers=org.hr["headers"]).json()
    assert reps["meta"]["total"] == 3

    in_use = client.delete(f"/api/loans/types/{t['id']}", params={"rowVersion": t["rowVersion"]},
                           headers=org.admin["headers"])
    assert in_use.status_code == 409

    # Cancelling the approved loan request removes the loan once the cancellation is approved.
    req = client.post(f"/api/requests/loan/{req['id']}/cancel", json={"reason": "Not needed",
                                                                       "rowVersion": req["rowVersion"]},
                      headers=org.staff.headers).json()["data"]
    req = client.post(f"/api/requests/approvals/{req['id']}/approve", json={"rowVersion": req["rowVersion"]},
                      headers=org.manager.headers).json()["data"]
    req = client.post(f"/api/requests/approvals/{req['id']}/approve", json={"rowVersion": req["rowVersion"]},
                      headers=org.fa.headers).json()["data"]
    assert req["status"] == "cancelled"
    assert client.get("/api/loans", params={"view": "my"}, headers=org.staff.headers).json()["meta"]["total"] == 0


def test_non_payable_loan_has_no_schedule(client, db, org):
    t = loan_type(client, org, db, nonPayable=True, guarantorRequired=False, minExperienceMonths=0)
    fr.execute(db, "UPDATE hr.employee SET employment_type_id = ? WHERE id = ?",
               int(t["employmentTypes"][0]["id"]), org.staff.employee_id)
    req = client.post("/api/requests/loan", json={"reason": "Laptop", "details": {
        "loanTypeId": t["id"], "amountRequested": 50000, "requiredDate": str(REPAY)}}, headers=org.staff.headers)
    assert req.status_code == 201, req.text
    req = req.json()["data"]
    fields = {"approvedAmount": 50000, "paymentMethod": "cash", "repaymentDate": str(REPAY)}
    req = client.post(f"/api/requests/approvals/{req['id']}/approve",
                      json={"rowVersion": req["rowVersion"], "details": fields}, headers=org.manager.headers).json()["data"]
    req = client.post(f"/api/requests/approvals/{req['id']}/approve",
                      json={"rowVersion": req["rowVersion"]}, headers=org.fa.headers).json()["data"]
    assert req["status"] == "approved"
    loan = client.get("/api/loans", params={"view": "my"}, headers=org.staff.headers).json()["data"][0]
    assert loan["status"] == "non_payable"
    detail = client.get(f"/api/loans/{loan['id']}", headers=org.staff.headers).json()["data"]
    assert detail["schedule"] == []


def test_bulk_approve_fills_the_loan_approval_fields(client, db, org):
    """Bulk approve sends no approval form: a loan's final step takes the amount asked and a repayment
    date from the month after the required date, as the approve popup would prefill them."""
    t = loan_type(client, org, db, guarantorRequired=False, minExperienceMonths=0)
    fr.execute(db, "UPDATE hr.employee SET employment_type_id = ? WHERE id = ?",
               int(t["employmentTypes"][0]["id"]), org.staff.employee_id)
    req = client.post("/api/requests/loan", json={"reason": "Bike", "details": {
        "loanTypeId": t["id"], "amountRequested": 60000, "requiredDate": str(REPAY)}}, headers=org.staff.headers)
    assert req.status_code == 201, req.text
    req = req.json()["data"]
    for who in (org.manager, org.fa):
        r = client.post("/api/requests/approvals/bulk-approve",
                        json={"items": [{"id": req["id"], "rowVersion": req["rowVersion"]}]}, headers=who.headers)
        assert r.status_code == 200, r.text
        result = r.json()["data"][0]
        assert result["ok"] is True, result.get("message")
        req = client.get(f"/api/requests/loan/{req['id']}", headers=org.staff.headers).json()["data"]
    assert req["status"] == "approved"
    assert req["details"]["approvedAmount"] == 60000 and req["details"]["paymentMethod"] == "cash"
    next_month = (REPAY.replace(day=28) + timedelta(days=4)).replace(day=1)
    assert req["details"]["repaymentDate"] == str(next_month)
    loan = client.get("/api/loans", params={"view": "my"}, headers=org.staff.headers).json()["data"][0]
    assert float(loan["principal"]) == 60000


def test_loan_form_options_for_staff(client, db, org):
    """Staff read the loan form's dropdowns without the loan settings permissions."""
    t = loan_type(client, org, db, guarantorRequired=False, minExperienceMonths=0)
    off = loan_type(client, org, db)
    client.put(f"/api/loans/types/{off['id']}", json={
        "name": off["name"], "installments": 3, "minExperienceMonths": 6, "isActive": False,
        "deductionPayItemId": fr.pay_item(db, org.company_id),
        "employmentTypeIds": [e["id"] for e in off["employmentTypes"]], "rowVersion": off["rowVersion"]},
        headers=org.admin["headers"])
    cat = client.post("/api/loans/categories", json={"name": "Vehicle"}, headers=org.admin["headers"]).json()["data"]
    assert client.get("/api/loans/types", headers=org.staff.headers).status_code == 403

    r = client.get("/api/requests/options/loan-types", headers=org.staff.headers)
    assert r.status_code == 200, r.text
    rows = {x["id"]: x for x in r.json()["data"]}
    assert t["id"] in rows and off["id"] not in rows
    assert rows[t["id"]]["installments"] == 3 and rows[t["id"]]["eligible"] is False
    fr.execute(db, "UPDATE hr.employee SET employment_type_id = ? WHERE id = ?",
               int(t["employmentTypes"][0]["id"]), org.staff.employee_id)
    rows = {x["id"]: x for x in client.get("/api/requests/options/loan-types", headers=org.staff.headers).json()["data"]}
    assert rows[t["id"]]["eligible"] is True
    cats = client.get("/api/requests/options/loan-categories", headers=org.staff.headers).json()["data"]
    assert [c["name"] for c in cats] == ["Vehicle"] and cats[0]["id"] == cat["id"]
