"""Payroll extras the frontend waits for (Backend Dependencies P1-P4): the close e-mail of a monthly run, the
salary revision letter, the bank transfer file, and the leave encashment preview with the type's limits.
Mail is not set up (settings.mail_enabled false): e-mails are recorded 'disabled'; the 'queued' path is
checked by switching the setting on for one test."""
from datetime import date

import pytest

from app.core.config import settings
from tests import factories
from tests import factories_payroll as fp

API = "/api/payroll"


@pytest.fixture(scope="module")
def ctx(db, client):
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    finance = factories.login_as(db, client, company, role_codes="finance")
    h = admin["headers"]
    tax = fp.tax_structure(client, h)
    bank = fp.bank(client, h)
    return {"company": company, "h": h, "finance": finance["headers"], "tax": tax, "bank": bank}


def _closable_run(client, db, ctx, month: str) -> dict:
    """A monthly run with two people, run and ready to close: one paid by bank with an e-mail, one paid in cash
    without one. Returns {"run", "banked", "cash", "account"}."""
    h, company = ctx["h"], ctx["company"]
    banked = fp.employee(db, company, salary=90000, first_name="Banked")
    cash = fp.employee(db, company, salary=40000, first_name="Cash")
    account = fp.bank_account(db, banked)
    fp.email(db, banked)
    run = fp.payroll(client, h, month, ctx["tax"]["id"], ctx["bank"]["id"], taxApplicable=False)
    r = client.put(f"{API}/payrolls/{run['id']}/employees", json={"employeeIds": [str(banked), str(cash)]}, headers=h)
    assert r.status_code == 200, r.text
    log = client.post(f"{API}/payrolls/{run['id']}/run", headers=h).json()["data"]
    assert log["processedCount"] == 2, log
    run = client.get(f"{API}/payrolls/{run['id']}", headers=h).json()["data"]
    return {"run": run, "banked": banked, "cash": cash, "account": account}


# --------------------------------------------------------------------------- P1 close e-mail, P3 bank file

def test_close_email_and_bank_file(client, db, ctx):
    h = ctx["h"]
    x = _closable_run(client, db, ctx, "2026-07-01")
    run = x["run"]

    preview = client.get(f"{API}/payrolls/{run['id']}/close-email/preview", headers=h)
    assert preview.status_code == 200, preview.text
    p = preview.json()["data"]
    assert p["enabled"] is False and p["recipientCount"] == 1
    assert "July 2026" in p["subject"] and "<p>" in p["bodyHtml"]
    before = client.get(f"{API}/payrolls/{run['id']}/close-email", headers=h).json()["data"]
    assert before["status"] == "none" and before["failures"] == []

    # The bank file waits for the close.
    early = client.get(f"{API}/payrolls/{run['id']}/bank-file", headers=h)
    assert early.status_code == 409 and early.json()["code"] == "PAYROLL_NOT_CLOSED"

    stale = client.post(f"{API}/payrolls/{run['id']}/close", json={"rowVersion": "0000000000000001"}, headers=h)
    assert stale.status_code == 409
    closed = client.post(f"{API}/payrolls/{run['id']}/close", json={"rowVersion": run["rowVersion"]}, headers=h)
    assert closed.status_code == 200, closed.text
    c = closed.json()["data"]
    assert c["status"] == "closed" and c["email"] == {"status": "disabled", "sentCount": 0, "failedCount": 0}

    state = client.get(f"{API}/payrolls/{run['id']}/close-email", headers=h).json()["data"]
    assert state["status"] == "disabled" and state["recipientCount"] == 1 and state["sentCount"] == 0
    assert state["queuedAt"] is None and state["sentAt"] is None and state["failures"] == []
    outbox = fp.rows(db, "SELECT employee_id, status FROM pay.mail_outbox WHERE entity_type = N'pay.payroll' AND entity_id = ?",
                     int(run["id"]))
    assert outbox == [{"employee_id": x["banked"], "status": "disabled"}]

    formats = client.get(f"{API}/bank-file-formats", headers=h)
    assert formats.status_code == 200
    assert [(f["code"], f["extension"]) for f in formats.json()["data"]] == [("csv", "csv"), ("txt", "txt")]

    csv_file = client.get(f"{API}/payrolls/{run['id']}/bank-file",
                          params={"disbursementBankId": ctx["bank"]["id"], "format": "csv"}, headers=h)
    assert csv_file.status_code == 200, csv_file.text
    assert csv_file.headers["content-type"].startswith("text/csv")
    assert csv_file.headers["content-disposition"].startswith("attachment; filename=") and ".csv" in \
        csv_file.headers["content-disposition"]
    lines = csv_file.content.decode("utf-8-sig").strip().splitlines()
    assert lines[0].startswith("Employee Code,") and len(lines) == 2          # the cash-paid person is left out
    assert x["account"] in lines[1] and lines[1].split(",")[6] == "90000.00"

    txt = client.get(f"{API}/payrolls/{run['id']}/bank-file", params={"format": "txt"}, headers=h)
    assert txt.status_code == 200 and txt.headers["content-type"].startswith("text/plain")
    records = txt.text.strip().splitlines()
    assert [r[0] for r in records] == ["H", "D", "T"] and x["account"] in records[1]
    assert records[2] == "T" + "000001" + "9000000".rjust(15, "0")

    bad = client.get(f"{API}/payrolls/{run['id']}/bank-file", params={"format": "pdf"}, headers=h)
    assert bad.status_code == 422 and "format" in bad.json()["fieldErrors"]
    other_bank = fp.bank(client, h)
    wrong = client.get(f"{API}/payrolls/{run['id']}/bank-file", params={"disbursementBankId": other_bank["id"]},
                       headers=h)
    assert wrong.status_code == 422 and "disbursementBankId" in wrong.json()["fieldErrors"]

    # Finance exports (payroll.*.export) but does not close.
    assert client.get(f"{API}/payrolls/{run['id']}/bank-file", headers=ctx["finance"]).status_code == 200
    assert client.get(f"{API}/bank-file-formats", headers=ctx["finance"]).status_code == 200
    assert client.get(f"{API}/payrolls/999999999/close-email/preview", headers=h).status_code == 404


