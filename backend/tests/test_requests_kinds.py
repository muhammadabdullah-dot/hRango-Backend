"""Per-type rules checked on submit and on approval (Functional Requirements pp. 1-97)."""
from datetime import date, time, timedelta

import pytest

from tests import factories, factories_requests as fr

DAY = date.today() + timedelta(days=45)
PAST = date.today() - timedelta(days=3)


@pytest.fixture
def org(db, client):
    return fr.org(db, client)


def post(client, who, type_slug, body):
    return client.post(f"/api/requests/{type_slug}", json=body, headers=who.headers)


def test_leave_rules_and_balance(client, db, org):
    lt = fr.leave_type(db, org.company_id)
    fr.allot_leave(db, org.staff.employee_id, lt, 5)
    body = {"fromDate": str(DAY), "toDate": str(DAY + timedelta(days=2)), "details": {"leaveTypeId": lt}}

    assert post(client, org.staff, "leave", body).status_code == 422  # Reason* is required
    r = post(client, org.staff, "leave", {**body, "reason": "Family wedding"})
    assert r.status_code == 201, r.text
    leave = r.json()["data"]
    assert leave["days"] == 3 and leave["details"]["days"] == 3 and leave["details"]["leaveTypeId"] == str(lt)

    overlap = post(client, org.staff, "leave", {**body, "reason": "x", "toDate": str(DAY)})
    assert overlap.status_code == 409 and overlap.json()["code"] == "LEAVE_OVERLAP"
    more = post(client, org.staff, "leave", {"fromDate": str(DAY + timedelta(days=10)),
                                             "toDate": str(DAY + timedelta(days=12)), "reason": "x",
                                             "details": {"leaveTypeId": lt}})
    assert more.status_code == 409 and more.json()["code"] == "LEAVE_BALANCE_EXCEEDED"
    short = post(client, org.staff, "leave", {"fromDate": str(DAY + timedelta(days=20)), "reason": "x",
                                              "details": {"leaveTypeId": lt, "isShort": True,
                                                          "shortLeaveType": "half_day", "startTime": "09:00",
                                                          "endTime": "13:00"}})
    assert short.status_code == 422 and "isShort" in short.json()["fieldErrors"]

    # Editing keeps this request's own days available to it.
    edit = client.put(f"/api/requests/leave/{leave['id']}",
                      json={**body, "reason": "Wedding", "toDate": str(DAY + timedelta(days=4)),
                            "rowVersion": leave["rowVersion"]}, headers=org.staff.headers)
    assert edit.status_code == 200, edit.text
    assert edit.json()["data"]["days"] == 5


def test_leave_type_preconditions(client, db, org):
    no_back = fr.leave_type(db, org.company_id, allow_back_date=0, is_deductible=0)
    r = post(client, org.staff, "leave", {"fromDate": str(PAST), "toDate": str(PAST), "reason": "x",
                                          "details": {"leaveTypeId": no_back}})
    assert r.status_code == 422 and "fromDate" in r.json()["fieldErrors"]
    female = fr.leave_type(db, org.company_id, gender="female", is_deductible=0)
    fr.execute(db, "UPDATE hr.employee SET gender = N'male' WHERE id = ?", org.staff.employee_id)
    r = post(client, org.staff, "leave", {"fromDate": str(DAY), "toDate": str(DAY), "reason": "x",
                                          "details": {"leaveTypeId": female}})
    assert r.status_code == 422 and "leaveTypeId" in r.json()["fieldErrors"]
    needs_file = fr.leave_type(db, org.company_id, attachment_required=1, is_deductible=0)
    body = {"fromDate": str(DAY), "toDate": str(DAY), "reason": "Sick", "details": {"leaveTypeId": needs_file}}
    assert post(client, org.staff, "leave", body).status_code == 422
    note = factories.upload(client, org.staff.headers, name="note.pdf", module="requests")
    assert post(client, org.staff, "leave", {**body, "attachments": [int(note["id"])]}).status_code == 201


