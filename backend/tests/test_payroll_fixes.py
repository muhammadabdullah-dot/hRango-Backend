"""Payroll findings of the Test Run (18-19 Nov 2026), fix group B:
8.42 / 8B.37 payroll e-mails really sent through the mail sender; 8B.16 four eyes on vouchers; 8B.18 a verified
Salary Advance posted to Employee Accounts and recovered from salary; 8B.42 the encashment maximum per person a
year; 8B.5 no daily wage for a day a monthly payroll pays; 13.46 a final settlement recovers salary paid after the
last working date; 8.30 one-off lines on Edit Pay Slip."""
from datetime import date
from email import message_from_bytes, policy

import pytest

from app.core import mail
from app.core.config import settings
from tests import factories
from tests import factories_payroll as fp

API = "/api/payroll"


@pytest.fixture(scope="module")
def ctx(db, client):
    company = factories.company(db)
    me = fp.employee(db, company, salary=90000, first_name="Usman", last_name="Manager")
    admin = factories.login_as(db, client, company, role_codes="company_admin", employee_id=me)
    finance = factories.login_as(db, client, company, role_codes="finance")
    h = admin["headers"]
    return {"company": company, "me": me, "h": h, "admin": admin, "finance": finance["headers"],
            "tax": fp.tax_structure(client, h), "bank": fp.bank(client, h)}


@pytest.fixture()
def file_mail(monkeypatch, tmp_path):
    """Mail on, written as .eml files to a folder of this test (the file backend)."""
    for name, value in {"mail_enabled": True, "mail_backend": "file", "mail_file_dir": str(tmp_path),
                        "mail_from": "hRango <no-reply@hrango.test>", "app_public_url": "https://app.hrango.test"}.items():
        monkeypatch.setattr(settings, name, value)
    return tmp_path


def _drain(db):
    while mail.deliver_due(db):
        pass


def _mails_to(folder, address: str) -> list:
    found = [message_from_bytes(f.read_bytes(), policy=policy.default) for f in sorted(folder.glob("*.eml"))]
    return [m for m in found if address in m["To"]]


def _run(client, db, ctx, month: str, people: list[int], **kw) -> dict:
    run = fp.payroll(client, ctx["h"], month, ctx["tax"]["id"], ctx["bank"]["id"], taxApplicable=False, **kw)
    r = client.put(f"{API}/payrolls/{run['id']}/employees", json={"employeeIds": [str(p) for p in people]}, headers=ctx["h"])
    assert r.status_code == 200, r.text
    log = client.post(f"{API}/payrolls/{run['id']}/run", headers=ctx["h"]).json()["data"]
    assert log["processedCount"] == len(people), log
    return client.get(f"{API}/payrolls/{run['id']}", headers=ctx["h"]).json()["data"]


def _close(client, ctx, run: dict) -> dict:
    current = client.get(f"{API}/payrolls/{run['id']}", headers=ctx["h"]).json()["data"]
    r = client.post(f"{API}/payrolls/{run['id']}/close", json={"rowVersion": current["rowVersion"]}, headers=ctx["h"])
    assert r.status_code == 200, r.text
    return r.json()["data"]


def _slip(client, ctx, run_id: str, employee_id: int) -> dict:
    slips = client.get(f"{API}/payslips", params={"payrollId": run_id}, headers=ctx["h"]).json()["data"]
    one = next(s for s in slips if s["employeeId"] == str(employee_id))
    return client.get(f"{API}/payslips/{one['id']}", headers=ctx["h"]).json()["data"]


# --------------------------------------------------------------------------- 8.42 close e-mail, 8B.37 revision letter

