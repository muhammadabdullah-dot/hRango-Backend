"""Daily wages, vouchers with finance verification, salary revision, balances, leave encashment, final
settlement and reports."""
from datetime import date, time

import pytest

from tests import factories
from tests import factories_events as fe
from tests import factories_payroll as fp


@pytest.fixture(scope="module")
def ctx(db, client):
    company = factories.company(db)
    me = fp.employee(db, company, salary=90000, first_name="Payroll", last_name="Manager")
    admin = factories.login_as(db, client, company, role_codes="company_admin", employee_id=me)
    finance = factories.login_as(db, client, company, role_codes="finance")
    return {"company": company, "h": admin["headers"], "me": me, "finance": finance["headers"]}


def test_daily_wages_from_the_time_sheet(client, db, ctx):
    h, company = ctx["h"], ctx["company"]
    work_date = date(2026, 8, 3)
    hourly = fp.employee(db, company, salary=500, frequency="hourly", first_name="Hourly")
    daily = fp.employee(db, company, salary=4000, frequency="daily", first_name="Daily")
    half = fp.employee(db, company, salary=3000, frequency="daily", first_name="Half")
    missing = fp.employee(db, company, salary=3000, frequency="daily", first_name="Missing")
    fp.day(db, company, hourly, work_date, "present", worked=450)
    fp.day(db, company, daily, work_date, "present", worked=480)
    fp.day(db, company, half, work_date, "half_day", worked=240)
    slot = fp.time_slot(db, company)

    r = client.post("/api/payroll/daily-wages", json={"name": "Site A", "workDate": str(work_date), "timeSlotId": str(slot),
                                                      "employeeIds": [str(hourly), str(daily), str(half), str(missing)]},
                    headers=h)
    assert r.status_code == 201, r.text
    run = r.json()["data"]
    assert run["kind"] == "daily_wage" and run["employeeCount"] == 4 and run["status"] == "open"

    before = client.get("/api/payroll/reports/daily-wages", params={"from": "2026-08-01", "to": "2026-08-31"},
                        headers=h).json()["data"]
    assert before[0]["employeeCount"] == 4 and before[0]["netPayable"] == 0   # people in the run, before processing

    log = client.post(f"/api/payroll/daily-wages/{run['id']}/process", headers=h).json()["data"]
    assert log["processedCount"] == 3 and log["errorCount"] == 1
    assert log["runByUserId"] is not None and log["runByName"] == "Payroll Manager"
    detail = client.get(f"/api/payroll/daily-wages/{run['id']}", headers=h).json()["data"]
    wages = {row["employeeId"]: row for row in detail["rows"]}
    assert wages[str(hourly)]["wage"] == 3750        # 500 x 7.5 hours
    assert wages[str(daily)]["wage"] == 4000
    assert wages[str(half)]["wage"] == 1500
    assert wages[str(missing)]["wage"] is None
    assert detail["netPayable"] == 9250

    edited = client.put(f"/api/payroll/daily-wages/{run['id']}", json={
        "name": "Site A (edited)", "rows": [{"employeeId": str(daily), "totalEarnings": 4200, "totalDeductions": 200}],
        "rowVersion": detail["rowVersion"]}, headers=h)
    assert edited.status_code == 200, edited.text
    e = edited.json()["data"]
    assert {row["employeeId"]: row for row in e["rows"]}[str(daily)]["netPayable"] == 4000 and e["name"] == "Site A (edited)"
    # Processing again keeps the hand-typed wage.
    client.post(f"/api/payroll/daily-wages/{run['id']}/process", headers=h)
    again = client.get(f"/api/payroll/daily-wages/{run['id']}", headers=h).json()["data"]
    assert {row["employeeId"]: row for row in again["rows"]}[str(daily)]["totalEarnings"] == 4200

    early = client.post(f"/api/payroll/daily-wages/{run['id']}/vouchers", headers=h)
    assert early.status_code == 409
    closed = client.post(f"/api/payroll/daily-wages/{run['id']}/close", json={"rowVersion": again["rowVersion"]}, headers=h)
    assert closed.status_code == 200, closed.text
    made = client.post(f"/api/payroll/daily-wages/{run['id']}/vouchers", headers=h).json()["data"]
    assert made["created"] == 3
    assert client.post(f"/api/payroll/daily-wages/{run['id']}/vouchers", headers=h).json()["data"]["created"] == 0
    vouchers = client.get("/api/payroll/vouchers", params={"payrollId": run["id"]}, headers=h).json()
    assert vouchers["meta"]["total"] == 3 and {v["status"] for v in vouchers["data"]} == {"approved"}

    report = client.get("/api/payroll/reports/daily-wages", params={"from": "2026-08-01", "to": "2026-08-31"},
                        headers=h).json()
    assert report["meta"]["total"] == 1 and report["data"][0]["voucherCount"] == 3
    assert report["data"][0]["employeeCount"] == 4 and report["data"][0]["netPayable"] == 9250