def test_punch_needs_a_shift_and_a_time_inside_it(client, db, org):
    body = {"details": {"punchDate": str(PAST), "punchType": "check_in", "punchTime": "09:05"}}
    r = post(client, org.staff, "punch", body)
    assert r.status_code == 422 and r.json()["code"] == "NO_SHIFT"
    slot = fr.time_slot(db, org.company_id)
    fr.schedule(db, org.company_id, org.staff.employee_id, PAST, slot)
    late = post(client, org.staff, "punch", {"details": {**body["details"], "punchTime": "20:00"}})
    assert late.status_code == 422 and "punchTime" in late.json()["fieldErrors"]
    ok = post(client, org.staff, "punch", body)
    assert ok.status_code == 201, ok.text
    assert ok.json()["data"]["details"]["punchType"] == "check_in" and ok.json()["data"]["fromDate"] == str(PAST)
    assert post(client, org.staff, "punch", body).status_code == 409
    future = post(client, org.staff, "punch", {"details": {**body["details"], "punchDate": str(DAY)}})
    assert future.status_code == 422


def test_relaxation_and_work_from_home_read_the_shift(client, db, org):
    slot = fr.time_slot(db, org.company_id)
    body = {"reason": "Doctor", "details": {"windowDate": str(DAY), "startTime": "10:00", "endTime": "12:00"}}
    assert post(client, org.staff, "relaxation", body).status_code == 422  # no shift that day
    fr.schedule(db, org.company_id, org.staff.employee_id, DAY, slot)
    outside = post(client, org.staff, "relaxation", {**body, "details": {**body["details"], "endTime": "18:00"}})
    assert outside.status_code == 422
    r = post(client, org.staff, "relaxation", body)
    assert r.status_code == 201, r.text
    req = r.json()["data"]
    assert req["details"]["timeSlotId"] == str(slot) and req["details"]["durationMinutes"] == 120
    # Approving a relaxation needs "Reason for Approval".
    no_reason = client.post(f"/api/requests/approvals/{req['id']}/approve", json={"rowVersion": req["rowVersion"]},
                            headers=org.manager.headers)
    assert no_reason.status_code == 422 and "remarks" in no_reason.json()["fieldErrors"]

    start = DAY + timedelta(days=7)
    wfh = {"fromDate": str(start), "toDate": str(start + timedelta(days=2)), "reason": "Renovation", "details": {}}
    assert post(client, org.staff, "work-from-home", wfh).status_code == 422
    fr.schedule(db, org.company_id, org.staff.employee_id, start, slot)
    fr.schedule(db, org.company_id, org.staff.employee_id, start + timedelta(days=2), slot)
    r = post(client, org.staff, "work-from-home", wfh)
    assert r.status_code == 201, r.text
    assert r.json()["data"]["days"] == 2 and len(r.json()["data"]["details"]["days"]) == 2
    assert post(client, org.staff, "work-from-home", wfh).status_code == 409


def test_shift_swap_asks_the_colleague_first(client, db, org):
    slot = fr.time_slot(db, org.company_id)
    late_slot = fr.time_slot(db, org.company_id, time(13, 0), time(21, 0))
    fr.schedule(db, org.company_id, org.staff.employee_id, DAY, slot)
    fr.schedule(db, org.company_id, org.staff2.employee_id, DAY, late_slot, time(13, 0), time(21, 0))
    same = post(client, org.staff, "shift-swap", {"details": {"shiftDate": str(DAY), "timeSlotId": slot}})
    assert same.status_code == 422
    r = post(client, org.staff, "shift-swap", {"details": {"shiftDate": str(DAY), "withEmployeeId": org.staff2.employee_id}})
    assert r.status_code == 201, r.text
    req = r.json()["data"]
    assert req["nextApproverName"].startswith("Saad") and req["steps"][-1]["isConsent"] is True
    r = client.post(f"/api/requests/approvals/{req['id']}/consent",
                    json={"agree": True, "rowVersion": req["rowVersion"]}, headers=org.staff2.headers)
    assert r.status_code == 200, r.text
    assert r.json()["data"]["nextApproverName"].startswith("Mansoor")


