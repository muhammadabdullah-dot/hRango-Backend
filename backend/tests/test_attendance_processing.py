"""Time-sheet processing (att.usp_timesheet_process) and the approval effects the requests engine calls."""
from datetime import date, datetime, timedelta

import pytest

from app.core.errors import AppError
from tests import factories
from tests import factories_attendance as fa
from tests import factories_events as fe

MON = date(2025, 3, 3)  # a Monday well in the past


def at(d: date, hhmm: str) -> datetime:
    return datetime.combine(d, datetime.strptime(hhmm, "%H:%M").time())


@pytest.fixture(scope="module")
def co(db) -> int:
    """A company of its own, so the settings below hold for every test in this file."""
    company_id = factories.company(db)
    fa.setting(db, company_id, "attendance", "late_grace_minutes", "10")
    fa.setting(db, company_id, "overtime", "overtime_on_check_out", "true")
    return company_id


def worked_day(db, co, emp, d, cin="09:00", cout="17:00", start="09:00", end="17:00"):
    fa.shift(db, co, emp, d, start, end)
    if cin:
        fa.punch(db, co, emp, at(d, cin), "check_in")
    if cout:
        fa.punch(db, co, emp, at(d, cout), "check_out")
    fa.process(db, co, emp, d)
    return fa.day(db, emp, d)


def test_on_time(db, co):
    emp = factories.employee(db, co)
    d = worked_day(db, co, emp, MON)
    assert d["day_status"] == "present"
    assert (d["late_minutes"], d["early_left_minutes"], d["worked_minutes"], d["expected_minutes"]) == (0, 0, 480, 480)
    assert d["first_in"] == at(MON, "09:00") and d["last_out"] == at(MON, "17:00")
    assert d["flags"] == {}


def test_late_within_and_beyond_grace(db, co):
    emp = factories.employee(db, co)
    d = worked_day(db, co, emp, MON, cin="09:07")
    assert d["day_status"] == "present" and d["late_minutes"] == 0 and d["grace_consumed_minutes"] == 7
    assert d["flags"] == {"grace": 7}

    d = worked_day(db, co, emp, MON + timedelta(days=1), cin="09:25")
    assert d["late_minutes"] == 25 and d["grace_consumed_minutes"] == 0 and d["flags"] == {"late": 25}
    assert d["shift_worked_minutes"] == 455


def test_early_leave_and_overtime(db, co):
    emp = factories.employee(db, co)
    d = worked_day(db, co, emp, MON, cout="16:30")
    assert d["early_left_minutes"] == 30 and d["flags"] == {"early": 30}

    d = worked_day(db, co, emp, MON + timedelta(days=1), cin="08:30", cout="18:15")
    # Overtime counts on check-out only (overtime_on_check_in is off); no approval needed, so it is approved.
    assert d["overtime_before_minutes"] == 0 and d["overtime_after_minutes"] == 75
    assert d["approved_overtime_minutes"] == 75 and d["flags"] == {"overtime": 75}
    assert d["shift_worked_minutes"] == 480 and d["worked_minutes"] == 585


def test_absent_missing_punch_and_no_shift(db, co):
    emp = factories.employee(db, co)
    assert worked_day(db, co, emp, MON, cin=None, cout=None)["day_status"] == "absent"

    d = worked_day(db, co, emp, MON + timedelta(days=1), cout=None)
    assert d["day_status"] == "present" and "missing_punch" in d["flags"] and d["worked_minutes"] is None

    sunday = MON + timedelta(days=6)
    fa.process(db, co, emp, sunday)
    assert fa.day(db, emp, sunday)["day_status"] == "weekend"


