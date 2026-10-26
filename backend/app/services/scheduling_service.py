"""Scheduling rules. Overlaps, rest days, multi-shift days and who the caller reaches are checked in
the procedures (they need the data); simple shape rules live here."""
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import invalid
from app.middlewares.auth import RequestContext
from app.repos import scheduling_repo

# Shifts are employee records; the procedures reach only the employees these permissions allow.
SCHEDULES_VIEW = "scheduling.schedules.view"
SCHEDULES_CREATE = "scheduling.schedules.create"
SCHEDULES_EDIT = "scheduling.schedules.edit"
SCHEDULES_DELETE = "scheduling.schedules.delete"
SCHEDULES_EXPORT = "scheduling.schedules.export"
REST_DAYS_DELETE = "scheduling.settings.rest_days.delete"

MAX_BOARD_DAYS = 93
TABS = ("my", "subordinates", "all")


def _range(from_date: date, to_date: date, max_days: int, to_field: str = "endDate") -> None:
    if to_date < from_date:
        raise invalid("The end date cannot be before the start date.", to_field)
    if (to_date - from_date).days > max_days:
        raise invalid(f"Pick at most {max_days + 1} days.", to_field)


def _weekdays(weekdays: list[int], field: str = "weekdays") -> list[int]:
    if any(w < 1 or w > 7 for w in weekdays):
        raise invalid("Weekdays are 1 (Monday) to 7 (Sunday).", field)
    return sorted(set(weekdays))


def _repeat(repeat_every_weeks: int, step: int) -> int:
    if repeat_every_weeks == 0:
        return 1
    if step > repeat_every_weeks:
        raise invalid("Step is between 1 and the number of weeks in the repeat.", "step")
    return step


# ---------------------------------------------------------------- time slots

