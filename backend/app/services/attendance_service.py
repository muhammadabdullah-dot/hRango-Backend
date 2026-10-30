"""Attendance rules. Set-based work (time-sheet processing, imports) lives in the procedures; checks that do
not need the database (address formats, whether a point is inside a fence, an IP inside a range, CSV
parsing and writing) live here."""
import csv
import io
import ipaddress
import json
import math
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any

from app.core.db import Db
from app.core.errors import AppError, forbidden, invalid
from app.middlewares.auth import RequestContext
from app.repos import attendance_repo
from app.schemas.attendance import BasicSettings, OvertimeSettings, SchedulingSettings

Row = dict[str, Any]

MAX_LOG_DAYS = 31
MAX_SHEET_DAYS = 366


def _check_range(from_date: date, to_date: date, max_days: int) -> None:
    if to_date < from_date:
        raise invalid("The end date is before the start date.", "toDate")
    if (to_date - from_date).days + 1 > max_days:
        raise invalid(f"Choose at most {max_days} days.", "toDate")


# ---------------------------------------------------------------- settings

SETTINGS_MODELS = {"attendance": BasicSettings, "overtime": OvertimeSettings, "scheduling": SchedulingSettings}


def _settings_out(model, version: bytes | None, values: dict[str, str]) -> tuple[Any, bytes | None]:
    data = {}
    for name, field in model.model_fields.items():
        if name == "row_version" or name not in values:
            continue
        raw = values[name]
        if field.annotation is bool:
            data[name] = raw in ("true", "1")
        else:
            try:
                data[name] = int(raw)
            except (TypeError, ValueError):
                pass
    return model(**data), version


def get_settings(db: Db, ctx: RequestContext, module: str):
    version, values = attendance_repo.get_settings(db, ctx.company_id, module)
    return _settings_out(SETTINGS_MODELS[module], version, values)


def save_settings(db: Db, ctx: RequestContext, module: str, body, row_version: bytes | None):
    values = {}
    for name, value in body.model_dump(exclude={"row_version"}, by_alias=False).items():
        values[name] = ("true" if value else "false") if isinstance(value, bool) else str(value)
    version, saved = attendance_repo.save_settings(db, ctx.company_id, ctx.user_id, module, values, row_version)
    return _settings_out(SETTINGS_MODELS[module], version, saved)


# ---------------------------------------------------------------- devices

def list_devices(db: Db, ctx: RequestContext, search, branch_id, status, page, page_size):
    return attendance_repo.list_devices(db, ctx.company_id, search, branch_id, status, page, page_size)


def get_device(db: Db, ctx: RequestContext, device_id: int) -> Row:
    return attendance_repo.get_device(db, ctx.company_id, device_id)


def save_device(db: Db, ctx: RequestContext, device_id: int | None, body, row_version: bytes | None) -> Row:
    if body.ip_address:
        try:
            ipaddress.ip_address(body.ip_address.strip())
        except ValueError:
            raise invalid("Not a valid IP address.", "ipAddress") from None
    return attendance_repo.save_device(db, ctx.company_id, ctx.user_id, device_id, body.name, body.model,
                                       body.serial_no, body.ip_address, body.port, body.branch_id, body.address,
                                       body.status, row_version)


def delete_device(db: Db, ctx: RequestContext, device_id: int, row_version: bytes) -> None:
    attendance_repo.delete_device(db, ctx.company_id, ctx.user_id, device_id, row_version)


def list_enrolments(db: Db, ctx: RequestContext, device_id: int) -> list[Row]:
    return attendance_repo.list_enrolments(db, ctx.company_id, device_id)


def save_enrolments(db: Db, ctx: RequestContext, device_id: int, enrolments, row_version: bytes) -> Row:
    rows = [{"employeeId": e.employee_id, "deviceUserNo": e.device_user_no.strip()} for e in enrolments]
    return attendance_repo.save_enrolments(db, ctx.company_id, ctx.user_id, device_id, rows, row_version)


# ---------------------------------------------------------------- punches

IMPORT_CODE = "attendance.logs.import"


