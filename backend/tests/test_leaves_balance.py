"""Balances: allotment, earned accrual, pro-rating, the ledger, lv.fn_leave_balance, the approval effect
(lv.usp_request_apply_leave), cancellation, carry forward and encashment."""
from datetime import date

import pytest

from app.core.errors import AppError
from tests import factories
from tests import factories_events as fe
from tests import factories_leaves as fl

Y = 2030


@pytest.fixture
def org(db, client):
    company = factories.company(db)
    fl.execute(db, "UPDATE org.company SET fiscal_year_start_month = 1 WHERE id = ?", company)  # calendar leave year
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    return company, admin["headers"]


def _allot(client, h, **body):
    r = client.post("/api/leaves/allotment/process", headers=h, json={"fiscalYear": Y, **body})
    assert r.status_code == 200, r.text
    return r.json()["data"]


def test_leave_year_follows_fiscal_start(db, org):
    company, _ = org
    fl.execute(db, "UPDATE org.company SET fiscal_year_start_month = 7 WHERE id = ?", company)
    y = fl.rows(db, "SELECT fiscal_year, year_start, year_end FROM lv.fn_leave_year(?, ?)", company, date(Y, 3, 1))[0]
    assert (y["fiscal_year"], y["year_start"], y["year_end"]) == (Y - 1, date(Y - 1, 7, 1), date(Y, 6, 30))


def test_balance_arithmetic_and_approval_effect(client, db, org):
    company, h = org
    t = fl.leave_type(client, h, allowance=10)
    fl.company_policy(client, h, [t["id"]])
    emp = fl.employee(db, company)
    tid = int(t["id"])

    first = _allot(client, h, employeeId=emp)
    assert first["allotted"] == 1 and first["days"] == 10
    assert _allot(client, h, employeeId=emp)["allotted"] == 0  # once per year
    assert fl.balance(db, company, emp, tid, date(Y, 5, 1)) == {"entitled": 10, "used": 0, "pending": 0, "available": 10}

    a = fl.leave_request(db, company, emp, tid, date(Y, 3, 1), date(Y, 3, 3), 3)
    assert fl.balance(db, company, emp, tid, date(Y, 5, 1)) == {"entitled": 10, "used": 0, "pending": 3, "available": 7}

    db.call("lv.usp_request_apply_leave", company_id=company, actor_user_id=None, request_id=a)
    db.call("lv.usp_request_apply_leave", company_id=company, actor_user_id=None, request_id=a)  # posts once
    fl.execute(db, "UPDATE req.request SET status = N'approved' WHERE id = ?", a)
    assert fl.balance(db, company, emp, tid, date(Y, 5, 1)) == {"entitled": 10, "used": 3, "pending": 0, "available": 7}
    availed = fl.rows(db, "SELECT days, reason, fiscal_year FROM lv.leave_ledger WHERE request_id = ?", a)
    assert [(float(r["days"]), r["reason"], r["fiscal_year"]) for r in availed] == [(-3, "availed", Y)]

    # Another pending request leaves 7 - 8 < 0: approval is refused.
    b = fl.leave_request(db, company, emp, tid, date(Y, 6, 1), date(Y, 6, 8), 8)
    assert fl.balance(db, company, emp, tid, date(Y, 5, 1))["available"] == -1
    with pytest.raises(AppError) as exc:
        db.call("lv.usp_request_apply_leave", company_id=company, actor_user_id=None, request_id=b)
    assert exc.value.status == 409 and exc.value.code == "LEAVE_BALANCE_EXCEEDED"
    with pytest.raises(AppError) as exc:
        db.call("lv.usp_leave_request_check", company_id=company, employee_id=emp, leave_type_id=tid,
                from_date=date(Y, 6, 1), to_date=date(Y, 6, 8), days=8, request_id=b, today=date(Y, 1, 1))
    assert exc.value.status == 409
    db.call("lv.usp_leave_request_check", company_id=company, employee_id=emp, leave_type_id=tid,
            from_date=date(Y, 6, 1), to_date=date(Y, 6, 7), days=7, request_id=b, today=date(Y, 1, 1))
    with pytest.raises(AppError) as exc:  # back-dated, and the type does not allow it
        db.call("lv.usp_leave_request_check", company_id=company, employee_id=emp, leave_type_id=tid,
                from_date=date(Y, 6, 1), to_date=date(Y, 6, 1), days=1, today=date(Y, 7, 1))
    assert exc.value.status == 422 and "fromDate" in exc.value.field_errors

    # Cancelling the approved one gives the days back, once.
    db.call("lv.usp_request_revert_leave", company_id=company, actor_user_id=None, request_id=a)
    db.call("lv.usp_request_revert_leave", company_id=company, actor_user_id=None, request_id=a)
    fl.execute(db, "UPDATE req.request SET status = N'cancelled' WHERE id = ?", a)
    assert fl.balance(db, company, emp, tid, date(Y, 5, 1)) == {"entitled": 10, "used": 0, "pending": 8, "available": 2}

    # Manual adjustment and opening balance.
    factories.user(db, company, employee_id=emp, role_codes="employee")
    adj = client.post("/api/leaves/ledger", headers=h, json={
        "employeeId": emp, "leaveTypeId": tid, "entryDate": f"{Y}-04-01", "days": 1.5, "reason": "adjustment",
        "remarks": "Overtime swap"})
    assert adj.status_code == 201, adj.text
    assert adj.json()["data"]["days"] == 1.5 and adj.json()["data"]["fiscalYear"] == Y
    entry = int(adj.json()["data"]["id"])
    published = fe.events(db, company, "leaves.balance_adjusted", entry)
    assert len(published) == 1 and published[0]["data"]["days"] == 1.5
    assert published[0]["data"]["employeeId"] == str(emp) and published[0]["data"]["reason"] == "adjustment"
    told = fe.notifications(db, company, emp, "lv.leave_ledger", entry)
    assert len(told) == 1 and "increased by 1.5 days" in told[0]["title"] and told[0]["body"] == "Overtime swap"
    no_reason = client.post("/api/leaves/ledger", headers=h, json={
        "employeeId": emp, "leaveTypeId": tid, "entryDate": f"{Y}-04-01", "days": 1, "reason": "adjustment"})
    assert no_reason.status_code == 422 and "remarks" in no_reason.json()["fieldErrors"]
    assert fl.balance(db, company, emp, tid, date(Y, 5, 1))["entitled"] == 11.5

    bal = client.get("/api/leaves/balances", headers=h, params={"employeeId": emp, "asOf": f"{Y}-05-01"}).json()
    assert bal["meta"]["total"] == 1
    assert {k: bal["data"][0][k] for k in ("entitled", "used", "pending", "available")} == \
        {"entitled": 11.5, "used": 0, "pending": 8, "available": 3.5}
    ledger = client.get("/api/leaves/ledger", headers=h, params={"employeeId": emp}).json()
    assert sorted(e["reason"] for e in ledger["data"]) == ["adjustment", "allotment", "availed", "restored"]


