"""Warning: policies with rules, penalties, raising warnings from processed time-sheet days, history."""
from datetime import date

import pytest

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


def _policy(client, h, **overrides) -> dict:
    body = {"title": f"Late {factories.tag()}", "appliesTo": "late_arrival", "period": "month",
            "rules": [{"clockEvent": "clock_in", "minutes": 10, "occurrenceCount": 2}], **overrides}
    r = client.post("/api/warning/policies", headers=h, json=body)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def test_policy_lifecycle_and_history(client, db, org):
    company, h = org
    p = _policy(client, h, title="Late arrival")
    assert p["rules"] == [{"clockEvent": "clock_in", "minutes": 10, "occurrenceCount": 2}] and p["penalties"] == []

    dup = client.post("/api/warning/policies", headers=h, json={
        "title": "late arrival", "appliesTo": "late_arrival", "period": "day", "rules": [{"clockEvent": "clock_in"}]})
    assert dup.status_code == 409 and dup.json()["code"] == "WARNING_POLICY_DUPLICATE"
    wrong = client.post("/api/warning/policies", headers=h, json={
        "title": "Early", "appliesTo": "late_arrival", "period": "day", "rules": [{"clockEvent": "clock_out"}]})
    assert wrong.status_code == 422 and "rules.0.clockEvent" in wrong.json()["fieldErrors"]
    no_rules = client.post("/api/warning/policies", headers=h, json={
        "title": "Empty", "appliesTo": "overtime", "period": "week", "rules": []})
    assert no_rules.status_code == 422

    weekly = client.put(f"/api/warning/policies/{p['id']}", headers=h, json={
        "title": "Late arrival", "appliesTo": "late_arrival", "period": "week", "graceMinutes": 30,
        "weekStartDay": "mon", "weekEndDay": "fri", "rules": [{"clockEvent": "clock_in", "minutes": 5}],
        "rowVersion": p["rowVersion"]})
    assert weekly.status_code == 200, weekly.text
    assert weekly.json()["data"]["weekEndDay"] == "fri" and weekly.json()["data"]["graceMinutes"] == 30
    stale = client.put(f"/api/warning/policies/{p['id']}", headers=h, json={
        "title": "x", "appliesTo": "late_arrival", "period": "day", "rules": [{"clockEvent": "clock_in"}],
        "rowVersion": p["rowVersion"]})
    assert stale.status_code == 409

    t = fl.leave_type(client, h)
    pen = client.put(f"/api/warning/policies/{p['id']}/penalties", headers=h, json={
        "penalties": [{"afterCount": 1, "period": "month", "penaltyType": "half_day", "deduction": "leave",
                       "leaveTypeId": t["id"]},
                      {"afterCount": 3, "period": "month", "penaltyType": "percentage", "percentage": 25,
                       "deduction": "payroll", "leaveTypeId": t["id"]}],
        "rowVersion": weekly.json()["data"]["rowVersion"]})
    assert pen.status_code == 200, pen.text
    penalties = pen.json()["data"]["penalties"]
    assert [(x["afterCount"], x["percentage"], x.get("leaveTypeId")) for x in penalties] == \
        [(1, 50, t["id"]), (3, 25, None)]
    missing = client.put(f"/api/warning/policies/{p['id']}/penalties", headers=h, json={
        "penalties": [{"afterCount": 1, "period": "year", "penaltyType": "percentage", "deduction": "leave"}],
        "rowVersion": pen.json()["data"]["rowVersion"]})
    assert missing.status_code == 422
    assert {"penalties.0.percentage", "penalties.0.leaveTypeId"} <= set(missing.json()["fieldErrors"])
    listed = client.get("/api/warning/penalties", headers=h, params={"policyId": p["id"]}).json()
    assert listed["meta"]["total"] == 2 and listed["data"][0]["policyTitle"] == "Late arrival"

    history = client.get("/api/warning/history", headers=h, params={"policyId": p["id"]}).json()
    actions = [(e["actionName"], e["fieldName"]) for e in history["data"]]
    assert ("create", "title") in actions and ("update", "penalties") in actions and ("update", "period") in actions
    assert all(e["policyTitle"] == "Late arrival" for e in history["data"])

    rv = client.get(f"/api/warning/policies/{p['id']}", headers=h).json()["data"]["rowVersion"]
    assert client.delete(f"/api/warning/policies/{p['id']}", params={"rowVersion": rv}, headers=h).status_code == 204
    gone = client.get("/api/warning/history", headers=h, params={"policyId": p["id"]}).json()["data"]
    assert gone[0]["actionName"] == "delete" and gone[0]["policyTitle"] == "Late arrival"


