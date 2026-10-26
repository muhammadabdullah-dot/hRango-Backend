"""HTTP shape for the roster screens: envelopes, row versions as text, rows to response models."""
from typing import Any

from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.roster import (DiscontinueIn, EnrolIn, EnrolmentEditIn, EnrolmentOut, RosterDayOut, RosterGroupIn,
                                RosterGroupOut)
from app.services import roster_service


def _group(row: dict[str, Any], days: list[dict[str, Any]] | None = None) -> RosterGroupOut:
    return RosterGroupOut(**{**row, "row_version": row_version_out(row["row_version"]),
                             "days": [RosterDayOut(**d) for d in days or []]})


def _enrolment(row: dict[str, Any]) -> EnrolmentOut:
    return EnrolmentOut(**{**row, "row_version": row_version_out(row["row_version"])})


def list_groups(db: Db, ctx: RequestContext, q: str | None, is_active: bool | None, paging: PageParams) -> dict:
    total, rows = roster_service.list_groups(db, ctx, q, is_active, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _group)


def get_group(db: Db, ctx: RequestContext, group_id: int) -> dict:
    return {"data": _group(*roster_service.get_group(db, ctx, group_id))}


def _save_group(db: Db, ctx: RequestContext, group_id: int | None, body: RosterGroupIn,
                row_version: bytes | None) -> dict:
    days = [d.model_dump(by_alias=False) for d in body.days]
    row, days = roster_service.save_group(db, ctx, group_id, body.title, body.from_date, body.to_date,
                                          body.description, body.is_active, days, row_version)
    return {"data": _group(row, days)}


def create_group(db: Db, ctx: RequestContext, body: RosterGroupIn) -> dict:
    return _save_group(db, ctx, None, body, None)


def update_group(db: Db, ctx: RequestContext, group_id: int, body: RosterGroupIn) -> dict:
    return _save_group(db, ctx, group_id, body, row_version_in(body.row_version))


def delete_group(db: Db, ctx: RequestContext, group_id: int, row_version: str | None) -> None:
    roster_service.delete_group(db, ctx, group_id, row_version_in(row_version))


def list_enrolments(db: Db, ctx: RequestContext, group_id: int, status: str | None, q: str | None,
                    paging: PageParams) -> dict:
    total, rows = roster_service.list_enrolments(db, ctx, group_id, status, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _enrolment)


def get_enrolment(db: Db, ctx: RequestContext, enrolment_id: int) -> dict:
    return {"data": _enrolment(roster_service.get_enrolment(db, ctx, enrolment_id))}


def enrol(db: Db, ctx: RequestContext, group_id: int, body: EnrolIn) -> dict:
    rows = roster_service.enrol(db, ctx, group_id, sorted(set(body.employee_ids)), body.start_date, body.end_date)
    return {"data": [_enrolment(r) for r in rows]}


def update_enrolment(db: Db, ctx: RequestContext, enrolment_id: int, body: EnrolmentEditIn) -> dict:
    row = roster_service.save_enrolment(db, ctx, enrolment_id, body.start_date, body.end_date,
                                        row_version_in(body.row_version))
    return {"data": _enrolment(row)}


def discontinue(db: Db, ctx: RequestContext, enrolment_id: int, body: DiscontinueIn) -> dict:
    row = roster_service.discontinue(db, ctx, enrolment_id, body.end_date, row_version_in(body.row_version))
    return {"data": _enrolment(row)}


def delete_enrolment(db: Db, ctx: RequestContext, enrolment_id: int, row_version: str | None) -> None:
    roster_service.delete_enrolment(db, ctx, enrolment_id, row_version_in(row_version))
