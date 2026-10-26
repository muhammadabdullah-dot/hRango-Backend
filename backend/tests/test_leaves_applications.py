"""My Leaves / Leave Applications: leave requests read from the requests module, by tab and scope."""
from datetime import date

import pytest

from tests import factories
from tests import factories_leaves as fl

Y = 2030


@pytest.fixture
def team(db, client):
    company = factories.company(db)
    fl.execute(db, "UPDATE org.company SET fiscal_year_start_month = 1 WHERE id = ?", company)  # calendar leave year
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    h = admin["headers"]
    t = fl.leave_type(client, h, allowance=10)
    fl.company_policy(client, h, [t["id"]])
    manager = fl.employee(db, company, first_name="Maryam")
    report = fl.employee(db, company, first_name="Rehan", line_manager_id=manager)
    outsider = fl.employee(db, company, first_name="Omer")
    r1 = fl.leave_request(db, company, report, int(t["id"]), date(Y, 3, 2), date(Y, 3, 3), 2)
    r2 = fl.leave_request(db, company, report, int(t["id"]), date(Y, 1, 10), date(Y, 1, 10), 1, "approved")
    r3 = fl.leave_request(db, company, outsider, int(t["id"]), date(Y, 2, 5), date(Y, 2, 6), 2, "rejected")
    return {"company": company, "admin": h, "type": t, "manager": manager, "report": report, "outsider": outsider,
            "requests": (r1, r2, r3)}


def _ids(r) -> set[str]:
    assert r.status_code == 200, r.text
    return {a["id"] for a in r.json()["data"]}


def test_all_tab_filters_and_detail(client, team):
    h, (r1, r2, r3) = team["admin"], team["requests"]
    assert _ids(client.get("/api/leaves/applications", headers=h)) == {str(r1), str(r2), str(r3)}
    assert _ids(client.get("/api/leaves/applications", headers=h, params={"status": "pending"})) == {str(r1)}
    assert _ids(client.get("/api/leaves/applications", headers=h,
                           params={"fromDate": f"{Y}-02-01", "toDate": f"{Y}-02-28"})) == {str(r3)}
    assert _ids(client.get("/api/leaves/applications", headers=h, params={"q": "Omer"})) == {str(r3)}
    bad = client.get("/api/leaves/applications", headers=h, params={"fromDate": f"{Y}-03-01", "toDate": f"{Y}-02-01"})
    assert bad.status_code == 422

    counts = client.get("/api/leaves/applications/counts", headers=h).json()["data"]
    assert counts == {"all": 3, "pending": 1, "approved": 1, "rejected": 1, "cancelling": 0, "cancelled": 0}

    one = client.get(f"/api/leaves/applications/{r1}", headers=h).json()["data"]
    assert one["days"] == 2 and one["leaveTypeId"] == team["type"]["id"] and one["employeeName"].startswith("Rehan")
    # Nothing allotted yet: 0 entitled, the 2 pending days held back.
    assert one["balance"] == {"entitled": 0, "used": 0, "pending": 2, "available": -2}


def test_my_and_subordinates_tabs_and_scope(client, db, team):
    company, (r1, r2, r3) = team["company"], team["requests"]
    mgr = factories.login_as(db, client, company, role_codes="line_manager", employee_id=team["manager"])
    me = factories.login_as(db, client, company, role_codes="employee", employee_id=team["report"])

    assert _ids(client.get("/api/leaves/applications", headers=mgr["headers"], params={"tab": "subordinates"})) == \
        {str(r1), str(r2)}
    assert _ids(client.get("/api/leaves/applications", headers=mgr["headers"], params={"tab": "my"})) == set()
    # Team scope: the outsider's leave is not reachable.
    assert _ids(client.get("/api/leaves/applications", headers=mgr["headers"])) == {str(r1), str(r2)}
    assert client.get(f"/api/leaves/applications/{r3}", headers=mgr["headers"]).status_code == 404

    assert _ids(client.get("/api/leaves/applications", headers=me["headers"], params={"tab": "my"})) == \
        {str(r1), str(r2)}
    assert client.get(f"/api/leaves/applications/{r3}", headers=me["headers"]).status_code == 404
    balances = client.get("/api/leaves/balances", headers=me["headers"]).json()
    assert {b["employeeId"] for b in balances["data"]} == {str(team["report"])}

    # Staff may not adjust balances, run allotment or encash, even their own.
    assert client.post("/api/leaves/ledger", headers=me["headers"], json={
        "employeeId": team["report"], "leaveTypeId": int(team["type"]["id"]), "entryDate": f"{Y}-01-01", "days": 5,
        "reason": "opening"}).status_code == 403
    assert client.post("/api/leaves/allotment/process", headers=me["headers"],
                       json={"fiscalYear": Y}).status_code == 403
    assert client.post("/api/leaves/encashments", headers=me["headers"], json={
        "leaveTypeId": team["type"]["id"], "fiscalYear": Y, "encashmentDate": f"{Y}-12-31", "appliesToAll": True,
        "basis": "earned_salary", "amountPerLeave": 1, "mode": "manual"}).status_code == 403
