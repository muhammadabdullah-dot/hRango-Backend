from datetime import date

from fastapi import APIRouter, Body, Depends, Query, Request, Response, status

from app.controllers import attendance_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.attendance import (BasicSettings, ClockIn, ClockStateOut, DayDetailOut, DayEditIn, DeviceIn, DeviceOut,
                                    DevicePunchesIn, EnrolmentOut, EnrolmentsIn, FilePunchesIn, GeoFenceIn, GeoFenceOut,
                                    HistoryOut, ImportResultOut, IpRestrictionIn, IpRestrictionOut, OverviewPageOut,
                                    OvertimePolicyIn, OvertimePolicyOut, OvertimeSettings, ProcessIn, ProcessOut,
                                    PunchIgnoreIn, PunchIn, PunchOut, SummaryOut, TimesheetDayOut)
from app.schemas.common import Item, Paginated

router = APIRouter(prefix="/attendance", tags=["attendance"])

CSV = {"content": {"text/csv": {}}, "description": "CSV file"}


def _no_content() -> Response:
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- overview

@router.get("/overview", response_model=OverviewPageOut)
def overview(month: str, tab: str = "all", department_id: int | None = Query(None, alias="departmentId"),
             branch_id: int | None = Query(None, alias="branchId"),
             employee_status: str | None = Query(None, alias="employeeStatus"), q: str | None = None,
             paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("attendance.overview.view"))) -> dict:
    return c.overview(db, ctx, tab, month, department_id, branch_id, employee_status, q, paging)


@router.get("/overview/export", responses={200: CSV})
def export_overview(month: str, tab: str = "all", department_id: int | None = Query(None, alias="departmentId"),
                    branch_id: int | None = Query(None, alias="branchId"),
                    employee_status: str | None = Query(None, alias="employeeStatus"), q: str | None = None,
                    db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("attendance.overview.export"))) -> Response:
    return c.export_overview(db, ctx, tab, month, department_id, branch_id, employee_status, q)


@router.get("/overview/summary", response_model=Item[SummaryOut])
def overview_summary(from_date: date = Query(alias="fromDate"), to_date: date = Query(alias="toDate"),
                     tab: str = "all", employee_id: int | None = Query(None, alias="employeeId"),
                     department_id: int | None = Query(None, alias="departmentId"), db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("attendance.overview.view"))) -> dict:
    return c.summary(db, ctx, "attendance.overview.view", tab, from_date, to_date, employee_id, department_id)


# ---------------------------------------------------------------- time sheet

@router.get("/time-sheet", response_model=Paginated[TimesheetDayOut])
def list_timesheet(from_date: date = Query(alias="fromDate"), to_date: date = Query(alias="toDate"),
                   tab: str = "my", employee_id: int | None = Query(None, alias="employeeId"),
                   department_id: int | None = Query(None, alias="departmentId"),
                   day_status: str | None = Query(None, alias="dayStatus"), flag: str | None = None,
                   time_slot_id: int | None = Query(None, alias="timeSlotId"),
                   employee_status: str | None = Query(None, alias="employeeStatus"), q: str | None = None,
                   paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("attendance.time_sheet.view"))) -> dict:
    return c.list_timesheet(db, ctx, tab, from_date, to_date, employee_id, department_id, day_status, flag,
                            time_slot_id, employee_status, q, paging)


@router.get("/time-sheet/export", responses={200: CSV})
def export_timesheet(from_date: date = Query(alias="fromDate"), to_date: date = Query(alias="toDate"),
                     tab: str = "all", employee_id: int | None = Query(None, alias="employeeId"),
                     department_id: int | None = Query(None, alias="departmentId"),
                     day_status: str | None = Query(None, alias="dayStatus"), flag: str | None = None,
                     time_slot_id: int | None = Query(None, alias="timeSlotId"),
                     employee_status: str | None = Query(None, alias="employeeStatus"), q: str | None = None,
                     db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("attendance.time_sheet.export"))) -> Response:
    return c.export_timesheet(db, ctx, tab, from_date, to_date, employee_id, department_id, day_status, flag,
                              time_slot_id, employee_status, q)