def test_pro_rated_earned_and_experience(client, db, org):
    company, h = org
    pro = fl.leave_type(client, h, allowance=12, proRated=True)
    earned = fl.leave_type(client, h, allowance=12, isEarned=True)
    exp = fl.leave_type(client, h, allowance=0, balanceBasis="experience",
                        experienceSlabs=[{"minMonths": 0, "maxMonths": 23, "balance": 5},
                                         {"minMonths": 24, "balance": 9}])
    women = fl.leave_type(client, h, allowance=3, gender="female")
    fl.company_policy(client, h, [pro["id"], earned["id"], exp["id"], women["id"]])
    joiner = fl.employee(db, company, joined=date(Y, 7, 15), gender="male")
    senior = fl.employee(db, company, joined=date(Y - 5, 1, 1), gender="female")

    _allot(client, h, asOf=f"{Y}-03-31")

    def bal(emp, t, on=date(Y, 12, 1)):
        return fl.balance(db, company, emp, int(t["id"]), on)["entitled"]

    assert bal(joiner, pro) == 5        # August to December
    assert bal(senior, pro) == 12
    assert bal(senior, earned) == 3     # January to March
    assert bal(joiner, earned) == 0     # not joined yet
    assert bal(joiner, exp) == 5 and bal(senior, exp) == 9
    assert bal(senior, women) == 3 and bal(joiner, women) == 0

    again = _allot(client, h, asOf=f"{Y}-06-30")
    assert again["allotted"] == 0 and again["earned"] == 1
    assert bal(senior, earned) == 6


