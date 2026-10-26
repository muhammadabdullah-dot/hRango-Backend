from datetime import date
from typing import Any, Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import scheduling_controller
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require, require_any
from app.schemas.common import Item, Paginated
from app.schemas.scheduling import (BoardPage, BreakTypeIn, BreakTypeOut, BulkDeleteIn, BulkDeleteOut, BulkEditIn,
                                    BulkEditOut, DefaultShiftIn, HolidayIn, HolidayOut, OptionList,
                                    RestDayRangeDeleteIn, RestDayRuleIn,
                                    RestDayRuleOut, ScheduleBatchIn, ScheduleBatchOut, ScheduleIn, ScheduleOut, SwapIn,
                                    TimeSlotIn, TimeSlotOut, YearPage)

router = APIRouter(prefix="/scheduling", tags=["scheduling"])

Tab = Literal["my", "subordinates", "all"]


def board_filters(q: str | None = None, employee_id: int | None = Query(None, alias="employeeId"),
                  department_id: int | None = Query(None, alias="departmentId"),
                  branch_id: int | None = Query(None, alias="branchId"),
                  location_id: int | None = Query(None, alias="locationId"),
                  designation_id: int | None = Query(None, alias="designationId"),
                  employment_type_id: int | None = Query(None, alias="employmentTypeId"),
                  employee_group_id: int | None = Query(None, alias="employeeGroupId"),
                  grade_id: int | None = Query(None, alias="gradeId"),
                  employee_status: str | None = Query(None, alias="employeeStatus"),
                  time_slot_id: int | None = Query(None, alias="timeSlotId"),
                  roster_group_id: int | None = Query(None, alias="rosterGroupId")) -> dict[str, Any]:
    """The planner's filters, named as the procedures take them."""
    return {"search": q, "employee_id": employee_id, "department_id": department_id, "branch_id": branch_id,
            "location_id": location_id, "designation_id": designation_id, "employment_type_id": employment_type_id,
            "employee_group_id": employee_group_id, "grade_id": grade_id, "status": employee_status,
            "time_slot_id": time_slot_id, "roster_group_id": roster_group_id}


# ---------------------------------------------------------------- the planner

@router.get("/schedules", response_model=BoardPage)
def board(tab: Tab = "all", from_date: date = Query(alias="from"), to_date: date = Query(alias="to"),
          filters: dict = Depends(board_filters), paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
          ctx: RequestContext = Depends(require("scheduling.schedules.view"))) -> dict:
    return scheduling_controller.board(db, ctx, tab, from_date, to_date, filters, paging)


@router.get("/schedules/year", response_model=YearPage)
def year(year_no: int = Query(alias="year"), tab: Tab = "all", filters: dict = Depends(board_filters),
         paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
         ctx: RequestContext = Depends(require("scheduling.schedules.view"))) -> dict:
    return scheduling_controller.year(db, ctx, tab, year_no, filters, paging)


@router.get("/schedules/export")
def export(tab: Tab = "all", from_date: date = Query(alias="from"), to_date: date = Query(alias="to"),
           filters: dict = Depends(board_filters), db: Db = Depends(get_db),
           ctx: RequestContext = Depends(require("scheduling.schedules.export"))) -> Response:
    text = scheduling_controller.export_csv(db, ctx, tab, from_date, to_date, filters)
    return Response(content=text, media_type="text/csv",
                    headers={"Content-Disposition": f'attachment; filename="schedule_{from_date}_{to_date}.csv"'})


@router.post("/schedules/batches", response_model=Item[ScheduleBatchOut], status_code=status.HTTP_201_CREATED)
def create_batch(body: ScheduleBatchIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("scheduling.schedules.create"))) -> dict:
    return scheduling_controller.create_batch(db, ctx, body)


@router.post("/schedules/default-shift", response_model=Item[ScheduleBatchOut], status_code=status.HTTP_201_CREATED)
def apply_default_shift(body: DefaultShiftIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("scheduling.schedules.create"))) -> dict:
    return scheduling_controller.apply_default_shift(db, ctx, body)


@router.post("/schedules/bulk-delete", response_model=Item[BulkDeleteOut])
def bulk_delete(body: BulkDeleteIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("scheduling.schedules.delete"))) -> dict:
    return scheduling_controller.bulk_delete(db, ctx, body)


