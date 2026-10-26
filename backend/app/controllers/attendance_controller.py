"""HTTP shape for attendance screens: envelopes, row versions as text, rows to response models, CSV files."""
import json
from datetime import date
from typing import Any

from fastapi import Response

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.attendance import (BreakOut, ClockStateOut, DayDetailOut, DeviceOut, EnrolmentOut, FlagOut,
                                    GeoFenceOut, GeoPoint, HistoryOut, ImportResultOut, IpRestrictionOut,
                                    OverviewRowOut, OverviewTotals, OvertimePolicyOut, OvertimeSlabOut, ProcessOut,
                                    PunchOut, SummaryOut, TargetOut, TimesheetDayOut)
from app.schemas.common import paginated
from app.schemas.files import FileRef
from app.services import attendance_service as svc

Row = dict[str, Any]
EXPORT_ROWS = 100_000


def _rv(row: Row) -> Row:
    return {**row, "row_version": row_version_out(row["row_version"])}


def _csv(name: str, text: str) -> Response:
    return Response(content=text.encode("utf-8"), media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="{name}"'})


# ---------------------------------------------------------------- settings

def get_settings(db: Db, ctx: RequestContext, module: str) -> dict:
    model, version = svc.get_settings(db, ctx, module)
    return {"data": model.model_copy(update={"row_version": row_version_out(version)})}


def save_settings(db: Db, ctx: RequestContext, module: str, body) -> dict:
    model, version = svc.save_settings(db, ctx, module, body, row_version_in(body.row_version, required=False))
    return {"data": model.model_copy(update={"row_version": row_version_out(version)})}


# ---------------------------------------------------------------- devices

def _device(row: Row) -> DeviceOut:
    return DeviceOut(**_rv(row))


def list_devices(db: Db, ctx: RequestContext, q, branch_id, status, paging: PageParams) -> dict:
    total, rows = svc.list_devices(db, ctx, q, branch_id, status, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _device)


def get_device(db: Db, ctx: RequestContext, device_id: int) -> dict:
    return {"data": _device(svc.get_device(db, ctx, device_id))}


def create_device(db: Db, ctx: RequestContext, body) -> dict:
    return {"data": _device(svc.save_device(db, ctx, None, body, None))}


def update_device(db: Db, ctx: RequestContext, device_id: int, body) -> dict:
    return {"data": _device(svc.save_device(db, ctx, device_id, body, row_version_in(body.row_version)))}


def delete_device(db: Db, ctx: RequestContext, device_id: int, row_version: str | None) -> None:
    svc.delete_device(db, ctx, device_id, row_version_in(row_version))


def list_enrolments(db: Db, ctx: RequestContext, device_id: int) -> dict:
    return {"data": [EnrolmentOut(**r) for r in svc.list_enrolments(db, ctx, device_id)]}


def save_enrolments(db: Db, ctx: RequestContext, device_id: int, body) -> dict:
    return {"data": _device(svc.save_enrolments(db, ctx, device_id, body.enrolments, row_version_in(body.row_version)))}


# ---------------------------------------------------------------- punches

def _punch(row: Row, company_id: int) -> PunchOut:
    photo = row.get("photo_file_id")
    return PunchOut(**_rv(row), editable=row["source"] in ("manual", "import_file"),
                    photo=FileRef(id=str(photo), name=row.get("photo_file_name"), url=file_url(photo, company_id))
                    if photo else None)


def _import_result(counts: Row, errors: list[Row]) -> dict:
    return {"data": ImportResultOut(created=counts["created"] or 0, skipped=counts["skipped"] or 0,
                                    failed=counts["failed"] or 0, errors=errors)}


def import_device_punches(db: Db, ctx: RequestContext, device_id: int, body) -> dict:
    return _import_result(*svc.import_device_punches(db, ctx, device_id, body.lines))


def import_file_punches(db: Db, ctx: RequestContext, body) -> dict:
    return _import_result(*svc.import_file_punches(db, ctx, body.lines))


def import_csv_punches(db: Db, ctx: RequestContext, raw: bytes) -> dict:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("latin-1")
    return _import_result(*svc.import_csv_punches(db, ctx, text))


def list_punches(db: Db, ctx: RequestContext, from_date: date, to_date: date, employee_id, punch_type, source,
                 device_id, q, paging: PageParams) -> dict:
    total, rows = svc.list_punches(db, ctx, "attendance.logs.view", from_date, to_date, employee_id, punch_type,
                                   source, device_id, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: _punch(r, ctx.company_id))


def export_punches(db: Db, ctx: RequestContext, from_date: date, to_date: date, employee_id, punch_type, source,
                   device_id, q) -> Response:
    _, rows = svc.list_punches(db, ctx, "attendance.logs.export", from_date, to_date, employee_id, punch_type,
                               source, device_id, q, 1, EXPORT_ROWS)
    text = svc.to_csv(
        ["Employee Code", "Employee Name", "Date", "Time", "Punch Type", "Break Type", "Source", "Machine", "Remarks",
         "Ignored", "Manually Updated"],
        [[r["employee_code"], r["employee_name"], r["punched_at"].date(), r["punched_at"].strftime("%H:%M:%S"),
          r["punch_type"], r["break_type_name"], r["source"], r["device_code"], r["remarks"],
          "yes" if r["is_ignored"] else "no", "yes" if r["is_manually_updated"] else "no"] for r in rows])
    return _csv(f"attendance-log-{from_date}-{to_date}.csv", text)


def get_punch(db: Db, ctx: RequestContext, punch_id: int) -> dict:
    return {"data": _punch(svc.get_punch(db, ctx, punch_id), ctx.company_id)}


def create_punch(db: Db, ctx: RequestContext, body) -> dict:
    return {"data": _punch(svc.save_punch(db, ctx, None, body, None), ctx.company_id)}


def update_punch(db: Db, ctx: RequestContext, punch_id: int, body) -> dict:
    row = svc.save_punch(db, ctx, punch_id, body, row_version_in(body.row_version))
    return {"data": _punch(row, ctx.company_id)}


def delete_punch(db: Db, ctx: RequestContext, punch_id: int, row_version: str | None) -> None:
    svc.delete_punch(db, ctx, punch_id, row_version_in(row_version))


def ignore_punch(db: Db, ctx: RequestContext, punch_id: int, body) -> dict:
    row = svc.ignore_punch(db, ctx, punch_id, body.is_ignored, row_version_in(body.row_version))
    return {"data": _punch(row, ctx.company_id)}


# ---------------------------------------------------------------- clock

def clock_state(db: Db, ctx: RequestContext) -> dict:
    s = svc.clock_state(db, ctx)
    return {"data": ClockStateOut(
        allowed=s["allowed"], reason=s["reason"], photo_required=bool(s["picture_required"]),
        location_required=s["location_required"], employee_id=s["employee_id"], employee_name=s["employee_name"],
        now=s["now_local"], clocked_in=s["last_punch_type"] in ("check_in", "break_in"),
        next_punch_type=s["next_punch_type"], last_punch_type=s["last_punch_type"],
        last_punched_at=s["last_punched_at"], expected_in=s["expected_in"], expected_out=s["expected_out"])}


def clock(db: Db, ctx: RequestContext, body, client_ip: str | None) -> dict:
    return {"data": _punch(svc.clock(db, ctx, body, client_ip), ctx.company_id)}


# ---------------------------------------------------------------- time sheet

def _statuses(row: Row, flags: list[str]) -> tuple[str | None, str | None]:
    missing = "missing_punch" in flags
    if row["first_in"] is None:
        cin = "absent" if row["day_status"] == "absent" else ("missing" if missing else None)
    elif row["late_minutes"]:
        cin = "late"
    elif "grace" in flags:
        cin = "grace"
    else:
        cin = "on_time"
    if row["last_out"] is None:
        cout = "absent" if row["day_status"] == "absent" else ("missing" if missing else None)
    elif row["early_left_minutes"]:
        cout = "early"
    elif row["overtime_after_minutes"]:
        cout = "overtime"
    else:
        cout = "on_time"
    return cin, cout


def _day(row: Row) -> TimesheetDayOut:
    flags = [f for f in (row["flags"] or "").split(",") if f]
    cin, cout = _statuses(row, flags)
    return TimesheetDayOut(**{**_rv(row), "flags": sorted(flags)}, clock_in_status=cin, clock_out_status=cout)


def _detail(company_id: int, day: Row, flags: list[Row], breaks: list[Row], punches: list[Row]) -> dict:
    return {"data": DayDetailOut(day=_day(day), flags=[FlagOut(**f) for f in flags],
                                 breaks=[BreakOut(**b) for b in breaks],
                                 punches=[_punch(p, company_id) for p in punches])}


def list_timesheet(db: Db, ctx: RequestContext, tab: str, from_date: date, to_date: date, employee_id, department_id,
                   day_status, flag, time_slot_id, employee_status, q, paging: PageParams) -> dict:
    total, rows = svc.list_timesheet(db, ctx, "attendance.time_sheet.view", tab, from_date, to_date, employee_id,
                                     department_id, day_status, flag, time_slot_id, employee_status, q, paging.page,
                                     paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _day)


def export_timesheet(db: Db, ctx: RequestContext, tab: str, from_date: date, to_date: date, employee_id,
                     department_id, day_status, flag, time_slot_id, employee_status, q) -> Response:
    _, rows = svc.list_timesheet(db, ctx, "attendance.time_sheet.export", tab, from_date, to_date, employee_id,
                                 department_id, day_status, flag, time_slot_id, employee_status, q, 1, EXPORT_ROWS)
    text = svc.to_csv(
        ["Employee Code", "Employee Name", "Department", "Date", "Time Slot", "Expected In", "Expected Out",
         "Clock In", "Clock Out", "Status", "Late Minutes", "Early Left Minutes", "Expected Minutes",
         "Worked Minutes", "Shift Worked Minutes", "Break Minutes", "Overtime Minutes", "Approved Overtime Minutes",
         "Flags", "Manually Updated"],
        [[r["employee_code"], r["employee_name"], r["department_name"], r["work_date"], r["time_slot_name"],
          r["expected_in"], r["expected_out"], r["first_in"], r["last_out"], r["day_status"], r["late_minutes"],
          r["early_left_minutes"], r["expected_minutes"], r["worked_minutes"], r["shift_worked_minutes"],
          r["break_minutes"], (r["overtime_before_minutes"] or 0) + (r["overtime_after_minutes"] or 0),
          r["approved_overtime_minutes"], (r["flags"] or "").replace(",", " "),
          "yes" if r["is_manually_updated"] else "no"] for r in rows])
    return _csv(f"time-sheet-{from_date}-{to_date}.csv", text)


def get_day(db: Db, ctx: RequestContext, employee_id: int, work_date: date) -> dict:
    return _detail(ctx.company_id, *svc.get_day(db, ctx, employee_id, work_date))


def save_day(db: Db, ctx: RequestContext, employee_id: int, work_date: date, body) -> dict:
    return _detail(ctx.company_id,
                   *svc.save_day(db, ctx, employee_id, work_date, body, row_version_in(body.row_version)))


def day_history(db: Db, ctx: RequestContext, employee_id: int, work_date: date, paging: PageParams) -> dict:
    total, rows = svc.day_history(db, ctx, employee_id, work_date, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: HistoryOut(**r))


def summary(db: Db, ctx: RequestContext, code: str, tab: str, from_date: date, to_date: date, employee_id,
            department_id) -> dict:
    row = svc.summary(db, ctx, code, tab, from_date, to_date, employee_id, department_id)
    return {"data": SummaryOut(from_date=from_date, to_date=to_date, **{k: v or 0 for k, v in row.items()})}


def process(db: Db, ctx: RequestContext, body) -> dict:
    return {"data": ProcessOut(**svc.process(db, ctx, body))}


# ---------------------------------------------------------------- overview

def _overview_row(row: Row) -> OverviewRowOut:
    totals = OverviewTotals(**{k: row[k] or 0 for k in OverviewTotals.model_fields})
    return OverviewRowOut(employee_id=row["employee_id"], employee_code=row["employee_code"],
                          employee_name=row["employee_name"], department_name=row["department_name"],
                          designation_name=row["designation_name"], employee_status=row["employee_status"],
                          totals=totals, days=row["days"])


def overview(db: Db, ctx: RequestContext, tab: str, month: str, department_id, branch_id, employee_status, q,
             paging: PageParams) -> dict:
    total, rows, days = svc.overview(db, ctx, "attendance.overview.view", tab, month, department_id, branch_id,
                                     employee_status, q, paging.page, paging.page_size)
    page = paginated(rows, total, paging.page, paging.page_size, _overview_row)
    return {**page, "days": days}


def export_overview(db: Db, ctx: RequestContext, tab: str, month: str, department_id, branch_id, employee_status,
                    q) -> Response:
    _, rows, days = svc.overview(db, ctx, "attendance.overview.export", tab, month, department_id, branch_id,
                                 employee_status, q, 1, EXPORT_ROWS)
    header = ["Employee Code", "Employee Name", "Department", "Total Days", "Present", "Absent", "Leave", "Holiday",
              "Days Off", "Late Arrival", "Early Left"] + [d.isoformat() for d in days]
    text = svc.to_csv(header, [[r["employee_code"], r["employee_name"], r["department_name"], r["total_days"],
                                r["present"], r["absent"], r["leave"], r["holiday"], r["days_off"], r["late_arrival"],
                                r["early_left"]] + [r["days"].get(d.isoformat()) for d in days] for r in rows])
    return _csv(f"attendance-overview-{month}.csv", text)


# ---------------------------------------------------------------- IP restrictions

def _ip_restriction(row: Row, targets: list[Row] | None = None) -> IpRestrictionOut:
    return IpRestrictionOut(**{**_rv(row), "target_count": row.get("target_count", len(targets or []))},
                            address_count=svc.address_count(row),
                            targets=[TargetOut(**t) for t in targets] if targets is not None else None)


def list_ip_restrictions(db: Db, ctx: RequestContext, q, is_active, paging: PageParams) -> dict:
    total, rows = svc.list_ip_restrictions(db, ctx, q, is_active, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _ip_restriction)


def get_ip_restriction(db: Db, ctx: RequestContext, restriction_id: int) -> dict:
    return {"data": _ip_restriction(*svc.get_ip_restriction(db, ctx, restriction_id))}


def create_ip_restriction(db: Db, ctx: RequestContext, body) -> dict:
    return {"data": _ip_restriction(*svc.save_ip_restriction(db, ctx, None, body, None))}


def update_ip_restriction(db: Db, ctx: RequestContext, restriction_id: int, body) -> dict:
    return {"data": _ip_restriction(*svc.save_ip_restriction(db, ctx, restriction_id, body,
                                                             row_version_in(body.row_version)))}


def delete_ip_restriction(db: Db, ctx: RequestContext, restriction_id: int, row_version: str | None) -> None:
    svc.delete_ip_restriction(db, ctx, restriction_id, row_version_in(row_version))


# ---------------------------------------------------------------- geo fences

def _geo_fence(row: Row, targets: list[Row] | None = None) -> GeoFenceOut:
    points = json.loads(row["polygon_points"]) if row["polygon_points"] else None
    return GeoFenceOut(**{**_rv(row), "target_count": row.get("target_count", len(targets or [])),
                          "polygon_points": [GeoPoint(**p) for p in points] if points else None},
                       targets=[TargetOut(**t) for t in targets] if targets is not None else None)


def list_geo_fences(db: Db, ctx: RequestContext, q, is_active, is_for_shift, paging: PageParams) -> dict:
    total, rows = svc.list_geo_fences(db, ctx, q, is_active, is_for_shift, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _geo_fence)


def get_geo_fence(db: Db, ctx: RequestContext, fence_id: int) -> dict:
    return {"data": _geo_fence(*svc.get_geo_fence(db, ctx, fence_id))}


def create_geo_fence(db: Db, ctx: RequestContext, body) -> dict:
    return {"data": _geo_fence(*svc.save_geo_fence(db, ctx, None, body, None))}


def update_geo_fence(db: Db, ctx: RequestContext, fence_id: int, body) -> dict:
    return {"data": _geo_fence(*svc.save_geo_fence(db, ctx, fence_id, body, row_version_in(body.row_version)))}


def delete_geo_fence(db: Db, ctx: RequestContext, fence_id: int, row_version: str | None) -> None:
    svc.delete_geo_fence(db, ctx, fence_id, row_version_in(row_version))


# ---------------------------------------------------------------- overtime policies

def _policy(row: Row, slabs: list[Row] | None = None) -> OvertimePolicyOut:
    return OvertimePolicyOut(**{**_rv(row), "slab_count": row.get("slab_count", len(slabs or []))},
                             slabs=[OvertimeSlabOut(**s) for s in slabs] if slabs is not None else None)


def list_overtime_policies(db: Db, ctx: RequestContext, q, period, paging: PageParams) -> dict:
    total, rows = svc.list_overtime_policies(db, ctx, q, period, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _policy)


def get_overtime_policy(db: Db, ctx: RequestContext, policy_id: int) -> dict:
    return {"data": _policy(*svc.get_overtime_policy(db, ctx, policy_id))}


def create_overtime_policy(db: Db, ctx: RequestContext, body) -> dict:
    return {"data": _policy(*svc.save_overtime_policy(db, ctx, None, body, None))}


def update_overtime_policy(db: Db, ctx: RequestContext, policy_id: int, body) -> dict:
    return {"data": _policy(*svc.save_overtime_policy(db, ctx, policy_id, body, row_version_in(body.row_version)))}


def delete_overtime_policy(db: Db, ctx: RequestContext, policy_id: int, row_version: str | None) -> None:
    svc.delete_overtime_policy(db, ctx, policy_id, row_version_in(row_version))

