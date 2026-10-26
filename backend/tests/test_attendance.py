"""Attendance screens through the API: logs (punches), import, clock in / out with geo-fence and IP checks,
the time sheet (My / Subordinates / All) with scope, editing a day and its history, the overview and exports."""
from datetime import date, datetime, timedelta

import pytest

from app.services.attendance_service import inside_fence, ip_allowed
from tests import factories
from tests import factories_attendance as fa
from tests import factories_events as fe

MON = date(2025, 5, 5)


def at(d: date, hhmm: str) -> datetime:
    return datetime.combine(d, datetime.strptime(hhmm, "%H:%M").time())


@pytest.fixture(scope="module")
def org(db, client):
    """One company: an admin, a manager with a report, and an outsider employee."""
    company_id = factories.company(db)
    dept = factories.department(db, company_id)
    manager = factories.employee(db, company_id, department_id=dept, first_name="Mona")
    report = factories.employee(db, company_id, department_id=dept, line_manager_id=manager, first_name="Rafay")
    outsider = factories.employee(db, company_id, first_name="Omar")
    return {
        "company": company_id, "manager": manager, "report": report, "outsider": outsider,
        "admin": factories.login_as(db, client, company_id, role_codes="company_admin")["headers"],
        "mgr": factories.login_as(db, client, company_id, role_codes="line_manager", employee_id=manager)["headers"],
        "staff": factories.login_as(db, client, company_id, role_codes="employee", employee_id=report)["headers"],
    }