def test_close_email_is_queued_when_mail_is_on(client, db, ctx, monkeypatch):
    x = _closable_run(client, db, ctx, "2026-08-01")
    monkeypatch.setattr(settings, "mail_enabled", True)
    assert client.get(f"{API}/payrolls/{x['run']['id']}/close-email/preview", headers=ctx["h"]).json()["data"]["enabled"]
    closed = client.post(f"{API}/payrolls/{x['run']['id']}/close", json={"rowVersion": x["run"]["rowVersion"]},
                         headers=ctx["h"])
    assert closed.status_code == 200, closed.text
    assert closed.json()["data"]["email"]["status"] == "queued"
    state = client.get(f"{API}/payrolls/{x['run']['id']}/close-email", headers=ctx["h"]).json()["data"]
    assert state["status"] == "queued" and state["queuedAt"] is not None and state["recipientCount"] == 1
    queued = fp.rows(db, "SELECT status, subject FROM pay.mail_outbox WHERE entity_type = N'pay.payroll' AND entity_id = ?",
                     int(x["run"]["id"]))
    assert len(queued) == 1 and queued[0]["status"] == "queued" and "August 2026" in queued[0]["subject"]


def test_daily_wage_bank_file(client, db, ctx):
    h, company = ctx["h"], ctx["company"]
    work_date = date(2026, 8, 4)
    worker = fp.employee(db, company, salary=4000, frequency="daily", first_name="Daily")
    account = fp.bank_account(db, worker)
    fp.day(db, company, worker, work_date, "present", worked=480)
    slot = fp.time_slot(db, company)
    run = client.post(f"{API}/daily-wages", json={"name": "Site B", "workDate": str(work_date), "timeSlotId": str(slot),
                                                  "employeeIds": [str(worker)]}, headers=h).json()["data"]
    assert client.get(f"{API}/daily-wages/{run['id']}/bank-file", params={"disbursementBankId": ctx["bank"]["id"]},
                      headers=h).json()["code"] == "PAYROLL_NOT_CLOSED"
    assert client.post(f"{API}/daily-wages/{run['id']}/process", headers=h).json()["data"]["processedCount"] == 1
    current = client.get(f"{API}/daily-wages/{run['id']}", headers=h).json()["data"]
    closed = client.post(f"{API}/daily-wages/{run['id']}/close", json={"rowVersion": current["rowVersion"]}, headers=h)
    assert closed.status_code == 200 and closed.json()["data"]["email"] is None, closed.text
    # A daily-wage run names no disbursement bank: the bank is required, and any of the company's will do.
    assert client.get(f"{API}/daily-wages/{run['id']}/bank-file", headers=h).status_code == 422
    f = client.get(f"{API}/daily-wages/{run['id']}/bank-file", params={"disbursementBankId": ctx["bank"]["id"]},
                   headers=h)
    assert f.status_code == 200, f.text
    rows = f.content.decode("utf-8-sig").strip().splitlines()
    assert len(rows) == 2 and account in rows[1] and rows[1].split(",")[6] == "4000.00"