def test_voucher_approval_then_finance_verification(client, db, ctx):
    h = ctx["h"]
    worker = fp.employee(db, ctx["company"], salary=40000)
    factories.user(db, ctx["company"], employee_id=worker, role_codes="employee")
    receipt = factories.upload(client, h, name="Lunch receipt.png", content=factories.PNG_BYTES, module="payroll")
    future = client.post("/api/payroll/vouchers", json={
        "employeeId": str(worker), "voucherType": "travel_allowance", "voucherDate": "2999-01-01", "amount": 1000,
        "paymentMethod": "cash", "purpose": "Trip"}, headers=h)
    assert future.status_code == 422 and "voucherDate" in future.json()["fieldErrors"]
    r = client.post("/api/payroll/vouchers", json={
        "employeeId": str(worker), "voucherType": "expense_reimbursement", "voucherDate": "2026-08-01", "amount": 2500,
        "paymentMethod": "bank_transfer", "purpose": "Client lunch", "fileId": int(receipt["id"])}, headers=h)
    assert r.status_code == 201, r.text
    v = r.json()["data"]
    assert v["fileId"] == receipt["id"] and v["file"]["name"] == "Lunch receipt.png"
    assert client.get(v["file"]["url"]).content == factories.PNG_BYTES
    assert v["status"] == "pending" and v["voucherNo"].startswith("VCH-") and v["requestedById"] == str(ctx["me"])
    dup = client.post("/api/payroll/vouchers", json={
        "employeeId": str(worker), "voucherNo": v["voucherNo"], "voucherType": "bonus", "voucherDate": "2026-08-01",
        "amount": 1, "paymentMethod": "cash", "purpose": "x"}, headers=h)
    assert dup.status_code == 409 and "voucherNo" in dup.json()["fieldErrors"]

    early = client.post(f"/api/payroll/vouchers/{v['id']}/verify", json={"rowVersion": v["rowVersion"]},
                        headers=ctx["finance"])
    assert early.status_code == 409
    assert client.post(f"/api/payroll/vouchers/{v['id']}/approve", json={"rowVersion": v["rowVersion"]},
                       headers=ctx["finance"]).status_code == 403
    approved = client.post(f"/api/payroll/vouchers/{v['id']}/approve", json={"rowVersion": v["rowVersion"]}, headers=h)
    assert approved.status_code == 200 and approved.json()["data"]["approvedById"] == str(ctx["me"])
    decided = fe.events(db, ctx["company"], "payroll.voucher_decided", int(v["id"]))
    assert len(decided) == 1 and decided[0]["data"]["action"] == "approve" and decided[0]["data"]["status"] == "approved"
    verified = client.post(f"/api/payroll/vouchers/{v['id']}/verify",
                           json={"rowVersion": approved.json()["data"]["rowVersion"], "remarks": "Paid"},
                           headers=ctx["finance"])
    assert verified.status_code == 200, verified.text
    assert verified.json()["data"]["status"] == "processed" and verified.json()["data"]["verifiedAt"]
    decisions = fe.events(db, ctx["company"], "payroll.voucher_decided", int(v["id"]))
    assert [e["data"]["status"] for e in decisions] == ["approved", "processed"]
    told = fe.notifications(db, ctx["company"], worker, "pay.voucher", int(v["id"]))
    assert [n["title"] for n in told] == [f"Your voucher {v['voucherNo']} was approved",
                                         f"Your voucher {v['voucherNo']} was verified for payment"]
    assert client.delete(f"/api/payroll/vouchers/{v['id']}", params={"rowVersion": verified.json()["data"]["rowVersion"]},
                         headers=h).status_code == 409

    own = client.post("/api/payroll/vouchers", json={
        "employeeId": str(ctx["me"]), "voucherType": "bonus", "voucherDate": "2026-08-01", "amount": 1,
        "paymentMethod": "cash", "purpose": "Me"}, headers=h)
    assert own.status_code == 403 and own.json()["code"] == "OWN_PAY_RECORD"