def test_close_email_goes_out_one_message_each_and_states_follow(client, db, ctx, file_mail):
    company = ctx["company"]
    asad = fp.employee(db, company, salary=120000, first_name="Asad", last_name="Mailed")
    komal = fp.employee(db, company, salary=80000, first_name="Komal", last_name="Mailed")
    broken = fp.employee(db, company, salary=50000, first_name="Bad", last_name="Address")
    asad_to, komal_to = fp.email(db, asad), fp.email(db, komal)
    fp.email(db, broken, "not-an-address")
    run = _run(client, db, ctx, "2026-09-01", [asad, komal, broken])

    closed = _close(client, ctx, run)
    # The bad address is refused by the sender at once; the other two wait for the worker.
    assert closed["email"] == {"status": "queued", "sentCount": 0, "failedCount": 1}
    rows = fp.rows(db, "SELECT employee_id, status, mail_message_id, error FROM pay.mail_outbox "
                       "WHERE entity_type = N'pay.payroll' AND entity_id = ? ORDER BY employee_id", int(run["id"]))
    by = {r["employee_id"]: r for r in rows}
    assert by[asad]["status"] == "queued" and by[asad]["mail_message_id"] is not None
    assert by[broken]["status"] == "failed" and by[broken]["mail_message_id"] is None and by[broken]["error"]

    _drain(db)
    for person, address in ((asad, asad_to), (komal, komal_to)):
        got = _mails_to(file_mail, address)
        assert len(got) == 1, address               # each person their own message
        assert got[0]["Subject"] == "Your payslip for September 2026 is ready"
        assert got[0]["To"].count("@") == 1
        text = got[0].get_body(("plain",)).get_content()
        assert "Mailed" in text and "Pay Slips" in text
        assert "120,000" not in text and "80,000" not in text   # no amounts
    assert {r["status"] for r in fp.rows(db, "SELECT status FROM pay.mail_outbox WHERE entity_type = N'pay.payroll' "
                                             "AND entity_id = ? AND employee_id <> ?", int(run["id"]), broken)} == {"sent"}

    state = client.get(f"{API}/payrolls/{run['id']}/close-email", headers=ctx["h"]).json()["data"]
    assert state["status"] == "failed" and state["sentCount"] == 2 and state["failedCount"] == 1
    assert state["sentAt"] is not None and [f["employeeId"] for f in state["failures"]] == [str(broken)]


def test_close_email_all_sent_and_mail_off_sends_nothing(client, db, ctx, file_mail, monkeypatch):
    company = ctx["company"]
    one = fp.employee(db, company, salary=60000, first_name="Only")
    to = fp.email(db, one)
    run = _run(client, db, ctx, "2026-10-01", [one])
    assert _close(client, ctx, run)["email"]["status"] == "queued"
    _drain(db)
    state = client.get(f"{API}/payrolls/{run['id']}/close-email", headers=ctx["h"]).json()["data"]
    assert state["status"] == "sent" and state["sentCount"] == 1 and state["failures"] == []
    assert len(_mails_to(file_mail, to)) == 1

    monkeypatch.setattr(settings, "mail_enabled", False)
    off = fp.employee(db, company, salary=60000, first_name="Off")
    off_to = fp.email(db, off)
    run2 = _run(client, db, ctx, "2026-10-01", [off], name=f"Second {factories.tag()}")
    assert _close(client, ctx, run2)["email"]["status"] == "disabled"
    assert fp.scalar(db, "SELECT COUNT(*) FROM core.mail_message WHERE to_address = ?", off_to) == 0
    assert fp.scalar(db, "SELECT status FROM pay.mail_outbox WHERE entity_type = N'pay.payroll' AND entity_id = ?",
                     int(run2["id"])) == "disabled"


def test_salary_revision_letter_is_sent_to_the_person(client, db, ctx, file_mail):
    e = fp.employee(db, ctx["company"], salary=135000, first_name="Taha", last_name="Revised")
    to = fp.email(db, e)
    rev = client.post(f"{API}/salary-revisions", json={"employeeId": str(e), "effectiveDate": "2026-12-01",
                                                       "changeType": "percent", "changeValue": 8}, headers=ctx["h"])
    assert rev.status_code == 201, rev.text
    rev = rev.json()["data"]
    sent = client.post(f"{API}/salary-revisions/{rev['id']}/email", json={"rowVersion": rev["rowVersion"]},
                       headers=ctx["h"])
    assert sent.status_code == 200 and sent.json()["data"]["status"] == "queued", sent.text
    _drain(db)
    got = _mails_to(file_mail, to)
    assert len(got) == 1 and got[0]["Subject"] == "Salary revision effective 01 December 2026"
    text = got[0].get_body(("plain",)).get_content()
    assert "135,000.00" in text and "145,800.00" in text and "Taha Revised" in text
    after = client.get(f"{API}/salary-revisions/{rev['id']}", headers=ctx["h"]).json()["data"]
    assert after["emailStatus"] == "sent" and after["emailedAt"] is not None