def test_promotion_transfer_and_resignation(client, db, org):
    def ref(table):
        return fr._scalar(db, f"SET NOCOUNT ON; INSERT org.{table} (company_id, name) OUTPUT INSERTED.id VALUES (?, ?)",
                          org.company_id, f"{table} {factories.tag()}")

    h = org.hr["headers"]
    fr.execute(db, "INSERT hr.employee_salary (employee_id, effective_date, amount) VALUES (?, '2025-01-01', 80000)",
               org.staff.employee_id)
    promo = {"employeeId": org.staff.employee_id, "details": {
        "gradeId": ref("grade"), "designationId": ref("designation"), "jobTitleId": ref("job_title"),
        "newSalary": 70000, "effectiveDate": str(DAY)}}
    lower = client.post("/api/requests/promotion", json=promo, headers=h)
    assert lower.status_code == 422 and "newSalary" in lower.json()["fieldErrors"]
    r = client.post("/api/requests/promotion", json={**promo, "details": {**promo["details"], "newSalary": 95000}},
                    headers=h)
    assert r.status_code == 201, r.text
    assert r.json()["data"]["details"]["previousSalary"] == 80000
    again = client.post("/api/requests/promotion", json={**promo, "details": {**promo["details"], "newSalary": 96000}},
                        headers=h)
    assert again.status_code == 409

    other_branch = factories.branch(db, org.company_id)
    transfer = {"employeeId": org.staff2.employee_id, "details": {
        "locationId": org.location_id, "branchId": other_branch, "departmentId": org.department_id,
        "lineManagerId": org.other_manager.employee_id, "finalAuthorityId": org.other_manager.employee_id,
        "effectiveDate": str(DAY)}}
    r = client.post("/api/requests/transfer", json=transfer, headers=h)
    assert r.status_code == 422 and "branchId" in r.json()["fieldErrors"]  # branch is in another location
    r = client.post("/api/requests/transfer", json={**transfer, "details": {**transfer["details"], "branchId": org.branch_id}},
                    headers=h)
    assert r.status_code == 201, r.text
    # The final authority chosen on the form decides the final step.
    assert r.json()["data"]["finalAuthorityName"].startswith("Omar")

    res = post(client, org.other, "resignation", {"reason": "Moving abroad",
                                                   "details": {"resignationType": "voluntary",
                                                               "resignationDate": str(DAY)}})
    assert res.status_code == 201, res.text
    req = res.json()["data"]
    req = client.post(f"/api/requests/approvals/{req['id']}/approve", json={"rowVersion": req["rowVersion"]},
                      headers=org.other_manager.headers).json()["data"]
    final = client.post(f"/api/requests/approvals/{req['id']}/approve", json={"rowVersion": req["rowVersion"]},
                        headers=org.fa.headers)
    assert final.status_code == 422 and "lastWorkingDate" in final.json()["fieldErrors"]


def test_shift_change_must_change_something(client, db, org):
    slot = fr.time_slot(db, org.company_id)
    twin = fr.time_slot(db, org.company_id)          # another slot with the same hours, 09:00-17:00
    fr.schedule(db, org.company_id, org.staff.employee_id, DAY, slot)
    fr.schedule(db, org.company_id, org.staff2.employee_id, DAY, slot)
    same = post(client, org.staff, "shift-swap", {"details": {"shiftDate": str(DAY), "timeSlotId": slot}})
    assert same.status_code == 422 and "timeSlotId" in same.json()["fieldErrors"]
    same_hours = post(client, org.staff, "shift-swap", {"details": {"shiftDate": str(DAY), "timeSlotId": twin}})
    assert same_hours.status_code == 422 and same_hours.json()["code"] == "SHIFT_UNCHANGED"
    assert "timeSlotId" in same_hours.json()["fieldErrors"]
    swap = post(client, org.staff, "shift-swap", {"details": {"shiftDate": str(DAY),
                                                              "withEmployeeId": org.staff2.employee_id}})
    assert swap.status_code == 422 and "withEmployeeId" in swap.json()["fieldErrors"]


def _wfh_flags(db, employee_id, days):
    return [fr._scalar(db, "SELECT CAST(is_wfh AS INT) FROM sch.schedule WHERE employee_id = ? AND work_date = ?",
                       employee_id, d) for d in days]


