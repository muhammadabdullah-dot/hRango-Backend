"""Roster groups (weekly patterns) and enrolling employees for a period."""
from datetime import date, timedelta

from tests import factories
from tests import factories_scheduling as fs

GR = "/api/roster/groups"


def _week(slot: int, off: tuple[int, ...] = (6, 7)) -> list[dict]:
    return [{"weekday": w, "isDayOff": w in off, "timeSlotId": None if w in off else slot} for w in range(1, 8)]


def test_roster_group_lifecycle(client, db, company, admin):
    h = admin["headers"]
    morning = fs.time_slot(db, company, "08:00", "16:00")
    title = f"Morning Work {factories.tag()}"
    body = {"title": title, "fromDate": str(fs.day(0)), "toDate": str(fs.day(90)), "days": _week(morning)}
    r = client.post(GR, json=body, headers=h)
    assert r.status_code == 201, r.text
    group = r.json()["data"]
    assert group["isActive"] is True and group["enrolledCount"] == 0 and len(group["days"]) == 7
    assert group["days"][0]["timeSlotId"] == str(morning) and group["days"][0]["startTime"] == "08:00:00"
    assert group["days"][6]["isDayOff"] is True

    # Days left out are days off.
    short = client.post(GR, json={**body, "title": f"Short {factories.tag()}",
                                  "days": [{"weekday": 3, "timeSlotId": morning}]}, headers=h)
    assert short.status_code == 201 and sum(not d["isDayOff"] for d in short.json()["data"]["days"]) == 1

    dup = client.post(GR, json={**body, "title": title.upper()}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "ROSTER_GROUP_DUPLICATE"
    all_off = client.post(GR, json={**body, "title": f"Off {factories.tag()}",
                                    "days": [{"weekday": 1, "isDayOff": True}]}, headers=h)
    assert all_off.status_code == 422 and "days" in all_off.json()["fieldErrors"]
    no_slot = client.post(GR, json={**body, "title": f"N {factories.tag()}", "days": [{"weekday": 1}]}, headers=h)
    assert no_slot.status_code == 422
    other_company_slot = fs.time_slot(db, factories.company(db))
    foreign = client.post(GR, json={**body, "title": f"F {factories.tag()}", "days": _week(other_company_slot)},
                          headers=h)
    assert foreign.status_code == 422

    listed = client.get(GR, params={"q": title}, headers=h).json()
    assert listed["meta"]["total"] == 1 and listed["data"][0]["workingDays"] == 5

    edited = client.put(f"{GR}/{group['id']}", json={**body, "days": _week(morning, off=(7,)),
                                                    "rowVersion": group["rowVersion"]}, headers=h)
    assert edited.status_code == 200 and edited.json()["data"]["days"][5]["isDayOff"] is False
    stale = client.put(f"{GR}/{group['id']}", json={**body, "rowVersion": group["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    emp = factories.employee(db, company)
    client.post(f"{GR}/{group['id']}/enrolments", json={"employeeIds": [emp], "startDate": str(fs.day(0))}, headers=h)
    rv = edited.json()["data"]["rowVersion"]
    assert client.delete(f"{GR}/{group['id']}", params={"rowVersion": rv}, headers=h).status_code == 409
    shrink = client.put(f"{GR}/{group['id']}", json={**body, "toDate": str(fs.day(30)), "rowVersion": rv}, headers=h)
    assert shrink.status_code == 409 and shrink.json()["code"] == "ENROLMENT_OUTSIDE_PERIOD"

    short_group = short.json()["data"]
    assert client.delete(f"{GR}/{short_group['id']}", params={"rowVersion": short_group["rowVersion"]},
                         headers=h).status_code == 204


def test_enrolment_rules(client, db, company, admin):
    h = admin["headers"]
    slot = fs.time_slot(db, company)
    today = date.today()
    g1 = fs.roster_group(db, company, {1: slot, 2: slot}, from_date=today - timedelta(days=60))
    g2 = fs.roster_group(db, company, {3: slot}, from_date=today - timedelta(days=60),
                         to_date=today + timedelta(days=200))
    a, b = factories.employee(db, company, first_name="Amna"), factories.employee(db, company, first_name="Bilal")

    r = client.post(f"{GR}/{g1}/enrolments", json={"employeeIds": [a, b, a], "startDate": str(today - timedelta(days=30))},
                    headers=h)
    assert r.status_code == 201, r.text
    rows = r.json()["data"]
    assert [x["employeeName"].split()[0] for x in rows] == ["Amna", "Bilal"] and rows[0]["status"] == "active"
    assert rows[0]["endDate"] is None

    # One roster at a time.
    clash = client.post(f"{GR}/{g2}/enrolments", json={"employeeIds": [a], "startDate": str(today)}, headers=h)
    assert clash.status_code == 409 and clash.json()["code"] == "ENROLMENT_OVERLAP"
    # Inside the group's period; an open end takes the group's end.
    early = client.post(f"{GR}/{g2}/enrolments", json={"employeeIds": [factories.employee(db, company)],
                                                      "startDate": str(today - timedelta(days=90))}, headers=h)
    assert early.status_code == 422
    c = factories.employee(db, company)
    later = client.post(f"{GR}/{g2}/enrolments", json={"employeeIds": [c], "startDate": str(today)}, headers=h)
    assert later.json()["data"][0]["endDate"] == str(today + timedelta(days=200))

    # Discontinue: ends today and moves to the discontinued tab tomorrow; ended in the past moves now.
    amna = rows[0]
    ended = client.patch(f"/api/roster/enrolments/{amna['id']}/discontinue",
                         json={"endDate": str(today - timedelta(days=1)), "rowVersion": amna["rowVersion"]}, headers=h)
    assert ended.status_code == 200, ended.text
    assert ended.json()["data"]["status"] == "discontinued"
    stale = client.put(f"/api/roster/enrolments/{amna['id']}",
                       json={"startDate": amna["startDate"], "rowVersion": amna["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    active = client.get(f"{GR}/{g1}/enrolments", params={"status": "active"}, headers=h).json()
    gone = client.get(f"{GR}/{g1}/enrolments", params={"status": "discontinued"}, headers=h).json()
    assert [x["employeeId"] for x in active["data"]] == [str(b)]
    assert [x["employeeId"] for x in gone["data"]] == [str(a)]
    assert client.get(f"{GR}/{g1}", headers=h).json()["data"]["enrolledCount"] == 1

    # Now free from today, Amna can join the other group.
    moved = client.post(f"{GR}/{g2}/enrolments", json={"employeeIds": [a], "startDate": str(today)}, headers=h)
    assert moved.status_code == 201

    bilal = active["data"][0]
    assert client.delete(f"/api/roster/enrolments/{bilal['id']}", params={"rowVersion": bilal["rowVersion"]},
                         headers=h).status_code == 204
    assert client.get(f"/api/roster/enrolments/{bilal['id']}", headers=h).status_code == 404


def test_enrolment_scope_and_permissions(client, db, company, admin):
    slot = fs.time_slot(db, company)
    group = fs.roster_group(db, company, {1: slot})
    manager = factories.employee(db, company)
    report = factories.employee(db, company, line_manager_id=manager)
    stranger = factories.employee(db, company)
    client.post(f"{GR}/{group}/enrolments", json={"employeeIds": [report, stranger], "startDate": str(fs.day(0))},
                headers=admin["headers"])

    lead = factories.login_as(db, client, company, role_codes="line_manager", employee_id=manager)
    seen = client.get(f"{GR}/{group}/enrolments", headers=lead["headers"]).json()
    assert [x["employeeId"] for x in seen["data"]] == [str(report)]
    # A line manager reads but does not enrol.
    assert client.post(f"{GR}/{group}/enrolments", json={"employeeIds": [report], "startDate": str(fs.day(0))},
                       headers=lead["headers"]).status_code == 403

    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=stranger)
    assert client.get(GR, headers=staff["headers"]).status_code == 403
    assert client.get(f"{GR}/{group}/enrolments", headers=staff["headers"]).status_code == 403
