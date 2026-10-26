"""HTTP shape for the scheduling screens: envelopes, row versions as text, rows to response models."""
import csv
import io
import math
from collections import defaultdict
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import PageMeta, paginated
from app.schemas.scheduling import (BoardEmployeeOut, BoardHolidayOut, BoardRestDayOut, BoardRowOut, BoardShiftOut,
                                    BreakTypeIn, BreakTypeOut, BulkDeleteIn, BulkDeleteOut, BulkEditIn, BulkEditOut,
                                    DayTotalOut, DefaultShiftIn, HolidayIn, HolidayOut, HolidayRuleOut, OptionOut,
                                    RestDayRangeDeleteIn, RestDayRuleIn, RestDayRuleOut, RuleEmployeeOut,
                                    ScheduleBatchIn, ScheduleBatchOut, ScheduleBreakOut, ScheduleIn, ScheduleOut, SwapIn, TimeSlotBreakOut, TimeSlotIn,
                                    TimeSlotOut, YearMonthOut, YearRowOut)
from app.services import roster_service, scheduling_service


def _rv(row: dict[str, Any]) -> dict[str, Any]:
    return {**row, "row_version": row_version_out(row["row_version"])}


def _weekday_list(text: str | None) -> list[int]:
    return [int(w) for w in (text or "").split(",") if w.strip()]


def _meta(total: int, paging: PageParams) -> PageMeta:
    return PageMeta(page=paging.page, page_size=paging.page_size, total=total,
                    total_pages=max(1, math.ceil(total / paging.page_size)))


# ---------------------------------------------------------------- time slots

def _time_slot(row: dict[str, Any], breaks: list[dict[str, Any]] | None = None) -> TimeSlotOut:
    return TimeSlotOut(**{**_rv(row), "breaks": [TimeSlotBreakOut(**b) for b in breaks or []]})


def list_time_slots(db: Db, ctx: RequestContext, q: str | None, is_flexible: bool | None, paging: PageParams) -> dict:
    total, rows = scheduling_service.list_time_slots(db, ctx, q, is_flexible, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _time_slot)


def get_time_slot(db: Db, ctx: RequestContext, slot_id: int) -> dict:
    return {"data": _time_slot(*scheduling_service.get_time_slot(db, ctx, slot_id))}


def create_time_slot(db: Db, ctx: RequestContext, body: TimeSlotIn) -> dict:
    return {"data": _time_slot(*scheduling_service.save_time_slot(db, ctx, None, body, None))}


def update_time_slot(db: Db, ctx: RequestContext, slot_id: int, body: TimeSlotIn) -> dict:
    return {"data": _time_slot(*scheduling_service.save_time_slot(db, ctx, slot_id, body,
                                                                  row_version_in(body.row_version)))}


def delete_time_slot(db: Db, ctx: RequestContext, slot_id: int, row_version: str | None) -> None:
    scheduling_service.delete_time_slot(db, ctx, slot_id, row_version_in(row_version))


# ---------------------------------------------------------------- break types

def _break_type(row: dict[str, Any]) -> BreakTypeOut:
    return BreakTypeOut(**_rv(row))


def list_break_types(db: Db, ctx: RequestContext, q: str | None, paging: PageParams) -> dict:
    total, rows = scheduling_service.list_break_types(db, ctx, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _break_type)


def get_break_type(db: Db, ctx: RequestContext, type_id: int) -> dict:
    return {"data": _break_type(scheduling_service.get_break_type(db, ctx, type_id))}


def create_break_type(db: Db, ctx: RequestContext, body: BreakTypeIn) -> dict:
    row = scheduling_service.save_break_type(db, ctx, None, body.name, body.start_identifier, body.end_identifier,
                                             None)
    return {"data": _break_type(row)}


def update_break_type(db: Db, ctx: RequestContext, type_id: int, body: BreakTypeIn) -> dict:
    row = scheduling_service.save_break_type(db, ctx, type_id, body.name, body.start_identifier,
                                             body.end_identifier, row_version_in(body.row_version))
    return {"data": _break_type(row)}


def delete_break_type(db: Db, ctx: RequestContext, type_id: int, row_version: str | None) -> None:
    scheduling_service.delete_break_type(db, ctx, type_id, row_version_in(row_version))


# ---------------------------------------------------------------- rest-day rules

def _rest_day_rule(row: dict[str, Any], employees: list[dict[str, Any]] | None = None) -> RestDayRuleOut:
    return RestDayRuleOut(**{**_rv(row), "weekdays": _weekday_list(row["weekdays"]),
                             "employees": [RuleEmployeeOut(**e) for e in employees or []]})