def test_holiday_rest_day_and_holiday_rules(db):
    co = factories.company(db)  # holidays are company-wide: keep them away from the other tests
    emp, other = factories.employee(db, co), factories.employee(db, co)
    d1, d2, d3 = MON, MON + timedelta(days=1), MON + timedelta(days=2)
    fa.holiday(db, co, d1)
    fa.holiday(db, co, d3, employee_id=other)  # applies to the other employee only
    fa.holiday(db, co, d2, exempt=False)       # listed, still worked
    for d in (d1, d2, d3):
        fa.shift(db, co, emp, d)
    fa.rest_day(db, co, emp, d2)
    fa.process(db, co, emp, d1, d3)
    assert fa.day(db, emp, d1)["day_status"] == "holiday"
    assert fa.day(db, emp, d2)["day_status"] == "rest_day"
    assert fa.day(db, emp, d3)["day_status"] == "absent"


def test_overnight_shift(db, co):
    emp = factories.employee(db, co)
    d1, d2 = MON, MON + timedelta(days=1)
    fa.shift(db, co, emp, d1, "22:00", "06:00")
    fa.shift(db, co, emp, d2, "22:00", "06:00")
    fa.punch(db, co, emp, at(d1, "21:55"), "check_in")
    fa.punch(db, co, emp, at(d2, "06:05"), "check_out")
    fa.punch(db, co, emp, at(d2, "22:20"), "check_in")
    fa.punch(db, co, emp, at(d2 + timedelta(days=1), "06:00"), "check_out")
    fa.process(db, co, emp, d1, d2)

    first, second = fa.day(db, emp, d1), fa.day(db, emp, d2)
    assert first["first_in"] == at(d1, "21:55") and first["last_out"] == at(d2, "06:05")
    assert first["worked_minutes"] == 490 and first["late_minutes"] == 0 and first["day_status"] == "present"
    assert second["first_in"] == at(d2, "22:20") and second["late_minutes"] == 20
    assert second["expected_out"] == at(d2 + timedelta(days=1), "06:00")


def test_breaks_from_punches(db, co):
    emp = factories.employee(db, co)
    lunch = fa.break_type(db, co)
    fa.shift(db, co, emp, MON)
    fa.punch(db, co, emp, at(MON, "09:00"), "check_in")
    fa.punch(db, co, emp, at(MON, "13:00"), "break_out", break_type_id=lunch)
    fa.punch(db, co, emp, at(MON, "13:45"), "break_in", break_type_id=lunch)
    fa.punch(db, co, emp, at(MON, "17:00"), "check_out")
    fa.process(db, co, emp, MON)
    d = fa.day(db, emp, MON)
    assert d["break_minutes"] == 45 and d["worked_minutes"] == 435


def test_leave_full_half_and_wfh(db, co):
    emp = factories.employee(db, co)
    d1, d2, d3 = MON, MON + timedelta(days=1), MON + timedelta(days=2)
    for d in (d1, d2, d3):
        fa.shift(db, co, emp, d)
    full = fa.leave_request(db, co, emp, d1)
    fa.leave_request(db, co, emp, d2, days=0.5, start="09:00", end="13:00")
    fa.punch(db, co, emp, at(d2, "13:05"), "check_in")
    fa.punch(db, co, emp, at(d2, "17:00"), "check_out")
    fa.request(db, co, emp, "work_from_home", d3)
    fa.leave_request(db, co, emp, d3 + timedelta(days=1), status="pending")  # not approved: no effect
    fa.process(db, co, emp, d1, d3 + timedelta(days=1))

    assert fa.day(db, emp, d1)["day_status"] == "leave" and fa.day(db, emp, d1)["leave_request_id"] == full
    half = fa.day(db, emp, d2)
    assert half["day_status"] == "half_day" and half["expected_in"] == at(d2, "13:00")
    assert half["late_minutes"] == 0 and half["flags"] == {"half_leave": None, "grace": 5}
    assert fa.day(db, emp, d3)["day_status"] == "wfh"
    assert fa.day(db, emp, d3 + timedelta(days=1))["day_status"] == "weekend"  # no shift that day


def test_sandwich(db, co):
    emp = factories.employee(db, co)
    fri, mon = MON + timedelta(days=4), MON + timedelta(days=7)
    lt = fa.leave_type(db, co, is_sandwich=True)
    fa.shift(db, co, emp, fri)
    fa.shift(db, co, emp, mon)
    fa.leave_request(db, co, emp, fri, leave_type_id=lt)
    fa.leave_request(db, co, emp, mon, leave_type_id=lt)
    fa.process(db, co, emp, fri, mon)
    assert [fa.day(db, emp, fri + timedelta(days=i))["day_status"] for i in range(4)] == \
        ["leave", "sandwich", "sandwich", "leave"]


