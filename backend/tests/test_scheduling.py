"""The shift planner: Create Scheduling batches, single shifts, swap, multi edit / delete, the board."""
from tests import factories
from tests import factories_scheduling as fs

SC = "/api/scheduling/schedules"


def _shifts(db, employee_id):
    cur = db.conn.cursor()
    try:
        return cur.execute("SELECT id, work_date, start_at, end_at, time_slot_id, planned_minutes FROM sch.schedule "
                           "WHERE employee_id = ? ORDER BY start_at", employee_id).fetchall()
    finally:
        cur.close()


def test_create_scheduling_batch(client, db, company, admin):
    h = admin["headers"]
    brk = fs.break_type(db, company)
    slot = fs.time_slot(db, company, "09:00", "17:00",
                        breaks=[{"break_type_id": brk, "start_time": "13:00", "end_time": "14:00"}])
    a, b = factories.employee(db, company), factories.employee(db, company)
    # Two weeks, Monday to Friday.
    body = {"startDate": str(fs.day(0)), "endDate": str(fs.day(13)), "timeSlotId": slot,
            "weekdays": [1, 2, 3, 4, 5], "employeeIds": [a, b], "isWfh": True}
    r = client.post(f"{SC}/batches", json=body, headers=h)
    assert r.status_code == 201, r.text
    batch = r.json()["data"]
    assert batch["createdCount"] == 20 and batch["replacedCount"] == 0 and batch["weekdays"] == [1, 2, 3, 4, 5]
    rows = _shifts(db, a)
    assert len(rows) == 10 and rows[0].planned_minutes == 420 and str(rows[0].start_at) == f"{fs.day(0)} 09:00:00"
    assert fs.scalar(db, "SELECT COUNT(*) FROM sch.schedule_break b JOIN sch.schedule s ON s.id = b.schedule_id "
                         "WHERE s.employee_id = ?", a) == 10

    # The same days again: refused, unless replacing.
    again = client.post(f"{SC}/batches", json=body, headers=h)
    assert again.status_code == 409 and again.json()["code"] == "SCHEDULE_OVERLAP"
    evening = fs.time_slot(db, company, "18:00", "21:00")
    same_day = client.post(f"{SC}/batches", json={**body, "timeSlotId": evening}, headers=h)
    assert same_day.status_code == 409 and same_day.json()["code"] == "SCHEDULE_DAY_TAKEN"
    night = fs.time_slot(db, company, "22:00", "06:00")
    over = client.post(f"{SC}/batches", json={**body, "timeSlotId": night, "endDate": str(fs.day(4)),
                                              "replaceExisting": True, "breaks": []}, headers=h)
    assert over.status_code == 201, over.text
    assert over.json()["data"]["replacedCount"] == 10 and over.json()["data"]["createdCount"] == 10
    rows = _shifts(db, a)
    assert len(rows) == 10 and rows[0].time_slot_id == night and str(rows[0].end_at) == f"{fs.day(1)} 06:00:00"
    assert rows[0].planned_minutes == 480

    # Every 2 weeks, one week on, over four weeks, Mondays only: weeks 1 and 3.
    c = factories.employee(db, company)
    rep = client.post(f"{SC}/batches", json={"startDate": str(fs.day(0)), "endDate": str(fs.day(27)),
                                             "timeSlotId": slot, "weekdays": [1], "repeatEveryWeeks": 2, "step": 1,
                                             "employeeIds": [c]}, headers=h)
    assert rep.status_code == 201
    assert [str(x.work_date) for x in _shifts(db, c)] == [str(fs.day(0)), str(fs.day(14))]

    # Validation.
    both = client.post(f"{SC}/batches", json={**body, "rosterGroupId": fs.roster_group(db, company, {1: slot})},
                       headers=h)
    assert both.status_code == 422 and "timeSlotId" in both.json()["fieldErrors"]
    backwards = client.post(f"{SC}/batches", json={**body, "endDate": str(fs.day(-1))}, headers=h)
    assert backwards.status_code == 422
    outside = client.post(f"{SC}/batches", json={**body, "replaceExisting": True,
                                                 "breaks": [{"breakTypeId": brk, "startTime": "18:00",
                                                             "endTime": "18:30"}]}, headers=h)
    assert outside.status_code == 422 and outside.json()["code"] == "BREAK_OUTSIDE_SHIFT"
    foreign = client.post(f"{SC}/batches", json={**body, "employeeIds": [factories.employee(db, factories.company(db))]},
                          headers=h)
    assert foreign.status_code == 422 and "employeeIds" in foreign.json()["fieldErrors"]


