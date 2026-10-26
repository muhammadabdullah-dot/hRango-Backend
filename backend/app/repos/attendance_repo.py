"""Attendance data access. The only layer that knows procedure names and parameters."""
import json
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from app.core.db import Db

Row = dict[str, Any]


def _page(sets: list[list[Row]]) -> tuple[int, list[Row]]:
    return sets[0][0]["total"], sets[1]


# ---------------------------------------------------------------- settings

def get_settings(db: Db, company_id: int, module: str) -> tuple[bytes | None, dict[str, str]]:
    version, rows = db.call_sets("att.usp_setting_get", company_id=company_id, module=module)
    return version[0]["row_version"], {r["setting_key"]: r["setting_value"] for r in rows}


def save_settings(db: Db, company_id: int, actor_user_id: int, module: str, values: dict[str, str],
                  row_version: bytes | None) -> tuple[bytes | None, dict[str, str]]:
    version, rows = db.call_sets("att.usp_setting_save", company_id=company_id, actor_user_id=actor_user_id,
                                 module=module, settings=json.dumps(values), row_version=row_version)
    return version[0]["row_version"], {r["setting_key"]: r["setting_value"] for r in rows}


# ---------------------------------------------------------------- devices

def list_devices(db: Db, company_id: int, search: str | None, branch_id: int | None, status: str | None,
                 page: int, page_size: int) -> tuple[int, list[Row]]:
    return _page(db.call_sets("att.usp_device_list", company_id=company_id, search=search, branch_id=branch_id,
                              status=status, page=page, page_size=page_size))


def get_device(db: Db, company_id: int, device_id: int) -> Row:
    return db.call_one("att.usp_device_get", company_id=company_id, id=device_id)


def save_device(db: Db, company_id: int, actor_user_id: int, device_id: int | None, name: str, model: str | None,
                serial_no: str | None, ip_address: str | None, port: int | None, branch_id: int | None,
                address: str | None, status: str, row_version: bytes | None) -> Row:
    return db.call_one("att.usp_device_save", company_id=company_id, actor_user_id=actor_user_id, id=device_id,
                       name=name, model=model, serial_no=serial_no, ip_address=ip_address, port=port,
                       branch_id=branch_id, address=address, status=status, row_version=row_version)


def delete_device(db: Db, company_id: int, actor_user_id: int, device_id: int, row_version: bytes) -> None:
    db.call("att.usp_device_delete", company_id=company_id, actor_user_id=actor_user_id, id=device_id,
            row_version=row_version)


def list_enrolments(db: Db, company_id: int, device_id: int) -> list[Row]:
    return db.call("att.usp_device_enrolment_list", company_id=company_id, device_id=device_id)


def save_enrolments(db: Db, company_id: int, actor_user_id: int, device_id: int, enrolments: list[dict],
                    row_version: bytes) -> Row:
    return db.call_one("att.usp_device_enrolment_save", company_id=company_id, actor_user_id=actor_user_id,
                       device_id=device_id, enrolments=json.dumps(enrolments), row_version=row_version)


# ---------------------------------------------------------------- punches

def import_punches(db: Db, company_id: int, actor_user_id: int, permission_code: str, device_id: int | None,
                   lines: list[dict]) -> tuple[Row, list[Row]]:
    counts, errors = db.call_sets("att.usp_punch_import", company_id=company_id, actor_user_id=actor_user_id,
                                  permission_code=permission_code, device_id=device_id, lines=json.dumps(lines))
    return counts[0], errors


def list_punches(db: Db, company_id: int, actor_user_id: int, permission_code: str, from_date: date, to_date: date,
                 employee_id: int | None, punch_type: str | None, source: str | None, device_id: int | None,
                 search: str | None, page: int, page_size: int) -> tuple[int, list[Row]]:
    return _page(db.call_sets("att.usp_punch_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=permission_code, from_date=from_date, to_date=to_date,
                              employee_id=employee_id, punch_type=punch_type, source=source, device_id=device_id,
                              search=search, page=page, page_size=page_size))