@router.post("/schedules/bulk-edit", response_model=Item[BulkEditOut])
def bulk_edit(body: BulkEditIn, db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("scheduling.schedules.edit"))) -> dict:
    return scheduling_controller.bulk_edit(db, ctx, body)


@router.get("/schedules/{schedule_id}", response_model=Item[ScheduleOut])
def get_schedule(schedule_id: int, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("scheduling.schedules.view"))) -> dict:
    return scheduling_controller.get_schedule(db, ctx, schedule_id)


@router.post("/schedules", response_model=Item[ScheduleOut], status_code=status.HTTP_201_CREATED)
def create_schedule(body: ScheduleIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("scheduling.schedules.create"))) -> dict:
    return scheduling_controller.create_schedule(db, ctx, body)


@router.put("/schedules/{schedule_id}", response_model=Item[ScheduleOut])
def update_schedule(schedule_id: int, body: ScheduleIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("scheduling.schedules.edit"))) -> dict:
    return scheduling_controller.update_schedule(db, ctx, schedule_id, body)


@router.delete("/schedules/{schedule_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_schedule(schedule_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                    db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("scheduling.schedules.delete"))) -> Response:
    scheduling_controller.delete_schedule(db, ctx, schedule_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/schedules/{schedule_id}/swap", response_model=Item[ScheduleOut])
def swap(schedule_id: int, body: SwapIn, db: Db = Depends(get_db),
         ctx: RequestContext = Depends(require("scheduling.schedules.edit"))) -> dict:
    return scheduling_controller.swap(db, ctx, schedule_id, body)


# ---------------------------------------------------------------- pickers for the planner's forms

@router.get("/options/time-slots", response_model=OptionList)
def time_slot_options(db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require_any("scheduling.schedules.view",
                                                                "scheduling.settings.time_slots.view"))) -> dict:
    return scheduling_controller.time_slot_options(db, ctx)


@router.get("/options/break-types", response_model=OptionList)
def break_type_options(db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require_any("scheduling.schedules.view",
                                                                 "scheduling.settings.break_types.view"))) -> dict:
    return scheduling_controller.break_type_options(db, ctx)


@router.get("/options/roster-groups", response_model=OptionList)
def roster_group_options(db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require_any("scheduling.schedules.view",
                                                                   "roster.groups.view"))) -> dict:
    return scheduling_controller.roster_group_options(db, ctx)


# ---------------------------------------------------------------- settings: time slots

@router.get("/settings/time-slots", response_model=Paginated[TimeSlotOut])
def list_time_slots(q: str | None = None, is_flexible: bool | None = Query(None, alias="isFlexible"),
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("scheduling.settings.time_slots.view"))) -> dict:
    return scheduling_controller.list_time_slots(db, ctx, q, is_flexible, paging)


@router.get("/settings/time-slots/{slot_id}", response_model=Item[TimeSlotOut])
def get_time_slot(slot_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("scheduling.settings.time_slots.view"))) -> dict:
    return scheduling_controller.get_time_slot(db, ctx, slot_id)


@router.post("/settings/time-slots", response_model=Item[TimeSlotOut], status_code=status.HTTP_201_CREATED)
def create_time_slot(body: TimeSlotIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("scheduling.settings.time_slots.create"))) -> dict:
    return scheduling_controller.create_time_slot(db, ctx, body)


@router.put("/settings/time-slots/{slot_id}", response_model=Item[TimeSlotOut])
def update_time_slot(slot_id: int, body: TimeSlotIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("scheduling.settings.time_slots.edit"))) -> dict:
    return scheduling_controller.update_time_slot(db, ctx, slot_id, body)


@router.delete("/settings/time-slots/{slot_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_time_slot(slot_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                     db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("scheduling.settings.time_slots.delete"))) -> Response:
    scheduling_controller.delete_time_slot(db, ctx, slot_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- settings: break types

@router.get("/settings/break-types", response_model=Paginated[BreakTypeOut])
def list_break_types(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("scheduling.settings.break_types.view"))) -> dict:
    return scheduling_controller.list_break_types(db, ctx, q, paging)


@router.get("/settings/break-types/{type_id}", response_model=Item[BreakTypeOut])
def get_break_type(type_id: int, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("scheduling.settings.break_types.view"))) -> dict:
    return scheduling_controller.get_break_type(db, ctx, type_id)