# --------------------------------------------------------------------------- 8B.16 four eyes, 8B.18 salary advance

def test_voucher_is_verified_by_someone_who_neither_raised_nor_approved_it(client, db, ctx):
    h, company = ctx["h"], ctx["company"]
    worker = fp.employee(db, company, salary=40000)
    other = factories.login_as(db, client, company, role_codes="company_admin")    # no employee record
    v = client.post(f"{API}/vouchers", json={"employeeId": str(worker), "voucherType": "bonus", "voucherDate": "2026-08-03",
                                            "amount": 1500, "paymentMethod": "cash", "purpose": "Award"}, headers=h).json()["data"]
    assert v["createdByUserId"] == str(ctx["admin"]["user_id"])
    a = client.post(f"{API}/vouchers/{v['id']}/approve", json={"rowVersion": v["rowVersion"]}, headers=h).json()["data"]
    mine = client.post(f"{API}/vouchers/{v['id']}/verify", json={"rowVersion": a["rowVersion"]}, headers=h)
    assert mine.status_code == 403 and mine.json()["code"] == "VOUCHER_SAME_PERSON"
    assert "approved" in mine.json()["message"]

    # Raised by one, approved by another: neither may verify; a third person does.
    v2 = client.post(f"{API}/vouchers", json={"employeeId": str(worker), "voucherType": "bonus", "voucherDate": "2026-08-04",
                                             "amount": 900, "paymentMethod": "cash", "purpose": "Award"}, headers=h).json()["data"]
    a2 = client.post(f"{API}/vouchers/{v2['id']}/approve", json={"rowVersion": v2["rowVersion"]},
                     headers=other["headers"]).json()["data"]
    raised = client.post(f"{API}/vouchers/{v2['id']}/verify", json={"rowVersion": a2["rowVersion"]}, headers=h)
    assert raised.status_code == 403 and "raised" in raised.json()["message"]
    approver = client.post(f"{API}/vouchers/{v2['id']}/verify", json={"rowVersion": a2["rowVersion"]},
                           headers=other["headers"])
    assert approver.status_code == 403 and approver.json()["code"] == "VOUCHER_SAME_PERSON"
    ok = client.post(f"{API}/vouchers/{v2['id']}/verify", json={"rowVersion": a2["rowVersion"]}, headers=ctx["finance"])
    assert ok.status_code == 200 and ok.json()["data"]["status"] == "processed", ok.text