def test_manual_and_frozen_days_are_kept(db, co):
    emp = factories.employee(db, co)
    d = worked_day(db, co, emp, MON, cin="09:30")
    # Edit as HR would (through SQL here; the endpoint is tested in test_attendance.py).
    cur = db.conn.cursor()
    cur.execute("UPDATE att.timesheet_day SET first_in = ?, is_manually_updated = 1 WHERE id = ?", at(MON, "09:00"), d["id"])
    cur.close()
    fa.punch(db, co, emp, at(MON, "08:50"), "check_in")
    fa.process(db, co, emp, MON)
    kept = fa.day(db, emp, MON)
    assert kept["first_in"] == at(MON, "09:00") and kept["late_minutes"] == 0 and kept["is_manually_updated"]

    fa.process(db, co, emp, MON, overwrite_manual=True)
    redone = fa.day(db, emp, MON)
    assert redone["first_in"] == at(MON, "08:50") and not redone["is_manually_updated"]

    fa.freeze(db, emp, MON)
    fa.punch(db, co, emp, at(MON, "08:00"), "check_in")
    fa.process(db, co, emp, MON, overwrite_manual=True)
    assert fa.day(db, emp, MON)["first_in"] == at(MON, "08:50")


def test_short_day_threshold(db):
    company_id = factories.company(db)
    fa.setting(db, company_id, "attendance", "minimum_workable_minutes", "300")
    fa.setting(db, company_id, "attendance", "short_duration_on_non_flexible", "true")
    emp = factories.employee(db, company_id)
    d = worked_day(db, company_id, emp, MON, cout="13:00")
    assert d["day_status"] == "short_day" and d["worked_minutes"] == 240


# ---------------------------------------------------------------- approval effects

def test_punch_request_apply_and_revert(db, co):
    emp = factories.employee(db, co)
    d = worked_day(db, co, emp, MON, cout=None)
    assert "missing_punch" in d["flags"]
    rq = fa.punch_request(db, co, emp, at(MON, "17:10"), "check_out")
    db.call("att.usp_request_apply_punch", company_id=co, actor_user_id=None, request_id=rq)
    d = fa.day(db, emp, MON)
    assert d["last_out"] == at(MON, "17:10") and "missing_punch" not in d["flags"]

    db.call("att.usp_request_revert_punch", company_id=co, actor_user_id=None, request_id=rq)
    assert fa.day(db, emp, MON)["last_out"] is None

    bad = fa.punch_request(db, co, emp, at(MON, "17:10"), "lunch")
    with pytest.raises(AppError) as e:
        db.call("att.usp_request_apply_punch", company_id=co, actor_user_id=None, request_id=bad)
    assert e.value.status == 422


def test_relaxation_and_official_visit(db, co):
    emp = factories.employee(db, co)
    d = worked_day(db, co, emp, MON, cin="09:40")
    assert d["late_minutes"] == 40
    rq = fa.time_window_request(db, co, emp, "relaxation", MON, "09:00", "10:00")
    db.call("att.usp_request_apply_time_window", company_id=co, actor_user_id=None, request_id=rq)
    d = fa.day(db, emp, MON)
    assert d["late_minutes"] == 0 and d["flags"] == {"relaxation": 40}

    tue = MON + timedelta(days=1)
    fa.shift(db, co, emp, tue)
    ov = fa.time_window_request(db, co, emp, "official_visit", tue, "09:00", "17:00")
    db.call("att.usp_request_apply_time_window", company_id=co, actor_user_id=None, request_id=ov)
    d = fa.day(db, emp, tue)
    assert d["day_status"] == "official_visit" and d["worked_minutes"] == 480
    db.call("att.usp_request_revert_time_window", company_id=co, actor_user_id=None, request_id=ov)
    assert fa.day(db, emp, tue)["day_status"] == "absent"