def test_salary_revision(client, db, ctx):
    h = ctx["h"]
    e = fp.employee(db, ctx["company"], salary=50000, joined=date(2025, 1, 1),
                    department_id=factories.department(db, ctx["company"]))
    flat = client.post("/api/payroll/salary-revisions", json={"employeeId": str(e), "effectiveDate": "2026-01-01",
                                                              "changeType": "flat", "changeValue": 10000}, headers=h)
    assert flat.status_code == 201, flat.text
    # The list carries the person's department / location / branch like the single record.
    listed = client.get("/api/payroll/salary-revisions", params={"employeeId": str(e)}, headers=h).json()["data"]
    one = client.get(f"/api/payroll/salary-revisions/{flat.json()['data']['id']}", headers=h).json()["data"]
    row = next(x for x in listed if x["id"] == one["id"])
    assert row["departmentName"] is not None and row["branchName"] is not None
    assert (row["departmentName"], row["locationName"], row["branchName"]) ==         (one["departmentName"], one["locationName"], one["branchName"])
    assert flat.json()["data"]["previousAmount"] == 50000 and flat.json()["data"]["amount"] == 60000
    pct = client.post("/api/payroll/salary-revisions", json={"employeeId": str(e), "effectiveDate": "2026-07-01",
                                                             "changeType": "percent", "changeValue": 10}, headers=h)
    assert pct.status_code == 201 and pct.json()["data"]["amount"] == 66000
    older = client.post("/api/payroll/salary-revisions", json={"employeeId": str(e), "effectiveDate": "2026-03-01",
                                                               "changeType": "flat", "changeValue": 1}, headers=h)
    assert older.status_code == 409 and "effectiveDate" in older.json()["fieldErrors"]

    edit_old = client.put(f"/api/payroll/salary-revisions/{flat.json()['data']['id']}", json={
        "employeeId": str(e), "effectiveDate": "2026-01-01", "changeType": "flat", "changeValue": 5,
        "rowVersion": flat.json()["data"]["rowVersion"]}, headers=h)
    assert edit_old.status_code == 409
    edited = client.put(f"/api/payroll/salary-revisions/{pct.json()['data']['id']}", json={
        "employeeId": str(e), "effectiveDate": "2026-07-01", "changeType": "percent", "changeValue": 20,
        "rowVersion": pct.json()["data"]["rowVersion"]}, headers=h)
    assert edited.status_code == 200 and edited.json()["data"]["amount"] == 72000
    current = client.get(f"/api/payroll/salary-revisions/current/{e}", params={"date": "2026-08-01"}, headers=h).json()
    assert current["data"]["salary"] == 72000

    code = fp.scalar(db, "SELECT code FROM hr.employee WHERE id = ?", e)
    imported = client.post("/api/payroll/salary-revisions/import", json={"rows": [
        {"employeeCode": code, "effectiveDate": "2027-01-01", "salary": 80000},
        {"employeeCode": "NOPE", "effectiveDate": "2027-01-01", "salary": 1}]}, headers=h).json()["data"]
    assert imported["created"] == 1 and imported["errors"] == ["Row 2: Employee code not found."]

    # The same import from an uploaded CSV sheet: headers as the sample shows them; bad rows are reported.
    sheet = (f"Employee Code,Effective Date,Salary\r\n{code},2027-06-01,85000\r\nNOPE,2027-06-01,1\r\n"
             f"{code},someday,90000\r\n").encode()
    csv_file = factories.upload(client, h, name="revisions.csv", content=sheet, module="payroll")
    from_file = client.post("/api/payroll/salary-revisions/import", json={"fileId": int(csv_file["id"])}, headers=h)
    assert from_file.status_code == 200, from_file.text
    assert from_file.json()["data"]["created"] == 1
    errors = from_file.json()["data"]["errors"]
    assert errors[0] == "Row 2: Employee code not found." and errors[1].startswith("Row 3: effective_date")
    pdf = factories.upload(client, h, module="payroll")
    not_csv = client.post("/api/payroll/salary-revisions/import", json={"fileId": int(pdf["id"])}, headers=h)
    assert not_csv.status_code == 422 and "fileId" in not_csv.json()["fieldErrors"]
    assert client.post("/api/payroll/salary-revisions/import", json={}, headers=h).status_code == 422
    own = client.post("/api/payroll/salary-revisions", json={"employeeId": str(ctx["me"]), "effectiveDate": "2027-01-01",
                                                             "changeType": "flat", "changeValue": 99999}, headers=h)
    assert own.status_code == 403