def test_rest_days_and_multi_shift(client, db, company, admin):
    h = admin["headers"]
    morning = fs.time_slot(db, company, "06:00", "10:00")
    evening = fs.time_slot(db, company, "18:00", "22:00")
    emp = factories.employee(db, company)
    rule = client.post("/api/scheduling/settings/rest-days",
                       json={"fromDate": str(fs.day(0)), "toDate": str(fs.day(6)), "weekdays": [3],
                             "employeeIds": [emp]}, headers=h)
    assert rule.status_code == 201
    r = client.post(f"{SC}/batches", json={"startDate": str(fs.day(0)), "endDate": str(fs.day(4)),
                                           "timeSlotId": morning, "employeeIds": [emp]}, headers=h)
    assert r.json()["data"]["createdCount"] == 4 and r.json()["data"]["skippedRestDays"] == 1
    on_rest = client.post(SC, json={"employeeId": emp, "workDate": str(fs.day(2)), "timeSlotId": morning}, headers=h)
    assert on_rest.status_code == 409 and on_rest.json()["code"] == "REST_DAY"

    second = {"employeeId": emp, "workDate": str(fs.day(0)), "timeSlotId": evening}
    refused = client.post(SC, json=second, headers=h)
    assert refused.status_code == 409 and refused.json()["code"] == "SCHEDULE_DAY_TAKEN"
    fs.allow_multi_shift(db, company)
    try:
        ok = client.post(SC, json=second, headers=h)
        assert ok.status_code == 201, ok.text
        overlap = client.post(SC, json={**second, "timeSlotId": morning, "startTime": "09:00", "endTime": "12:00"},
                              headers=h)
        assert overlap.status_code == 409 and overlap.json()["code"] == "SCHEDULE_OVERLAP"
    finally:
        fs.allow_multi_shift(db, company, False)

    days = db.conn.cursor().execute("SELECT work_date, day_kind, schedule_id FROM sch.fn_employee_day_schedule(?, ?, ?, ?) "
                                    "ORDER BY work_date, start_at", company, emp, fs.day(0), fs.day(5)).fetchall()
    kinds = [(str(d.work_date), d.day_kind) for d in days]
    assert kinds[:2] == [(str(fs.day(0)), "shift"), (str(fs.day(0)), "shift")]
    assert (str(fs.day(2)), "rest_day") in kinds and (str(fs.day(5)), "unscheduled") in kinds


def test_roster_and_default_shift_batches(client, db, company, admin):
    h = admin["headers"]
    early = fs.time_slot(db, company, "07:00", "15:00")
    late = fs.time_slot(db, company, "15:00", "23:00")
    group = fs.roster_group(db, company, {1: early, 2: late, 3: early}, from_date=fs.day(0), to_date=fs.day(30))
    member = factories.employee(db, company)
    client.post(f"/api/roster/groups/{group}/enrolments", json={"employeeIds": [member], "startDate": str(fs.day(7))},
                headers=h)

    # A roster group with no employees: its members, on the dates they are enrolled.
    r = client.post(f"{SC}/batches", json={"startDate": str(fs.day(0)), "endDate": str(fs.day(13)),
                                           "rosterGroupId": group}, headers=h)
    assert r.status_code == 201, r.text
    rows = _shifts(db, member)
    assert [(str(x.work_date), x.time_slot_id) for x in rows] == [
        (str(fs.day(7)), early), (str(fs.day(8)), late), (str(fs.day(9)), early)]

    # Apply Default Shift: the roster while enrolled, otherwise the employee's default slot.
    plain = factories.employee(db, company)
    db.conn.cursor().execute("UPDATE hr.employee SET default_time_slot_id = ? WHERE id = ?", late, plain).close()
    nobody = factories.employee(db, company)
    d = client.post(f"{SC}/default-shift", json={"startDate": str(fs.day(14)), "endDate": str(fs.day(20)),
                                                 "employeeIds": [member, plain, nobody]}, headers=h)
    assert d.status_code == 201, d.text
    assert d.json()["data"]["batchKind"] == "default_shift"
    assert d.json()["data"]["createdCount"] == 3 + 7 and d.json()["data"]["skippedNoShift"] == 4 + 7
    assert {x.time_slot_id for x in _shifts(db, plain)} == {late}
    none = client.post(f"{SC}/default-shift", json={"startDate": str(fs.day(14)), "endDate": str(fs.day(20)),
                                                    "employeeIds": [nobody]}, headers=h)
    assert none.status_code == 422 and none.json()["code"] == "NOTHING_TO_SCHEDULE"