def test_verified_salary_advance_is_posted_and_recovered_from_salary(client, db, ctx):
    h, company = ctx["h"], ctx["company"]
    asad = fp.employee(db, company, salary=90000, first_name="Asad", last_name="Advance")
    v = client.post(f"{API}/vouchers", json={"employeeId": str(asad), "voucherType": "salary_advance",
                                            "voucherDate": "2026-09-05", "amount": 25000, "paymentMethod": "bank_transfer",
                                            "purpose": "Test salary advance"}, headers=h).json()["data"]
    a = client.post(f"{API}/vouchers/{v['id']}/approve", json={"rowVersion": v["rowVersion"]}, headers=h).json()["data"]
    done = client.post(f"{API}/vouchers/{v['id']}/verify", json={"rowVersion": a["rowVersion"], "remarks": "Paid"},
                       headers=ctx["finance"])
    assert done.status_code == 200, done.text
    assert done.json()["data"]["loanId"] is not None

    # Employee Accounts and the statement: a debit of the advance.
    statement = client.get(f"{API}/account-statement", params={"employeeId": str(asad)}, headers=h).json()["data"]
    assert [(r["accountName"], r["debit"], r["credit"], r["balance"]) for r in statement] == [("Salary Advance", 25000, 0, -25000)]
    assert v["voucherNo"] in statement[0]["description"] and "September 2026" in statement[0]["description"]
    summary = client.get(f"{API}/payslips/summary", params={"employeeId": str(asad)}, headers=h).json()["data"]
    assert summary["advancesPaid"] == 25000 and not summary["outstandingLoan"] and summary["accounts"] == []
    inst = fp.rows(db, "SELECT i.due_month, i.amount, i.status FROM loan.loan_installment i WHERE i.loan_id = ?",
                   int(done.json()["data"]["loanId"]))
    assert inst == [{"due_month": date(2026, 9, 1), "amount": 25000, "status": "due"}]
    # The posted entry is the voucher's: Employee Accounts cannot change it.
    entry = fp.rows(db, "SELECT id, row_version FROM pay.employee_account_entry WHERE voucher_id = ?", int(v["id"]))[0]
    gone = client.delete(f"{API}/employee-accounts/{entry['id']}", params={"rowVersion": entry["row_version"].hex()},
                         headers=h)
    assert gone.status_code == 409 and gone.json()["code"] == "ENTRY_FROM_VOUCHER"

    # September's payroll deducts it; closing marks it recovered and credits the account back.
    run = _run(client, db, ctx, "2026-09-01", [asad], name=f"Advance {factories.tag()}")
    slip = _slip(client, ctx, run["id"], asad)
    assert {l["systemCode"]: l["amount"] for l in slip["lines"] if l["systemCode"]}["loan_deduction"] == 25000
    assert slip["netPayable"] == 65000
    _close(client, ctx, run)
    statement = client.get(f"{API}/account-statement", params={"employeeId": str(asad)}, headers=h).json()["data"]
    assert [(r["debit"], r["credit"], r["balance"]) for r in statement] == [(25000, 0, -25000), (0, 25000, 0)]
    summary = client.get(f"{API}/payslips/summary", params={"employeeId": str(asad)}, headers=h).json()["data"]
    assert summary["advancesPaid"] == 0 and not summary["outstandingLoan"]
    assert fp.scalar(db, "SELECT status FROM loan.loan WHERE id = ?", int(done.json()["data"]["loanId"])) == "settled"


def test_salary_advance_in_a_closed_month_is_recovered_the_month_after(client, db, ctx):
    h, company = ctx["h"], ctx["company"]
    e = fp.employee(db, company, salary=50000, first_name="Late")
    _close(client, ctx, _run(client, db, ctx, "2026-11-01", [e], name=f"Nov {factories.tag()}"))
    v = client.post(f"{API}/vouchers", json={"employeeId": str(e), "voucherType": "salary_advance", "voucherDate": "2026-11-18",
                                            "amount": 10000, "paymentMethod": "cash", "purpose": "Advance"}, headers=h).json()["data"]
    a = client.post(f"{API}/vouchers/{v['id']}/approve", json={"rowVersion": v["rowVersion"]}, headers=h).json()["data"]
    done = client.post(f"{API}/vouchers/{v['id']}/verify", json={"rowVersion": a["rowVersion"]}, headers=ctx["finance"])
    assert done.status_code == 200, done.text
    due = fp.scalar(db, "SELECT due_month FROM loan.loan_installment WHERE loan_id = ?", int(done.json()["data"]["loanId"]))
    assert due == date(2026, 12, 1)


# --------------------------------------------------------------------------- 8B.42 encashment maximum per year

