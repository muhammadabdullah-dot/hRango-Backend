"""Attendance findings of the Test Run (18-19 Nov 2026), fix group D:
S1.76 / S1.77 "Active Staff" is everyone employed (active, probation, notice), on the overview, the time sheet,
their exports and payroll's "Add Matching"; R1.6 the log download follows the page's filters; 4.11 / 4.42 a double
press of Clock In / Out or of Create does not make a second punch."""
import threading
from datetime import date, datetime, timedelta

import pytest

from app.core.db import Db, connect
from tests import factories
from tests import factories_attendance as fa
from tests import factories_payroll as fp

DAY = date(2025, 9, 1)  # a Monday


def at(d: date, hhmm: str) -> datetime:
    return datetime.combine(d, datetime.strptime(hhmm, "%H:%M").time())


@pytest.fixture(scope="module")
def staff(db, client):
    """A manager with four reports: active, on probation, serving notice, switched off."""
    company = factories.company(db)
    dept = factories.department(db, company)
    manager = factories.employee(db, company, department_id=dept, first_name="Faisal")
    people = {}
    for status in ("active", "probation", "notice", "inactive"):
        emp = factories.employee(db, company, department_id=dept, line_manager_id=manager, first_name=status.title())
        fp.execute(db, "UPDATE hr.employee SET status = ? WHERE id = ?", status, emp)
        fa.shift(db, company, emp, DAY)
        fa.punch(db, company, emp, at(DAY, "09:00"))
        fa.punch(db, company, emp, at(DAY, "17:00"), "check_out")
        fa.process(db, company, emp, DAY)
        people[status] = emp
    return {"company": company, "dept": dept, "manager": manager, "people": people,
            "admin": factories.login_as(db, client, company, role_codes="company_admin"),
            "mgr": factories.login_as(db, client, company, role_codes="line_manager", employee_id=manager)["headers"]}


def _ids(rows) -> set[str]:
    return {r["employeeId"] for r in rows}


def test_active_staff_is_everyone_employed(client, staff):
    p, h, mgr = staff["people"], staff["admin"]["headers"], staff["mgr"]
    employed = {str(p["active"]), str(p["probation"]), str(p["notice"])}
    q = {"fromDate": str(DAY), "toDate": str(DAY)}

    sheet = client.get("/api/attendance/time-sheet", params={**q, "tab": "subordinates", "employeeStatus": "active"},
                       headers=mgr)
    assert sheet.status_code == 200, sheet.text
    assert _ids(sheet.json()["data"]) == employed  # the probation and notice people are there (S1.77)
    off = client.get("/api/attendance/time-sheet", params={**q, "tab": "subordinates", "employeeStatus": "inactive"},
                     headers=mgr).json()["data"]
    assert _ids(off) == {str(p["inactive"])}
    one = client.get("/api/attendance/time-sheet", params={**q, "tab": "subordinates", "employeeStatus": "probation"},
                     headers=mgr).json()["data"]
    assert _ids(one) == {str(p["probation"])}  # a single status still filters exactly

    month = {"month": DAY.strftime("%Y-%m")}
    overview = client.get("/api/attendance/overview", params={**month, "tab": "subordinates", "employeeStatus": "active"},
                          headers=mgr)
    assert overview.status_code == 200, overview.text
    assert _ids(overview.json()["data"]) == employed and overview.json()["meta"]["total"] == 3  # S1.76
    everyone = client.get("/api/attendance/overview", params={**month, "tab": "subordinates"}, headers=mgr).json()
    assert everyone["meta"]["total"] == 4

    csv = client.get("/api/attendance/overview/export", params={**month, "tab": "all", "employeeStatus": "active",
                                                                 "departmentId": staff["dept"]}, headers=h)
    assert csv.status_code == 200
    assert len(csv.text.strip().splitlines()) == 1 + 4  # the header, the manager and the three employed reports
    sheet_csv = client.get("/api/attendance/time-sheet/export", params={**q, "tab": "all", "employeeStatus": "active",
                                                                         "departmentId": staff["dept"]}, headers=h)
    assert sheet_csv.status_code == 200 and len(sheet_csv.text.strip().splitlines()) == 1 + 3


def test_add_matching_takes_people_on_probation_and_notice(client, db, staff):
    """Payroll's "Add Matching" sends employeeStatus active: everyone employed is paid, not only status active."""
    company, h, p = staff["company"], staff["admin"]["headers"], staff["people"]
    run = fp.payroll(client, h, "2026-10-01", fp.tax_structure(client, h)["id"], fp.bank(client, h)["id"],
                     taxApplicable=False)
    added = db.call_one("pay.usp_payroll_employee_add_filtered", company_id=company,
                        actor_user_id=staff["admin"]["user_id"], permission_code="payroll.payrolls.edit",
                        id=int(run["id"]), department_id=staff["dept"], employee_status="active")
    assert added["added"] == 4  # the manager, the active, probation and notice reports; not the switched-off one
    people = client.get(f"/api/payroll/payrolls/{run['id']}/employees", headers=h).json()["data"]
    assert str(p["probation"]) in _ids(people) and str(p["notice"]) in _ids(people)
    assert str(p["inactive"]) not in _ids(people)