def test_single_shift_edit_swap_and_bulk(client, db, company, admin):
    h = admin["headers"]
    brk = fs.break_type(db, company)
    slot = fs.time_slot(db, company, "09:00", "17:00")
    other_slot = fs.time_slot(db, company, "12:00", "20:00")
    a, b = factories.employee(db, company), factories.employee(db, company)

    r = client.post(SC, json={"employeeId": a, "workDate": str(fs.day(0)), "timeSlotId": slot,
                              "breaks": [{"breakTypeId": brk, "startTime": "12:00", "endTime": "12:30"}]}, headers=h)
    assert r.status_code == 201, r.text
    s1 = r.json()["data"]
    assert s1["plannedMinutes"] == 450 and len(s1["breaks"]) == 1 and s1["isOvernight"] is False

    moved = client.put(f"{SC}/{s1['id']}", json={"workDate": str(fs.day(1)), "timeSlotId": slot, "startTime": "20:00",
                                                "endTime": "04:00", "rowVersion": s1["rowVersion"]}, headers=h)
    assert moved.status_code == 200, moved.text
    m = moved.json()["data"]
    assert m["isOvernight"] is True and m["endAt"].startswith(str(fs.day(2))) and m["plannedMinutes"] == 480
    assert m["employeeId"] == str(a) and m["breaks"] == []
    stale = client.put(f"{SC}/{s1['id']}", json={"workDate": str(fs.day(1)), "timeSlotId": slot,
                                                "rowVersion": s1["rowVersion"]}, headers=h)
    assert stale.status_code == 409
    one_time = client.put(f"{SC}/{s1['id']}", json={"workDate": str(fs.day(1)), "timeSlotId": slot,
                                                   "startTime": "08:00", "rowVersion": m["rowVersion"]}, headers=h)
    assert one_time.status_code == 422

    s2 = client.post(SC, json={"employeeId": b, "workDate": str(fs.day(3)), "timeSlotId": slot}, headers=h).json()["data"]
    swapped = client.post(f"{SC}/{s1['id']}/swap", json={"withScheduleId": s2["id"], "rowVersion": m["rowVersion"]},
                          headers=h)
    assert swapped.status_code == 200, swapped.text
    assert swapped.json()["data"]["employeeId"] == str(b)
    assert client.get(f"{SC}/{s2['id']}", headers=h).json()["data"]["employeeId"] == str(a)
    stale_swap = client.post(f"{SC}/{s1['id']}/swap", json={"withEmployeeId": a, "rowVersion": m["rowVersion"]},
                             headers=h)
    assert stale_swap.status_code == 409
    rv = swapped.json()["data"]["rowVersion"]
    self_swap = client.post(f"{SC}/{s1['id']}/swap", json={"withEmployeeId": b, "rowVersion": rv}, headers=h)
    assert self_swap.status_code == 422 and "withEmployeeId" in self_swap.json()["fieldErrors"]

    # Give s1 (now b's, day 1) to a, who already works day 3 only: fine. Then a clash.
    give = client.post(f"{SC}/{s1['id']}/swap", json={"withEmployeeId": a, "rowVersion": rv}, headers=h)
    assert give.status_code == 200 and give.json()["data"]["employeeId"] == str(a)
    s3 = client.post(SC, json={"employeeId": b, "workDate": str(fs.day(3)), "timeSlotId": other_slot},
                     headers=h).json()["data"]
    clash = client.post(f"{SC}/{s3['id']}/swap", json={"withEmployeeId": a, "rowVersion": s3["rowVersion"]},
                        headers=h)
    assert clash.status_code == 409 and clash.json()["code"] == "SCHEDULE_OVERLAP"

    edited = client.post(f"{SC}/bulk-edit", json={"ids": [s1["id"], s2["id"]], "timeSlotId": other_slot, "isWfh": True},
                         headers=h)
    assert edited.status_code == 200, edited.text
    assert edited.json()["data"]["updatedSchedules"] == 2
    after = client.get(f"{SC}/{s2['id']}", headers=h).json()["data"]
    assert after["timeSlotId"] == str(other_slot) and after["isWfh"] is True and after["startAt"].endswith("12:00:00")
    assert client.post(f"{SC}/bulk-edit", json={"ids": [s1["id"]]}, headers=h).status_code == 422

    gone = client.post(f"{SC}/bulk-delete", json={"ids": [s1["id"], s2["id"]]}, headers=h)
    assert gone.status_code == 200 and gone.json()["data"]["deletedSchedules"] == 2
    assert client.get(f"{SC}/{s1['id']}", headers=h).status_code == 404
    assert client.delete(f"{SC}/{s3['id']}", params={"rowVersion": "0000000000000000"}, headers=h).status_code == 409
    assert client.delete(f"{SC}/{s3['id']}", params={"rowVersion": s3["rowVersion"]}, headers=h).status_code == 204