def test_encashment_maximum_is_per_person_a_year(client, db, ctx):
    h, company = ctx["h"], ctx["company"]
    annual = fp.leave_type(db, company, f"Annual {factories.tag()}", encash=True, encash_max=10)
    fp.execute(db, "UPDATE lv.leave_type SET encashment_min = 2 WHERE id = ?", annual)
    maham = fp.employee(db, company, salary=60000, first_name="Maham")
    other = fp.employee(db, company, salary=60000, first_name="Other")
    fp.ledger(db, maham, annual, 2026, date(2026, 1, 1), 14)
    fp.ledger(db, other, annual, 2026, date(2026, 1, 1), 6)
    body = {"leaveTypeId": str(annual), "fiscalYear": 2026, "employeeIds": [str(maham), str(other)],
            "basis": "earned_salary"}
    first = client.post(f"{API}/leave-encashments", json={**body, "mode": "manual"}, headers=h)
    assert first.status_code == 201, first.text
    assert {x["employeeId"]: x["days"] for x in first.json()["data"]["employees"]} == {str(maham): 10, str(other): 6}

    fp.ledger(db, other, annual, 2026, date(2026, 6, 1), 8)    # more leave given later in the year
    preview = client.post(f"{API}/leave-encashments/preview", json=body, headers=h).json()["data"]
    by = {x["employeeId"]: x for x in preview}
    # Maham has 4 days left but has had the year's maximum of 10; Other may have 4 more (10 - 6).
    assert (by[str(maham)]["availableDays"], by[str(maham)]["alreadyEncashedDays"], by[str(maham)]["encashableDays"],
            by[str(maham)]["cappedBy"], by[str(maham)]["amount"]) == (4, 10, 0, "max", 0)
    assert (by[str(other)]["availableDays"], by[str(other)]["alreadyEncashedDays"], by[str(other)]["encashableDays"],
            by[str(other)]["cappedBy"]) == (8, 6, 4, "max")

    only_maham = client.post(f"{API}/leave-encashments", json={**body, "employeeIds": [str(maham)], "mode": "manual"},
                             headers=h)
    assert only_maham.status_code == 422
    assert "maximum of 10 days" in only_maham.json()["fieldErrors"]["employeeIds"]
    second = client.post(f"{API}/leave-encashments", json={**body, "mode": "manual"}, headers=h)
    assert second.status_code == 201, second.text
    assert {x["employeeId"]: x["days"] for x in second.json()["data"]["employees"]} == {str(other): 4}
    assert fp.scalar(db, "SELECT -SUM(days) FROM lv.leave_ledger WHERE employee_id = ? AND leave_type_id = ? "
                         "AND reason = N'encashed'", other, annual) == 10


# --------------------------------------------------------------------------- 8B.5 daily wages and monthly payroll