# --------------------------------------------------------------------------- P2 salary revision letter

def test_salary_revision_email(client, db, ctx, monkeypatch):
    h, company = ctx["h"], ctx["company"]
    e = fp.employee(db, company, salary=50000, first_name="Revised", last_name="Person")
    address = fp.email(db, e)
    r = client.post(f"{API}/salary-revisions", json={"employeeId": str(e), "effectiveDate": "2026-10-01",
                                                     "changeType": "flat", "changeValue": 5000}, headers=h)
    assert r.status_code == 201, r.text
    rev = r.json()["data"]
    assert rev["emailStatus"] == "none" and rev["emailedAt"] is None
    listed = client.get(f"{API}/salary-revisions", params={"employeeId": str(e)}, headers=h).json()["data"]
    assert {x["emailStatus"] for x in listed} == {"none"}

    preview = client.get(f"{API}/salary-revisions/{rev['id']}/email/preview", headers=h)
    assert preview.status_code == 200, preview.text
    p = preview.json()["data"]
    assert p["to"] == address and "01 October 2026" in p["subject"] and "55,000.00" in p["bodyHtml"]

    stale = client.post(f"{API}/salary-revisions/{rev['id']}/email", json={"rowVersion": "0000000000000001"}, headers=h)
    assert stale.status_code == 409
    assert client.post(f"{API}/salary-revisions/{rev['id']}/email", json={"rowVersion": rev["rowVersion"]},
                       headers=ctx["finance"]).status_code == 403
    sent = client.post(f"{API}/salary-revisions/{rev['id']}/email", json={"rowVersion": rev["rowVersion"]}, headers=h)
    assert sent.status_code == 200, sent.text
    assert sent.json()["data"] == {"status": "disabled", "sentAt": None}
    assert client.get(f"{API}/salary-revisions/{rev['id']}", headers=h).json()["data"]["emailStatus"] == "disabled"

    monkeypatch.setattr(settings, "mail_enabled", True)
    queued = client.post(f"{API}/salary-revisions/{rev['id']}/email", json={"rowVersion": rev["rowVersion"]}, headers=h)
    assert queued.status_code == 200 and queued.json()["data"]["status"] == "queued", queued.text
    again = client.post(f"{API}/salary-revisions/{rev['id']}/email", json={"rowVersion": rev["rowVersion"]}, headers=h)
    assert again.status_code == 409 and again.json()["code"] == "EMAIL_QUEUED"

    no_mail = fp.employee(db, company, salary=30000, first_name="No", last_name="Mail")
    r2 = client.post(f"{API}/salary-revisions", json={"employeeId": str(no_mail), "effectiveDate": "2026-10-01",
                                                      "changeType": "percent", "changeValue": 10}, headers=h).json()["data"]
    assert client.get(f"{API}/salary-revisions/{r2['id']}/email/preview", headers=h).json()["data"]["to"] == ""
    missing = client.post(f"{API}/salary-revisions/{r2['id']}/email", json={"rowVersion": r2["rowVersion"]}, headers=h)
    assert missing.status_code == 422 and "to" in missing.json()["fieldErrors"]

    # Deleting the revision withdraws the unsent letter.
    gone = client.delete(f"{API}/salary-revisions/{rev['id']}", params={"rowVersion": rev["rowVersion"]}, headers=h)
    assert gone.status_code == 204, gone.text
    assert fp.scalar(db, "SELECT COUNT(*) FROM pay.mail_outbox WHERE entity_type = N'hr.employee_salary' AND entity_id = ?",
                     int(rev["id"])) == 0