def test_delete_range_keeps_rest_days_unless_asked(client, db, company, admin):
    h = admin["headers"]
    slot = fs.time_slot(db, company)
    emp = factories.employee(db, company)
    client.post("/api/scheduling/settings/rest-days", json={"fromDate": str(fs.day(0)), "toDate": str(fs.day(6)),
                                                            "weekdays": [7], "employeeIds": [emp]}, headers=h)
    client.post(f"{SC}/batches", json={"startDate": str(fs.day(0)), "endDate": str(fs.day(6)), "timeSlotId": slot,
                                       "employeeIds": [emp]}, headers=h)
    r = client.post(f"{SC}/bulk-delete", json={"startDate": str(fs.day(0)), "endDate": str(fs.day(2)),
                                               "employeeIds": [emp]}, headers=h)
    assert r.json()["data"] == {"deletedSchedules": 3, "deletedRestDays": 0}
    r = client.post(f"{SC}/bulk-delete", json={"startDate": str(fs.day(0)), "endDate": str(fs.day(6)),
                                               "employeeIds": [emp], "deleteRestDays": True}, headers=h)
    assert r.json()["data"] == {"deletedSchedules": 3, "deletedRestDays": 1}
    missing = client.post(f"{SC}/bulk-delete", json={"startDate": str(fs.day(0)), "endDate": str(fs.day(6))}, headers=h)
    assert missing.status_code == 422