def test_no_daily_wage_for_a_day_the_monthly_payroll_pays(client, db, ctx):
    h, company = ctx["h"], ctx["company"]
    day = date(2026, 10, 14)
    dept = factories.department(db, company)
    maham = fp.employee(db, company, salary=155000, first_name="Maham", last_name="Monthly", department_id=dept)
    late = fp.employee(db, company, salary=155000, first_name="Joins", last_name="Later", joined=date(2026, 10, 20),
                       department_id=dept)
    worker = fp.employee(db, company, salary=4000, frequency="daily", first_name="Daily", last_name="Worker",
                         department_id=dept)
    for person in (maham, late, worker):
        fp.day(db, company, person, day, "present", worked=480)
    monthly = fp.payroll(client, h, "2026-10-01", ctx["tax"]["id"], ctx["bank"]["id"], taxApplicable=False,
                         name=f"October {factories.tag()}")
    assert client.put(f"{API}/payrolls/{monthly['id']}/employees", json={"employeeIds": [str(maham), str(late)]},
                      headers=h).status_code == 200
    slot = fp.time_slot(db, company)

    refused = client.post(f"{API}/daily-wages", json={"name": "Site", "workDate": str(day), "timeSlotId": str(slot),
                                                     "employeeIds": [str(maham), str(worker)]}, headers=h)
    assert refused.status_code == 409 and refused.json()["code"] == "PAID_BY_MONTHLY_PAYROLL"
    assert "Maham Monthly" in refused.json()["fieldErrors"]["employeeIds"] and monthly["code"] in refused.json()["message"]
    # Someone who joins after the day is not paid for it by October's payroll; a daily worker never is.
    run = client.post(f"{API}/daily-wages", json={"name": "Site", "workDate": str(day), "timeSlotId": str(slot),
                                                 "employeeIds": [str(late), str(worker)]}, headers=h)
    assert run.status_code == 201, run.text
    run = run.json()["data"]
    # Adding everyone of the department skips (and counts) the person October's payroll pays for the day.
    added = db.call_one("pay.usp_payroll_employee_add_filtered", company_id=company, actor_user_id=ctx["admin"]["user_id"],
                        permission_code="payroll.daily_wages.edit", id=int(run["id"]), department_id=dept)
    assert (added["added"], added["skipped"], added["employee_count"]) == (0, 1, 2)
    people = client.get(f"{API}/payrolls/{run['id']}/employees", headers=h).json()["data"]
    assert {p["employeeId"] for p in people} == {str(late), str(worker)}

    # Processed before a monthly payroll took the worker in: processing again leaves them out, and closing waits.
    assert client.post(f"{API}/daily-wages/{run['id']}/process", headers=h).status_code == 200
    assert client.put(f"{API}/payrolls/{monthly['id']}/employees",
                      json={"employeeIds": [str(maham), str(late), str(worker)]}, headers=h).status_code == 200
    current = client.get(f"{API}/daily-wages/{run['id']}", headers=h).json()["data"]
    blocked = client.post(f"{API}/daily-wages/{run['id']}/close", json={"rowVersion": current["rowVersion"]}, headers=h)
    assert blocked.status_code == 409 and blocked.json()["code"] == "PAID_BY_MONTHLY_PAYROLL"
    log = client.post(f"{API}/daily-wages/{run['id']}/process", headers=h).json()["data"]
    assert log["errorCount"] >= 1
    errors = client.get(f"{API}/daily-wages/{run['id']}/errors", headers=h).json()["data"]
    assert any(e["employeeId"] == str(worker) and "monthly payroll" in e["message"] for e in errors)
    detail = client.get(f"{API}/daily-wages/{run['id']}", headers=h).json()["data"]
    assert {r["employeeId"]: r["wage"] for r in detail["rows"]}[str(worker)] is None


# --------------------------------------------------------------------------- 13.46 final settlement in a paid month

def test_final_settlement_recovers_salary_paid_after_the_last_working_date(client, db, ctx):
    h, company = ctx["h"], ctx["company"]
    danish = fp.employee(db, company, salary=165000, first_name="Danish", last_name="Leaver", joined=date(2021, 9, 13))
    run = _run(client, db, ctx, "2026-11-01", [danish], name=f"November {factories.tag()}")
    assert {l["systemCode"]: l["amount"] for l in _slip(client, ctx, run["id"], danish)["lines"]
            if l["systemCode"]}["salary"] == 165000
    _close(client, ctx, run)
    eoe = fp.end_of_employment(db, company, danish, date(2026, 11, 18))

    fs = client.post(f"{API}/final-settlements/{eoe}/recalculate", headers=h)
    assert fs.status_code == 200, fs.text
    slip = client.get(f"{API}/final-settlements/{eoe}/payslip", headers=h).json()["data"]
    lines = {l["systemCode"]: l for l in slip["lines"] if l["systemCode"]}
    assert "salary" not in lines                                   # November was paid by the closed payroll
    recovery = lines["salary_recovery"]
    assert recovery["amount"] == 66000 and recovery["itemType"] == "deduction"   # 19-30 Nov: 12 x 165,000 / 30
    assert recovery["payItemLabel"] == "Salary paid after last working day"
    assert slip["totalDeductions"] >= 66000

    # A month whose payroll is not closed yet is left to that payroll: nothing is recovered.
    other = fp.employee(db, company, salary=90000, first_name="Open", last_name="Month")
    _run(client, db, ctx, "2026-12-01", [other], name=f"December {factories.tag()}")
    eoe2 = fp.end_of_employment(db, company, other, date(2026, 12, 10))
    assert client.post(f"{API}/final-settlements/{eoe2}/recalculate", headers=h).status_code == 200
    slip2 = client.get(f"{API}/final-settlements/{eoe2}/payslip", headers=h).json()["data"]
    assert "salary_recovery" not in {l["systemCode"] for l in slip2["lines"]}
    # Monthly payrolls do not carry the settlement-only item.
    assert "salary_recovery" not in {i["systemCode"] for i in run["payItems"]}


