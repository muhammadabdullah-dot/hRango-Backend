"""Attendance test set-up with plain SQL: shifts, rest days, holidays, punches, settings and approved
requests. These tables belong to other modules (sch, req, lv); tests write them directly so attendance
tests do not depend on those modules' endpoints."""
from datetime import date, datetime, time, timedelta

from app.core.db import Db
from tests import factories
from tests.factories import tag


def _scalar(db: Db, sql: str, *params):
    cur = db.conn.cursor()
    try:
        return cur.execute(sql, *params).fetchval()
    finally:
        cur.close()


def _exec(db: Db, sql: str, *params) -> None:
    cur = db.conn.cursor()
    try:
        cur.execute(sql, *params)
    finally:
        cur.close()


def time_slot(db: Db, company_id: int, start: str = "09:00", end: str = "17:00", workable_minutes: int | None = None,
              is_flexible: bool = False) -> int:
    s, e = time.fromisoformat(start), time.fromisoformat(end)
    span = (datetime.combine(date.min, e) - datetime.combine(date.min, s)).seconds // 60
    return _scalar(db, "SET NOCOUNT ON; INSERT sch.time_slot (company_id, code, name, start_time, end_time, "
                       "duration_minutes, workable_minutes, is_flexible, is_overnight) OUTPUT INSERTED.id "
                       "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                   company_id, f"TS-{tag()}", f"Slot {tag()}", s, e, span,
                   workable_minutes if workable_minutes is not None else span, is_flexible, e <= s)


