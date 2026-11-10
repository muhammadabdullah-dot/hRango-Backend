from typing import Any

from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.platform_auth import StaffContext
from app.repos import platform_repo
from app.schemas.common import paginated
from app.schemas.platform import StaffAuditOut, StaffIn, StaffLoginIn, StaffMe, StaffOut, StaffPasswordIn, StaffSession
from app.services import platform_service as s


def _staff(row: dict[str, Any]) -> StaffOut:
    return StaffOut(**{**row, "row_version": row_version_out(row["row_version"])})


def login(db: Db, body: StaffLoginIn, device: str | None, ip_address: str | None) -> dict:
    token, account = s.login(db, body.email, body.password, device, ip_address)
    return {"data": StaffSession(token=token, staff=StaffMe(**account))}


def me(ctx: StaffContext) -> dict:
    return {"data": StaffMe(id=ctx.staff_id, email=ctx.email, display_name=ctx.display_name, role=ctx.role)}


def logout(db: Db, ctx: StaffContext) -> None:
    platform_repo.session_end(db, ctx.session_id)
    platform_repo.audit(db, ctx.staff_id, "signed_out")


def list_staff(db: Db, q: str | None, paging: PageParams) -> dict:
    total, rows = platform_repo.list_staff(db, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _staff)


def get_staff(db: Db, staff_id: int) -> dict:
    return {"data": _staff(platform_repo.get_staff(db, staff_id))}


def add_staff(db: Db, ctx: StaffContext, body: StaffIn) -> dict:
    return {"data": _staff(s.add_staff(db, ctx.staff_id, body.model_dump(by_alias=False)))}


def update_staff(db: Db, ctx: StaffContext, staff_id: int, body: StaffIn) -> dict:
    rv = row_version_in(body.row_version)
    return {"data": _staff(s.update_staff(db, ctx.staff_id, staff_id, body.model_dump(by_alias=False), rv))}


def set_password(db: Db, ctx: StaffContext, staff_id: int, body: StaffPasswordIn) -> None:
    s.set_password(db, ctx.staff_id, staff_id, body.password)


def list_audit(db: Db, paging: PageParams) -> dict:
    total, rows = platform_repo.list_audit(db, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: StaffAuditOut(**r))
