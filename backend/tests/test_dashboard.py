"""CEO, HR and My dashboards: figures follow the dashboard permission's scope."""
from datetime import date

from tests import factories
from tests import factories_organisation as fo


def _employee(db, company, **kw) -> int:
    emp = factories.employee(db, company, **kw)
    fo.execute(db, "INSERT hr.employment_period (employee_id, joining_date) VALUES (?, ?)", emp, date.today().replace(day=1))
    return emp


def test_hr_and_ceo_dashboards(client, db):
    company = factories.company(db)
    h = factories.login_as(db, client, company, role_codes="company_admin")["headers"]
    dept = factories.department(db, company, name="People")
    permanent = fo.scalar(db, "SELECT id FROM org.employment_type WHERE company_id = ? AND name = N'Permanent'", company)
    women = [_employee(db, company, department_id=dept) for _ in range(2)]
    men = [_employee(db, company) for _ in range(3)]
    for e in women:
        fo.execute(db, "UPDATE hr.employee SET gender = N'female', employment_type_id = ?, date_of_birth = '1996-05-01' "
                       "WHERE id = ?", permanent, e)
    for e in men:
        fo.execute(db, "UPDATE hr.employee SET gender = N'male', date_of_birth = '1980-05-01' WHERE id = ?", e)
    today = date.today()
    fo.timesheet_day(db, company, women[0], today, "present")
    fo.timesheet_day(db, company, men[0], today, "absent")
    fo.timesheet_day(db, company, men[1], today, "leave")
    client.post("/api/organisation/announcements", headers=h, json={"kind": "notice", "title": "Policy updated"})
    client.post("/api/organisation/announcements", headers=h,
                json={"kind": "event", "title": "Annual dinner", "eventDate": str(today.replace(year=today.year + 1))})

    r = client.get("/api/dashboard/hr", headers=h)
    assert r.status_code == 200, r.text
    d = r.json()["data"]
    w = d["workforce"]
    assert (w["headcount"], w["women"], w["men"], w["hired"]) == (5, 2, 3, 5)
    assert w["womenPercent"] == 40.0
    assert {x["name"]: x["count"] for x in w["byDepartment"]} == {"People": 2, "No department": 3}
    assert {x["name"]: x["count"] for x in w["byEmploymentType"]} == {"Permanent": 2, "Not set": 3}
    assert {b["band"]: (b["male"], b["female"]) for b in w["byAge"]}.get("26-35") == (0, 2)
    assert len(w["turnoverByMonth"]) == 12 and w["turnoverByMonth"][-1]["hired"] == 5
    a = d["attendance"]
    assert (a["present"], a["absent"], a["onLeave"], a["absenteeismPercent"]) == (1, 1, 1, 50.0)
    assert [n["title"] for n in d["noticeBoard"]] == ["Policy updated"]
    assert [n["title"] for n in d["upcomingEvents"]] == ["Annual dinner"]

    ceo = client.get("/api/dashboard/ceo", headers=h).json()["data"]
    assert ceo["workforce"]["headcount"] == 5 and isinstance(ceo["leaveApplications"], list)


def test_scope_narrows_dashboard(client, db):
    company = factories.company(db)
    dept = factories.department(db, company)
    head = _employee(db, company, department_id=dept)
    _employee(db, company, department_id=dept)
    _employee(db, company)
    hod = factories.login_as(db, client, company, role_codes="department_head", employee_id=head)["headers"]
    assert client.get("/api/dashboard/hr", headers=hod).json()["data"]["workforce"]["headcount"] == 2

    me = _employee(db, company)
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=me)["headers"]
    fo.timesheet_day(db, company, me, date.today(), "present")
    mine = client.get("/api/dashboard/me", headers=staff)
    assert mine.status_code == 200, mine.text
    assert mine.json()["data"]["employeeId"] == str(me) and mine.json()["data"]["attendance"]["present"] == 1

    nobody = factories.login_as(db, client, company)["headers"]
    assert client.get("/api/dashboard/hr", headers=nobody).status_code == 403
    assert client.get("/api/dashboard/me", headers=nobody).status_code == 403