def list_rest_day_rules(db: Db, ctx: RequestContext, employee_id: int | None, from_date: date | None,
                        to_date: date | None, paging: PageParams) -> dict:
    total, rows = scheduling_service.list_rest_day_rules(db, ctx, employee_id, from_date, to_date, paging.page,
                                                         paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _rest_day_rule)


def get_rest_day_rule(db: Db, ctx: RequestContext, rule_id: int) -> dict:
    return {"data": _rest_day_rule(*scheduling_service.get_rest_day_rule(db, ctx, rule_id))}


def create_rest_day_rule(db: Db, ctx: RequestContext, body: RestDayRuleIn) -> dict:
    return {"data": _rest_day_rule(*scheduling_service.save_rest_day_rule(db, ctx, None, body, None))}


def update_rest_day_rule(db: Db, ctx: RequestContext, rule_id: int, body: RestDayRuleIn) -> dict:
    return {"data": _rest_day_rule(*scheduling_service.save_rest_day_rule(db, ctx, rule_id, body,
                                                                          row_version_in(body.row_version)))}


def delete_rest_day_rule(db: Db, ctx: RequestContext, rule_id: int, row_version: str | None) -> None:
    scheduling_service.delete_rest_day_rule(db, ctx, rule_id, row_version_in(row_version))


def delete_rest_day_range(db: Db, ctx: RequestContext, body: RestDayRangeDeleteIn) -> dict:
    return {"data": BulkDeleteOut(**scheduling_service.delete_rest_day_range(db, ctx, body))}


# ---------------------------------------------------------------- holidays

def _holiday(row: dict[str, Any], rules: list[dict[str, Any]] | None = None) -> HolidayOut:
    return HolidayOut(**{**_rv(row), "rules": [HolidayRuleOut(**r) for r in rules or []]})


def list_holidays(db: Db, ctx: RequestContext, year: int | None, q: str | None, holiday_type: str | None,
                  paging: PageParams) -> dict:
    total, rows = scheduling_service.list_holidays(db, ctx, year, q, holiday_type, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _holiday)


def get_holiday(db: Db, ctx: RequestContext, holiday_id: int) -> dict:
    return {"data": _holiday(*scheduling_service.get_holiday(db, ctx, holiday_id))}


def create_holiday(db: Db, ctx: RequestContext, body: HolidayIn) -> dict:
    return {"data": _holiday(*scheduling_service.save_holiday(db, ctx, None, body, None))}


def update_holiday(db: Db, ctx: RequestContext, holiday_id: int, body: HolidayIn) -> dict:
    return {"data": _holiday(*scheduling_service.save_holiday(db, ctx, holiday_id, body,
                                                              row_version_in(body.row_version)))}


def delete_holiday(db: Db, ctx: RequestContext, holiday_id: int, row_version: str | None) -> None:
    scheduling_service.delete_holiday(db, ctx, holiday_id, row_version_in(row_version))


# ---------------------------------------------------------------- schedules

def _schedule(row: dict[str, Any], breaks: list[dict[str, Any]]) -> ScheduleOut:
    return ScheduleOut(**{**_rv(row), "breaks": [ScheduleBreakOut(**b) for b in breaks]})


def board(db: Db, ctx: RequestContext, tab: str, from_date: date, to_date: date, filters: dict[str, Any],
          paging: PageParams) -> dict:
    total, employees, shifts, rest_days, holidays, totals = scheduling_service.board(
        db, ctx, tab, from_date, to_date, filters, paging.page, paging.page_size)
    by_emp: dict[int, dict[str, list]] = defaultdict(lambda: {"shifts": [], "rest_days": [], "holidays": []})
    for s in shifts:
        by_emp[s["employee_id"]]["shifts"].append(BoardShiftOut(**_rv(s)))
    for r in rest_days:
        by_emp[r["employee_id"]]["rest_days"].append(BoardRestDayOut(**r))
    for h in holidays:
        by_emp[h["employee_id"]]["holidays"].append(BoardHolidayOut(**h))
    rows = [BoardRowOut(employee=BoardEmployeeOut(**e), **by_emp[e["id"]]) for e in employees]
    return {"data": rows, "meta": _meta(total[0]["total"], paging), "day_totals": [DayTotalOut(**t) for t in totals]}


def year(db: Db, ctx: RequestContext, tab: str, year_no: int, filters: dict[str, Any], paging: PageParams) -> dict:
    total, employees, months = scheduling_service.year(db, ctx, tab, year_no, filters, paging.page, paging.page_size)
    by_emp: dict[int, list[YearMonthOut]] = defaultdict(list)
    for m in months:
        by_emp[m["employee_id"]].append(YearMonthOut(month=m["month_no"], planned_minutes=m["planned_minutes"],
                                                     shift_count=m["shift_count"], rest_days=m["rest_days"]))
    rows = [YearRowOut(employee=BoardEmployeeOut(**e), months=by_emp[e["id"]]) for e in employees]
    return {"data": rows, "meta": _meta(total[0]["total"], paging)}


