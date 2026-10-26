from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import roster_controller
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.roster import (DiscontinueIn, EnrolIn, EnrolmentEditIn, EnrolmentList, EnrolmentOut, RosterGroupIn,
                                RosterGroupOut)

router = APIRouter(prefix="/roster", tags=["roster"])


@router.get("/groups", response_model=Paginated[RosterGroupOut])
def list_groups(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
                paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("roster.groups.view"))) -> dict:
    return roster_controller.list_groups(db, ctx, q, is_active, paging)


@router.get("/groups/{group_id}", response_model=Item[RosterGroupOut])
def get_group(group_id: int, db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("roster.groups.view"))) -> dict:
    return roster_controller.get_group(db, ctx, group_id)


@router.post("/groups", response_model=Item[RosterGroupOut], status_code=status.HTTP_201_CREATED)
def create_group(body: RosterGroupIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("roster.groups.create"))) -> dict:
    return roster_controller.create_group(db, ctx, body)


@router.put("/groups/{group_id}", response_model=Item[RosterGroupOut])
def update_group(group_id: int, body: RosterGroupIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("roster.groups.edit"))) -> dict:
    return roster_controller.update_group(db, ctx, group_id, body)


@router.delete("/groups/{group_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_group(group_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("roster.groups.delete"))) -> Response:
    roster_controller.delete_group(db, ctx, group_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/groups/{group_id}/enrolments", response_model=Paginated[EnrolmentOut])
def list_enrolments(group_id: int, status_: Literal["active", "discontinued"] | None = Query(None, alias="status"),
                    q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("roster.enrolments.view"))) -> dict:
    return roster_controller.list_enrolments(db, ctx, group_id, status_, q, paging)


@router.post("/groups/{group_id}/enrolments", response_model=EnrolmentList, status_code=status.HTTP_201_CREATED)
def enrol(group_id: int, body: EnrolIn, db: Db = Depends(get_db),
          ctx: RequestContext = Depends(require("roster.enrolments.enroll"))) -> dict:
    return roster_controller.enrol(db, ctx, group_id, body)


@router.get("/enrolments/{enrolment_id}", response_model=Item[EnrolmentOut])
def get_enrolment(enrolment_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("roster.enrolments.view"))) -> dict:
    return roster_controller.get_enrolment(db, ctx, enrolment_id)


@router.put("/enrolments/{enrolment_id}", response_model=Item[EnrolmentOut])
def update_enrolment(enrolment_id: int, body: EnrolmentEditIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("roster.enrolments.edit"))) -> dict:
    return roster_controller.update_enrolment(db, ctx, enrolment_id, body)


@router.patch("/enrolments/{enrolment_id}/discontinue", response_model=Item[EnrolmentOut])
def discontinue(enrolment_id: int, body: DiscontinueIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("roster.enrolments.edit"))) -> dict:
    return roster_controller.discontinue(db, ctx, enrolment_id, body)


@router.delete("/enrolments/{enrolment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_enrolment(enrolment_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                     db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("roster.enrolments.delete"))) -> Response:
    roster_controller.delete_enrolment(db, ctx, enrolment_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