def test_board_tabs_and_scope(client, db, company, admin):
    h = admin["headers"]
    slot = fs.time_slot(db, company, "10:00", "17:00")
    dept = factories.department(db, company)
    manager = factories.employee(db, company, department_id=dept, first_name="Mona")
    report = factories.employee(db, company, department_id=dept, line_manager_id=manager, first_name="Rafay")
    deep = factories.employee(db, company, department_id=dept, line_manager_id=report, first_name="Sana")
    stranger = factories.employee(db, company, department_id=dept, first_name="Tariq")
    client.post(f"{SC}/batches", json={"startDate": str(fs.day(0)), "endDate": str(fs.day(6)), "timeSlotId": slot,
                                       "weekdays": [1, 2, 3, 4, 5], "employeeIds": [manager, report, deep, stranger]},
                headers=h)
    client.post("/api/scheduling/settings/rest-days", json={"fromDate": str(fs.day(0)), "toDate": str(fs.day(6)),
                                                            "weekdays": [6], "employeeIds": [report]}, headers=h)
    week = {"from": str(fs.day(0)), "to": str(fs.day(6)), "departmentId": dept}

    everyone = client.get(SC, params={**week, "pageSize": 3}, headers=h)
    assert everyone.status_code == 200, everyone.text
    page = everyone.json()
    assert page["meta"]["total"] == 4 and len(page["data"]) == 3
    first = page["data"][0]
    assert first["employee"]["name"].startswith("Mona") and len(first["shifts"]) == 5
    assert first["employee"]["plannedMinutes"] == 5 * 420 and first["shifts"][0]["timeSlotId"] == str(slot)
    assert page["dayTotals"][0] == {"workDate": str(fs.day(0)), "plannedMinutes": 4 * 420, "shiftCount": 4}
    rafay = page["data"][1]
    assert rafay["restDays"][0]["restDate"] == str(fs.day(5))

    lead = factories.login_as(db, client, company, role_codes="line_manager", employee_id=manager)
    subs = client.get(SC, params={**week, "tab": "subordinates"}, headers=lead["headers"]).json()
    assert [r["employee"]["id"] for r in subs["data"]] == [str(report), str(deep)]
    mine = client.get(SC, params={**week, "tab": "my"}, headers=lead["headers"]).json()
    assert [r["employee"]["id"] for r in mine["data"]] == [str(manager)]
    allowed = client.get(SC, params=week, headers=lead["headers"]).json()
    assert {r["employee"]["id"] for r in allowed["data"]} == {str(manager), str(report), str(deep)}
    stranger_shift = fs.scalar(db, "SELECT TOP 1 id FROM sch.schedule WHERE employee_id = ?", stranger)
    assert client.get(f"{SC}/{stranger_shift}", headers=lead["headers"]).status_code == 404
    # A line manager plans their own team, not anyone else.
    planned = client.post(SC, json={"employeeId": report, "workDate": str(fs.day(6)), "timeSlotId": slot},
                          headers=lead["headers"])
    assert planned.status_code == 201, planned.text
    assert client.delete(f"{SC}/{planned.json()['data']['id']}", params={"rowVersion": planned.json()["data"]["rowVersion"]},
                         headers=lead["headers"]).status_code == 204
    assert client.post(SC, json={"employeeId": stranger, "workDate": str(fs.day(6)), "timeSlotId": slot},
                       headers=lead["headers"]).status_code in (403, 404, 422)

    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=deep)
    own = client.get(SC, params=week, headers=staff["headers"]).json()
    assert [r["employee"]["id"] for r in own["data"]] == [str(deep)]
    assert client.post(f"{SC}/batches", json={"startDate": str(fs.day(0)), "endDate": str(fs.day(0)),
                                              "timeSlotId": slot, "employeeIds": [deep]},
                       headers=staff["headers"]).status_code == 403

    officer = factories.login_as(db, client, company, role_codes="hr_officer")
    blocked = client.post(f"{SC}/bulk-delete", json={"ids": [stranger_shift]}, headers=officer["headers"])
    assert blocked.status_code == 403
    assert client.get(SC, params={"from": str(fs.day(0)), "to": str(fs.day(100))}, headers=h).status_code == 422

    year = client.get(f"{SC}/year", params={"year": fs.day(0).year, "departmentId": dept}, headers=h).json()
    rafay_year = next(r for r in year["data"] if r["employee"]["id"] == str(report))
    assert rafay_year["months"] == [{"month": fs.day(0).month, "plannedMinutes": 5 * 420, "shiftCount": 5,
                                     "restDays": 1}]

    csv_text = client.get(f"{SC}/export", params=week, headers=h)
    assert csv_text.status_code == 200 and csv_text.headers["content-type"].startswith("text/csv")
    lines = csv_text.text.strip().splitlines()
    assert lines[0].startswith("Employee Code") and len(lines) == 1 + 4 * 5 + 1
    assert any("Rest Day" in line for line in lines)


def test_options_for_the_planner_forms(client, db, company, admin):
    slot = fs.time_slot(db, company)
    officer = factories.login_as(db, client, company, role_codes="hr_officer")
    # HR officers have no settings access but still pick slots in Create Scheduling.
    r = client.get("/api/scheduling/options/time-slots", headers=officer["headers"])
    assert r.status_code == 200 and str(slot) in [o["id"] for o in r.json()["data"]]
    assert client.get("/api/scheduling/options/roster-groups", headers=officer["headers"]).status_code == 200
    nobody = factories.login_as(db, client, company)
    assert client.get("/api/scheduling/options/break-types", headers=nobody["headers"]).status_code == 403
