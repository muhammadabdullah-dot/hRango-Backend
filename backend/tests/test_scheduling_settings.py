"""Scheduling settings: time slots, break types, rest-day rules and holidays."""
import pytest

from tests import factories
from tests import factories_scheduling as fs

TS = "/api/scheduling/settings/time-slots"
BT = "/api/scheduling/settings/break-types"
RD = "/api/scheduling/settings/rest-days"
HO = "/api/scheduling/settings/holidays"


def test_time_slot_lifecycle(client, db, company, admin):
    h = admin["headers"]
    lunch = fs.break_type(db, company)
    name = f"Day {factories.tag()}"
    body = {"name": name, "startTime": "09:00", "endTime": "17:00", "fullOvertime": True,
            "breaks": [{"breakTypeId": str(lunch), "startTime": "13:00", "endTime": "13:45"}]}
    r = client.post(TS, json=body, headers=h)
    assert r.status_code == 201, r.text
    slot = r.json()["data"]
    assert slot["code"].startswith("TS-") and slot["durationMinutes"] == 480
    assert slot["workableMinutes"] == 435 and slot["isOvernight"] is False and slot["fullOvertime"] is True
    assert slot["breaks"][0]["breakTypeId"] == str(lunch) and slot["startTime"] == "09:00:00"

    second = client.post(TS, json={"name": f"Night {factories.tag()}", "startTime": "22:00", "endTime": "06:00",
                                   "breaks": [{"breakTypeId": lunch, "startTime": "02:00", "endTime": "02:30",
                                               "isInclusive": True}]}, headers=h)
    assert second.status_code == 201, second.text
    night = second.json()["data"]
    assert night["isOvernight"] is True and night["durationMinutes"] == 480 and night["workableMinutes"] == 480
    assert int(night["code"][3:]) == int(slot["code"][3:]) + 1

    dup = client.post(TS, json={**body, "name": name.lower()}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "TIME_SLOT_DUPLICATE"

    outside = client.post(TS, json={**body, "name": f"X {factories.tag()}",
                                    "breaks": [{"breakTypeId": lunch, "startTime": "18:00", "endTime": "18:30"}]},
                          headers=h)
    assert outside.status_code == 422 and outside.json()["code"] == "BREAK_OUTSIDE_SLOT"

    flexible = client.post(TS, json={"name": f"Flex {factories.tag()}", "startTime": "07:00", "endTime": "19:00",
                                     "isFlexible": True}, headers=h)
    assert flexible.status_code == 422 and "workableMinutes" in flexible.json()["fieldErrors"]

    page = client.get(TS, params={"q": name}, headers=h).json()
    assert page["meta"]["total"] == 1 and page["data"][0]["breakCount"] == 1

    edited = client.put(f"{TS}/{slot['id']}", json={**body, "endTime": "18:00", "rowVersion": slot["rowVersion"]},
                        headers=h)
    assert edited.status_code == 200, edited.text
    assert edited.json()["data"]["workableMinutes"] == 495
    stale = client.put(f"{TS}/{slot['id']}", json={**body, "rowVersion": slot["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    # In use by a shift: refused. Then free: deleted.
    emp = factories.employee(db, company)
    shift = client.post("/api/scheduling/schedules", json={"employeeId": emp, "workDate": str(fs.day(0)),
                                                          "timeSlotId": slot["id"]}, headers=h)
    assert shift.status_code == 201, shift.text
    rv = edited.json()["data"]["rowVersion"]
    assert client.delete(f"{TS}/{slot['id']}", params={"rowVersion": rv}, headers=h).status_code == 409
    sh = shift.json()["data"]
    assert client.delete(f"/api/scheduling/schedules/{sh['id']}", params={"rowVersion": sh["rowVersion"]},
                         headers=h).status_code == 204
    assert client.delete(f"{TS}/{slot['id']}", params={"rowVersion": rv}, headers=h).status_code == 204
    assert client.get(f"{TS}/{slot['id']}", headers=h).status_code == 404


def test_break_type_lifecycle(client, db, company, admin):
    h = admin["headers"]
    t = factories.tag()
    r = client.post(BT, json={"name": f"Prayer {t}", "startIdentifier": f"P{t} Out", "endIdentifier": f"P{t} In"},
                    headers=h)
    assert r.status_code == 201, r.text
    bt = r.json()["data"]

    same = client.post(BT, json={"name": f"Other {t}", "startIdentifier": f"P{t} In", "endIdentifier": f"Z{t}"},
                       headers=h)
    assert same.status_code == 409 and same.json()["code"] == "IDENTIFIER_DUPLICATE"
    assert "startIdentifier" in same.json()["fieldErrors"]
    blank = client.post(BT, json={"name": "", "startIdentifier": "a", "endIdentifier": "b"}, headers=h)
    assert blank.status_code == 422

    renamed = client.put(f"{BT}/{bt['id']}", json={"name": f"Prayer 2 {t}", "startIdentifier": f"P{t} Out",
                                                  "endIdentifier": f"P{t} In", "rowVersion": bt["rowVersion"]},
                         headers=h)
    assert renamed.status_code == 200
    stale = client.delete(f"{BT}/{bt['id']}", params={"rowVersion": bt["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    fs.time_slot(db, company, breaks=[{"break_type_id": int(bt["id"]), "start_time": "12:00", "end_time": "12:30"}])
    in_use = client.delete(f"{BT}/{bt['id']}", params={"rowVersion": renamed.json()["data"]["rowVersion"]}, headers=h)
    assert in_use.status_code == 409


def test_rest_day_rule_generates_days(client, db, company, admin):
    h = admin["headers"]
    a, b = factories.employee(db, company), factories.employee(db, company)
    # Every 2 weeks, 1 week on, Saturday and Sunday, over four weeks: weeks 1 and 3.
    body = {"fromDate": str(fs.day(0)), "toDate": str(fs.day(27)), "weekdays": [7, 6], "repeatEveryWeeks": 2,
            "step": 1, "isPayable": True, "employeeIds": [a, b]}
    r = client.post(RD, json=body, headers=h)
    assert r.status_code == 201, r.text
    rule = r.json()["data"]
    assert rule["weekdays"] == [6, 7] and rule["employeeCount"] == 2 and rule["restDayCount"] == 8
    dates = sorted(str(d) for d in [fs.day(5), fs.day(6), fs.day(19), fs.day(20)])
    got = [str(x.rest_date) for x in db.conn.cursor().execute(
        "SELECT rest_date FROM sch.rest_day WHERE employee_id = ? ORDER BY rest_date", a).fetchall()]
    assert got == dates

    bad_step = client.post(RD, json={**body, "step": 3}, headers=h)
    assert bad_step.status_code == 422 and "step" in bad_step.json()["fieldErrors"]
    no_days = client.post(RD, json={**body, "weekdays": [9]}, headers=h)
    assert no_days.status_code == 422

    # A second rule over the same dates leaves existing rest days alone.
    other = client.post(RD, json={**body, "repeatEveryWeeks": 0, "employeeIds": [a]}, headers=h).json()["data"]
    assert other["restDayCount"] == 4

    edited = client.put(f"{RD}/{rule['id']}", json={**body, "employeeIds": [b], "rowVersion": rule["rowVersion"]},
                        headers=h)
    assert edited.status_code == 200 and edited.json()["data"]["employeeCount"] == 1
    assert client.get(RD, params={"employeeId": a}, headers=h).json()["meta"]["total"] == 1
    rv = edited.json()["data"]["rowVersion"]
    assert client.delete(f"{RD}/{rule['id']}", params={"rowVersion": rv}, headers=h).status_code == 204
    assert fs.scalar(db, "SELECT COUNT(*) FROM sch.rest_day WHERE employee_id = ?", b) == 0


def test_holiday_rules_decide_who_gets_it(client, db, company, admin):
    h = admin["headers"]
    loc = factories.location(db, company)
    br = factories.branch(db, company, location_id=loc)
    inside = factories.employee(db, company, branch_id=br)
    named = factories.employee(db, company)
    outside = factories.employee(db, company)
    t = factories.tag()
    body = {"name": f"Eid {t}", "holidayType": "public", "startDate": str(fs.day(2)), "endDate": str(fs.day(3)),
            "attendanceExempt": True,
            "rules": [{"ruleType": "org_structure", "locationId": loc, "branchId": br},
                      {"ruleType": "employee", "employeeId": named}]}
    r = client.post(HO, json=body, headers=h)
    assert r.status_code == 201, r.text
    hol = r.json()["data"]
    assert hol["dayCount"] == 2 and len(hol["rules"]) == 2 and hol["rules"][0]["branchId"] == str(br)

    who = {row.employee_id for row in db.conn.cursor().execute(
        "SELECT DISTINCT employee_id FROM sch.fn_employee_holidays(?, ?, ?) WHERE holiday_id = ?",
        company, fs.day(0), fs.day(6), int(hol["id"])).fetchall()}
    assert inside in who and named in who and outside not in who

    day = db.conn.cursor().execute("SELECT day_kind, holiday_name FROM sch.fn_employee_day_schedule(?, ?, ?, ?) "
                                   "WHERE work_date = ?", company, inside, fs.day(0), fs.day(6), fs.day(2)).fetchone()
    assert day.day_kind == "holiday" and day.holiday_name == f"Eid {t}"

    other_loc = factories.location(db, company)
    wrong = client.post(HO, json={**body, "name": f"X {t}",
                                  "rules": [{"ruleType": "org_structure", "locationId": other_loc, "branchId": br}]},
                        headers=h)
    assert wrong.status_code == 422 and "rules" in wrong.json()["fieldErrors"]
    missing = client.post(HO, json={**body, "name": f"Y {t}", "rules": [{"ruleType": "religion"}]}, headers=h)
    assert missing.status_code == 422
    backwards = client.post(HO, json={**body, "name": f"Z {t}", "endDate": str(fs.day(1))}, headers=h)
    assert backwards.status_code == 422
    dup = client.post(HO, json=body, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "HOLIDAY_DUPLICATE"

    listed = client.get(HO, params={"year": fs.day(2).year, "q": f"Eid {t}"}, headers=h).json()
    assert listed["meta"]["total"] == 1 and listed["data"][0]["ruleCount"] == 2

    everyone = client.put(f"{HO}/{hol['id']}", json={**body, "rules": [], "rowVersion": hol["rowVersion"]}, headers=h)
    assert everyone.status_code == 200 and everyone.json()["data"]["rules"] == []
    assert fs.scalar(db, "SELECT COUNT(*) FROM sch.fn_employee_holidays(?, ?, ?) WHERE holiday_id = ? AND employee_id = ?",
                     company, fs.day(2), fs.day(2), int(hol["id"]), outside) == 1
    assert client.delete(f"{HO}/{hol['id']}", params={"rowVersion": hol["rowVersion"]}, headers=h).status_code == 409
    assert client.delete(f"{HO}/{hol['id']}", params={"rowVersion": everyone.json()["data"]["rowVersion"]},
                         headers=h).status_code == 204


@pytest.mark.parametrize("role", ["employee", "hr_officer", "line_manager"])
def test_settings_need_the_settings_permission(client, db, company, role):
    who = factories.login_as(db, client, company, role_codes=role, employee_id=factories.employee(db, company))
    for url in (TS, BT, RD, HO):
        assert client.get(url, headers=who["headers"]).status_code == 403
    assert client.post(BT, json={"name": "x", "startIdentifier": "a", "endIdentifier": "b"},
                       headers=who["headers"]).status_code == 403


def test_other_company_cannot_see_settings(client, db, admin, company):
    slot = fs.time_slot(db, company)
    other = factories.company(db)
    other_admin = factories.login_as(db, client, other, role_codes="company_admin")
    assert client.get(f"{TS}/{slot}", headers=other_admin["headers"]).status_code == 404


def test_rest_day_range_delete_keeps_shifts(client, db, company, admin):
    h = admin["headers"]
    slot = fs.time_slot(db, company)
    emp = factories.employee(db, company)
    client.post(RD, json={"fromDate": str(fs.day(0)), "toDate": str(fs.day(13)), "weekdays": [6, 7],
                          "employeeIds": [emp]}, headers=h)
    client.post("/api/scheduling/schedules/batches", json={"startDate": str(fs.day(0)), "endDate": str(fs.day(4)),
                                                         "timeSlotId": slot, "employeeIds": [emp]}, headers=h)
    r = client.post(f"{RD}/delete-range", json={"startDate": str(fs.day(0)), "endDate": str(fs.day(6)),
                                                 "employeeIds": [emp]}, headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["data"] == {"deletedSchedules": 0, "deletedRestDays": 2}
    assert fs.scalar(db, "SELECT COUNT(*) FROM sch.rest_day WHERE employee_id = ?", emp) == 2
    assert fs.scalar(db, "SELECT COUNT(*) FROM sch.schedule WHERE employee_id = ?", emp) == 5
    nobody = client.post(f"{RD}/delete-range", json={"startDate": str(fs.day(0)), "endDate": str(fs.day(6))},
                         headers=h)
    assert nobody.status_code == 422