@router.get("/time-sheet/summary", response_model=Item[SummaryOut])
def timesheet_summary(from_date: date = Query(alias="fromDate"), to_date: date = Query(alias="toDate"),
                      tab: str = "my", employee_id: int | None = Query(None, alias="employeeId"),
                      department_id: int | None = Query(None, alias="departmentId"), db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("attendance.time_sheet.view"))) -> dict:
    return c.summary(db, ctx, "attendance.time_sheet.view", tab, from_date, to_date, employee_id, department_id)


@router.post("/time-sheet/process", response_model=Item[ProcessOut])
def process_timesheet(body: ProcessIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("attendance.time_sheet.process"))) -> dict:
    return c.process(db, ctx, body)


@router.get("/days/{employee_id}/{work_date}", response_model=Item[DayDetailOut])
def get_day(employee_id: int, work_date: date, db: Db = Depends(get_db),
            ctx: RequestContext = Depends(require("attendance.time_sheet.view"))) -> dict:
    return c.get_day(db, ctx, employee_id, work_date)


@router.put("/days/{employee_id}/{work_date}", response_model=Item[DayDetailOut])
def update_day(employee_id: int, work_date: date, body: DayEditIn = Body(), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("attendance.time_sheet.edit"))) -> dict:
    return c.save_day(db, ctx, employee_id, work_date, body)


@router.get("/days/{employee_id}/{work_date}/history", response_model=Paginated[HistoryOut])
def day_history(employee_id: int, work_date: date, paging: PageParams = Depends(page_params),
                db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("attendance.time_sheet.view"))) -> dict:
    return c.day_history(db, ctx, employee_id, work_date, paging)


# ---------------------------------------------------------------- clock in / out

@router.get("/clock", response_model=Item[ClockStateOut])
def clock_state(db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("attendance.time_sheet.clock"))) -> dict:
    return c.clock_state(db, ctx)


@router.post("/clock", response_model=Item[PunchOut], status_code=status.HTTP_201_CREATED)
def clock(request: Request, body: ClockIn, db: Db = Depends(get_db),
          ctx: RequestContext = Depends(require("attendance.time_sheet.clock"))) -> dict:
    return c.clock(db, ctx, body, request.client.host if request.client else None)


# ---------------------------------------------------------------- attendance logs (punches)

@router.get("/logs", response_model=Paginated[PunchOut])
def list_logs(from_date: date = Query(alias="fromDate"), to_date: date = Query(alias="toDate"),
              employee_id: int | None = Query(None, alias="employeeId"),
              punch_type: str | None = Query(None, alias="punchType"), source: str | None = None,
              device_id: int | None = Query(None, alias="deviceId"), q: str | None = None,
              paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("attendance.logs.view"))) -> dict:
    return c.list_punches(db, ctx, from_date, to_date, employee_id, punch_type, source, device_id, q, paging)


@router.get("/logs/export", responses={200: CSV})
def export_logs(from_date: date = Query(alias="fromDate"), to_date: date = Query(alias="toDate"),
                employee_id: int | None = Query(None, alias="employeeId"),
                punch_type: str | None = Query(None, alias="punchType"), source: str | None = None,
                device_id: int | None = Query(None, alias="deviceId"), q: str | None = None,
                db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("attendance.logs.export"))) -> Response:
    return c.export_punches(db, ctx, from_date, to_date, employee_id, punch_type, source, device_id, q)


@router.post("/logs/import", response_model=Item[ImportResultOut])
def import_logs(body: FilePunchesIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("attendance.logs.import"))) -> dict:
    return c.import_file_punches(db, ctx, body)


@router.post("/logs/import/csv", response_model=Item[ImportResultOut],
             openapi_extra={"requestBody": {"content": {"text/csv": {"schema": {"type": "string"}}}}})
async def import_logs_csv(request: Request, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("attendance.logs.import"))) -> dict:
    raw = await request.body()
    return c.import_csv_punches(db, ctx, raw)


@router.get("/logs/{punch_id}", response_model=Item[PunchOut])
def get_log(punch_id: int, db: Db = Depends(get_db),
            ctx: RequestContext = Depends(require("attendance.logs.view"))) -> dict:
    return c.get_punch(db, ctx, punch_id)


@router.post("/logs", response_model=Item[PunchOut], status_code=status.HTTP_201_CREATED)
def create_log(body: PunchIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("attendance.logs.create"))) -> dict:
    return c.create_punch(db, ctx, body)