def export_csv(db: Db, ctx: RequestContext, tab: str, from_date: date, to_date: date, filters: dict[str, Any]) -> str:
    """One line per employee and date in the range: the shifts, or Rest Day / Holiday."""
    _, employees, shifts, rest_days, holidays, _ = scheduling_service.export(db, ctx, tab, from_date, to_date, filters)
    cells: dict[tuple[int, date], list[str]] = defaultdict(list)
    for s in shifts:
        cells[(s["employee_id"], s["work_date"])].append(
            f"{s['time_slot_name']} {s['start_at']:%H:%M}-{s['end_at']:%H:%M}" + (" WFH" if s["is_wfh"] else ""))
    for r in rest_days:
        cells[(r["employee_id"], r["rest_date"])].insert(0, "Rest Day")
    for h in holidays:
        cells[(h["employee_id"], h["holiday_date"])].insert(0, f"Holiday: {h['holiday_name']}")
    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(["Employee Code", "Employee Name", "Designation", "Department", "Date", "Schedule", "Planned Minutes"])
    planned: dict[tuple[int, date], int] = defaultdict(int)
    for s in shifts:
        planned[(s["employee_id"], s["work_date"])] += s["planned_minutes"]
    for e in employees:
        for (emp_id, day), texts in sorted((k, v) for k, v in cells.items() if k[0] == e["id"]):
            w.writerow([e["code"], e["name"], e["designation_name"] or "", e["department_name"] or "",
                        day.isoformat(), "; ".join(texts), planned.get((emp_id, day), 0)])
    return out.getvalue()


def get_schedule(db: Db, ctx: RequestContext, schedule_id: int) -> dict:
    return {"data": _schedule(*scheduling_service.get_schedule(db, ctx, schedule_id))}


def create_schedule(db: Db, ctx: RequestContext, body: ScheduleIn) -> dict:
    return {"data": _schedule(*scheduling_service.save_schedule(db, ctx, None, body, None))}


def update_schedule(db: Db, ctx: RequestContext, schedule_id: int, body: ScheduleIn) -> dict:
    return {"data": _schedule(*scheduling_service.save_schedule(db, ctx, schedule_id, body,
                                                                row_version_in(body.row_version)))}


def delete_schedule(db: Db, ctx: RequestContext, schedule_id: int, row_version: str | None) -> None:
    scheduling_service.delete_schedule(db, ctx, schedule_id, row_version_in(row_version))


def _batch(row: dict[str, Any]) -> ScheduleBatchOut:
    return ScheduleBatchOut(**{**row, "weekdays": _weekday_list(row["weekdays"])})


def create_batch(db: Db, ctx: RequestContext, body: ScheduleBatchIn) -> dict:
    return {"data": _batch(scheduling_service.create_batch(db, ctx, body))}


def apply_default_shift(db: Db, ctx: RequestContext, body: DefaultShiftIn) -> dict:
    return {"data": _batch(scheduling_service.apply_default_shift(db, ctx, body))}


def bulk_delete(db: Db, ctx: RequestContext, body: BulkDeleteIn) -> dict:
    return {"data": BulkDeleteOut(**scheduling_service.bulk_delete(db, ctx, body))}


def bulk_edit(db: Db, ctx: RequestContext, body: BulkEditIn) -> dict:
    return {"data": BulkEditOut(**scheduling_service.bulk_edit(db, ctx, body))}


def swap(db: Db, ctx: RequestContext, schedule_id: int, body: SwapIn) -> dict:
    row, breaks = scheduling_service.swap(db, ctx, schedule_id, body.with_schedule_id, body.with_employee_id,
                                          row_version_in(body.row_version))
    return {"data": _schedule(row, breaks)}


# ---------------------------------------------------------------- pickers

def time_slot_options(db: Db, ctx: RequestContext) -> dict:
    _, rows = scheduling_service.list_time_slots(db, ctx, None, None, 1, 1000)
    return {"data": [OptionOut(id=r["id"], name=r["name"], code=r["code"], start_time=r["start_time"],
                               end_time=r["end_time"], is_overnight=r["is_overnight"], is_flexible=r["is_flexible"])
                     for r in rows]}


def break_type_options(db: Db, ctx: RequestContext) -> dict:
    _, rows = scheduling_service.list_break_types(db, ctx, None, 1, 1000)
    return {"data": [OptionOut(id=r["id"], name=r["name"]) for r in rows]}


def roster_group_options(db: Db, ctx: RequestContext) -> dict:
    _, rows = roster_service.list_groups(db, ctx, None, True, 1, 1000)
    return {"data": [OptionOut(id=r["id"], name=r["title"]) for r in rows]}