def test_overtime_request_when_approval_required(db):
    company_id = factories.company(db)
    fa.setting(db, company_id, "overtime", "overtime_on_check_out", "true")
    fa.setting(db, company_id, "overtime", "overtime_approval_required", "true")
    emp = factories.employee(db, company_id)
    d = worked_day(db, company_id, emp, MON, cout="19:00")
    assert d["overtime_after_minutes"] == 120 and d["approved_overtime_minutes"] == 0
    rq = fa.overtime_request(db, company_id, emp, MON, applied=120, approved=90)
    db.call("att.usp_request_apply_overtime", company_id=company_id, actor_user_id=None, request_id=rq)
    assert fa.day(db, emp, MON)["approved_overtime_minutes"] == 90
    fa.set_status(db, rq, "cancelling")
    db.call("att.usp_request_revert_overtime", company_id=company_id, actor_user_id=None, request_id=rq)
    assert fa.day(db, emp, MON)["approved_overtime_minutes"] == 0


def test_work_from_home_request_and_frozen_refusal(db, co):
    emp = factories.employee(db, co)
    fa.shift(db, co, emp, MON)
    fa.shift(db, co, emp, MON + timedelta(days=1))
    rq = fa.request(db, co, emp, "work_from_home", MON, MON + timedelta(days=1), status="pending")
    db.call("att.usp_request_apply_work_from_home", company_id=co, actor_user_id=None, request_id=rq)
    assert fa.day(db, emp, MON)["day_status"] == "wfh" and fa.day(db, emp, MON + timedelta(days=1))["day_status"] == "wfh"

    fa.freeze(db, emp, MON)
    with pytest.raises(AppError) as e:
        db.call("att.usp_request_revert_work_from_home", company_id=co, actor_user_id=None, request_id=rq)
    assert e.value.status == 409 and e.value.code == "ATTENDANCE_FROZEN"
    # Approval marked the planned shifts work from home; the refused revert left them so.
    flags = db.conn.cursor().execute("SELECT CAST(is_wfh AS INT) FROM sch.schedule WHERE employee_id = ? "
                                     "ORDER BY work_date", emp).fetchall()
    assert [r[0] for r in flags] == [1, 1]


def test_warnings_raised_after_processing(db):
    """Processing hands the new minutes to att.usp_warning_raise (warning module) when a policy is active."""
    company_id = factories.company(db)
    policy = factories._scalar(db, "SET NOCOUNT ON; INSERT att.warning_policy (company_id, title, applies_to, period, "
                                   "grace_minutes, is_active) OUTPUT INSERTED.id VALUES (?, ?, N'late_arrival', "
                                   "N'month', 0, 1)", company_id, f"Late {factories.tag()}")
    cur = db.conn.cursor()
    cur.execute("INSERT att.warning_policy_rule (warning_policy_id, clock_event, minutes, occurrence_count) "
                "VALUES (?, N'clock_in', 0, 1)", policy)
    cur.close()
    emp = factories.employee(db, company_id)
    factories.user(db, company_id, employee_id=emp, role_codes="employee")
    d = worked_day(db, company_id, emp, MON, cin="09:20")
    assert d["late_minutes"] == 20
    assert factories._scalar(db, "SELECT COUNT(*) FROM att.warning WHERE timesheet_day_id = ?", d["id"]) == 1
    assert len(fe.events(db, company_id, "warning.issued", emp)) == 1
    fa.process(db, company_id, emp, MON)  # nothing changed: nothing new is issued
    assert len(fe.events(db, company_id, "warning.issued", emp)) == 1
    assert len(fe.notifications(db, company_id, emp, "hr.employee", emp)) == 1
    fa.punch(db, company_id, emp, at(MON, "08:55"), "check_in")
    fa.process(db, company_id, emp, MON)
    assert factories._scalar(db, "SELECT COUNT(*) FROM att.warning WHERE timesheet_day_id = ?", d["id"]) == 0