def import_device_punches(db: Db, ctx: RequestContext, device_id: int, lines) -> tuple[Row, list[Row]]:
    rows = [{"line": ln.line or i + 1, "deviceUserNo": ln.device_user_no, "punchedAt": ln.punched_at,
             "punchType": ln.punch_type} for i, ln in enumerate(lines)]
    return attendance_repo.import_punches(db, ctx.company_id, ctx.user_id, IMPORT_CODE, device_id, rows)


def import_file_punches(db: Db, ctx: RequestContext, lines) -> tuple[Row, list[Row]]:
    rows = [{"line": ln.line or i + 1, "employeeCode": ln.employee_code, "punchedAt": ln.punched_at,
             "punchType": ln.punch_type} for i, ln in enumerate(lines)]
    return attendance_repo.import_punches(db, ctx.company_id, ctx.user_id, IMPORT_CODE, None, rows)


_CSV_COLUMNS = {"employee code": "employeeCode", "employee_code": "employeeCode", "employeecode": "employeeCode",
                "date": "date", "time": "time", "punch type": "punchType", "punch_type": "punchType",
                "punchtype": "punchType", "punched at": "punchedAt", "punched_at": "punchedAt",
                "punchedat": "punchedAt"}


def import_csv_punches(db: Db, ctx: RequestContext, text: str) -> tuple[Row, list[Row]]:
    """CSV with a header: Employee Code, Date (yyyy-mm-dd), Time (hh:mm[:ss]), Punch Type; or Punched At."""
    reader = csv.reader(io.StringIO(text.lstrip("﻿")))
    rows = [r for r in reader if any(c.strip() for c in r)]
    if len(rows) < 2:
        raise invalid("The file has no punches. The first line names the columns.", "file")
    header = [_CSV_COLUMNS.get(h.strip().lower()) for h in rows[0]]
    if "employeeCode" not in header or not ("punchedAt" in header or ("date" in header and "time" in header)):
        raise invalid("The columns must be Employee Code, Date, Time and Punch Type.", "file")
    if len(rows) - 1 > 20000:
        raise invalid("Import at most 20,000 lines at a time.", "file")
    lines = []
    for n, r in enumerate(rows[1:], start=2):
        cell = {k: (r[i].strip() if i < len(r) else "") for i, k in enumerate(header) if k}
        at = cell.get("punchedAt") or f"{cell.get('date', '')}T{cell.get('time', '')}"
        if len(at) == 16:  # yyyy-mm-ddThh:mm
            at += ":00"
        lines.append({"line": n, "employeeCode": cell.get("employeeCode") or None, "punchedAt": at,
                      "punchType": cell.get("punchType") or None})
    return attendance_repo.import_punches(db, ctx.company_id, ctx.user_id, IMPORT_CODE, None, lines)


def list_punches(db: Db, ctx: RequestContext, code: str, from_date: date, to_date: date, employee_id, punch_type,
                 source, device_id, search, page, page_size, max_days: int = MAX_LOG_DAYS):
    _check_range(from_date, to_date, max_days)
    return attendance_repo.list_punches(db, ctx.company_id, ctx.user_id, code, from_date, to_date, employee_id,
                                        punch_type, source, device_id, search, page, page_size)


def get_punch(db: Db, ctx: RequestContext, punch_id: int) -> Row:
    return attendance_repo.get_punch(db, ctx.company_id, ctx.user_id, "attendance.logs.view", punch_id)


def _not_own(ctx: RequestContext, employee_id: int) -> None:
    # Employees correct their own punches through a punch request, not by entering them (REQ-1).
    if ctx.employee_id is not None and ctx.employee_id == employee_id:
        raise forbidden("You cannot enter or change your own punches. Raise a punch request instead.")


def save_punch(db: Db, ctx: RequestContext, punch_id: int | None, body, row_version: bytes | None) -> Row:
    _not_own(ctx, body.employee_id)
    code = "attendance.logs.create" if punch_id is None else "attendance.logs.edit"
    return attendance_repo.save_punch(db, ctx.company_id, ctx.user_id, code, punch_id, body.employee_id,
                                      body.punched_at.replace(tzinfo=None, microsecond=0), body.punch_type,
                                      body.break_type_id, body.remarks, row_version)