def test_manual_punch_lifecycle(client, db, org):
    h, emp = org["admin"], org["outsider"]
    fa.shift(db, org["company"], emp, MON)
    r = client.post("/api/attendance/logs", json={"employeeId": emp, "punchedAt": "2025-05-05T09:03:00",
                                                  "punchType": "check_in", "remarks": "Forgot card"}, headers=h)
    assert r.status_code == 201, r.text
    p = r.json()["data"]
    assert p["source"] == "manual" and p["editable"] is True and p["employeeId"] == str(emp)

    dup = client.post("/api/attendance/logs", json={"employeeId": emp, "punchedAt": "2025-05-05T09:03:00",
                                                    "punchType": "check_in"}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "PUNCH_DUPLICATE"
    bad = client.post("/api/attendance/logs", json={"employeeId": emp, "punchedAt": "2025-05-05T09:03:00",
                                                    "punchType": "lunch"}, headers=h)
    assert bad.status_code == 422

    upd = client.put(f"/api/attendance/logs/{p['id']}", json={"employeeId": emp, "punchedAt": "2025-05-05T08:58:00",
                                                             "punchType": "check_in", "rowVersion": p["rowVersion"]},
                     headers=h)
    assert upd.status_code == 200 and upd.json()["data"]["isManuallyUpdated"] is True
    stale = client.put(f"/api/attendance/logs/{p['id']}", json={"employeeId": emp, "punchedAt": "2025-05-05T08:59:00",
                                                               "punchType": "check_in", "rowVersion": p["rowVersion"]},
                       headers=h)
    assert stale.status_code == 409
    assert fa.day(db, emp, MON)["first_in"] == at(MON, "08:58")

    device_punch = fa.punch(db, org["company"], emp, at(MON, "17:00"), "check_out")
    dp = client.get(f"/api/attendance/logs/{device_punch}", headers=h).json()["data"]
    assert dp["editable"] is False
    ro = client.delete(f"/api/attendance/logs/{device_punch}", params={"rowVersion": dp["rowVersion"]}, headers=h)
    assert ro.status_code == 409 and ro.json()["code"] == "PUNCH_READ_ONLY"
    ign = client.patch(f"/api/attendance/logs/{device_punch}/ignore",
                       json={"isIgnored": True, "rowVersion": dp["rowVersion"]}, headers=h)
    assert ign.status_code == 200 and ign.json()["data"]["isIgnored"] is True

    page = client.get("/api/attendance/logs", params={"fromDate": "2025-05-05", "toDate": "2025-05-05",
                                                       "employeeId": emp}, headers=h).json()
    assert page["meta"]["total"] == 2
    only_manual = client.get("/api/attendance/logs", params={"fromDate": "2025-05-05", "toDate": "2025-05-05",
                                                              "employeeId": emp, "source": "manual"}, headers=h).json()
    assert only_manual["meta"]["total"] == 1
    too_long = client.get("/api/attendance/logs", params={"fromDate": "2025-01-01", "toDate": "2025-05-05"}, headers=h)
    assert too_long.status_code == 422

    csv = client.get("/api/attendance/logs/export", params={"fromDate": "2025-05-05", "toDate": "2025-05-05",
                                                             "employeeId": emp}, headers=h)
    assert csv.status_code == 200 and csv.headers["content-type"].startswith("text/csv")
    assert csv.text.splitlines()[0].lstrip("﻿").startswith("Employee Code,Employee Name,Date,Time")
    assert len(csv.text.strip().splitlines()) == 3

    assert client.delete(f"/api/attendance/logs/{p['id']}", params={"rowVersion": upd.json()["data"]["rowVersion"]},
                         headers=h).status_code == 204


def test_own_punches_and_logs_scope(client, db, org):
    staff = org["staff"]
    mine = client.post("/api/attendance/logs", json={"employeeId": org["report"], "punchedAt": "2025-05-06T09:00:00",
                                                     "punchType": "check_in"}, headers=staff)
    assert mine.status_code == 403  # nobody enters their own punches; a punch request is the way
    fa.punch(db, org["company"], org["report"], at(MON + timedelta(days=1), "09:00"))
    fa.punch(db, org["company"], org["outsider"], at(MON + timedelta(days=1), "09:00"))
    seen = client.get("/api/attendance/logs", params={"fromDate": "2025-05-06", "toDate": "2025-05-06"},
                      headers=staff).json()["data"]
    assert {p["employeeId"] for p in seen} == {str(org["report"])}
    assert client.get("/api/attendance/logs/export", params={"fromDate": "2025-05-06", "toDate": "2025-05-06"},
                      headers=staff).status_code == 403


def test_csv_and_json_import(client, db, org):
    h = org["admin"]
    code = factories._scalar(db, "SELECT code FROM hr.employee WHERE id = ?", org["outsider"])
    text = ("Employee Code,Date,Time,Punch Type\r\n"
            f"{code},2025-05-07,09:05,Check In\r\n"
            f"{code},2025-05-07,17:10,check-out\r\n"
            "NOBODY,2025-05-07,09:00,check_in\r\n")
    r = client.post("/api/attendance/logs/import/csv", content=text.encode(), headers={**h, "Content-Type": "text/csv"})
    assert r.status_code == 200, r.text
    res = r.json()["data"]
    assert (res["created"], res["failed"]) == (2, 1) and res["errors"][0]["line"] == 4
    again = client.post("/api/attendance/logs/import", json={"lines": [
        {"employeeCode": code, "punchedAt": "2025-05-07T09:05:00", "punchType": "check_in"}]}, headers=h)
    assert again.json()["data"]["skipped"] == 1
    bad = client.post("/api/attendance/logs/import/csv", content=b"Name,When\r\nx,y\r\n",
                      headers={**h, "Content-Type": "text/csv"})
    assert bad.status_code == 422
    assert client.post("/api/attendance/logs/import", json={"lines": []}, headers=org["staff"]).status_code in (403, 422)


def test_time_sheet_tabs_and_scope(client, db, org):
    d = MON + timedelta(days=14)
    for emp in (org["manager"], org["report"], org["outsider"]):
        fa.shift(db, org["company"], emp, d)
        fa.punch(db, org["company"], emp, at(d, "09:30"))
        fa.punch(db, org["company"], emp, at(d, "17:00"), "check_out")
    before = len(fe.events(db, org["company"], "attendance.timesheet_processed"))
    r = client.post("/api/attendance/time-sheet/process", json={"fromDate": str(d), "toDate": str(d)},
                    headers=org["admin"])
    assert r.status_code == 200, r.text
    assert r.json()["data"]["processedDays"] >= 3
    # One summary event for the run, none for the punches that re-processed days on the way.
    runs = fe.events(db, org["company"], "attendance.timesheet_processed")
    assert len(runs) == before + 1
    assert runs[-1]["data"]["fromDate"] == str(d) and runs[-1]["data"]["processedDays"] == r.json()["data"]["processedDays"]
    assert runs[-1]["data"]["trigger"] == "manual"
    assert client.post("/api/attendance/time-sheet/process", json={"fromDate": str(d), "toDate": str(d)},
                       headers=org["staff"]).status_code == 403

    q = {"fromDate": str(d), "toDate": str(d)}

    def ids(headers, tab):
        res = client.get("/api/attendance/time-sheet", params={**q, "tab": tab}, headers=headers)
        assert res.status_code == 200, res.text
        return {row["employeeId"] for row in res.json()["data"]}

    assert ids(org["admin"], "all") >= {str(org["manager"]), str(org["report"]), str(org["outsider"])}
    assert ids(org["mgr"], "all") == {str(org["manager"]), str(org["report"])}
    assert ids(org["mgr"], "subordinates") == {str(org["report"])}
    assert ids(org["mgr"], "my") == {str(org["manager"])}
    assert ids(org["staff"], "all") == {str(org["report"])}

    row = client.get("/api/attendance/time-sheet", params={**q, "tab": "my"}, headers=org["staff"]).json()["data"][0]
    assert row["lateMinutes"] == 30 and row["clockInStatus"] == "late" and row["flags"] == ["late"]
    assert client.get("/api/attendance/time-sheet", params={**q, "tab": "everyone"},
                      headers=org["admin"]).status_code == 422
    late = client.get("/api/attendance/time-sheet", params={**q, "tab": "all", "flag": "late"}, headers=org["admin"])
    assert late.json()["meta"]["total"] >= 3

    other = client.get(f"/api/attendance/days/{org['outsider']}/{d}", headers=org["staff"])
    assert other.status_code == 404
    summary = client.get("/api/attendance/time-sheet/summary", params={**q, "tab": "my"}, headers=org["staff"]).json()
    assert summary["data"]["present"] == 1 and summary["data"]["lateArrival"] == 1

    csv = client.get("/api/attendance/time-sheet/export", params={**q, "tab": "all"}, headers=org["mgr"])
    assert csv.status_code == 200  # a line manager exports their own team's time sheet
    csv = client.get("/api/attendance/time-sheet/export", params={**q, "tab": "all"}, headers=org["admin"])
    assert csv.status_code == 200 and "Clock In" in csv.text.splitlines()[0]


def test_edit_day_and_history(client, db, org):
    d, emp, h = MON + timedelta(days=21), org["outsider"], org["admin"]
    fa.shift(db, org["company"], emp, d)
    fa.punch(db, org["company"], emp, at(d, "09:45"))
    detail = client.get(f"/api/attendance/days/{emp}/{d}", headers=h)  # processed on first read
    assert detail.status_code == 200, detail.text
    day = detail.json()["data"]["day"]
    assert day["lateMinutes"] == 45 and day["dayStatus"] == "present" and len(detail.json()["data"]["punches"]) == 1

    lunch = fa.break_type(db, org["company"])
    body = {"expectedIn": f"{d}T09:00:00", "expectedOut": f"{d}T17:00:00", "firstIn": f"{d}T09:00:00",
            "lastOut": f"{d}T17:00:00", "comments": "Card reader fault",
            "breaks": [{"breakTypeId": lunch, "outAt": f"{d}T13:00:00", "inAt": f"{d}T13:30:00"}],
            "rowVersion": day["rowVersion"]}
    r = client.put(f"/api/attendance/days/{emp}/{d}", json=body, headers=h)
    assert r.status_code == 200, r.text
    saved = r.json()["data"]
    assert saved["day"]["isManuallyUpdated"] is True and saved["day"]["lateMinutes"] == 0
    assert saved["day"]["workedMinutes"] == 450 and saved["breaks"][0]["minutes"] == 30

    assert client.put(f"/api/attendance/days/{emp}/{d}", json=body, headers=h).status_code == 409  # stale
    marked = client.put(f"/api/attendance/days/{emp}/{d}",
                        json={**body, "markedStatus": "half_day", "rowVersion": saved["day"]["rowVersion"]}, headers=h)
    assert marked.status_code == 200 and marked.json()["data"]["day"]["dayStatus"] == "half_day"
    wrong = client.put(f"/api/attendance/days/{emp}/{d}",
                       json={**body, "firstIn": f"{d}T18:00:00", "rowVersion": marked.json()["data"]["day"]["rowVersion"]},
                       headers=h)
    assert wrong.status_code == 422 and "lastOut" in wrong.json()["fieldErrors"]

    hist = client.get(f"/api/attendance/days/{emp}/{d}/history", headers=h).json()
    fields = {x["fieldName"] for x in hist["data"]}
    assert {"first_in", "breaks", "comments", "marked_status"} <= fields
    assert hist["data"][0]["performedByName"]

    assert client.put(f"/api/attendance/days/{org['report']}/{d}", json=body, headers=org["staff"]).status_code == 403
    fa.freeze(db, emp, d)
    current = client.get(f"/api/attendance/days/{emp}/{d}", headers=h).json()["data"]["day"]
    assert current["isFrozen"] is True
    frozen = client.put(f"/api/attendance/days/{emp}/{d}", json={**body, "rowVersion": current["rowVersion"]}, headers=h)
    assert frozen.status_code == 409 and frozen.json()["code"] == "DAY_FROZEN"


def test_edit_day_is_a_partial_update(client, db, org):
    """A field not sent keeps its value (omitting the expected times must not turn the day into a weekend);
    a field sent as null is cleared. Only the changed fields reach the history."""
    d, emp, h = MON + timedelta(days=22), org["outsider"], org["admin"]
    fa.shift(db, org["company"], emp, d)
    fa.punch(db, org["company"], emp, at(d, "09:00"))
    fa.punch(db, org["company"], emp, at(d, "17:00"), "check_out")
    day = client.get(f"/api/attendance/days/{emp}/{d}", headers=h).json()["data"]["day"]
    assert day["dayStatus"] == "present" and day["expectedIn"]
    lunch = fa.break_type(db, org["company"])
    first = client.put(f"/api/attendance/days/{emp}/{d}", headers=h, json={
        "breaks": [{"breakTypeId": lunch, "outAt": f"{d}T13:00:00", "inAt": f"{d}T13:30:00"}],
        "rowVersion": day["rowVersion"]})
    assert first.status_code == 200, first.text

    r = client.put(f"/api/attendance/days/{emp}/{d}", headers=h,
                   json={"comments": "Checked", "rowVersion": first.json()["data"]["day"]["rowVersion"]})
    assert r.status_code == 200, r.text
    saved = r.json()["data"]
    assert saved["day"]["dayStatus"] == "present" and saved["day"]["comments"] == "Checked"
    assert saved["day"]["expectedIn"] == day["expectedIn"] and saved["day"]["expectedOut"] == day["expectedOut"]
    assert saved["day"]["firstIn"] == day["firstIn"] and len(saved["breaks"]) == 1
    hist = client.get(f"/api/attendance/days/{emp}/{d}/history", headers=h).json()["data"]
    assert [x["fieldName"] for x in hist if x["newValue"] == "Checked"] == ["comments"]
    assert not [x for x in hist if x["fieldName"] in ("expected_in", "expected_out", "first_in")]

    cleared = client.put(f"/api/attendance/days/{emp}/{d}", headers=h,
                         json={"comments": None, "breaks": None, "rowVersion": saved["day"]["rowVersion"]})
    assert cleared.status_code == 200, cleared.text
    out = cleared.json()["data"]
    assert out["day"]["comments"] is None and out["breaks"] == [] and out["day"]["dayStatus"] == "present"


def test_overview(client, db, org):
    d = date(2025, 6, 2)
    fa.shift(db, org["company"], org["report"], d)
    fa.punch(db, org["company"], org["report"], at(d, "09:00"))
    fa.punch(db, org["company"], org["report"], at(d, "17:00"), "check_out")
    fa.process(db, org["company"], org["report"], date(2025, 6, 1), date(2025, 6, 30))
    r = client.get("/api/attendance/overview", params={"month": "2025-06", "tab": "subordinates"}, headers=org["mgr"])
    assert r.status_code == 200, r.text
    body = r.json()
    assert len(body["days"]) == 30 and body["meta"]["total"] == 1
    row = body["data"][0]
    assert row["employeeId"] == str(org["report"]) and row["days"]["2025-06-02"] == "present"
    assert row["totals"]["present"] == 1 and row["totals"]["daysOff"] == 29
    assert client.get("/api/attendance/overview", params={"month": "June"}, headers=org["mgr"]).status_code == 422
    csv = client.get("/api/attendance/overview/export", params={"month": "2025-06", "tab": "all"}, headers=org["admin"])
    assert csv.status_code == 200 and "2025-06-30" in csv.text.splitlines()[0]
    counts = client.get("/api/attendance/overview/summary", params={"fromDate": "2025-06-01", "toDate": "2025-06-30",
                                                                     "employeeId": org["report"]}, headers=org["admin"])
    assert counts.json()["data"]["present"] == 1 and counts.json()["data"]["weekend"] == 29


def test_clock_in_and_out(client, db):
    company_id = factories.company(db)
    emp = factories.employee(db, company_id)
    staff = factories.login_as(db, client, company_id, role_codes="employee", employee_id=emp)["headers"]
    admin = factories.login_as(db, client, company_id, role_codes="company_admin")["headers"]

    off = client.get("/api/attendance/clock", headers=staff).json()["data"]
    assert off["allowed"] is False and off["nextPunchType"] == "check_in"
    assert client.post("/api/attendance/clock", json={}, headers=staff).status_code == 403
    assert client.get("/api/attendance/clock", headers=admin).json()["data"]["allowed"] is False  # no employee record

    fa.setting(db, company_id, "attendance", "dashboard_punch", "true")
    r = client.post("/api/attendance/clock", json={"source": "mobile"}, headers=staff)
    assert r.status_code == 201, r.text
    assert r.json()["data"]["punchType"] == "check_in" and r.json()["data"]["source"] == "mobile"
    state = client.get("/api/attendance/clock", headers=staff).json()["data"]
    assert state["clockedIn"] is True and state["nextPunchType"] == "check_out"
    assert client.post("/api/attendance/clock", json={"punchType": "check_in"}, headers=staff).status_code == 409

    fence = client.post("/api/attendance/settings/geo-fences", json={
        "name": "Office", "shape": "circle", "centerLat": 24.86, "centerLng": 67.00, "radiusM": 300,
        "appliesToAll": False, "targets": [{"targetType": "employee", "targetId": emp}]}, headers=admin)
    assert fence.status_code == 201, fence.text
    assert client.get("/api/attendance/clock", headers=staff).json()["data"]["locationRequired"] is True
    no_loc = client.post("/api/attendance/clock", json={}, headers=staff)
    assert no_loc.status_code == 422 and "latitude" in no_loc.json()["fieldErrors"]
    far = client.post("/api/attendance/clock", json={"latitude": 24.90, "longitude": 67.00}, headers=staff)
    assert far.status_code == 403 and far.json()["code"] == "OUTSIDE_GEO_FENCE"
    near = client.post("/api/attendance/clock", json={"latitude": 24.861, "longitude": 67.001}, headers=staff)
    assert near.status_code == 201, near.text
    assert near.json()["data"]["punchType"] == "check_out"

    restriction = client.post("/api/attendance/settings/ip-restrictions", json={
        "ipv4": "10.20.0.0/16", "appliesToAll": False, "targets": [{"targetType": "employee", "targetId": emp}]},
        headers=admin)
    assert restriction.status_code == 201
    blocked = client.post("/api/attendance/clock", json={"latitude": 24.861, "longitude": 67.001,
                                                         "punchType": "check_in"}, headers=staff)
    assert blocked.status_code == 403 and blocked.json()["code"] == "IP_NOT_ALLOWED"

    fa.setting(db, company_id, "attendance", "picture_on_dashboard_punch", "true")
    pic = client.post("/api/attendance/clock", json={"latitude": 24.861, "longitude": 67.001}, headers=staff)
    assert pic.status_code == 422 and "photoFileId" in pic.json()["fieldErrors"]


def test_clock_in_with_photo(client, db):
    company_id = factories.company(db)
    emp = factories.employee(db, company_id)
    staff = factories.login_as(db, client, company_id, role_codes="employee", employee_id=emp)["headers"]
    admin = factories.login_as(db, client, company_id, role_codes="company_admin")["headers"]
    fa.setting(db, company_id, "attendance", "dashboard_punch", "true")
    fa.setting(db, company_id, "attendance", "picture_on_dashboard_punch", "true")
    assert client.get("/api/attendance/clock", headers=staff).json()["data"]["photoRequired"] is True

    # A file from another company cannot be used.
    other = factories.company(db)
    stranger = factories.login_as(db, client, other, role_codes="company_admin")["headers"]
    foreign = factories.upload(client, stranger, name="me.png", content=factories.PNG_BYTES, module="attendance")
    bad = client.post("/api/attendance/clock", json={"photoFileId": int(foreign["id"])}, headers=staff)
    assert bad.status_code == 422 and "photoFileId" in bad.json()["fieldErrors"]

    photo = factories.upload(client, staff, name="selfie.png", content=factories.PNG_BYTES, module="attendance")
    r = client.post("/api/attendance/clock", json={"photoFileId": int(photo["id"])}, headers=staff)
    assert r.status_code == 201, r.text
    punch = r.json()["data"]
    assert punch["photoFileId"] == photo["id"] and punch["photo"]["name"] == "selfie.png"
    assert client.get(punch["photo"]["url"]).content == factories.PNG_BYTES

    seen = client.get(f"/api/attendance/logs/{punch['id']}", headers=admin).json()["data"]
    assert seen["photo"]["id"] == photo["id"] and seen["photo"]["url"]


def test_fence_and_ip_checks():
    circle = {"shape": "circle", "center_lat": 24.86, "center_lng": 67.0, "radius_m": 100, "polygon_points": None}
    assert inside_fence(24.8605, 67.0, circle) and not inside_fence(24.87, 67.0, circle)
    square = {"shape": "polygon", "polygon_points": '[{"lat":0,"lng":0},{"lat":0,"lng":1},{"lat":1,"lng":1},{"lat":1,"lng":0}]'}
    assert inside_fence(0.5, 0.5, square) and not inside_fence(1.5, 0.5, square)
    net = {"ipv4": "192.168.2.0", "netmask": "255.255.255.0", "ipv6": None, "range_start": None, "range_end": None}
    assert ip_allowed("192.168.2.77", net) and not ip_allowed("192.168.3.1", net)
    rng = {"ipv4": None, "netmask": None, "ipv6": None, "range_start": "10.0.0.10", "range_end": "10.0.0.20"}
    assert ip_allowed("10.0.0.15", rng) and not ip_allowed("10.0.0.21", rng) and not ip_allowed("testclient", rng)


def test_other_company_cannot_see(client, db, org):
    other = factories.company(db)
    other_admin = factories.login_as(db, client, other, role_codes="company_admin")["headers"]
    pid = fa.punch(db, org["company"], org["outsider"], at(MON + timedelta(days=30), "09:00"))
    assert client.get(f"/api/attendance/logs/{pid}", headers=other_admin).status_code == 404
    d = MON + timedelta(days=30)
    assert client.get(f"/api/attendance/days/{org['outsider']}/{d}", headers=other_admin).status_code == 404