def test_carry_forward_and_encashment(client, db, org):
    company, h = org
    cf = fl.leave_type(client, h, allowance=10, carryForward=True, accumulativeCount=2)
    enc = fl.leave_type(client, h, allowance=10, allowEncashment=True, encashmentMin=2, encashmentMax=5)
    fl.company_policy(client, h, [cf["id"], enc["id"]])
    rich, poor = fl.employee(db, company), fl.employee(db, company)
    _allot(client, h)
    db.call("lv.usp_request_apply_leave", company_id=company, actor_user_id=None,
            request_id=fl.leave_request(db, company, rich, int(cf["id"]), date(Y, 2, 1), date(Y, 2, 3), 3, "approved"))

    r = client.post("/api/leaves/carry-forward/process", headers=h, json={"fromFiscalYear": Y,
                                                                         "leaveTypeId": int(cf["id"])})
    assert r.status_code == 200, r.text
    assert r.json()["data"]["carried"] == 2 and r.json()["data"]["days"] == 17  # 7 + 10
    assert client.post("/api/leaves/carry-forward/process", headers=h,
                       json={"fromFiscalYear": Y}).json()["data"]["carried"] == 0
    assert fl.balance(db, company, rich, int(cf["id"]), date(Y + 1, 2, 1))["available"] == 7
    assert fl.balance(db, company, rich, int(cf["id"]), date(Y, 12, 1))["available"] == 0
    not_cf = client.post("/api/leaves/carry-forward/process", headers=h,
                         json={"fromFiscalYear": Y, "leaveTypeId": int(enc["id"])})
    assert not_cf.status_code == 422 and "leaveTypeId" in not_cf.json()["fieldErrors"]

    # poor keeps 1 day: below the minimum of 2, so skipped; rich has 10, capped at 5.
    fl.insert(db, "lv.leave_ledger", {"employee_id": poor, "leave_type_id": int(enc["id"]), "fiscal_year": Y,
                                      "entry_date": date(Y, 3, 1), "days": -9, "reason": "adjustment"})
    made = client.post("/api/leaves/encashments", headers=h, json={
        "leaveTypeId": enc["id"], "fiscalYear": Y, "encashmentDate": f"{Y}-12-31", "employeeIds": [rich, poor],
        "basis": "earned_salary", "amountPerLeave": 1000, "mode": "payroll"})
    assert made.status_code == 201, made.text
    e = made.json()["data"]
    assert e["employeeCount"] == 1 and e["totalDays"] == 5 and e["totalAmount"] == 5000
    assert e["lines"][0]["employeeId"] == str(rich)
    assert fl.balance(db, company, rich, int(enc["id"]), date(Y, 6, 1)) == \
        {"entitled": 10, "used": 5, "pending": 0, "available": 5}

    nobody = client.post("/api/leaves/encashments", headers=h, json={
        "leaveTypeId": enc["id"], "fiscalYear": Y, "encashmentDate": f"{Y}-12-31", "employeeIds": [poor],
        "basis": "earned_salary", "amountPerLeave": 1000, "mode": "manual"})
    assert nobody.status_code == 422
    not_allowed = client.post("/api/leaves/encashments", headers=h, json={
        "leaveTypeId": cf["id"], "fiscalYear": Y, "encashmentDate": f"{Y}-12-31", "appliesToAll": True,
        "basis": "earned_salary", "amountPerLeave": 1000, "mode": "manual"})
    assert not_allowed.status_code == 422 and "leaveTypeId" in not_allowed.json()["fieldErrors"]

    upd = client.put(f"/api/leaves/encashments/{e['id']}", headers=h, json={
        "encashmentDate": f"{Y}-12-30", "basis": "per_hour_rate", "amountPerLeave": 1200, "mode": "manual",
        "rowVersion": e["rowVersion"]})
    assert upd.status_code == 200 and upd.json()["data"]["totalAmount"] == 6000
    stale = client.put(f"/api/leaves/encashments/{e['id']}", headers=h, json={
        "encashmentDate": f"{Y}-12-30", "basis": "per_hour_rate", "amountPerLeave": 1, "mode": "manual",
        "rowVersion": e["rowVersion"]})
    assert stale.status_code == 409
    listed = client.get("/api/leaves/encashments", headers=h, params={"fiscalYear": Y}).json()
    assert listed["meta"]["total"] == 1

    assert client.delete(f"/api/leaves/encashments/{e['id']}", headers=h,
                         params={"rowVersion": upd.json()["data"]["rowVersion"]}).status_code == 204
    assert fl.balance(db, company, rich, int(enc["id"]), date(Y, 6, 1))["available"] == 10