def test_work_from_home_keeps_its_dates_and_marks_the_shifts(client, db, org):
    """From / To stay as entered; the ticked shift days are the request's days; approval marks those
    shifts work from home and the cancellation puts them back."""
    slot = fr.time_slot(db, org.company_id)
    start = DAY + timedelta(days=60)
    days = [start, start + timedelta(days=2), start + timedelta(days=4)]
    for d in days:
        fr.schedule(db, org.company_id, org.staff.employee_id, d, slot)
    body = {"fromDate": str(start), "toDate": str(start + timedelta(days=4)), "reason": "Renovation",
            "details": {"dates": [str(days[0]), str(days[2])]}}
    outside = post(client, org.staff, "work-from-home",
                   {**body, "details": {"dates": [str(start + timedelta(days=9))]}})
    assert outside.status_code == 422 and "dates" in outside.json()["fieldErrors"]
    r = post(client, org.staff, "work-from-home", body)
    assert r.status_code == 201, r.text
    req = r.json()["data"]
    assert req["fromDate"] == str(start) and req["toDate"] == str(start + timedelta(days=4)) and req["days"] == 2
    assert [d["requestDate"] for d in req["details"]["days"]] == [str(days[0]), str(days[2])]

    for who in (org.manager, org.fa):
        req = client.post(f"/api/requests/approvals/{req['id']}/approve", json={"rowVersion": req["rowVersion"]},
                          headers=who.headers).json()["data"]
    assert req["status"] == "approved"
    assert _wfh_flags(db, org.staff.employee_id, days) == [1, 0, 1]

    req = client.post(f"/api/requests/work-from-home/{req['id']}/cancel",
                      json={"reason": "Back at the office", "rowVersion": req["rowVersion"]},
                      headers=org.staff.headers).json()["data"]
    for who in (org.manager, org.fa):
        req = client.post(f"/api/requests/approvals/{req['id']}/approve", json={"rowVersion": req["rowVersion"]},
                          headers=who.headers).json()["data"]
    assert req["status"] == "cancelled"
    assert _wfh_flags(db, org.staff.employee_id, days) == [0, 0, 0]


def _half_short_policy(db, company_id, half: int, short: int) -> None:
    fr.execute(db, "UPDATE lv.leave_policy SET is_active = 0 WHERE company_id = ? AND policy_kind = N'half_short'",
               company_id)
    fr.execute(db, "INSERT lv.leave_policy (company_id, title, policy_kind, policy_level, allow_half_day, "
                   "allow_short_leave, is_active) VALUES (?, ?, N'half_short', N'company', ?, ?, 1)",
               company_id, f"Half and short {factories.tag()}", half, short)


def test_half_day_and_short_leave_follow_the_policy(client, db, org):
    lt = fr.leave_type(db, org.company_id, is_short_leave=1, is_deductible=0)

    def short(day_offset, kind):
        return post(client, org.staff, "leave", {
            "fromDate": str(DAY + timedelta(days=day_offset)), "reason": "Errand",
            "details": {"leaveTypeId": lt, "isShort": True, "shortLeaveType": kind,
                        "startTime": "09:00", "endTime": "11:00"}})

    _half_short_policy(db, org.company_id, half=0, short=1)
    half = short(1, "half_day")
    assert half.status_code == 422 and half.json()["code"] == "HALF_DAY_NOT_ALLOWED"
    assert "shortLeaveType" in half.json()["fieldErrors"]
    assert short(2, "quarter_day").status_code == 201

    _half_short_policy(db, org.company_id, half=1, short=0)
    quarter = short(3, "quarter_day")
    assert quarter.status_code == 422 and quarter.json()["code"] == "SHORT_LEAVE_NOT_ALLOWED"
    assert short(4, "half_day").status_code == 201


def test_leave_type_options_for_the_apply_form(client, db, org):
    """Staff read the leave types they may apply for, with balance and rules, without the leave settings
    permission; another person's list needs the leave create permission to reach them."""
    lt = fr.leave_type(db, org.company_id, is_short_leave=1, attachment_required=1)
    fr.allot_leave(db, org.staff.employee_id, lt, 5)
    _half_short_policy(db, org.company_id, half=1, short=0)
    off = fr.leave_type(db, org.company_id, is_active=0)
    assert client.get("/api/leaves/types", headers=org.staff.headers).status_code == 403

    r = client.get("/api/requests/options/leave-types", params={"asOf": "2026-06-01"}, headers=org.staff.headers)
    assert r.status_code == 200, r.text
    rows = {x["id"]: x for x in r.json()["data"]}
    assert str(off) not in rows
    mine = rows[str(lt)]
    assert mine["available"] == 5 and mine["entitled"] == 5 and mine["isDeductible"] is True
    assert mine["allowHalfDay"] is True and mine["allowShortLeave"] is False
    assert mine["attachmentRequired"] is True and mine["attachmentRule"] == "refuse"

    assert client.get("/api/requests/options/leave-types", params={"employeeId": org.other.employee_id},
                      headers=org.staff.headers).status_code == 404
    hr = client.get("/api/requests/options/leave-types",
                    params={"employeeId": org.staff.employee_id, "asOf": "2026-06-01"}, headers=org.hr["headers"])
    assert hr.status_code == 200 and str(lt) in [x["id"] for x in hr.json()["data"]]