def get_punch(db: Db, company_id: int, actor_user_id: int, permission_code: str, punch_id: int) -> Row:
    return db.call_one("att.usp_punch_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=punch_id)


def save_punch(db: Db, company_id: int, actor_user_id: int, permission_code: str, punch_id: int | None,
               employee_id: int, punched_at: datetime, punch_type: str, break_type_id: int | None,
               remarks: str | None, row_version: bytes | None) -> Row:
    return db.call_one("att.usp_punch_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=punch_id, employee_id=employee_id, punched_at=punched_at,
                       punch_type=punch_type, break_type_id=break_type_id, remarks=remarks, row_version=row_version)


def delete_punch(db: Db, company_id: int, actor_user_id: int, permission_code: str, punch_id: int,
                 row_version: bytes) -> None:
    db.call("att.usp_punch_delete", company_id=company_id, actor_user_id=actor_user_id,
            permission_code=permission_code, id=punch_id, row_version=row_version)


def ignore_punch(db: Db, company_id: int, actor_user_id: int, permission_code: str, punch_id: int, is_ignored: bool,
                 row_version: bytes) -> Row:
    return db.call_one("att.usp_punch_ignore", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=punch_id, is_ignored=is_ignored, row_version=row_version)


def clock_context(db: Db, company_id: int, actor_user_id: int) -> tuple[Row, list[Row], list[Row]]:
    state, fences, restrictions = db.call_sets("att.usp_clock_context", company_id=company_id,
                                               actor_user_id=actor_user_id)
    return state[0], fences, restrictions


def clock_punch(db: Db, company_id: int, actor_user_id: int, punch_type: str, source: str,
                latitude: Decimal | None, longitude: Decimal | None, ip_address: str | None,
                photo_file_id: int | None) -> Row:
    return db.call_one("att.usp_clock_punch", company_id=company_id, actor_user_id=actor_user_id,
                       punch_type=punch_type, source=source, latitude=latitude, longitude=longitude,
                       ip_address=ip_address, photo_file_id=photo_file_id)


# ---------------------------------------------------------------- time sheet

def process(db: Db, company_id: int, actor_user_id: int, permission_code: str, from_date: date, to_date: date,
            employee_ids: list[int] | None, overwrite_manual: bool) -> Row:
    return db.call_one("att.usp_timesheet_process", company_id=company_id, actor_user_id=actor_user_id,
                       from_date=from_date, to_date=to_date,
                       employee_ids=json.dumps(employee_ids) if employee_ids is not None else None,
                       permission_code=permission_code, overwrite_manual=overwrite_manual)


def list_timesheet(db: Db, company_id: int, actor_user_id: int, permission_code: str, tab: str, from_date: date,
                   to_date: date, employee_id: int | None, department_id: int | None, day_status: str | None,
                   flag: str | None, time_slot_id: int | None, employee_status: str | None, search: str | None,
                   page: int, page_size: int) -> tuple[int, list[Row]]:
    return _page(db.call_sets("att.usp_timesheet_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=permission_code, tab=tab, from_date=from_date, to_date=to_date,
                              employee_id=employee_id, department_id=department_id, day_status=day_status, flag=flag,
                              time_slot_id=time_slot_id, employee_status=employee_status, search=search, page=page,
                              page_size=page_size))


def get_day(db: Db, company_id: int, actor_user_id: int, permission_code: str, employee_id: int,
            work_date: date) -> tuple[Row, list[Row], list[Row], list[Row]]:
    day, flags, breaks, punches = db.call_sets("att.usp_timesheet_day_get", company_id=company_id,
                                               actor_user_id=actor_user_id, permission_code=permission_code,
                                               employee_id=employee_id, work_date=work_date)
    return day[0], flags, breaks, punches


def save_day(db: Db, company_id: int, actor_user_id: int, permission_code: str, employee_id: int, work_date: date,
             expected_in: datetime | None, expected_out: datetime | None, first_in: datetime | None,
             last_out: datetime | None, marked_status: str | None, comments: str | None, breaks: list[dict],
             row_version: bytes, sent: str | None = None) -> tuple[Row, list[Row], list[Row], list[Row]]:
    day, flags, brk, punches = db.call_sets(
        "att.usp_timesheet_day_save", company_id=company_id, actor_user_id=actor_user_id,
        permission_code=permission_code, employee_id=employee_id, work_date=work_date, expected_in=expected_in,
        expected_out=expected_out, first_in=first_in, last_out=last_out, marked_status=marked_status,
        comments=comments, breaks=json.dumps(breaks), row_version=row_version, sent=sent)
    return day[0], flags, brk, punches


def day_history(db: Db, company_id: int, actor_user_id: int, permission_code: str, employee_id: int,
                work_date: date, page: int, page_size: int) -> tuple[int, list[Row]]:
    return _page(db.call_sets("att.usp_timesheet_day_history", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=permission_code, employee_id=employee_id, work_date=work_date,
                              page=page, page_size=page_size))


def summary(db: Db, company_id: int, actor_user_id: int, permission_code: str, tab: str, from_date: date,
            to_date: date, employee_id: int | None, department_id: int | None) -> Row:
    return db.call_one("att.usp_timesheet_summary", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, tab=tab, from_date=from_date, to_date=to_date,
                       employee_id=employee_id, department_id=department_id)


def overview(db: Db, company_id: int, actor_user_id: int, permission_code: str, tab: str, from_date: date,
             to_date: date, department_id: int | None, branch_id: int | None, employee_status: str | None,
             search: str | None, page: int, page_size: int) -> tuple[int, list[Row], list[Row]]:
    total, rows, days = db.call_sets("att.usp_overview_list", company_id=company_id, actor_user_id=actor_user_id,
                                     permission_code=permission_code, tab=tab, from_date=from_date, to_date=to_date,
                                     department_id=department_id, branch_id=branch_id, employee_status=employee_status,
                                     search=search, page=page, page_size=page_size)
    return total[0]["total"], rows, days


# ---------------------------------------------------------------- IP restrictions

def list_ip_restrictions(db: Db, company_id: int, search: str | None, is_active: bool | None, page: int,
                         page_size: int) -> tuple[int, list[Row]]:
    return _page(db.call_sets("att.usp_ip_restriction_list", company_id=company_id, search=search,
                              is_active=is_active, page=page, page_size=page_size))


def get_ip_restriction(db: Db, company_id: int, restriction_id: int) -> tuple[Row, list[Row]]:
    row, targets = db.call_sets("att.usp_ip_restriction_get", company_id=company_id, id=restriction_id)
    return row[0], targets


def save_ip_restriction(db: Db, company_id: int, actor_user_id: int, restriction_id: int | None,
                        ipv4: str | None, ipv6: str | None, netmask: str | None, range_start: str | None,
                        range_end: str | None, applies_to_all: bool, is_active: bool, targets: list[dict],
                        row_version: bytes | None) -> tuple[Row, list[Row]]:
    row, saved = db.call_sets("att.usp_ip_restriction_save", company_id=company_id, actor_user_id=actor_user_id,
                              id=restriction_id, ipv4=ipv4, ipv6=ipv6, netmask=netmask, range_start=range_start,
                              range_end=range_end, applies_to_all=applies_to_all, is_active=is_active,
                              targets=json.dumps(targets), row_version=row_version)
    return row[0], saved


def delete_ip_restriction(db: Db, company_id: int, actor_user_id: int, restriction_id: int,
                          row_version: bytes) -> None:
    db.call("att.usp_ip_restriction_delete", company_id=company_id, actor_user_id=actor_user_id, id=restriction_id,
            row_version=row_version)


# ---------------------------------------------------------------- geo fences

def list_geo_fences(db: Db, company_id: int, search: str | None, is_active: bool | None, is_for_shift: bool | None,
                    page: int, page_size: int) -> tuple[int, list[Row]]:
    return _page(db.call_sets("att.usp_geo_fence_list", company_id=company_id, search=search, is_active=is_active,
                              is_for_shift=is_for_shift, page=page, page_size=page_size))


def get_geo_fence(db: Db, company_id: int, fence_id: int) -> tuple[Row, list[Row]]:
    row, targets = db.call_sets("att.usp_geo_fence_get", company_id=company_id, id=fence_id)
    return row[0], targets


def save_geo_fence(db: Db, company_id: int, actor_user_id: int, fence_id: int | None, name: str, shape: str,
                   center_lat: Decimal | None, center_lng: Decimal | None, radius_m: int | None,
                   polygon_points: str | None, applies_to_all: bool, joining_from_date: date | None,
                   joining_to_date: date | None, is_for_shift: bool, is_active: bool, targets: list[dict],
                   row_version: bytes | None) -> tuple[Row, list[Row]]:
    row, saved = db.call_sets("att.usp_geo_fence_save", company_id=company_id, actor_user_id=actor_user_id,
                              id=fence_id, name=name, shape=shape, center_lat=center_lat, center_lng=center_lng,
                              radius_m=radius_m, polygon_points=polygon_points, applies_to_all=applies_to_all,
                              joining_from_date=joining_from_date, joining_to_date=joining_to_date,
                              is_for_shift=is_for_shift, is_active=is_active, targets=json.dumps(targets),
                              row_version=row_version)
    return row[0], saved


def delete_geo_fence(db: Db, company_id: int, actor_user_id: int, fence_id: int, row_version: bytes) -> None:
    db.call("att.usp_geo_fence_delete", company_id=company_id, actor_user_id=actor_user_id, id=fence_id,
            row_version=row_version)


# ---------------------------------------------------------------- overtime policies

def list_overtime_policies(db: Db, company_id: int, search: str | None, period: str | None, page: int,
                           page_size: int) -> tuple[int, list[Row]]:
    return _page(db.call_sets("att.usp_overtime_policy_list", company_id=company_id, search=search, period=period,
                              page=page, page_size=page_size))


def get_overtime_policy(db: Db, company_id: int, policy_id: int) -> tuple[Row, list[Row]]:
    row, slabs = db.call_sets("att.usp_overtime_policy_get", company_id=company_id, id=policy_id)
    return row[0], slabs


def save_overtime_policy(db: Db, company_id: int, actor_user_id: int, policy_id: int | None, name: str, period: str,
                         description: str | None, is_active: bool, slabs: list[dict],
                         row_version: bytes | None) -> tuple[Row, list[Row]]:
    row, saved = db.call_sets("att.usp_overtime_policy_save", company_id=company_id, actor_user_id=actor_user_id,
                              id=policy_id, name=name, period=period, description=description, is_active=is_active,
                              slabs=json.dumps(slabs), row_version=row_version)
    return row[0], saved


def delete_overtime_policy(db: Db, company_id: int, actor_user_id: int, policy_id: int, row_version: bytes) -> None:
    db.call("att.usp_overtime_policy_delete", company_id=company_id, actor_user_id=actor_user_id, id=policy_id,
            row_version=row_version)