def delete_punch(db: Db, ctx: RequestContext, punch_id: int, row_version: bytes) -> None:
    punch = attendance_repo.get_punch(db, ctx.company_id, ctx.user_id, "attendance.logs.delete", punch_id)
    _not_own(ctx, punch["employee_id"])
    attendance_repo.delete_punch(db, ctx.company_id, ctx.user_id, "attendance.logs.delete", punch_id, row_version)


def ignore_punch(db: Db, ctx: RequestContext, punch_id: int, is_ignored: bool, row_version: bytes) -> Row:
    punch = attendance_repo.get_punch(db, ctx.company_id, ctx.user_id, "attendance.logs.edit", punch_id)
    _not_own(ctx, punch["employee_id"])
    return attendance_repo.ignore_punch(db, ctx.company_id, ctx.user_id, "attendance.logs.edit", punch_id,
                                        is_ignored, row_version)


# ---------------------------------------------------------------- clock in / out

EARTH_RADIUS_M = 6_371_000


def distance_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def inside_polygon(lat: float, lng: float, points: list[dict]) -> bool:
    inside, n = False, len(points)
    for i in range(n):
        a, b = points[i], points[(i + 1) % n]
        if (a["lat"] > lat) != (b["lat"] > lat):
            cross = (b["lng"] - a["lng"]) * (lat - a["lat"]) / (b["lat"] - a["lat"]) + a["lng"]
            if lng < cross:
                inside = not inside
    return inside


def inside_fence(lat: float, lng: float, fence: Row) -> bool:
    if fence["shape"] == "circle":
        if fence["center_lat"] is None or fence["center_lng"] is None or not fence["radius_m"]:
            return False
        return distance_m(lat, lng, float(fence["center_lat"]), float(fence["center_lng"])) <= fence["radius_m"]
    try:
        points = json.loads(fence["polygon_points"] or "[]")
    except ValueError:
        return False
    return len(points) >= 3 and inside_polygon(lat, lng, points)


def _network(ipv4: str | None, netmask: str | None):
    text = ipv4.strip()
    if "/" not in text and netmask:
        text = f"{text}/{netmask.strip()}"
    return ipaddress.ip_network(text, strict=False)


def ip_allowed(ip: str, restriction: Row) -> bool:
    try:
        address = ipaddress.ip_address(ip)
    except ValueError:
        return False
    try:
        if restriction["ipv4"] and address in _network(restriction["ipv4"], restriction["netmask"]):
            return True
        if restriction["ipv6"] and address in ipaddress.ip_network(restriction["ipv6"].strip(), strict=False):
            return True
        if restriction["range_start"] and restriction["range_end"]:
            lo, hi = ipaddress.ip_address(restriction["range_start"]), ipaddress.ip_address(restriction["range_end"])
            if lo.version == address.version and lo <= address <= hi:
                return True
    except ValueError:
        return False
    return False


def clock_state(db: Db, ctx: RequestContext) -> Row:
    state, fences, _ = attendance_repo.clock_context(db, ctx.company_id, ctx.user_id)
    reason = None
    if state["employee_id"] is None:
        reason = "Your user is not linked to an employee in this company."
    elif not state["dashboard_punch"]:
        reason = "Clocking in from the dashboard is switched off. Use the attendance machine."
    return {**state, "allowed": reason is None, "reason": reason, "location_required": bool(fences)}


def clock(db: Db, ctx: RequestContext, body, client_ip: str | None) -> Row:
    state, fences, restrictions = attendance_repo.clock_context(db, ctx.company_id, ctx.user_id)
    if state["employee_id"] is None:
        raise forbidden("Your user is not linked to an employee in this company.")
    if not state["dashboard_punch"]:
        raise AppError(403, "DASHBOARD_PUNCH_OFF", "Clocking in from the dashboard is switched off. "
                                                   "Use the attendance machine.")
    if state["picture_required"] and body.photo_file_id is None:
        raise invalid("Take a picture to clock in.", "photoFileId")
    if fences:
        if body.latitude is None or body.longitude is None:
            raise invalid("Your location is needed to clock in.", "latitude")
        lat, lng = float(body.latitude), float(body.longitude)
        shift_fences = [f for f in fences if f["is_shift_fence"]]
        allowed = shift_fences or fences
        if not any(inside_fence(lat, lng, f) for f in allowed):
            names = ", ".join(f["name"] for f in allowed)
            raise AppError(403, "OUTSIDE_GEO_FENCE", f"You are outside the allowed area ({names}).",
                           {"latitude": "Outside the allowed area."})
    if restrictions and not (client_ip and any(ip_allowed(client_ip, r) for r in restrictions)):
        raise AppError(403, "IP_NOT_ALLOWED", "You cannot clock in from this network.")
    punch_type = body.punch_type or state["next_punch_type"]
    return attendance_repo.clock_punch(db, ctx.company_id, ctx.user_id, punch_type, body.source, body.latitude,
                                       body.longitude, client_ip, body.photo_file_id)