@router.put("/logs/{punch_id}", response_model=Item[PunchOut])
def update_log(punch_id: int, body: PunchIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("attendance.logs.edit"))) -> dict:
    return c.update_punch(db, ctx, punch_id, body)


@router.patch("/logs/{punch_id}/ignore", response_model=Item[PunchOut])
def ignore_log(punch_id: int, body: PunchIgnoreIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("attendance.logs.edit"))) -> dict:
    return c.ignore_punch(db, ctx, punch_id, body)


@router.delete("/logs/{punch_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_log(punch_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("attendance.logs.delete"))) -> Response:
    c.delete_punch(db, ctx, punch_id, row_version)
    return _no_content()


# ---------------------------------------------------------------- settings: basic and overtime

@router.get("/settings/basic", response_model=Item[BasicSettings])
def get_basic(db: Db = Depends(get_db), ctx: RequestContext = Depends(require("attendance.settings.basic.view"))) -> dict:
    return c.get_settings(db, ctx, "attendance")


@router.put("/settings/basic", response_model=Item[BasicSettings])
def save_basic(body: BasicSettings, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("attendance.settings.basic.edit"))) -> dict:
    return c.save_settings(db, ctx, "attendance", body)


@router.get("/settings/overtime", response_model=Item[OvertimeSettings])
def get_overtime(db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("attendance.settings.overtime.view"))) -> dict:
    return c.get_settings(db, ctx, "overtime")


@router.put("/settings/overtime", response_model=Item[OvertimeSettings])
def save_overtime(body: OvertimeSettings, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("attendance.settings.overtime.edit"))) -> dict:
    return c.save_settings(db, ctx, "overtime", body)


# ---------------------------------------------------------------- settings: biometric devices

@router.get("/settings/devices", response_model=Paginated[DeviceOut])
def list_devices(q: str | None = None, branch_id: int | None = Query(None, alias="branchId"),
                 status_: str | None = Query(None, alias="status"), paging: PageParams = Depends(page_params),
                 db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("attendance.settings.devices.view"))) -> dict:
    return c.list_devices(db, ctx, q, branch_id, status_, paging)


@router.get("/settings/devices/{device_id}", response_model=Item[DeviceOut])
def get_device(device_id: int, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("attendance.settings.devices.view"))) -> dict:
    return c.get_device(db, ctx, device_id)


@router.post("/settings/devices", response_model=Item[DeviceOut], status_code=status.HTTP_201_CREATED)
def create_device(body: DeviceIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("attendance.settings.devices.create"))) -> dict:
    return c.create_device(db, ctx, body)


@router.put("/settings/devices/{device_id}", response_model=Item[DeviceOut])
def update_device(device_id: int, body: DeviceIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("attendance.settings.devices.edit"))) -> dict:
    return c.update_device(db, ctx, device_id, body)


@router.delete("/settings/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_device(device_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("attendance.settings.devices.delete"))) -> Response:
    c.delete_device(db, ctx, device_id, row_version)
    return _no_content()


@router.get("/settings/devices/{device_id}/enrolments", response_model=Item[list[EnrolmentOut]])
def list_enrolments(device_id: int, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("attendance.settings.devices.view"))) -> dict:
    return c.list_enrolments(db, ctx, device_id)


@router.put("/settings/devices/{device_id}/enrolments", response_model=Item[DeviceOut])
def save_enrolments(device_id: int, body: EnrolmentsIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("attendance.settings.devices.enroll"))) -> dict:
    return c.save_enrolments(db, ctx, device_id, body)


# Punches a device (or the connector that reads it) hands over: "Import Attendance Log -> Machine".
@router.post("/settings/devices/{device_id}/punches", response_model=Item[ImportResultOut])
def import_device_punches(device_id: int, body: DevicePunchesIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("attendance.logs.import"))) -> dict:
    return c.import_device_punches(db, ctx, device_id, body)


# ---------------------------------------------------------------- settings: IP restrictions

@router.get("/settings/ip-restrictions", response_model=Paginated[IpRestrictionOut])
def list_ip_restrictions(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
                         paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("attendance.settings.ip_restrictions.view"))) -> dict:
    return c.list_ip_restrictions(db, ctx, q, is_active, paging)


