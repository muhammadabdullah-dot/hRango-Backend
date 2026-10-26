"""Leaves: settings (general, leave types, policies and enrolment), balances and the leave ledger,
allotment and carry forward, leave encashment, and the My Leaves / Leave Applications lists.
Applying for leave and deciding on it are requests: POST /api/requests/... (the requests module)."""
from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import leaves_controller
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.leaves import (AllotmentIn, AllotmentOut, ApplicationCountsOut, BalanceOut, CarryForwardIn,
                                CarryForwardOut, EncashmentDetailOut, EncashmentIn, EncashmentOut,
                                EncashmentUpdateIn, EnrolIn, EnrolledEmployeeOut, LeaveApplicationDetailOut,
                                LeaveApplicationOut, LeavePolicyIn, LeavePolicyOut, LeaveSettingsIn,
                                LeaveSettingsOut, LeaveTypeIn, LeaveTypeOut, LedgerEntryIn, LedgerEntryOut)

router = APIRouter(prefix="/leaves", tags=["leaves"])

Tab = Literal["my", "subordinates", "all"]
Status = Literal["pending", "approved", "rejected", "cancelling", "cancelled"]


# --- General settings ------------------------------------------------------------------------------

@router.get("/settings", response_model=Item[LeaveSettingsOut])
def get_settings(db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("leaves.settings.general.view"))) -> dict:
    return leaves_controller.get_settings(db, ctx)


@router.put("/settings", response_model=Item[LeaveSettingsOut])
def save_settings(body: LeaveSettingsIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("leaves.settings.general.edit"))) -> dict:
    return leaves_controller.save_settings(db, ctx, body)


# --- Leave types -----------------------------------------------------------------------------------

@router.get("/types", response_model=Paginated[LeaveTypeOut])
def list_types(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
               paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("leaves.settings.types.view"))) -> dict:
    return leaves_controller.list_types(db, ctx, q, is_active, paging)


@router.get("/types/{type_id}", response_model=Item[LeaveTypeOut])
def get_type(type_id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("leaves.settings.types.view"))) -> dict:
    return leaves_controller.get_type(db, ctx, type_id)


@router.post("/types", response_model=Item[LeaveTypeOut], status_code=status.HTTP_201_CREATED)
def create_type(body: LeaveTypeIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("leaves.settings.types.create"))) -> dict:
    return leaves_controller.create_type(db, ctx, body)


@router.put("/types/{type_id}", response_model=Item[LeaveTypeOut])
def update_type(type_id: int, body: LeaveTypeIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("leaves.settings.types.edit"))) -> dict:
    return leaves_controller.update_type(db, ctx, type_id, body)


@router.delete("/types/{type_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_type(type_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("leaves.settings.types.delete"))) -> Response:
    leaves_controller.delete_type(db, ctx, type_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Leave policies --------------------------------------------------------------------------------

@router.get("/policies", response_model=Paginated[LeavePolicyOut])
def list_policies(q: str | None = None, kind: Literal["distribution", "half_short"] | None = None,
                  paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("leaves.settings.policies.view"))) -> dict:
    return leaves_controller.list_policies(db, ctx, q, kind, paging)


@router.get("/policies/{policy_id}", response_model=Item[LeavePolicyOut])
def get_policy(policy_id: int, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("leaves.settings.policies.view"))) -> dict:
    return leaves_controller.get_policy(db, ctx, policy_id)


@router.post("/policies", response_model=Item[LeavePolicyOut], status_code=status.HTTP_201_CREATED)
def create_policy(body: LeavePolicyIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("leaves.settings.policies.create"))) -> dict:
    return leaves_controller.create_policy(db, ctx, body)


@router.put("/policies/{policy_id}", response_model=Item[LeavePolicyOut])
def update_policy(policy_id: int, body: LeavePolicyIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("leaves.settings.policies.edit"))) -> dict:
    return leaves_controller.update_policy(db, ctx, policy_id, body)