# ---------------------------------------------------------------- time sheet

def _tab_code(tab: str, code: str) -> str:
    if tab not in ("my", "subordinates", "all"):
        raise invalid("Tab must be my, subordinates or all.", "tab")
    return code


def list_timesheet(db: Db, ctx: RequestContext, code: str, tab: str, from_date: date, to_date: date, employee_id,
                   department_id, day_status, flag, time_slot_id, employee_status, search, page, page_size):
    _tab_code(tab, code)
    _check_range(from_date, to_date, MAX_SHEET_DAYS)
    return attendance_repo.list_timesheet(db, ctx.company_id, ctx.user_id, code, tab, from_date, to_date,
                                          employee_id, department_id, day_status, flag, time_slot_id,
                                          employee_status, search, page, page_size)


def get_day(db: Db, ctx: RequestContext, employee_id: int, work_date: date):
    return attendance_repo.get_day(db, ctx.company_id, ctx.user_id, "attendance.time_sheet.view", employee_id,
                                   work_date)


def save_day(db: Db, ctx: RequestContext, employee_id: int, work_date: date, body, row_version: bytes):
    if ctx.employee_id is not None and ctx.employee_id == employee_id:
        raise forbidden("You cannot edit your own time sheet.")

    def local(v: datetime | None) -> datetime | None:
        return v.replace(tzinfo=None, microsecond=0) if v else None

    breaks = [{"breakTypeId": b.break_type_id, "outAt": local(b.out_at).isoformat(),
               "inAt": local(b.in_at).isoformat() if b.in_at else None} for b in (body.breaks or [])]
    # Partial update: only the fields the client sent change (an explicit null clears one).
    sent = ",".join(sorted(f for f in body.model_fields_set if f != "row_version"))
    return attendance_repo.save_day(db, ctx.company_id, ctx.user_id, "attendance.time_sheet.edit", employee_id,
                                    work_date, local(body.expected_in), local(body.expected_out), local(body.first_in),
                                    local(body.last_out), body.marked_status, body.comments, breaks, row_version,
                                    sent)


def day_history(db: Db, ctx: RequestContext, employee_id: int, work_date: date, page: int, page_size: int):
    return attendance_repo.day_history(db, ctx.company_id, ctx.user_id, "attendance.time_sheet.view", employee_id,
                                       work_date, page, page_size)


def summary(db: Db, ctx: RequestContext, code: str, tab: str, from_date: date, to_date: date, employee_id,
            department_id) -> Row:
    _tab_code(tab, code)
    _check_range(from_date, to_date, MAX_SHEET_DAYS)
    return attendance_repo.summary(db, ctx.company_id, ctx.user_id, code, tab, from_date, to_date, employee_id,
                                   department_id)


def process(db: Db, ctx: RequestContext, body) -> Row:
    _check_range(body.from_date, body.to_date, MAX_SHEET_DAYS)
    return attendance_repo.process(db, ctx.company_id, ctx.user_id, "attendance.time_sheet.process", body.from_date,
                                   body.to_date, body.employee_ids, body.overwrite_manual)


def month_range(month: str) -> tuple[date, date]:
    try:
        first = datetime.strptime(month, "%Y-%m").date()
    except ValueError:
        raise invalid("Month must be yyyy-mm.", "month") from None
    nxt = (first.replace(day=28) + timedelta(days=4)).replace(day=1)
    return first, nxt - timedelta(days=1)