def test_balances_and_statement(client, db, ctx):
    h, company = ctx["h"], ctx["company"]
    e = fp.employee(db, company, salary=50000)
    items = client.get("/api/payroll/pay-items", params={"pageSize": 100}, headers=h).json()["data"]
    salary = next(i for i in items if i["systemCode"] == "salary")
    ob = client.post("/api/payroll/opening-balances", json={"employeeId": str(e), "balanceMonth": "2026-07-15",
                                                            "payItemId": salary["id"], "amount": 1500, "isTaxable": True},
                     headers=h)
    assert ob.status_code == 201 and ob.json()["data"]["balanceMonth"] == "2026-07-01"
    listed = client.get("/api/payroll/opening-balances", params={"employeeId": str(e)}, headers=h).json()
    assert listed["data"][0]["netAmount"] == 1500
    detail = client.get(f"/api/payroll/opening-balances/employees/{e}", headers=h).json()["data"]
    assert len(detail["entries"]) == 1
    code = fp.scalar(db, "SELECT code FROM hr.employee WHERE id = ?", e)
    imp = client.post("/api/payroll/opening-balances/import", json={"rows": [
        {"employeeCode": code, "payItem": salary["name"], "month": "2026-08", "amount": 200},
        {"employeeCode": code, "payItem": "Nope", "month": "2026-08", "amount": 200}]}, headers=h).json()["data"]
    assert imp["created"] == 1 and imp["errors"] == ["Row 2: Pay item not found."]
    sheet = f"employeeCode,payItem,month,amount,taxable\n{code},{salary['name']},2026-09,300,true\n".encode()
    up = factories.upload(client, h, name="opening.csv", content=sheet, module="payroll")
    imp = client.post("/api/payroll/opening-balances/import", json={"fileId": int(up["id"])}, headers=h).json()["data"]
    assert imp == {"created": 1, "errors": []}

    acct = client.post("/api/payroll/account-types", json={"name": f"EOBI {factories.tag()}", "category": "custom_pay_item",
                                                           "refId": salary["id"]}, headers=h).json()["data"]
    for month, direction, amount in (("2026-07-01", "credit", 1000), ("2026-08-01", "credit", 1000), ("2026-09-01", "debit", 300)):
        r = client.post("/api/payroll/employee-accounts", json={"employeeId": str(e), "accountTypeId": acct["id"],
                                                                "entryMonth": month, "direction": direction,
                                                                "amount": amount}, headers=h)
        assert r.status_code == 201, r.text
    statement = client.get("/api/payroll/account-statement", params={"employeeId": str(e)}, headers=h).json()
    assert [row["balance"] for row in statement["data"]] == [1000, 2000, 1700]
    summary = client.get("/api/payroll/payslips/summary", params={"employeeId": str(e)}, headers=h).json()["data"]
    assert summary["accounts"][0]["balance"] == 1700
    report = client.get("/api/payroll/reports/employee-accounts", params={"from": "2026-01-01", "to": "2026-12-31",
                                                                          "q": code}, headers=h).json()
    assert report["data"][0]["accounts"][0]["balance"] == 1700