@router.delete("/policies/{policy_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_policy(policy_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                  db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("leaves.settings.policies.delete"))) -> Response:
    leaves_controller.delete_policy(db, ctx, policy_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/policies/{policy_id}/employees", response_model=Paginated[EnrolledEmployeeOut])
def list_enrolled(policy_id: int, q: str | None = None, paging: PageParams = Depends(page_params),
                  db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("leaves.settings.policies.view"))) -> dict:
    return leaves_controller.list_enrolled(db, ctx, policy_id, q, paging)


@router.post("/policies/{policy_id}/employees", response_model=Item[LeavePolicyOut])
def enrol(policy_id: int, body: EnrolIn, db: Db = Depends(get_db),
          ctx: RequestContext = Depends(require("leaves.settings.policies.enroll"))) -> dict:
    return leaves_controller.enrol(db, ctx, policy_id, body.employee_ids)


@router.delete("/policies/{policy_id}/employees/{employee_id}", status_code=status.HTTP_204_NO_CONTENT)
def unenrol(policy_id: int, employee_id: int, db: Db = Depends(get_db),
            ctx: RequestContext = Depends(require("leaves.settings.policies.enroll"))) -> Response:
    leaves_controller.unenrol(db, ctx, policy_id, employee_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Balances, ledger, allotment, carry forward ----------------------------------------------------

@router.get("/balances", response_model=Paginated[BalanceOut])
def list_balances(employee_id: int | None = Query(None, alias="employeeId"),
                  leave_type_id: int | None = Query(None, alias="leaveTypeId"),
                  as_of: date | None = Query(None, alias="asOf"), q: str | None = None,
                  paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("leaves.balances.view"))) -> dict:
    return leaves_controller.list_balances(db, ctx, employee_id, leave_type_id, as_of, q, paging)


@router.get("/ledger", response_model=Paginated[LedgerEntryOut])
def list_ledger(employee_id: int | None = Query(None, alias="employeeId"),
                leave_type_id: int | None = Query(None, alias="leaveTypeId"),
                fiscal_year: int | None = Query(None, alias="fiscalYear"), reason: str | None = None,
                paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("leaves.balances.view"))) -> dict:
    return leaves_controller.list_ledger(db, ctx, employee_id, leave_type_id, fiscal_year, reason, paging)


@router.post("/ledger", response_model=Item[LedgerEntryOut], status_code=status.HTTP_201_CREATED)
def add_ledger_entry(body: LedgerEntryIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("leaves.balances.edit"))) -> dict:
    return leaves_controller.add_ledger_entry(db, ctx, body)


@router.post("/allotment/process", response_model=Item[AllotmentOut])
def process_allotment(body: AllotmentIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("leaves.allotment.process"))) -> dict:
    return leaves_controller.process_allotment(db, ctx, body)


@router.post("/carry-forward/process", response_model=Item[CarryForwardOut])
def process_carry_forward(body: CarryForwardIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("leaves.allotment.process"))) -> dict:
    return leaves_controller.process_carry_forward(db, ctx, body)


# --- Leave applications (My Leaves / Leave Applications) -------------------------------------------

def _application_filters(status_: Status | None = Query(None, alias="status"),
                         leave_type_id: int | None = Query(None, alias="leaveTypeId"),
                         employee_id: int | None = Query(None, alias="employeeId"),
                         department_id: int | None = Query(None, alias="departmentId"),
                         from_date: date | None = Query(None, alias="fromDate"),
                         to_date: date | None = Query(None, alias="toDate"), q: str | None = None) -> dict:
    return {"status": status_, "leave_type_id": leave_type_id, "employee_id": employee_id,
            "department_id": department_id, "from_date": from_date, "to_date": to_date, "search": q}


@router.get("/applications", response_model=Paginated[LeaveApplicationOut])
def list_applications(tab: Tab = "all", filters: dict = Depends(_application_filters),
                      paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("leaves.applications.view"))) -> dict:
    return leaves_controller.list_applications(db, ctx, tab, filters, paging)


@router.get("/applications/counts", response_model=Item[ApplicationCountsOut])
def count_applications(tab: Tab = "all", filters: dict = Depends(_application_filters), db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("leaves.applications.view"))) -> dict:
    return leaves_controller.count_applications(db, ctx, tab, filters)


@router.get("/applications/{application_id}", response_model=Item[LeaveApplicationDetailOut])
def get_application(application_id: int, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("leaves.applications.view"))) -> dict:
    return leaves_controller.get_application(db, ctx, application_id)


# --- Leave encashment ------------------------------------------------------------------------------

@router.get("/encashments", response_model=Paginated[EncashmentOut])
def list_encashments(leave_type_id: int | None = Query(None, alias="leaveTypeId"),
                     fiscal_year: int | None = Query(None, alias="fiscalYear"),
                     employee_id: int | None = Query(None, alias="employeeId"),
                     mode: Literal["payroll", "manual"] | None = None,
                     paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("leaves.encashments.view"))) -> dict:
    return leaves_controller.list_encashments(db, ctx, leave_type_id, fiscal_year, employee_id, mode, paging)


@router.get("/encashments/{encashment_id}", response_model=Item[EncashmentDetailOut])
def get_encashment(encashment_id: int, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("leaves.encashments.view"))) -> dict:
    return leaves_controller.get_encashment(db, ctx, encashment_id)


@router.post("/encashments", response_model=Item[EncashmentDetailOut], status_code=status.HTTP_201_CREATED)
def create_encashment(body: EncashmentIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("leaves.encashments.process"))) -> dict:
    return leaves_controller.create_encashment(db, ctx, body)


@router.put("/encashments/{encashment_id}", response_model=Item[EncashmentDetailOut])
def update_encashment(encashment_id: int, body: EncashmentUpdateIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("leaves.encashments.edit"))) -> dict:
    return leaves_controller.update_encashment(db, ctx, encashment_id, body)


@router.delete("/encashments/{encashment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_encashment(encashment_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                      db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("leaves.encashments.delete"))) -> Response:
    leaves_controller.delete_encashment(db, ctx, encashment_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