def test_log_download_follows_the_filters(client, db, staff):
    """R1.6: the export takes the list's Employee, Punch Type and Source filters."""
    h, emp = staff["admin"]["headers"], staff["people"]["probation"]
    q = {"fromDate": str(DAY), "toDate": str(DAY)}
    everyone = client.get("/api/attendance/logs/export", params=q, headers=h)
    assert len(everyone.text.strip().splitlines()) == 1 + 8
    mine = client.get("/api/attendance/logs/export", params={**q, "employeeId": emp}, headers=h)
    assert len(mine.text.strip().splitlines()) == 1 + 2
    ins = client.get("/api/attendance/logs/export", params={**q, "employeeId": emp, "punchType": "check_in"},
                     headers=h).text.strip().splitlines()
    assert len(ins) == 2 and ",check_in," in ins[1]
    manual = client.get("/api/attendance/logs/export", params={**q, "source": "manual"}, headers=h)
    assert len(manual.text.strip().splitlines()) == 1


def _clocker(db, client):
    company = factories.company(db)
    emp = factories.employee(db, company)
    fa.setting(db, company, "attendance", "dashboard_punch", "true")
    login = factories.login_as(db, client, company, role_codes="employee", employee_id=emp)
    return company, emp, login


def _punches(db, emp) -> list[dict]:
    return fp.rows(db, "SELECT id, punch_type, punched_at FROM att.punch WHERE employee_id = ? ORDER BY id", emp)


def test_a_second_press_of_clock_keeps_the_first_punch(client, db):
    """4.11: the first press was saved while the screen gave up; pressing again (minutes later) is the same punch."""
    _, emp, login = _clocker(db, client)
    h = login["headers"]
    first = client.post("/api/attendance/clock", json={"punchType": "check_in"}, headers=h)
    assert first.status_code == 201, first.text
    # The first answer took a while: the screen gave up and the person presses again two minutes later.
    fp.execute(db, "UPDATE att.punch SET punched_at = DATEADD(MINUTE, -2, punched_at) WHERE employee_id = ?", emp)
    again = client.post("/api/attendance/clock", json={"punchType": "check_in"}, headers=h)
    assert again.status_code == 201, again.text
    assert again.json()["data"]["id"] == first.json()["data"]["id"]
    assert len(_punches(db, emp)) == 1

    out = client.post("/api/attendance/clock", json={"punchType": "check_out"}, headers=h)
    assert out.status_code == 201 and out.json()["data"]["punchType"] == "check_out"
    # Out, then in again a minute later: a new punch, since the last one was a check out.
    back = client.post("/api/attendance/clock", json={"punchType": "check_in"}, headers=h)
    assert back.status_code == 201 and back.json()["data"]["id"] != first.json()["data"]["id"]
    assert [p["punch_type"] for p in _punches(db, emp)] == ["check_in", "check_out", "check_in"]

    # Long after (over five minutes), the same type again is a punch of its own.
    fp.execute(db, "UPDATE att.punch SET punched_at = DATEADD(MINUTE, -10, punched_at) WHERE employee_id = ?", emp)
    later = client.post("/api/attendance/clock", json={"punchType": "check_in"}, headers=h)
    assert later.status_code == 201 and len(_punches(db, emp)) == 4


def _at_once(calls) -> list:
    """Runs each call on its own database connection at the same moment; returns results or exceptions."""
    results: list = [None] * len(calls)
    start = threading.Barrier(len(calls))

    def run(i, call):
        conn = connect()
        try:
            start.wait()
            results[i] = call(Db(conn))
        except Exception as exc:  # noqa: BLE001 - the test inspects what each call raised
            results[i] = exc
        finally:
            conn.close()

    threads = [threading.Thread(target=run, args=(i, c)) for i, c in enumerate(calls)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(120)
    return results


def test_two_presses_at_once_make_one_punch(client, db):
    company, emp, login = _clocker(db, client)

    def press(conn: Db):
        return conn.call_one("att.usp_clock_punch", company_id=company, actor_user_id=login["user_id"],
                             punch_type="check_in", source="web")

    results = _at_once([press, press, press])
    assert all(isinstance(r, dict) for r in results), results
    assert len({r["id"] for r in results}) == 1
    assert len(_punches(db, emp)) == 1


def test_a_second_create_of_the_same_manual_punch_is_refused(client, db):
    """4.42: Create pressed again after a slow answer finds the punch the first press saved."""
    company = factories.company(db)
    emp = factories.employee(db, company)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    body = {"employeeId": emp, "punchedAt": f"{DAY}T09:05:00", "punchType": "check_in", "remarks": "Forgot card"}

    def create(conn: Db):
        return conn.call_one("att.usp_punch_save", company_id=company, actor_user_id=admin["user_id"],
                             permission_code="attendance.logs.create", id=None, employee_id=emp,
                             punched_at=at(DAY, "09:05"), punch_type="check_in", remarks="Forgot card")

    results = _at_once([create, create])
    saved = [r for r in results if isinstance(r, dict)]
    refused = [r for r in results if not isinstance(r, dict)]
    assert len(saved) == 1 and len(refused) == 1, results
    assert getattr(refused[0], "code", None) == "PUNCH_DUPLICATE"
    assert len(_punches(db, emp)) == 1

    again = client.post("/api/attendance/logs", json=body, headers=admin["headers"])
    assert again.status_code == 409 and again.json()["code"] == "PUNCH_DUPLICATE"
    assert "in the log" in again.json()["message"]
    assert len(_punches(db, emp)) == 1