def test_leave_encashment_and_final_settlement(client, db, ctx):
    h, company = ctx["h"], ctx["company"]
    annual = fp.leave_type(db, company, "Annual Leave", encash=True, encash_max=10)
    e = fp.employee(db, company, salary=60000, joined=date(2024, 1, 1))
    factories.user(db, company, employee_id=e, role_codes="employee")
    other = fp.employee(db, company, salary=30000)
    fp.ledger(db, e, annual, 2026, date(2026, 1, 1), 14)
    fp.ledger(db, other, annual, 2026, date(2026, 1, 1), 0)

    refused = client.post("/api/payroll/leave-encashments", json={
        "leaveTypeId": str(annual), "fiscalYear": 2026, "employeeIds": [str(other)], "mode": "manual",
        "basis": "earned_salary"}, headers=h)
    assert refused.status_code == 422
    enc = client.post("/api/payroll/leave-encashments", json={
        "leaveTypeId": str(annual), "fiscalYear": 2026, "employeeIds": [str(e)], "mode": "manual", "basis": "earned_salary"},
                      headers=h)
    assert enc.status_code == 201, enc.text
    row = enc.json()["data"]["employees"][0]
    assert row["days"] == 10 and row["amount"] == 20000  # capped at 10 days x 60,000 / 30
    balance = fp.scalar(db, "SELECT SUM(days) FROM lv.leave_ledger WHERE employee_id = ? AND leave_type_id = ?", e, annual)
    assert balance == 4
    gone = client.delete(f"/api/payroll/leave-encashments/{enc.json()['data']['id']}",
                         params={"rowVersion": enc.json()["data"]["rowVersion"]}, headers=h)
    assert gone.status_code == 204
    assert fp.scalar(db, "SELECT SUM(days) FROM lv.leave_ledger WHERE employee_id = ? AND leave_type_id = ?", e, annual) == 14

    # Final settlement: leaves on 15 Sep 2026 with 14 days of encashable leave (capped at 10) and a loan left.
    fp.loan(db, company, e, [(date(2026, 10, 1), 7000), (date(2026, 11, 1), 7000)])
    d = date(2026, 9, 1)
    while d.day <= 15:
        fp.day(db, company, e, d, "weekend" if d.weekday() == 6 else "present", worked=0 if d.weekday() == 6 else 480)
        d = date(2026, 9, d.day + 1)
    eoe = fp.end_of_employment(db, company, e, date(2026, 9, 15))

    listed = client.get("/api/payroll/final-settlements", params={"q": fp.scalar(db, "SELECT code FROM hr.employee WHERE id = ?", e)},
                        headers=h).json()
    assert listed["meta"]["total"] == 1 and listed["data"][0]["status"] == "pending"
    not_yet = client.post(f"/api/payroll/final-settlements/{eoe}/close", json={"rowVersion": "0000000000000000"}, headers=h)
    assert not_yet.status_code == 409
    fs = client.post(f"/api/payroll/final-settlements/{eoe}/recalculate", headers=h)
    assert fs.status_code == 200, fs.text
    fs = fs.json()["data"]
    slip = client.get(f"/api/payroll/final-settlements/{eoe}/payslip", headers=h).json()["data"]
    lines = {l["systemCode"]: l["amount"] for l in slip["lines"] if l["systemCode"]}
    assert lines["salary"] == 30000                  # 60,000 x 15 / 30 days of September
    assert lines["leave_encashment"] == 20000        # 10 days x 60,000 / 30
    assert lines["loan_deduction"] == 14000          # every unpaid installment
    assert slip["isFinalSettlement"] is True and fs["netPayable"] == 36000

    letter = factories.upload(client, h, name="Settlement letter.pdf", module="payroll")
    closed = client.post(f"/api/payroll/final-settlements/{eoe}/close",
                         json={"rowVersion": fs["rowVersion"], "fileId": int(letter["id"])}, headers=h)
    assert closed.status_code == 200, closed.text
    assert closed.json()["data"]["status"] == "closed"
    assert closed.json()["data"]["file"]["name"] == "Settlement letter.pdf"
    fs_id = int(closed.json()["data"]["finalSettlementId"])
    published = fe.events(db, company, "payroll.final_settlement_closed", fs_id)
    assert len(published) == 1 and published[0]["data"]["netPayable"] == 36000
    told = fe.notifications(db, company, e, "pay.payslip")
    assert [n["title"] for n in told] == ["Your final settlement payslip is ready"]
    assert fp.scalar(db, "SELECT COUNT(*) FROM loan.loan_installment i JOIN loan.loan l ON l.id = i.loan_id "
                         "WHERE l.employee_id = ? AND i.status = N'paid'", e) == 2
    assert fp.scalar(db, "SELECT status FROM loan.loan WHERE employee_id = ?", e) == "settled"
    assert fp.scalar(db, "SELECT SUM(days) FROM lv.leave_ledger WHERE employee_id = ? AND leave_type_id = ?", e, annual) == 4
    again = client.post(f"/api/payroll/final-settlements/{eoe}/recalculate", headers=h)
    assert again.status_code == 409