@router.get("/settings/ip-restrictions/{restriction_id}", response_model=Item[IpRestrictionOut])
def get_ip_restriction(restriction_id: int, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("attendance.settings.ip_restrictions.view"))) -> dict:
    return c.get_ip_restriction(db, ctx, restriction_id)


@router.post("/settings/ip-restrictions", response_model=Item[IpRestrictionOut], status_code=status.HTTP_201_CREATED)
def create_ip_restriction(body: IpRestrictionIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("attendance.settings.ip_restrictions.create"))) -> dict:
    return c.create_ip_restriction(db, ctx, body)


@router.put("/settings/ip-restrictions/{restriction_id}", response_model=Item[IpRestrictionOut])
def update_ip_restriction(restriction_id: int, body: IpRestrictionIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("attendance.settings.ip_restrictions.edit"))) -> dict:
    return c.update_ip_restriction(db, ctx, restriction_id, body)


@router.delete("/settings/ip-restrictions/{restriction_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_ip_restriction(restriction_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                          db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("attendance.settings.ip_restrictions.delete"))) -> Response:
    c.delete_ip_restriction(db, ctx, restriction_id, row_version)
    return _no_content()


# ---------------------------------------------------------------- settings: geo fencing

@router.get("/settings/geo-fences", response_model=Paginated[GeoFenceOut])
def list_geo_fences(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
                    is_for_shift: bool | None = Query(None, alias="isForShift"),
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("attendance.settings.geo_fencing.view"))) -> dict:
    return c.list_geo_fences(db, ctx, q, is_active, is_for_shift, paging)


@router.get("/settings/geo-fences/{fence_id}", response_model=Item[GeoFenceOut])
def get_geo_fence(fence_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("attendance.settings.geo_fencing.view"))) -> dict:
    return c.get_geo_fence(db, ctx, fence_id)


@router.post("/settings/geo-fences", response_model=Item[GeoFenceOut], status_code=status.HTTP_201_CREATED)
def create_geo_fence(body: GeoFenceIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("attendance.settings.geo_fencing.create"))) -> dict:
    return c.create_geo_fence(db, ctx, body)


@router.put("/settings/geo-fences/{fence_id}", response_model=Item[GeoFenceOut])
def update_geo_fence(fence_id: int, body: GeoFenceIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("attendance.settings.geo_fencing.edit"))) -> dict:
    return c.update_geo_fence(db, ctx, fence_id, body)


@router.delete("/settings/geo-fences/{fence_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_geo_fence(fence_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("attendance.settings.geo_fencing.delete"))) -> Response:
    c.delete_geo_fence(db, ctx, fence_id, row_version)
    return _no_content()


# ---------------------------------------------------------------- settings: overtime policies

@router.get("/settings/overtime-policies", response_model=Paginated[OvertimePolicyOut])
def list_overtime_policies(q: str | None = None, period: str | None = None,
                           paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("attendance.settings.overtime_policies.view"))) -> dict:
    return c.list_overtime_policies(db, ctx, q, period, paging)


@router.get("/settings/overtime-policies/{policy_id}", response_model=Item[OvertimePolicyOut])
def get_overtime_policy(policy_id: int, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("attendance.settings.overtime_policies.view"))) -> dict:
    return c.get_overtime_policy(db, ctx, policy_id)


@router.post("/settings/overtime-policies", response_model=Item[OvertimePolicyOut], status_code=status.HTTP_201_CREATED)
def create_overtime_policy(body: OvertimePolicyIn, db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("attendance.settings.overtime_policies.create"))) -> dict:
    return c.create_overtime_policy(db, ctx, body)


@router.put("/settings/overtime-policies/{policy_id}", response_model=Item[OvertimePolicyOut])
def update_overtime_policy(policy_id: int, body: OvertimePolicyIn, db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("attendance.settings.overtime_policies.edit"))) -> dict:
    return c.update_overtime_policy(db, ctx, policy_id, body)


@router.delete("/settings/overtime-policies/{policy_id}", status_code=status.HTTP_204_NO_CONTENT,
               responses={409: {"description": "IN_USE: approved overtime fell under this policy (usageCount > 0)"}})
def delete_overtime_policy(policy_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                           db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("attendance.settings.overtime_policies.delete"))) -> Response:
    """Refused (409 IN_USE) once approved overtime fell under the policy: make it inactive instead."""
    c.delete_overtime_policy(db, ctx, policy_id, row_version)
    return _no_content()