def list_time_slots(db: Db, ctx: RequestContext, search: str | None, is_flexible: bool | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return scheduling_repo.list_time_slots(db, ctx.company_id, search, is_flexible, page, page_size)


def get_time_slot(db: Db, ctx: RequestContext, slot_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    return scheduling_repo.get_time_slot(db, ctx.company_id, slot_id)


def save_time_slot(db: Db, ctx: RequestContext, slot_id: int | None, body: Any,
                   row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if body.is_flexible and body.workable_minutes is None:
        raise invalid("Workable minutes are required for a flexible slot.", "workableMinutes")
    return scheduling_repo.save_time_slot(db, ctx.company_id, ctx.user_id, slot_id, body.name, body.color,
                                          body.start_time, body.end_time,
                                          body.workable_minutes if body.is_flexible else None, body.is_flexible,
                                          body.full_overtime, body.short_overtime,
                                          [b.model_dump(by_alias=False) for b in body.breaks], row_version)


def delete_time_slot(db: Db, ctx: RequestContext, slot_id: int, row_version: bytes) -> None:
    scheduling_repo.delete_time_slot(db, ctx.company_id, ctx.user_id, slot_id, row_version)


# ---------------------------------------------------------------- break types

def list_break_types(db: Db, ctx: RequestContext, search: str | None, page: int,
                     page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return scheduling_repo.list_break_types(db, ctx.company_id, search, page, page_size)


def get_break_type(db: Db, ctx: RequestContext, type_id: int) -> dict[str, Any]:
    return scheduling_repo.get_break_type(db, ctx.company_id, type_id)


def save_break_type(db: Db, ctx: RequestContext, type_id: int | None, name: str, start_identifier: str,
                    end_identifier: str, row_version: bytes | None) -> dict[str, Any]:
    if start_identifier.strip().lower() == end_identifier.strip().lower():
        raise invalid("The end identifier must differ from the start identifier.", "endIdentifier")
    return scheduling_repo.save_break_type(db, ctx.company_id, ctx.user_id, type_id, name, start_identifier,
                                           end_identifier, row_version)


def delete_break_type(db: Db, ctx: RequestContext, type_id: int, row_version: bytes) -> None:
    scheduling_repo.delete_break_type(db, ctx.company_id, ctx.user_id, type_id, row_version)


# ---------------------------------------------------------------- rest-day rules

def list_rest_day_rules(db: Db, ctx: RequestContext, employee_id: int | None, from_date: date | None,
                        to_date: date | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return scheduling_repo.list_rest_day_rules(db, ctx.company_id, employee_id, from_date, to_date, page, page_size)


def get_rest_day_rule(db: Db, ctx: RequestContext, rule_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    return scheduling_repo.get_rest_day_rule(db, ctx.company_id, rule_id)


def save_rest_day_rule(db: Db, ctx: RequestContext, rule_id: int | None, body: Any,
                       row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    _range(body.from_date, body.to_date, 366, "toDate")
    step = _repeat(body.repeat_every_weeks, body.step)
    return scheduling_repo.save_rest_day_rule(db, ctx.company_id, ctx.user_id, rule_id, body.from_date, body.to_date,
                                              _weekdays(body.weekdays), body.repeat_every_weeks, step,
                                              body.is_payable, sorted(set(body.employee_ids)), row_version)


def delete_rest_day_rule(db: Db, ctx: RequestContext, rule_id: int, row_version: bytes) -> None:
    scheduling_repo.delete_rest_day_rule(db, ctx.company_id, ctx.user_id, rule_id, row_version)


def delete_rest_day_range(db: Db, ctx: RequestContext, body: Any) -> dict[str, Any]:
    """Rest Days tab, Delete for a date range: rest days only, whatever rule or request made them."""
    _range(body.start_date, body.end_date, 366)
    if not body.all_employees and not body.employee_ids:
        raise invalid("Select at least one employee, or all employees.", "employeeIds")
    return scheduling_repo.bulk_delete(db, ctx.company_id, ctx.user_id, REST_DAYS_DELETE, None, body.start_date,
                                       body.end_date, body.employee_ids, body.all_employees, True,
                                       delete_schedules=False)


# ---------------------------------------------------------------- holidays

def list_holidays(db: Db, ctx: RequestContext, year: int | None, search: str | None, holiday_type: str | None,
                  page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return scheduling_repo.list_holidays(db, ctx.company_id, year, search, holiday_type, page, page_size)


def get_holiday(db: Db, ctx: RequestContext, holiday_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    return scheduling_repo.get_holiday(db, ctx.company_id, holiday_id)


_RULE_FIELDS = {"employee": ("employee_id",), "org_structure": ("location_id", "branch_id"),
                "geo_location": ("country_id", "state_id", "city_id"), "religion": ("religion",)}


def save_holiday(db: Db, ctx: RequestContext, holiday_id: int | None, body: Any,
                 row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    _range(body.start_date, body.end_date, 366)
    rules = []
    for i, rule in enumerate(body.rules):
        needed = _RULE_FIELDS[rule.rule_type]
        values = rule.model_dump(by_alias=False)
        if any(values[f] in (None, "") for f in needed):
            raise invalid(f"Rule {i + 1} needs {', '.join(needed)}.", f"rules[{i}]")
        rules.append({"rule_type": rule.rule_type, **{f: values[f] for f in needed}})
    return scheduling_repo.save_holiday(db, ctx.company_id, ctx.user_id, holiday_id, body.name, body.holiday_type,
                                        body.start_date, body.end_date, body.description, body.attendance_exempt,
                                        rules, row_version)


def delete_holiday(db: Db, ctx: RequestContext, holiday_id: int, row_version: bytes) -> None:
    scheduling_repo.delete_holiday(db, ctx.company_id, ctx.user_id, holiday_id, row_version)


# ---------------------------------------------------------------- schedules

def board(db: Db, ctx: RequestContext, tab: str, from_date: date, to_date: date, filters: dict[str, Any],
          page: int, page_size: int) -> list[list[dict[str, Any]]]:
    if tab not in TABS:
        raise invalid("Tab is my, subordinates or all.", "tab")
    _range(from_date, to_date, MAX_BOARD_DAYS - 1, "to")
    return scheduling_repo.board(db, ctx.company_id, ctx.user_id, SCHEDULES_VIEW, tab, from_date, to_date, filters,
                                 page, page_size)


def export(db: Db, ctx: RequestContext, tab: str, from_date: date, to_date: date,
           filters: dict[str, Any]) -> list[list[dict[str, Any]]]:
    """Every matching employee (up to 5,000) and their shifts, for the CSV export."""
    if tab not in TABS:
        raise invalid("Tab is my, subordinates or all.", "tab")
    _range(from_date, to_date, MAX_BOARD_DAYS - 1, "to")
    return scheduling_repo.board(db, ctx.company_id, ctx.user_id, SCHEDULES_EXPORT, tab, from_date, to_date,
                                 filters, 1, 5000)


def year(db: Db, ctx: RequestContext, tab: str, year_no: int, filters: dict[str, Any], page: int,
         page_size: int) -> list[list[dict[str, Any]]]:
    if tab not in TABS:
        raise invalid("Tab is my, subordinates or all.", "tab")
    if year_no < 2000 or year_no > 2100:
        raise invalid("Year is not valid.", "year")
    return scheduling_repo.year(db, ctx.company_id, ctx.user_id, SCHEDULES_VIEW, tab, year_no, filters, page,
                                page_size)


def get_schedule(db: Db, ctx: RequestContext, schedule_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    return scheduling_repo.get_schedule(db, ctx.company_id, ctx.user_id, SCHEDULES_VIEW, schedule_id)


def save_schedule(db: Db, ctx: RequestContext, schedule_id: int | None, body: Any,
                  row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if schedule_id is None and body.employee_id is None:
        raise invalid("Pick the employee.", "employeeId")
    if (body.start_time is None) != (body.end_time is None):
        raise invalid("Give both the start and the end time, or neither.", "endTime")
    breaks = None if body.breaks is None else [b.model_dump(by_alias=False) for b in body.breaks]
    code = SCHEDULES_CREATE if schedule_id is None else SCHEDULES_EDIT
    return scheduling_repo.save_schedule(db, ctx.company_id, ctx.user_id, code, schedule_id, body.employee_id,
                                         body.work_date, body.time_slot_id, body.start_time, body.end_time,
                                         body.geo_fence_id, body.is_wfh, breaks, row_version)


def delete_schedule(db: Db, ctx: RequestContext, schedule_id: int, row_version: bytes) -> None:
    scheduling_repo.delete_schedule(db, ctx.company_id, ctx.user_id, SCHEDULES_DELETE, schedule_id, row_version)


def create_batch(db: Db, ctx: RequestContext, body: Any) -> dict[str, Any]:
    _range(body.start_date, body.end_date, 366)
    if (body.time_slot_id is None) == (body.roster_group_id is None):
        raise invalid("Pick either a time slot or a roster group.", "timeSlotId")
    if not body.employee_ids and body.roster_group_id is None:
        raise invalid("Select at least one employee.", "employeeIds")
    step = _repeat(body.repeat_every_weeks, body.step)
    breaks = None if body.breaks is None else [b.model_dump(by_alias=False) for b in body.breaks]
    return scheduling_repo.create_batch(db, ctx.company_id, ctx.user_id, SCHEDULES_CREATE, "create", body.start_date,
                                        body.end_date, body.time_slot_id, body.roster_group_id,
                                        _weekdays(body.weekdays), body.repeat_every_weeks, step, body.geo_fence_id,
                                        body.is_wfh, sorted(set(body.employee_ids)), breaks, body.replace_existing)


def apply_default_shift(db: Db, ctx: RequestContext, body: Any) -> dict[str, Any]:
    _range(body.start_date, body.end_date, 366)
    return scheduling_repo.create_batch(db, ctx.company_id, ctx.user_id, SCHEDULES_CREATE, "default_shift",
                                        body.start_date, body.end_date, None, None, [], 0, 1, None, False,
                                        sorted(set(body.employee_ids)), None, body.replace_existing)


def bulk_delete(db: Db, ctx: RequestContext, body: Any) -> dict[str, Any]:
    if body.ids is None:
        if body.start_date is None or body.end_date is None:
            raise invalid("Give the shifts, or a start and an end date.", "startDate")
        _range(body.start_date, body.end_date, 366)
        if not body.all_employees and not body.employee_ids:
            raise invalid("Select at least one employee, or all employees.", "employeeIds")
    elif not body.ids:
        raise invalid("Select at least one shift.", "ids")
    return scheduling_repo.bulk_delete(db, ctx.company_id, ctx.user_id, SCHEDULES_DELETE, body.ids, body.start_date,
                                       body.end_date, body.employee_ids, body.all_employees, body.delete_rest_days)


def bulk_edit(db: Db, ctx: RequestContext, body: Any) -> dict[str, Any]:
    if body.geo_fence_id is not None and body.clear_geo_fence:
        raise invalid("Set a geo fence or clear it, not both.", "geoFenceId")
    return scheduling_repo.bulk_edit(db, ctx.company_id, ctx.user_id, SCHEDULES_EDIT, body.ids, body.time_slot_id,
                                     body.geo_fence_id, body.clear_geo_fence, body.is_wfh)


def swap(db: Db, ctx: RequestContext, schedule_id: int, with_schedule_id: int | None, with_employee_id: int | None,
         row_version: bytes) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if with_schedule_id is None and with_employee_id is None:
        raise invalid("Pick the shift or the employee to swap with.", "withScheduleId")
    with db.transaction():
        scheduling_repo.swap(db, ctx.company_id, ctx.user_id, SCHEDULES_EDIT, schedule_id, with_schedule_id,
                             with_employee_id, row_version)
        return scheduling_repo.get_schedule(db, ctx.company_id, ctx.user_id, SCHEDULES_EDIT, schedule_id)