def overview(db: Db, ctx: RequestContext, code: str, tab: str, month: str, department_id, branch_id,
             employee_status, search, page, page_size):
    _tab_code(tab, code)
    first, last = month_range(month)
    total, rows, days = attendance_repo.overview(db, ctx.company_id, ctx.user_id, code, tab, first, last,
                                                 department_id, branch_id, employee_status, search, page, page_size)
    by_employee: dict[int, dict[str, str]] = {}
    for d in days:
        by_employee.setdefault(d["employee_id"], {})[d["work_date"].isoformat()] = d["day_status"]
    for r in rows:
        r["days"] = by_employee.get(r["employee_id"], {})
    return total, rows, [first + timedelta(days=i) for i in range((last - first).days + 1)]


# ---------------------------------------------------------------- IP restrictions

def _ip_check(body) -> None:
    def addr(value: str | None, field: str, version: int | None = None):
        try:
            a = ipaddress.ip_address(value.strip())
        except ValueError:
            raise invalid("Not a valid IP address.", field) from None
        if version and a.version != version:
            raise invalid(f"Not an IPv{version} address.", field)
        return a

    if not (body.ipv4 or body.ipv6 or (body.range_start and body.range_end)):
        raise invalid("Give an IPv4 or IPv6 address, or a range.", "ipv4")
    if body.ipv4:
        try:
            net = _network(body.ipv4, body.netmask)
        except ValueError:
            raise invalid("Not a valid IPv4 address, network or subnet mask.",
                          "netmask" if body.netmask else "ipv4") from None
        if net.version != 4:
            raise invalid("Not an IPv4 address.", "ipv4")
    elif body.netmask:
        raise invalid("A subnet mask goes with an IPv4 address.", "netmask")
    if body.ipv6:
        try:
            if ipaddress.ip_network(body.ipv6.strip(), strict=False).version != 6:
                raise ValueError
        except ValueError:
            raise invalid("Not a valid IPv6 address or network.", "ipv6") from None
    if bool(body.range_start) != bool(body.range_end):
        raise invalid("Give both ends of the range.", "rangeEnd" if body.range_start else "rangeStart")
    if body.range_start:
        lo = addr(body.range_start, "rangeStart")
        hi = addr(body.range_end, "rangeEnd", lo.version)
        if hi < lo:
            raise invalid("The range ends before it starts.", "rangeEnd")


def address_count(row: Row) -> int | None:
    total = 0
    try:
        if row["ipv4"]:
            total += _network(row["ipv4"], row["netmask"]).num_addresses
        if row["ipv6"]:
            total += ipaddress.ip_network(row["ipv6"].strip(), strict=False).num_addresses
        if row["range_start"] and row["range_end"]:
            total += int(ipaddress.ip_address(row["range_end"])) - int(ipaddress.ip_address(row["range_start"])) + 1
    except ValueError:
        return None
    return total


def _targets(targets) -> list[dict]:
    out = []
    for t in targets:
        if t.target_type in ("religion", "nationality"):
            if not (t.target_value or "").strip():
                raise invalid("Each target needs a value.", "targets")
            out.append({"targetType": t.target_type, "targetValue": t.target_value.strip()})
        else:
            if t.target_id is None:
                raise invalid("Each target needs a value.", "targets")
            out.append({"targetType": t.target_type, "targetId": t.target_id})
    return out


def list_ip_restrictions(db: Db, ctx: RequestContext, search, is_active, page, page_size):
    return attendance_repo.list_ip_restrictions(db, ctx.company_id, search, is_active, page, page_size)


def get_ip_restriction(db: Db, ctx: RequestContext, restriction_id: int):
    return attendance_repo.get_ip_restriction(db, ctx.company_id, restriction_id)


def save_ip_restriction(db: Db, ctx: RequestContext, restriction_id: int | None, body, row_version: bytes | None):
    _ip_check(body)
    clean = {k: (getattr(body, k) or "").strip() or None for k in ("ipv4", "ipv6", "netmask", "range_start", "range_end")}
    return attendance_repo.save_ip_restriction(db, ctx.company_id, ctx.user_id, restriction_id, clean["ipv4"],
                                               clean["ipv6"], clean["netmask"], clean["range_start"],
                                               clean["range_end"], body.applies_to_all, body.is_active,
                                               _targets(body.targets), row_version)


