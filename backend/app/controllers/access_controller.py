"""HTTP shape for users, roles, grants and sessions."""
from collections import defaultdict
from typing import Any

from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.access import (AuditOut, EffectivePermissionOut, EndedOut, OverrideIn, OverrideOut, PermissionOut,
                                RefOut, RoleCopyIn, RoleDetailOut, RoleIn, RoleOut, RolePermissionsIn, RoleRef,
                                SessionOut, TickOut, UnitOut, UserDetailOut, UserIn, UserOut, UserRolesIn)
from app.schemas.common import paginated
from app.services import access_service as s


def _rv(row: dict[str, Any]) -> dict[str, Any]:
    return {**row, "row_version": row_version_out(row["row_version"])}


def _user(row: dict[str, Any]) -> UserOut:
    return UserOut(**_rv(row))


def _user_detail(sets: tuple[dict[str, Any], list[dict], list[dict]]) -> dict:
    user, roles, companies = sets
    return {"data": UserDetailOut(**_rv(user), roles=[RoleRef(**r) for r in roles],
                                  companies=[RefOut(**c) for c in companies])}


def _role(row: dict[str, Any]) -> RoleOut:
    return RoleOut(**_rv(row))


def _role_detail(sets: tuple[dict[str, Any], list[dict], list[dict]]) -> dict:
    role, ticks, units = sets
    by_code: dict[str, list[UnitOut]] = defaultdict(list)
    for u in units:
        by_code[u["code"]].append(UnitOut(**u))
    return {"data": RoleDetailOut(**_rv(role), permissions=[TickOut(**t, units=by_code[t["code"]]) for t in ticks])}


# ---------------------------------------------------------------- users

def list_users(db: Db, ctx: RequestContext, q: str | None, is_active: bool | None, role_id: int | None,
               paging: PageParams) -> dict:
    total, rows = s.list_users(db, ctx, q, is_active, role_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _user)


def get_user(db: Db, ctx: RequestContext, user_id: int) -> dict:
    return _user_detail(s.get_user(db, ctx, user_id))


def create_user(db: Db, ctx: RequestContext, body: UserIn) -> dict:
    return _user_detail(s.create_user(db, ctx, body.model_dump(by_alias=False, exclude={"row_version"})))


def update_user(db: Db, ctx: RequestContext, user_id: int, body: UserIn) -> dict:
    fields = body.model_dump(by_alias=False, exclude={"row_version", "password", "role_ids"})
    if "company_ids" not in body.model_fields_set:
        fields["company_ids"] = None
    return _user_detail(s.update_user(db, ctx, user_id, fields, row_version_in(body.row_version)))


def set_user_active(db: Db, ctx: RequestContext, user_id: int, active: bool, row_version: str) -> dict:
    return _user_detail(s.set_user_active(db, ctx, user_id, active, row_version_in(row_version)))


def set_user_roles(db: Db, ctx: RequestContext, user_id: int, body: UserRolesIn) -> dict:
    return _user_detail(s.set_user_roles(db, ctx, user_id, body.role_ids, row_version_in(body.row_version)))


def set_user_password(db: Db, ctx: RequestContext, user_id: int, password: str) -> None:
    s.set_user_password(db, ctx, user_id, password)


def change_own_password(db: Db, ctx: RequestContext, current: str, new: str) -> None:
    s.change_own_password(db, ctx, current, new)


def effective_permissions(db: Db, ctx: RequestContext, user_id: int) -> dict:
    rows = s.effective_permissions(db, ctx, user_id)
    return {"data": [EffectivePermissionOut(**{**r, "scopes": sorted(set((r["scopes"] or "").split(",")) - {""})})
                     for r in rows]}


# ---------------------------------------------------------------- roles

def list_permissions(db: Db) -> dict:
    return {"data": [PermissionOut(**r) for r in s.list_permissions(db)]}


def list_roles(db: Db, ctx: RequestContext, q: str | None, include_retired: bool, paging: PageParams) -> dict:
    total, rows = s.list_roles(db, ctx, q, include_retired, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _role)


def get_role(db: Db, ctx: RequestContext, role_id: int) -> dict:
    return _role_detail(s.get_role(db, ctx, role_id))


def create_role(db: Db, ctx: RequestContext, body: RoleIn) -> dict:
    return _role_detail(s.save_role(db, ctx, None, body.name, body.description, None))


def update_role(db: Db, ctx: RequestContext, role_id: int, body: RoleIn) -> dict:
    return _role_detail(s.save_role(db, ctx, role_id, body.name, body.description, row_version_in(body.row_version)))


def save_role_permissions(db: Db, ctx: RequestContext, role_id: int, body: RolePermissionsIn) -> dict:
    ticks = [t.model_dump(by_alias=False) for t in body.permissions]
    return _role_detail(s.save_role_permissions(db, ctx, role_id, ticks, row_version_in(body.row_version)))


def copy_role(db: Db, ctx: RequestContext, role_id: int, body: RoleCopyIn) -> dict:
    return _role_detail(s.copy_role(db, ctx, role_id, body.name))


def set_role_active(db: Db, ctx: RequestContext, role_id: int, active: bool, row_version: str) -> dict:
    return _role_detail(s.set_role_active(db, ctx, role_id, active, row_version_in(row_version)))


def delete_role(db: Db, ctx: RequestContext, role_id: int, row_version: str | None) -> None:
    s.delete_role(db, ctx, role_id, row_version_in(row_version))


# ---------------------------------------------------------------- grants and denials

def list_overrides(db: Db, ctx: RequestContext, user_id: int) -> dict:
    return {"data": [OverrideOut(**_rv(r)) for r in s.list_overrides(db, ctx, user_id)]}


def save_override(db: Db, ctx: RequestContext, user_id: int, body: OverrideIn) -> dict:
    return {"data": OverrideOut(**_rv(s.save_override(db, ctx, user_id, body.model_dump(by_alias=False))))}


def delete_override(db: Db, ctx: RequestContext, user_id: int, override_id: int, row_version: str | None) -> None:
    s.delete_override(db, ctx, user_id, override_id, row_version_in(row_version))


# ---------------------------------------------------------------- sessions and history

def list_sessions(db: Db, ctx: RequestContext, user_id: int | None, active_only: bool, paging: PageParams) -> dict:
    total, rows = s.list_sessions(db, ctx, user_id, active_only, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: SessionOut(**r))


def end_session(db: Db, ctx: RequestContext, session_id: int) -> dict:
    return {"data": EndedOut(ended=s.end_session(db, ctx, session_id))}


def end_user_sessions(db: Db, ctx: RequestContext, user_id: int) -> dict:
    return {"data": EndedOut(ended=s.end_user_sessions(db, ctx, user_id))}


def list_audit(db: Db, ctx: RequestContext, entity: str | None, entity_id: int | None, paging: PageParams) -> dict:
    total, rows = s.list_audit(db, ctx, entity, entity_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: AuditOut(**r))