@router.post("/settings/break-types", response_model=Item[BreakTypeOut], status_code=status.HTTP_201_CREATED)
def create_break_type(body: BreakTypeIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("scheduling.settings.break_types.create"))) -> dict:
    return scheduling_controller.create_break_type(db, ctx, body)


@router.put("/settings/break-types/{type_id}", response_model=Item[BreakTypeOut])
def update_break_type(type_id: int, body: BreakTypeIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("scheduling.settings.break_types.edit"))) -> dict:
    return scheduling_controller.update_break_type(db, ctx, type_id, body)


@router.delete("/settings/break-types/{type_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_break_type(type_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                      db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("scheduling.settings.break_types.delete"))) -> Response:
    scheduling_controller.delete_break_type(db, ctx, type_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- settings: rest days

@router.get("/settings/rest-days", response_model=Paginated[RestDayRuleOut])
def list_rest_day_rules(employee_id: int | None = Query(None, alias="employeeId"),
                        from_date: date | None = Query(None, alias="from"), to_date: date | None = Query(None, alias="to"),
                        paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("scheduling.settings.rest_days.view"))) -> dict:
    return scheduling_controller.list_rest_day_rules(db, ctx, employee_id, from_date, to_date, paging)


@router.post("/settings/rest-days/delete-range", response_model=Item[BulkDeleteOut])
def delete_rest_day_range(body: RestDayRangeDeleteIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("scheduling.settings.rest_days.delete"))) -> dict:
    return scheduling_controller.delete_rest_day_range(db, ctx, body)


@router.get("/settings/rest-days/{rule_id}", response_model=Item[RestDayRuleOut])
def get_rest_day_rule(rule_id: int, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("scheduling.settings.rest_days.view"))) -> dict:
    return scheduling_controller.get_rest_day_rule(db, ctx, rule_id)


@router.post("/settings/rest-days", response_model=Item[RestDayRuleOut], status_code=status.HTTP_201_CREATED)
def create_rest_day_rule(body: RestDayRuleIn, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("scheduling.settings.rest_days.create"))) -> dict:
    return scheduling_controller.create_rest_day_rule(db, ctx, body)


@router.put("/settings/rest-days/{rule_id}", response_model=Item[RestDayRuleOut])
def update_rest_day_rule(rule_id: int, body: RestDayRuleIn, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("scheduling.settings.rest_days.edit"))) -> dict:
    return scheduling_controller.update_rest_day_rule(db, ctx, rule_id, body)


@router.delete("/settings/rest-days/{rule_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_rest_day_rule(rule_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                         db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("scheduling.settings.rest_days.delete"))) -> Response:
    scheduling_controller.delete_rest_day_rule(db, ctx, rule_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- settings: holidays

@router.get("/settings/holidays", response_model=Paginated[HolidayOut])
def list_holidays(year_no: int | None = Query(None, alias="year"), q: str | None = None,
                  holiday_type: Literal["public", "local"] | None = Query(None, alias="holidayType"),
                  paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("scheduling.settings.holidays.view"))) -> dict:
    return scheduling_controller.list_holidays(db, ctx, year_no, q, holiday_type, paging)


@router.get("/settings/holidays/{holiday_id}", response_model=Item[HolidayOut])
def get_holiday(holiday_id: int, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("scheduling.settings.holidays.view"))) -> dict:
    return scheduling_controller.get_holiday(db, ctx, holiday_id)


@router.post("/settings/holidays", response_model=Item[HolidayOut], status_code=status.HTTP_201_CREATED)
def create_holiday(body: HolidayIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("scheduling.settings.holidays.create"))) -> dict:
    return scheduling_controller.create_holiday(db, ctx, body)


@router.put("/settings/holidays/{holiday_id}", response_model=Item[HolidayOut])
def update_holiday(holiday_id: int, body: HolidayIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("scheduling.settings.holidays.edit"))) -> dict:
    return scheduling_controller.update_holiday(db, ctx, holiday_id, body)


@router.delete("/settings/holidays/{holiday_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_holiday(holiday_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                   db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("scheduling.settings.holidays.delete"))) -> Response:
    scheduling_controller.delete_holiday(db, ctx, holiday_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