def test_raise_warnings_with_penalties(client, db, org):
    company, h = org
    t = fl.leave_type(client, h, allowance=10)
    p = _policy(client, h)  # monthly; late over 10 minutes; every 2nd occurrence warns
    client.put(f"/api/warning/policies/{p['id']}/penalties", headers=h, json={
        "penalties": [{"afterCount": 1, "period": "month", "penaltyType": "half_day", "deduction": "leave",
                       "leaveTypeId": t["id"]},
                      {"afterCount": 2, "period": "month", "penaltyType": "full_day", "deduction": "payroll"}],
        "rowVersion": p["rowVersion"]}).raise_for_status()
    emp = fl.employee(db, company)
    factories.user(db, company, employee_id=emp, role_codes="employee")
    for day, late in [(2, 5), (3, 15), (4, 20), (7, 30), (8, 25), (9, 40)]:
        fl.timesheet_day(db, company, emp, date(Y, 1, day), late_minutes=late)
    fl.timesheet_day(db, company, emp, date(Y, 2, 1), late_minutes=50)   # a new month starts the count again
    unprocessed = fl.timesheet_day(db, company, emp, date(Y, 2, 2), late_minutes=50)
    fl.execute(db, "UPDATE att.timesheet_day SET processed_at = NULL WHERE id = ?", unprocessed)

    r = client.post("/api/warning/warnings/process", headers=h, json={"fromDate": f"{Y}-01-01", "toDate": f"{Y}-01-31"})
    assert r.status_code == 200, r.text
    assert r.json()["data"]["raised"] == 2 and r.json()["data"]["penalised"] == 2

    def warnings():
        data = client.get("/api/warning/warnings", headers=h, params={"employeeId": emp}).json()["data"]
        return sorted((w["workDate"], w["occurrenceNo"], w["penaltyType"], w["deduction"]) for w in data)

    # Occurrences: Jan 3, 4, 7, 8, 9 (late > 10); every 2nd warns: Jan 4 and Jan 8. February has one.
    assert warnings() == [(f"{Y}-01-04", 2, "half_day", "leave"), (f"{Y}-01-08", 4, "full_day", "payroll")]
    assert fl.balance(db, company, emp, int(t["id"]), date(Y, 1, 1))["used"] == 0.5

    # Issued: one event and one notification for the employee, listing both warnings.
    issued = fe.events(db, company, "warning.issued", emp)
    assert len(issued) == 1 and issued[0]["data"]["warnings"] == 2
    assert [i["workDate"] for i in issued[0]["data"]["items"]] == [f"{Y}-01-04", f"{Y}-01-08"]
    told = fe.notifications(db, company, emp, "hr.employee", emp)
    assert len(told) == 1 and told[0]["title"] == "You received 2 attendance warnings"

    again = client.post("/api/warning/warnings/process", headers=h, json={"fromDate": f"{Y}-01-15",
                                                                         "toDate": f"{Y}-01-15"})
    assert again.json()["data"]["raised"] == 2
    # The same warnings worked out again are not issued again.
    assert len(fe.events(db, company, "warning.issued", emp)) == 1
    assert len(fe.notifications(db, company, emp, "hr.employee", emp)) == 1
    assert warnings() == [(f"{Y}-01-04", 2, "half_day", "leave"), (f"{Y}-01-08", 4, "full_day", "payroll")]
    assert fl.balance(db, company, emp, int(t["id"]), date(Y, 1, 1))["used"] == 0.5

    rv = client.get(f"/api/warning/policies/{p['id']}", headers=h).json()["data"]["rowVersion"]
    assert client.delete(f"/api/warning/policies/{p['id']}", params={"rowVersion": rv}, headers=h).status_code == 409


def test_grace_minutes_week_days_and_scope(client, db, org):
    company, h = org
    _policy(client, h, title="Weekly grace", period="week", graceMinutes=40, weekStartDay="mon", weekEndDay="fri",
            rules=[{"clockEvent": "clock_in", "minutes": 0, "occurrenceCount": 1}])
    manager = fl.employee(db, company)
    report = fl.employee(db, company, line_manager_id=manager)
    other = fl.employee(db, company)
    # 2030-01-07 is a Monday. Running total 15, 35, 55, 75 → days 3 and 4 pass the 40-minute grace;
    # Saturday is outside Mon-Fri and does not count.
    for emp in (report, other):
        for day, late in [(7, 15), (8, 20), (9, 20), (10, 20), (12, 90)]:
            fl.timesheet_day(db, company, emp, date(Y, 1, day), late_minutes=late)
    r = client.post("/api/warning/warnings/process", headers=h, json={"fromDate": f"{Y}-01-07", "toDate": f"{Y}-01-13"})
    assert r.json()["data"]["raised"] == 4

    mgr = factories.login_as(db, client, company, role_codes="line_manager", employee_id=manager)
    seen = client.get("/api/warning/warnings", headers=mgr["headers"]).json()
    assert {w["employeeId"] for w in seen["data"]} == {str(report)}
    assert sorted(w["workDate"] for w in seen["data"]) == [f"{Y}-01-09", f"{Y}-01-10"]
    assert client.post("/api/warning/warnings/process", headers=mgr["headers"],
                       json={"fromDate": f"{Y}-01-07", "toDate": f"{Y}-01-13"}).status_code == 403
    assert client.get("/api/warning/policies", headers=mgr["headers"]).status_code == 403

    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=report)
    own = client.get("/api/warning/warnings", headers=staff["headers"]).json()["data"]
    assert {w["employeeId"] for w in own} == {str(report)}  # staff see their own warnings only