def test_lists_and_reports_answer(client, ctx):
    h = ctx["h"]
    for url in ("/api/payroll/payrolls", "/api/payroll/daily-wages", "/api/payroll/payslips", "/api/payroll/vouchers",
                "/api/payroll/final-settlements", "/api/payroll/opening-balances", "/api/payroll/employee-accounts",
                "/api/payroll/salary-revisions", "/api/payroll/leave-encashments", "/api/payroll/reports/employee-wise",
                "/api/payroll/formulas", "/api/payroll/rules", "/api/payroll/account-types", "/api/payroll/benefits",
                "/api/payroll/incentives", "/api/payroll/tax-rebates"):
        r = client.get(url, headers=h)
        assert r.status_code == 200, (url, r.text)
        assert set(r.json()) == {"data", "meta"}
    assert client.get("/api/payroll/dashboard", headers=h).status_code == 200


def test_voucher_decider_without_an_employee_record_and_code_search(client, db, ctx):
    h = ctx["h"]
    worker = fp.employee(db, ctx["company"], salary=40000)
    bare = factories.login_as(db, client, ctx["company"], role_codes="company_admin")   # no employee record
    r = client.post("/api/payroll/vouchers", json={
        "employeeId": str(worker), "voucherType": "bonus", "voucherDate": "2026-08-02", "amount": 700,
        "paymentMethod": "cash", "purpose": "Award"}, headers=h)
    assert r.status_code == 201, r.text
    v = r.json()["data"]
    approved = client.post(f"/api/payroll/vouchers/{v['id']}/approve", json={"rowVersion": v["rowVersion"]},
                           headers=bare["headers"])
    assert approved.status_code == 200, approved.text
    a = approved.json()["data"]
    assert a["approvedById"] is None
    assert a["approvedByUserId"] == str(bare["user_id"]) and a["approvedByName"] == "Test User"
    verified = client.post(f"/api/payroll/vouchers/{v['id']}/verify", json={"rowVersion": a["rowVersion"]},
                           headers=bare["headers"])
    assert verified.status_code == 200, verified.text
    assert verified.json()["data"]["verifiedByUserId"] == str(bare["user_id"])
    assert verified.json()["data"]["verifiedByName"] == "Test User"

    # voucherCode is a contains search (escaped), not an exact match.
    digits = v["voucherNo"].split("-")[-1]
    found = client.get("/api/payroll/vouchers", params={"voucherCode": digits}, headers=h).json()
    assert v["id"] in [x["id"] for x in found["data"]]
    none = client.get("/api/payroll/vouchers", params={"voucherCode": "%"}, headers=h).json()
    assert none["meta"]["total"] == 0
