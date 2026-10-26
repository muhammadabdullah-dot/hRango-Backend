"""HTTP shape for the Warning screens: envelopes, row versions as text, rows to response models."""
import json
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.warning import (HistoryOut, PenaltiesIn, PenaltyListOut, RaiseIn, RaiseOut, WarningOut,
                                 WarningPolicyIn, WarningPolicyOut)
from app.services import warning_service


def _policy(row: dict[str, Any]) -> WarningPolicyOut:
    return WarningPolicyOut(**{**row, "row_version": row_version_out(row["row_version"]),
                               "rules": json.loads(row["rules"] or "[]"),
                               "penalties": json.loads(row["penalties"] or "[]")})


def list_policies(db: Db, ctx: RequestContext, q: str | None, applies_to: str | None, paging: PageParams) -> dict:
    total, rows = warning_service.list_policies(db, ctx, q, applies_to, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _policy)


def get_policy(db: Db, ctx: RequestContext, policy_id: int) -> dict:
    return {"data": _policy(warning_service.get_policy(db, ctx, policy_id))}


def create_policy(db: Db, ctx: RequestContext, body: WarningPolicyIn) -> dict:
    return {"data": _policy(warning_service.save_policy(db, ctx, None, body, None))}


def update_policy(db: Db, ctx: RequestContext, policy_id: int, body: WarningPolicyIn) -> dict:
    return {"data": _policy(warning_service.save_policy(db, ctx, policy_id, body, row_version_in(body.row_version)))}


def delete_policy(db: Db, ctx: RequestContext, policy_id: int, row_version: str | None) -> None:
    warning_service.delete_policy(db, ctx, policy_id, row_version_in(row_version))


def save_penalties(db: Db, ctx: RequestContext, policy_id: int, body: PenaltiesIn) -> dict:
    row = warning_service.save_penalties(db, ctx, policy_id, body.penalties, row_version_in(body.row_version))
    return {"data": _policy(row)}


def list_penalties(db: Db, ctx: RequestContext, policy_id: int | None, paging: PageParams) -> dict:
    total, rows = warning_service.list_penalties(db, ctx, policy_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: PenaltyListOut(**r))


def list_warnings(db: Db, ctx: RequestContext, employee_id: int | None, policy_id: int | None,
                  applies_to: str | None, from_date: date | None, to_date: date | None, q: str | None,
                  paging: PageParams) -> dict:
    total, rows = warning_service.list_warnings(db, ctx, employee_id, policy_id, applies_to, from_date, to_date, q,
                                                paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: WarningOut(**r))


def raise_warnings(db: Db, ctx: RequestContext, body: RaiseIn) -> dict:
    row = warning_service.raise_warnings(db, ctx, body.from_date, body.to_date, body.employee_id,
                                         body.warning_policy_id)
    return {"data": RaiseOut(**row)}


def list_history(db: Db, ctx: RequestContext, policy_id: int | None, paging: PageParams) -> dict:
    total, rows = warning_service.list_history(db, ctx, policy_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: HistoryOut(**r))
