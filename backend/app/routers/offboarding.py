from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import offboarding_controller
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.offboarding import (ActiveChecklistFieldOut, ChecklistAnswersIn, ChecklistIn, ChecklistOut,
                                     EndOfEmploymentIn, EndOfEmploymentOut, EndOfEmploymentRowOut, RehireIn,
                                     RowVersionIn)

router = APIRouter(prefix="/offboarding", tags=["offboarding"])


# --- End of employment (All / Pending / Completed is the status filter) --------------------------

@router.get("/end-of-employment", response_model=Paginated[EndOfEmploymentRowOut])
def list_end_of_employment(q: str | None = None,
                           record_status: Literal["pending", "completed"] | None = Query(None, alias="status"),
                           employee_id: int | None = Query(None, alias="employeeId"),
                           department_id: int | None = Query(None, alias="departmentId"),
                           branch_id: int | None = Query(None, alias="branchId"),
                           location_id: int | None = Query(None, alias="locationId"),
                           designation_id: int | None = Query(None, alias="designationId"),
                           serve_notice: bool | None = Query(None, alias="serveNotice"),
                           from_date: date | None = Query(None, alias="from"),
                           to_date: date | None = Query(None, alias="to"),
                           paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("offboarding.end_of_employment.view"))) -> dict:
    filters = {"search": q, "status": record_status, "employee_id": employee_id, "department_id": department_id,
               "branch_id": branch_id, "location_id": location_id, "designation_id": designation_id,
               "serve_notice": serve_notice, "from_date": from_date, "to_date": to_date}
    return offboarding_controller.list_end_of_employment(db, ctx, filters, paging)


@router.get("/end-of-employment/checklist-fields", response_model=Item[list[ActiveChecklistFieldOut]])
def active_checklist_fields(db: Db = Depends(get_db),
                            ctx: RequestContext = Depends(require("offboarding.end_of_employment.view"))) -> dict:
    return offboarding_controller.active_checklist_fields(db, ctx)


@router.get("/end-of-employment/{record_id}", response_model=Item[EndOfEmploymentOut])
def get_end_of_employment(record_id: int, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("offboarding.end_of_employment.view"))) -> dict:
    return offboarding_controller.get_end_of_employment(db, ctx, record_id)


@router.post("/end-of-employment", response_model=Item[EndOfEmploymentOut], status_code=status.HTTP_201_CREATED)
def create_end_of_employment(body: EndOfEmploymentIn, db: Db = Depends(get_db),
                             ctx: RequestContext = Depends(require("offboarding.end_of_employment.create"))) -> dict:
    return offboarding_controller.create_end_of_employment(db, ctx, body)


@router.put("/end-of-employment/{record_id}", response_model=Item[EndOfEmploymentOut])
def update_end_of_employment(record_id: int, body: EndOfEmploymentIn, db: Db = Depends(get_db),
                             ctx: RequestContext = Depends(require("offboarding.end_of_employment.edit"))) -> dict:
    return offboarding_controller.update_end_of_employment(db, ctx, record_id, body)


@router.put("/end-of-employment/{record_id}/checklist", response_model=Item[EndOfEmploymentOut])
def save_checklist_answers(record_id: int, body: ChecklistAnswersIn, db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("offboarding.end_of_employment.edit"))) -> dict:
    return offboarding_controller.save_checklist_answers(db, ctx, record_id, body)


@router.patch("/end-of-employment/{record_id}/complete", response_model=Item[EndOfEmploymentOut])
def complete_end_of_employment(record_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                               ctx: RequestContext = Depends(require("offboarding.end_of_employment.edit"))) -> dict:
    return offboarding_controller.complete_end_of_employment(db, ctx, record_id, body.row_version)


@router.patch("/end-of-employment/{record_id}/rehire", response_model=Item[EndOfEmploymentOut])
def rehire(record_id: int, body: RehireIn, db: Db = Depends(get_db),
           ctx: RequestContext = Depends(require("offboarding.rehire.process"))) -> dict:
    return offboarding_controller.rehire(db, ctx, record_id, body)


@router.delete("/end-of-employment/{record_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_end_of_employment(record_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                             db: Db = Depends(get_db),
                             ctx: RequestContext = Depends(require("offboarding.end_of_employment.delete"))) -> Response:
    offboarding_controller.delete_end_of_employment(db, ctx, record_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Settings -> Off Boarding Checklist ----------------------------------------------------------

@router.get("/settings/checklists", response_model=Paginated[ChecklistOut])
def list_checklists(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("offboarding.settings.checklist.view"))) -> dict:
    return offboarding_controller.list_checklists(db, ctx, q, is_active, paging)


@router.get("/settings/checklists/{checklist_id}", response_model=Item[ChecklistOut])
def get_checklist(checklist_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("offboarding.settings.checklist.view"))) -> dict:
    return offboarding_controller.get_checklist(db, ctx, checklist_id)


@router.post("/settings/checklists", response_model=Item[ChecklistOut], status_code=status.HTTP_201_CREATED)
def create_checklist(body: ChecklistIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("offboarding.settings.checklist.create"))) -> dict:
    return offboarding_controller.create_checklist(db, ctx, body)


@router.put("/settings/checklists/{checklist_id}", response_model=Item[ChecklistOut])
def update_checklist(checklist_id: int, body: ChecklistIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("offboarding.settings.checklist.edit"))) -> dict:
    return offboarding_controller.update_checklist(db, ctx, checklist_id, body)


@router.delete("/settings/checklists/{checklist_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_checklist(checklist_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                     db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("offboarding.settings.checklist.delete"))) -> Response:
    offboarding_controller.delete_checklist(db, ctx, checklist_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