# --------------------------------------------------------------------------- 8.30 one-off lines on a pay slip

def test_one_off_line_is_added_kept_on_recalculate_and_removed(client, db, ctx):
    h, company = ctx["h"], ctx["company"]
    junaid = fp.employee(db, company, salary=100000, first_name="Junaid", last_name="OneOff")
    bonus = client.post(f"{API}/pay-items", json={"name": f"Test bonus {factories.tag()}", "itemType": "earning",
                                                  "calculationType": "manual", "taxDistribution": "current_month"},
                        headers=h).json()["data"]
    run = _run(client, db, ctx, "2026-08-01", [junaid], name=f"August {factories.tag()}")
    slip = _slip(client, ctx, run["id"], junaid)
    assert slip["netPayable"] == 100000 and bonus["id"] not in {l["payItemId"] for l in slip["lines"]}

    added = client.put(f"{API}/payslips/{slip['id']}", json={"rowVersion": slip["rowVersion"], "lines": [
        {"payItemId": bonus["id"], "amount": 5000, "label": "  Test bonus  "}]}, headers=h)
    assert added.status_code == 200, added.text
    a = added.json()["data"]
    line = next(l for l in a["lines"] if l["payItemId"] == bonus["id"])
    assert line["label"] == "Test bonus" and line["isOneOff"] and line["isManuallyUpdated"] and line["amount"] == 5000
    assert a["netPayable"] == 105000 and a["totalEarnings"] == 105000
    history = client.get(f"{API}/payslips/{slip['id']}/history", headers=h).json()["data"]
    assert any(x["actionName"] == "add" and x["newValue"] == "5000.00" for x in history)

    again = client.post(f"{API}/payslips/{slip['id']}/recalculate", headers=h)
    assert again.status_code == 200, again.text
    kept = _slip(client, ctx, run["id"], junaid)
    line = next(l for l in kept["lines"] if l["payItemId"] == bonus["id"])
    assert (line["label"], line["isOneOff"], line["amount"]) == ("Test bonus", True, 5000) and kept["netPayable"] == 105000

    salary = next(l for l in kept["lines"] if l["systemCode"] == "salary")
    fixed = client.put(f"{API}/payslips/{slip['id']}", json={"rowVersion": kept["rowVersion"], "lines": [
        {"payItemId": salary["payItemId"], "remove": True}]}, headers=h)
    assert fixed.status_code == 422 and fixed.json()["code"] == "LINE_NOT_ONE_OFF"
    no_amount = client.put(f"{API}/payslips/{slip['id']}", json={"rowVersion": kept["rowVersion"], "lines": [
        {"payItemId": bonus["id"]}]}, headers=h)
    assert no_amount.status_code == 422
    negative = client.put(f"{API}/payslips/{slip['id']}", json={"rowVersion": kept["rowVersion"], "lines": [
        {"payItemId": bonus["id"], "amount": -5}]}, headers=h)
    assert negative.status_code == 422

    removed = client.put(f"{API}/payslips/{slip['id']}", json={"rowVersion": kept["rowVersion"], "lines": [
        {"payItemId": bonus["id"], "remove": True}]}, headers=h)
    assert removed.status_code == 200, removed.text
    r = removed.json()["data"]
    assert bonus["id"] not in {l["payItemId"] for l in r["lines"]} and r["netPayable"] == 100000
    history = client.get(f"{API}/payslips/{slip['id']}/history", headers=h).json()["data"]
    assert any(x["actionName"] == "remove" and x["oldValue"] == "5000.00" for x in history)

    _close(client, ctx, run)
    closed = _slip(client, ctx, run["id"], junaid)
    locked = client.put(f"{API}/payslips/{slip['id']}", json={"rowVersion": closed["rowVersion"], "lines": [
        {"payItemId": bonus["id"], "amount": 1}]}, headers=h)
    assert locked.status_code == 409 and locked.json()["code"] == "PAYSLIP_LOCKED"
