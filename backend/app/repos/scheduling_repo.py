"""Scheduling data access. The only layer that knows procedure names and parameters.
Child rows (breaks, rules, employee lists) go to the procedures as JSON."""
import json
from datetime import date, time
from typing import Any

from app.core.db import Db


def _t(value: time | None) -> str | None:
    return value.strftime("%H:%M:%S") if value is not None else None


def _breaks(breaks: list[dict[str, Any]] | None) -> str | None:
    if breaks is None:
        return None
    return json.dumps([{"break_type_id": b["break_type_id"], "start_time": _t(b["start_time"]),
                        "end_time": _t(b["end_time"]), "is_inclusive": bool(b["is_inclusive"])} for b in breaks])


def _ids(ids: list[int] | None) -> str | None:
    return json.dumps(ids) if ids is not None else None


# ---------------------------------------------------------------- time slots

def list_time_slots(db: Db, company_id: int, search: str | None, is_flexible: bool | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("sch.usp_time_slot_list", company_id=company_id, search=search,
                               is_flexible=is_flexible, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_time_slot(db: Db, company_id: int, slot_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    slot, breaks = db.call_sets("sch.usp_time_slot_get", company_id=company_id, id=slot_id)
    return slot[0], breaks


def save_time_slot(db: Db, company_id: int, actor_user_id: int, slot_id: int | None, name: str, color: str | None,
                   start_time: time, end_time: time, workable_minutes: int | None, is_flexible: bool,
                   full_overtime: bool, short_overtime: bool, breaks: list[dict[str, Any]],
                   row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    slot, rows = db.call_sets("sch.usp_time_slot_save", company_id=company_id, actor_user_id=actor_user_id,
                              id=slot_id, name=name, color=color, start_time=_t(start_time), end_time=_t(end_time),
                              workable_minutes=workable_minutes, is_flexible=is_flexible,
                              full_overtime=full_overtime, short_overtime=short_overtime, breaks=_breaks(breaks),
                              row_version=row_version)
    return slot[0], rows


def delete_time_slot(db: Db, company_id: int, actor_user_id: int, slot_id: int, row_version: bytes) -> None:
    db.call("sch.usp_time_slot_delete", company_id=company_id, actor_user_id=actor_user_id, id=slot_id,
            row_version=row_version)


# ---------------------------------------------------------------- break types

def list_break_types(db: Db, company_id: int, search: str | None, page: int,
                     page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("sch.usp_break_type_list", company_id=company_id, search=search, page=page,
                               page_size=page_size)
    return total[0]["total"], rows


def get_break_type(db: Db, company_id: int, type_id: int) -> dict[str, Any]:
    return db.call_one("sch.usp_break_type_get", company_id=company_id, id=type_id)


def save_break_type(db: Db, company_id: int, actor_user_id: int, type_id: int | None, name: str,
                    start_identifier: str, end_identifier: str, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("sch.usp_break_type_save", company_id=company_id, actor_user_id=actor_user_id, id=type_id,
                       name=name, start_identifier=start_identifier, end_identifier=end_identifier,
                       row_version=row_version)


def delete_break_type(db: Db, company_id: int, actor_user_id: int, type_id: int, row_version: bytes) -> None:
    db.call("sch.usp_break_type_delete", company_id=company_id, actor_user_id=actor_user_id, id=type_id,
            row_version=row_version)


# ---------------------------------------------------------------- rest-day rules

def list_rest_day_rules(db: Db, company_id: int, employee_id: int | None, from_date: date | None,
                        to_date: date | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("sch.usp_rest_day_rule_list", company_id=company_id, employee_id=employee_id,
                               from_date=from_date, to_date=to_date, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_rest_day_rule(db: Db, company_id: int, rule_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    rule, employees = db.call_sets("sch.usp_rest_day_rule_get", company_id=company_id, id=rule_id)
    return rule[0], employees


def save_rest_day_rule(db: Db, company_id: int, actor_user_id: int, rule_id: int | None, from_date: date,
                       to_date: date, weekdays: list[int], repeat_every_weeks: int, step: int, is_payable: bool,
                       employee_ids: list[int],
                       row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    rule, employees = db.call_sets("sch.usp_rest_day_rule_save", company_id=company_id,
                                   actor_user_id=actor_user_id, id=rule_id, from_date=from_date, to_date=to_date,
                                   weekdays=",".join(str(w) for w in weekdays),
                                   repeat_every_weeks=repeat_every_weeks, step=step, is_payable=is_payable,
                                   employee_ids=_ids(employee_ids), row_version=row_version)
    return rule[0], employees


def delete_rest_day_rule(db: Db, company_id: int, actor_user_id: int, rule_id: int, row_version: bytes) -> None:
    db.call("sch.usp_rest_day_rule_delete", company_id=company_id, actor_user_id=actor_user_id, id=rule_id,
            row_version=row_version)


# ---------------------------------------------------------------- holidays

def list_holidays(db: Db, company_id: int, year: int | None, search: str | None, holiday_type: str | None,
                  page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("sch.usp_holiday_list", company_id=company_id, year=year, search=search,
                               holiday_type=holiday_type, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_holiday(db: Db, company_id: int, holiday_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    holiday, rules = db.call_sets("sch.usp_holiday_get", company_id=company_id, id=holiday_id)
    return holiday[0], rules


def save_holiday(db: Db, company_id: int, actor_user_id: int, holiday_id: int | None, name: str,
                 holiday_type: str, start_date: date, end_date: date, description: str | None,
                 attendance_exempt: bool, rules: list[dict[str, Any]],
                 row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    holiday, rows = db.call_sets("sch.usp_holiday_save", company_id=company_id, actor_user_id=actor_user_id,
                                 id=holiday_id, name=name, holiday_type=holiday_type, start_date=start_date,
                                 end_date=end_date, description=description, attendance_exempt=attendance_exempt,
                                 rules=json.dumps(rules), row_version=row_version)
    return holiday[0], rows


def delete_holiday(db: Db, company_id: int, actor_user_id: int, holiday_id: int, row_version: bytes) -> None:
    db.call("sch.usp_holiday_delete", company_id=company_id, actor_user_id=actor_user_id, id=holiday_id,
            row_version=row_version)


# ---------------------------------------------------------------- schedules

def board(db: Db, company_id: int, actor_user_id: int, permission_code: str, tab: str, from_date: date,
          to_date: date, filters: dict[str, Any], page: int, page_size: int) -> list[list[dict[str, Any]]]:
    """Sets: total, employees, shifts, rest days, holidays, day totals."""
    return db.call_sets("sch.usp_schedule_board", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=permission_code, tab=tab, from_date=from_date, to_date=to_date,
                        page=page, page_size=page_size, **filters)


def year(db: Db, company_id: int, actor_user_id: int, permission_code: str, tab: str, year_no: int,
         filters: dict[str, Any], page: int, page_size: int) -> list[list[dict[str, Any]]]:
    """Sets: total, employees, months."""
    return db.call_sets("sch.usp_schedule_year", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=permission_code, tab=tab, year=year_no, page=page, page_size=page_size,
                        **filters)


def get_schedule(db: Db, company_id: int, actor_user_id: int, permission_code: str,
                 schedule_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    row, breaks = db.call_sets("sch.usp_schedule_get", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=permission_code, id=schedule_id)
    return row[0], breaks


def save_schedule(db: Db, company_id: int, actor_user_id: int, permission_code: str, schedule_id: int | None,
                  employee_id: int | None, work_date: date, time_slot_id: int, start_time: time | None,
                  end_time: time | None, geo_fence_id: int | None, is_wfh: bool,
                  breaks: list[dict[str, Any]] | None,
                  row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    row, rows = db.call_sets("sch.usp_schedule_save", company_id=company_id, actor_user_id=actor_user_id,
                             permission_code=permission_code, id=schedule_id, employee_id=employee_id,
                             work_date=work_date, time_slot_id=time_slot_id, start_time=_t(start_time),
                             end_time=_t(end_time), geo_fence_id=geo_fence_id, is_wfh=is_wfh,
                             breaks=_breaks(breaks), row_version=row_version)
    return row[0], rows


def delete_schedule(db: Db, company_id: int, actor_user_id: int, permission_code: str, schedule_id: int,
                    row_version: bytes) -> None:
    db.call("sch.usp_schedule_delete", company_id=company_id, actor_user_id=actor_user_id,
            permission_code=permission_code, id=schedule_id, row_version=row_version)


def create_batch(db: Db, company_id: int, actor_user_id: int, permission_code: str, batch_kind: str,
                 start_date: date, end_date: date, time_slot_id: int | None, roster_group_id: int | None,
                 weekdays: list[int], repeat_every_weeks: int, step: int, geo_fence_id: int | None, is_wfh: bool,
                 employee_ids: list[int], breaks: list[dict[str, Any]] | None,
                 replace_existing: bool) -> dict[str, Any]:
    return db.call_one("sch.usp_schedule_batch_create", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, batch_kind=batch_kind, start_date=start_date,
                       end_date=end_date, time_slot_id=time_slot_id, roster_group_id=roster_group_id,
                       weekdays=",".join(str(w) for w in weekdays) or None, repeat_every_weeks=repeat_every_weeks,
                       step=step, geo_fence_id=geo_fence_id, is_wfh=is_wfh, employee_ids=_ids(employee_ids),
                       breaks=_breaks(breaks), replace_existing=replace_existing)


def bulk_delete(db: Db, company_id: int, actor_user_id: int, permission_code: str, ids: list[int] | None,
                start_date: date | None, end_date: date | None, employee_ids: list[int], all_employees: bool,
                delete_rest_days: bool, delete_schedules: bool = True) -> dict[str, Any]:
    return db.call_one("sch.usp_schedule_bulk_delete", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, ids=_ids(ids), start_date=start_date, end_date=end_date,
                       employee_ids=_ids(employee_ids), all_employees=all_employees,
                       delete_rest_days=delete_rest_days, delete_schedules=delete_schedules)


def bulk_edit(db: Db, company_id: int, actor_user_id: int, permission_code: str, ids: list[int],
              time_slot_id: int | None, geo_fence_id: int | None, clear_geo_fence: bool,
              is_wfh: bool | None) -> dict[str, Any]:
    return db.call_one("sch.usp_schedule_bulk_edit", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, ids=_ids(ids), time_slot_id=time_slot_id,
                       geo_fence_id=geo_fence_id, clear_geo_fence=clear_geo_fence, is_wfh=is_wfh)


def swap(db: Db, company_id: int, actor_user_id: int, permission_code: str, schedule_id: int,
         with_schedule_id: int | None, with_employee_id: int | None, row_version: bytes | None) -> None:
    db.call("sch.usp_schedule_swap", company_id=company_id, actor_user_id=actor_user_id,
            permission_code=permission_code, schedule_id=schedule_id, with_schedule_id=with_schedule_id,
            with_employee_id=with_employee_id, row_version=row_version)