def delete_ip_restriction(db: Db, ctx: RequestContext, restriction_id: int, row_version: bytes) -> None:
    attendance_repo.delete_ip_restriction(db, ctx.company_id, ctx.user_id, restriction_id, row_version)


# ---------------------------------------------------------------- geo fences

def list_geo_fences(db: Db, ctx: RequestContext, search, is_active, is_for_shift, page, page_size):
    return attendance_repo.list_geo_fences(db, ctx.company_id, search, is_active, is_for_shift, page, page_size)


def get_geo_fence(db: Db, ctx: RequestContext, fence_id: int):
    return attendance_repo.get_geo_fence(db, ctx.company_id, fence_id)


def save_geo_fence(db: Db, ctx: RequestContext, fence_id: int | None, body, row_version: bytes | None):
    points = None
    if body.shape == "circle":
        if body.center_lat is None or body.center_lng is None:
            raise invalid("A circle needs a centre.", "centerLat")
        if not body.radius_m:
            raise invalid("A circle needs a radius above zero.", "radiusM")
    else:
        if not body.polygon_points or len(body.polygon_points) < 3:
            raise invalid("A polygon needs at least three points.", "polygonPoints")
        points = json.dumps([{"lat": p.lat, "lng": p.lng} for p in body.polygon_points])
    if body.joining_from_date and body.joining_to_date and body.joining_to_date < body.joining_from_date:
        raise invalid("The joining end date is before the start date.", "joiningToDate")
    return attendance_repo.save_geo_fence(db, ctx.company_id, ctx.user_id, fence_id, body.name.strip(), body.shape,
                                          body.center_lat if body.shape == "circle" else None,
                                          body.center_lng if body.shape == "circle" else None,
                                          body.radius_m if body.shape == "circle" else None, points,
                                          body.applies_to_all, body.joining_from_date, body.joining_to_date,
                                          body.is_for_shift, body.is_active, _targets(body.targets), row_version)


def delete_geo_fence(db: Db, ctx: RequestContext, fence_id: int, row_version: bytes) -> None:
    attendance_repo.delete_geo_fence(db, ctx.company_id, ctx.user_id, fence_id, row_version)


# ---------------------------------------------------------------- overtime policies

def list_overtime_policies(db: Db, ctx: RequestContext, search, period, page, page_size):
    return attendance_repo.list_overtime_policies(db, ctx.company_id, search, period, page, page_size)


def get_overtime_policy(db: Db, ctx: RequestContext, policy_id: int):
    return attendance_repo.get_overtime_policy(db, ctx.company_id, policy_id)


def save_overtime_policy(db: Db, ctx: RequestContext, policy_id: int | None, body, row_version: bytes | None):
    slabs = sorted(body.slabs, key=lambda s: s.min_minutes)
    for s in slabs:
        if s.max_minutes < s.min_minutes:
            raise invalid("A slab's maximum minutes are below its minimum.", "slabs")
        if s.encashment_type == "leave" and s.leave_type_id is None:
            raise invalid("Choose the leave type a slab converts to.", "slabs")
    for a, b in zip(slabs, slabs[1:]):
        if b.min_minutes <= a.max_minutes:
            raise invalid("Slabs overlap.", "slabs")
    rows = [{"minMinutes": s.min_minutes, "maxMinutes": s.max_minutes, "encashmentType": s.encashment_type,
             "leaveTypeId": s.leave_type_id if s.encashment_type == "leave" else None} for s in slabs]
    return attendance_repo.save_overtime_policy(db, ctx.company_id, ctx.user_id, policy_id, body.name.strip(),
                                                body.period, body.description, body.is_active, rows, row_version)


def delete_overtime_policy(db: Db, ctx: RequestContext, policy_id: int, row_version: bytes) -> None:
    attendance_repo.delete_overtime_policy(db, ctx.company_id, ctx.user_id, policy_id, row_version)


# ---------------------------------------------------------------- CSV

def to_csv(header: list[str], rows: list[list[Any]]) -> str:
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\r\n")
    w.writerow(header)
    for r in rows:
        w.writerow(["" if v is None else (v.isoformat() if isinstance(v, (date, datetime)) else
                                         (str(v) if isinstance(v, Decimal) else v)) for v in r])
    return "﻿" + out.getvalue()