# --------------------------------------------------------------------------- P4 leave encashment limits

def test_leave_encashment_preview_and_limits(client, db, ctx):
    h, company = ctx["h"], ctx["company"]
    casual = fp.leave_type(db, company, f"Casual {factories.tag()}", encash=True, encash_max=10)
    fp.execute(db, "UPDATE lv.leave_type SET encashment_min = 2 WHERE id = ?", casual)
    off = fp.leave_type(db, company, f"Sick {factories.tag()}", encash=False)
    many = fp.employee(db, company, salary=60000, first_name="Many")
    few = fp.employee(db, company, salary=60000, first_name="Few")
    some = fp.employee(db, company, salary=60000, first_name="Some")
    for emp, days in ((many, 14), (few, 1), (some, 5)):
        fp.ledger(db, emp, casual, 2026, date(2026, 1, 1), days)
    people = [str(many), str(few), str(some)]
    body = {"leaveTypeId": str(casual), "fiscalYear": 2026, "allEmployees": False, "employeeIds": people,
            "basis": "overtime", "amountPerLeave": 1000}

    r = client.post(f"{API}/leave-encashments/preview", json=body, headers=h)
    assert r.status_code == 200, r.text
    by = {x["employeeId"]: x for x in r.json()["data"]}
    assert (by[str(many)]["availableDays"], by[str(many)]["encashableDays"], by[str(many)]["cappedBy"],
            by[str(many)]["amount"]) == (14, 10, "max", 10000)
    assert (by[str(few)]["encashableDays"], by[str(few)]["cappedBy"], by[str(few)]["amount"]) == (0, "min", 0)
    assert (by[str(some)]["encashableDays"], by[str(some)]["cappedBy"], by[str(some)]["amount"]) == (5, None, 5000)
    assert by[str(many)]["employeeName"].startswith("Many")

    refused = client.post(f"{API}/leave-encashments/preview", json={**body, "leaveTypeId": str(off)}, headers=h)
    assert refused.status_code == 422 and "leaveTypeId" in refused.json()["fieldErrors"]
    nobody = client.post(f"{API}/leave-encashments/preview", json={**body, "employeeIds": []}, headers=h)
    assert nobody.status_code == 422 and "employeeIds" in nobody.json()["fieldErrors"]

    # Saving applies the same limits: the type must allow encashment, under the minimum is left out, above the
    # maximum is paid for the maximum, nobody left is refused on employeeIds.
    save = {**body, "mode": "manual"}
    off_type = client.post(f"{API}/leave-encashments", json={**save, "leaveTypeId": str(off)}, headers=h)
    assert off_type.status_code == 422 and "leaveTypeId" in off_type.json()["fieldErrors"]
    only_few = client.post(f"{API}/leave-encashments", json={**save, "employeeIds": [str(few)]}, headers=h)
    assert only_few.status_code == 422 and "minimum of 2 days" in only_few.json()["fieldErrors"]["employeeIds"]
    created = client.post(f"{API}/leave-encashments", json=save, headers=h)
    assert created.status_code == 201, created.text
    enc = created.json()["data"]
    paid = {x["employeeId"]: (x["days"], x["amount"]) for x in enc["employees"]}
    assert paid == {str(many): (10, 10000), str(some): (5, 5000)}

    # Editing: the preview gives the encashment's own days back.
    again = client.post(f"{API}/leave-encashments/preview", json={**body, "id": enc["id"]}, headers=h).json()["data"]
    assert {x["employeeId"]: x["availableDays"] for x in again} == {str(many): 14, str(few): 1, str(some): 5}
    edited = client.put(f"{API}/leave-encashments/{enc['id']}", json={**save, "employeeIds": [str(some)],
                                                                      "rowVersion": enc["rowVersion"]}, headers=h)
    assert edited.status_code == 200, edited.text
    assert [(x["employeeId"], x["days"]) for x in edited.json()["data"]["employees"]] == [(str(some), 5)]

    # Finance reads payroll but does not create encashments.
    assert client.post(f"{API}/leave-encashments/preview", json=body, headers=ctx["finance"]).status_code == 403
