"""Warning: policies (with their rules per clock event), penalties, warnings raised from processed
time sheets, and the History of policy changes."""
from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import warning_controller
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.warning import (HistoryOut, PenaltiesIn, PenaltyListOut, RaiseIn, RaiseOut, WarningOut,
                                 WarningPolicyIn, WarningPolicyOut)

router = APIRouter(prefix="/warning", tags=["warning"])

AppliesTo = Literal["late_arrival", "early_departure", "overtime", "half_day_leave"]


@router.get("/policies", response_model=Paginated[WarningPolicyOut])
def list_policies(q: str | None = None, applies_to: AppliesTo | None = Query(None, alias="appliesTo"),
                  paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("warning.settings.policies.view"))) -> dict:
    return warning_controller.list_policies(db, ctx, q, applies_to, paging)


@router.get("/policies/{policy_id}", response_model=Item[WarningPolicyOut])
def get_policy(policy_id: int, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("warning.settings.policies.view"))) -> dict:
    return warning_controller.get_policy(db, ctx, policy_id)


@router.post("/policies", response_model=Item[WarningPolicyOut], status_code=status.HTTP_201_CREATED)
def create_policy(body: WarningPolicyIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("warning.settings.policies.create"))) -> dict:
    return warning_controller.create_policy(db, ctx, body)


@router.put("/policies/{policy_id}", response_model=Item[WarningPolicyOut])
def update_policy(policy_id: int, body: WarningPolicyIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("warning.settings.policies.edit"))) -> dict:
    return warning_controller.update_policy(db, ctx, policy_id, body)


@router.delete("/policies/{policy_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_policy(policy_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                  db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("warning.settings.policies.delete"))) -> Response:
    warning_controller.delete_policy(db, ctx, policy_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put("/policies/{policy_id}/penalties", response_model=Item[WarningPolicyOut])
def save_penalties(policy_id: int, body: PenaltiesIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("warning.settings.penalties.edit"))) -> dict:
    return warning_controller.save_penalties(db, ctx, policy_id, body)


@router.get("/penalties", response_model=Paginated[PenaltyListOut])
def list_penalties(policy_id: int | None = Query(None, alias="policyId"), paging: PageParams = Depends(page_params),
                   db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("warning.settings.penalties.view"))) -> dict:
    return warning_controller.list_penalties(db, ctx, policy_id, paging)


@router.get("/warnings", response_model=Paginated[WarningOut])
def list_warnings(employee_id: int | None = Query(None, alias="employeeId"),
                  policy_id: int | None = Query(None, alias="policyId"),
                  applies_to: AppliesTo | None = Query(None, alias="appliesTo"),
                  from_date: date | None = Query(None, alias="fromDate"),
                  to_date: date | None = Query(None, alias="toDate"), q: str | None = None,
                  paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("warning.warnings.view"))) -> dict:
    return warning_controller.list_warnings(db, ctx, employee_id, policy_id, applies_to, from_date, to_date, q, paging)


@router.post("/warnings/process", response_model=Item[RaiseOut])
def raise_warnings(body: RaiseIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("warning.warnings.process"))) -> dict:
    return warning_controller.raise_warnings(db, ctx, body)


@router.get("/history", response_model=Paginated[HistoryOut])
def list_history(policy_id: int | None = Query(None, alias="policyId"), paging: PageParams = Depends(page_params),
                 db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("warning.settings.history.view"))) -> dict:
    return warning_controller.list_history(db, ctx, policy_id, paging)