def shift(db: Db, company_id: int, employee_id: int, work_date: date, start: str = "09:00", end: str = "17:00",
          slot_id: int | None = None, planned_minutes: int | None = None, is_flexible: bool = False,
          geo_fence_id: int | None = None, is_wfh: bool = False) -> int:
    """One planned shift. An end at or before the start ends the next day."""
    slot_id = slot_id or time_slot(db, company_id, start, end, planned_minutes, is_flexible)
    start_at = datetime.combine(work_date, time.fromisoformat(start))
    end_at = datetime.combine(work_date, time.fromisoformat(end))
    if end_at <= start_at:
        end_at += timedelta(days=1)
    planned = planned_minutes if planned_minutes is not None else int((end_at - start_at).total_seconds() // 60)
    return _scalar(db, "SET NOCOUNT ON; INSERT sch.schedule (company_id, employee_id, work_date, start_at, end_at, "
                       "time_slot_id, geo_fence_id, is_wfh, planned_minutes) OUTPUT INSERTED.id "
                       "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                   company_id, employee_id, work_date, start_at, end_at, slot_id, geo_fence_id, is_wfh, planned)


def rest_day(db: Db, company_id: int, employee_id: int, rest_date: date) -> int:
    return _scalar(db, "SET NOCOUNT ON; INSERT sch.rest_day (company_id, employee_id, rest_date) OUTPUT INSERTED.id "
                       "VALUES (?, ?, ?)", company_id, employee_id, rest_date)


def holiday(db: Db, company_id: int, start: date, end: date | None = None, exempt: bool = True,
            employee_id: int | None = None) -> int:
    holiday_id = _scalar(db, "SET NOCOUNT ON; INSERT sch.holiday (company_id, name, holiday_type, start_date, end_date, "
                             "attendance_exempt) OUTPUT INSERTED.id VALUES (?, ?, N'public', ?, ?, ?)",
                         company_id, f"Holiday {tag()}", start, end or start, exempt)
    if employee_id:
        _exec(db, "INSERT sch.holiday_rule (holiday_id, rule_type, employee_id) VALUES (?, N'employee', ?)",
              holiday_id, employee_id)
    return holiday_id


def break_type(db: Db, company_id: int, name: str | None = None) -> int:
    name = name or f"Break {tag()}"
    return _scalar(db, "SET NOCOUNT ON; INSERT sch.break_type (company_id, name, start_identifier, end_identifier) "
                       "OUTPUT INSERTED.id VALUES (?, ?, ?, ?)", company_id, name, f"{name} Out", f"{name} In")


def punch(db: Db, company_id: int, employee_id: int, at: datetime, punch_type: str = "check_in",
          source: str = "biometric", break_type_id: int | None = None) -> int:
    return _scalar(db, "SET NOCOUNT ON; INSERT att.punch (company_id, employee_id, punched_at, punch_type, source, "
                       "break_type_id) OUTPUT INSERTED.id VALUES (?, ?, ?, ?, ?, ?)",
                   company_id, employee_id, at, punch_type, source, break_type_id)


def setting(db: Db, company_id: int, module: str, key: str, value: str) -> None:
    _exec(db, "MERGE core.company_setting AS t USING (SELECT ? AS company_id, ? AS module, ? AS setting_key) s "
              "ON t.company_id = s.company_id AND t.module = s.module AND t.setting_key = s.setting_key "
              "WHEN MATCHED THEN UPDATE SET setting_value = ? "
              "WHEN NOT MATCHED THEN INSERT (company_id, module, setting_key, setting_value) VALUES (?, ?, ?, ?);",
          company_id, module, key, value, company_id, module, key, value)


def process(db: Db, company_id: int, employee_id: int, from_date: date, to_date: date | None = None,
            overwrite_manual: bool = False) -> None:
    db.call("att.usp_timesheet_process", company_id=company_id, from_date=from_date, to_date=to_date or from_date,
            employee_ids=f"[{employee_id}]", overwrite_manual=overwrite_manual, quiet=True)


def day(db: Db, employee_id: int, work_date: date) -> dict | None:
    cur = db.conn.cursor()
    try:
        row = cur.execute("SELECT * FROM att.timesheet_day WHERE employee_id = ? AND work_date = ?",
                          employee_id, work_date).fetchone()
        if row is None:
            return None
        out = dict(zip([d[0] for d in cur.description], row))
        out["flags"] = {r.flag: r.minutes for r in cur.execute(
            "SELECT flag, minutes FROM att.timesheet_flag WHERE timesheet_day_id = ?", out["id"]).fetchall()}
        return out
    finally:
        cur.close()


def request_type_id(db: Db, code: str) -> int:
    found = _scalar(db, "SELECT id FROM req.request_type WHERE code = ?", code)
    if found:
        return found
    return _scalar(db, "SET NOCOUNT ON; INSERT req.request_type (code, name) OUTPUT INSERTED.id VALUES (?, ?)",
                   code, code)


def request(db: Db, company_id: int, employee_id: int, type_code: str, from_date: date, to_date: date | None = None,
            status: str = "approved") -> int:
    request_id = _scalar(db, "SET NOCOUNT ON; INSERT req.request (company_id, code, request_type_id, employee_id, "
                             "from_date, to_date, status) OUTPUT INSERTED.id VALUES (?, ?, ?, ?, ?, ?, ?)",
                         company_id, f"RQ-{tag()}", request_type_id(db, type_code), employee_id, from_date,
                         to_date or from_date, status)
    if type_code == "work_from_home":
        # The requests engine stores a WFH request's days (the ticked shift days) as request_day rows;
        # attendance reads those, not the whole from..to range. Here: every day of the range.
        day = from_date
        while day <= (to_date or from_date):
            _exec(db, "INSERT req.request_day (request_id, request_date) VALUES (?, ?)", request_id, day)
            day += timedelta(days=1)
    return request_id


def leave_type(db: Db, company_id: int, is_sandwich: bool = False) -> int:
    return _scalar(db, "SET NOCOUNT ON; INSERT lv.leave_type (company_id, title, short_code, is_sandwich, gender, "
                       "marital_status, tenure, balance_basis) OUTPUT INSERTED.id "
                       "VALUES (?, ?, ?, ?, N'any', N'any', N'yearly', N'flat')",
                   company_id, f"Leave {tag()}", tag()[:6].upper(), is_sandwich)


def leave_request(db: Db, company_id: int, employee_id: int, from_date: date, to_date: date | None = None,
                  leave_type_id: int | None = None, days: float | None = None, is_short: bool = False,
                  start: str | None = None, end: str | None = None, status: str = "approved") -> int:
    request_id = request(db, company_id, employee_id, "leave", from_date, to_date, status)
    _exec(db, "INSERT req.req_leave (request_id, leave_type_id, is_short, start_time, end_time, days) "
              "VALUES (?, ?, ?, ?, ?, ?)", request_id, leave_type_id or leave_type(db, company_id), is_short,
          time.fromisoformat(start) if start else None, time.fromisoformat(end) if end else None,
          days if days is not None else ((to_date or from_date) - from_date).days + 1)
    return request_id


def punch_request(db: Db, company_id: int, employee_id: int, at: datetime, punch_type: str = "check_out",
                  status: str = "pending") -> int:
    request_id = request(db, company_id, employee_id, "punch", at.date(), status=status)
    _exec(db, "INSERT req.req_punch (request_id, punch_date, punch_type, punch_time) VALUES (?, ?, ?, ?)",
          request_id, at.date(), punch_type, at.time())
    return request_id


def time_window_request(db: Db, company_id: int, employee_id: int, kind: str, window_date: date, start: str,
                        end: str, status: str = "pending") -> int:
    request_id = request(db, company_id, employee_id, kind, window_date, status=status)
    slot = _scalar(db, "SELECT TOP 1 time_slot_id FROM sch.schedule WHERE employee_id = ? AND work_date = ?",
                   employee_id, window_date) or time_slot(db, company_id)
    _exec(db, "INSERT req.req_time_window (request_id, kind, window_date, start_time, end_time, time_slot_id) "
              "VALUES (?, ?, ?, ?, ?, ?)", request_id, kind, window_date, time.fromisoformat(start),
          time.fromisoformat(end), slot)
    return request_id


def overtime_request(db: Db, company_id: int, employee_id: int, overtime_date: date, applied: int,
                     approved: int | None = None, status: str = "pending") -> int:
    request_id = request(db, company_id, employee_id, "overtime", overtime_date, status=status)
    dept = _scalar(db, "SELECT department_id FROM hr.employee WHERE id = ?", employee_id) or factories.department(
        db, company_id)
    branch, loc = _scalar(db, "SELECT branch_id FROM hr.employee WHERE id = ?", employee_id), None
    loc = _scalar(db, "SELECT location_id FROM org.branch WHERE id = ?", branch)
    _exec(db, "INSERT req.req_overtime (request_id, department_id, location_id, branch_id, overtime_date, start_time, "
              "end_time, applied_minutes, approved_minutes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", request_id, dept, loc,
          branch, overtime_date, time(17, 0), time(19, 0), applied, approved)
    return request_id


def set_status(db: Db, request_id: int, status: str) -> None:
    _exec(db, "UPDATE req.request SET status = ? WHERE id = ?", status, request_id)


def freeze(db: Db, employee_id: int, work_date: date) -> None:
    _exec(db, "UPDATE att.timesheet_day SET is_frozen = 1 WHERE employee_id = ? AND work_date = ?",
          employee_id, work_date)
