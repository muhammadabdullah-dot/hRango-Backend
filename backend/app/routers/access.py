"""Users, roles, per-user grants and denials, sessions and the access change history
(Settings -> System User / User Group Permissions; Mini SRS 3.1)."""
from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import access_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, get_context, require
from app.schemas.access import (AuditOut, EffectivePermissionOut, EndedOut, OverrideIn, OverrideOut, OwnPasswordIn,
                                PasswordIn, PermissionOut, RoleCopyIn, RoleDetailOut, RoleIn, RoleOut,
                                RolePermissionsIn, RowVersionIn, SessionOut, UserDetailOut, UserIn, UserOut,
                                UserRolesIn)
from app.schemas.common import Item, Paginated

router = APIRouter(prefix="/access", tags=["access"])
NO_CONTENT = status.HTTP_204_NO_CONTENT


# ---------------------------------------------------------------- the catalogue

@router.get("/permissions", response_model=Item[list[PermissionOut]])
def list_permissions(db: Db = Depends(get_db), _: RequestContext = Depends(require("access.roles.view"))) -> dict:
    """Every tick the role screen offers, in screen order."""
    return c.list_permissions(db)


# ---------------------------------------------------------------- users

@router.get("/users", response_model=Paginated[UserOut])
def list_users(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
               role_id: int | None = Query(None, alias="roleId"), paging: PageParams = Depends(page_params),
               db: Db = Depends(get_db), ctx: RequestContext = Depends(require("access.users.view"))) -> dict:
    return c.list_users(db, ctx, q, is_active, role_id, paging)


@router.get("/users/{user_id}", response_model=Item[UserDetailOut])
def get_user(user_id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("access.users.view"))) -> dict:
    return c.get_user(db, ctx, user_id)


@router.post("/users", response_model=Item[UserDetailOut], status_code=status.HTTP_201_CREATED)
def create_user(body: UserIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("access.users.create"))) -> dict:
    return c.create_user(db, ctx, body)


@router.put("/users/{user_id}", response_model=Item[UserDetailOut])
def update_user(user_id: int, body: UserIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("access.users.edit"))) -> dict:
    return c.update_user(db, ctx, user_id, body)


@router.patch("/users/{user_id}/disable", response_model=Item[UserDetailOut])
def disable_user(user_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("access.users.delete"))) -> dict:
    """Switches the account off and ends its sessions. Accounts are never deleted (history keeps them)."""
    return c.set_user_active(db, ctx, user_id, False, body.row_version)


@router.patch("/users/{user_id}/enable", response_model=Item[UserDetailOut])
def enable_user(user_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("access.users.delete"))) -> dict:
    return c.set_user_active(db, ctx, user_id, True, body.row_version)


@router.put("/users/{user_id}/password", status_code=NO_CONTENT)
def set_user_password(user_id: int, body: PasswordIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("access.users.edit"))) -> Response:
    """Sets a new password and signs the user out everywhere."""
    c.set_user_password(db, ctx, user_id, body.password)
    return Response(status_code=NO_CONTENT)


@router.put("/users/{user_id}/roles", response_model=Item[UserDetailOut])
def set_user_roles(user_id: int, body: UserRolesIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("access.roles.assign"))) -> dict:
    """The user's roles in the active company, all at once."""
    return c.set_user_roles(db, ctx, user_id, body)


@router.get("/users/{user_id}/permissions", response_model=Item[list[EffectivePermissionOut]])
def effective_permissions(user_id: int, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("access.users.view"))) -> dict:
    """What the user holds in the active company: roles plus grants minus denials."""
    return c.effective_permissions(db, ctx, user_id)


@router.get("/users/{user_id}/overrides", response_model=Item[list[OverrideOut]])
def list_overrides(user_id: int, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("access.overrides.view"))) -> dict:
    return c.list_overrides(db, ctx, user_id)


@router.put("/users/{user_id}/overrides", response_model=Item[OverrideOut])
def save_override(user_id: int, body: OverrideIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("access.overrides.edit"))) -> dict:
    """Adds or replaces the user's grant or denial of one permission."""
    return c.save_override(db, ctx, user_id, body)


@router.delete("/users/{user_id}/overrides/{override_id}", status_code=NO_CONTENT)
def delete_override(user_id: int, override_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                    db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("access.overrides.edit"))) -> Response:
    c.delete_override(db, ctx, user_id, override_id, row_version)
    return Response(status_code=NO_CONTENT)


@router.patch("/users/{user_id}/sessions/end", response_model=Item[EndedOut])
def end_user_sessions(user_id: int, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("access.sessions.end_session"))) -> dict:
    return c.end_user_sessions(db, ctx, user_id)


# ---------------------------------------------------------------- the signed-in user

@router.post("/me/password", status_code=NO_CONTENT)
def change_own_password(body: OwnPasswordIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(get_context)) -> Response:
    """Change Password (profile menu): the user's other sessions end."""
    c.change_own_password(db, ctx, body.current_password, body.new_password)
    return Response(status_code=NO_CONTENT)


# ---------------------------------------------------------------- roles

@router.get("/roles", response_model=Paginated[RoleOut])
def list_roles(q: str | None = None, include_retired: bool = Query(False, alias="includeRetired"),
               paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("access.roles.view"))) -> dict:
    return c.list_roles(db, ctx, q, include_retired, paging)


@router.get("/roles/{role_id}", response_model=Item[RoleDetailOut])
def get_role(role_id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("access.roles.view"))) -> dict:
    return c.get_role(db, ctx, role_id)


@router.post("/roles", response_model=Item[RoleDetailOut], status_code=status.HTTP_201_CREATED)
def create_role(body: RoleIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("access.roles.create"))) -> dict:
    return c.create_role(db, ctx, body)


@router.put("/roles/{role_id}", response_model=Item[RoleDetailOut])
def update_role(role_id: int, body: RoleIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("access.roles.edit"))) -> dict:
    return c.update_role(db, ctx, role_id, body)


@router.put("/roles/{role_id}/permissions", response_model=Item[RoleDetailOut])
def save_role_permissions(role_id: int, body: RolePermissionsIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("access.roles.edit"))) -> dict:
    """The role's ticks, each with a scope (and units for selected_units). Replaces them all."""
    return c.save_role_permissions(db, ctx, role_id, body)


@router.post("/roles/{role_id}/copy", response_model=Item[RoleDetailOut], status_code=status.HTTP_201_CREATED)
def copy_role(role_id: int, body: RoleCopyIn, db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("access.roles.create"))) -> dict:
    return c.copy_role(db, ctx, role_id, body)


@router.patch("/roles/{role_id}/retire", response_model=Item[RoleDetailOut])
def retire_role(role_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("access.roles.delete"))) -> dict:
    return c.set_role_active(db, ctx, role_id, False, body.row_version)


@router.patch("/roles/{role_id}/restore", response_model=Item[RoleDetailOut])
def restore_role(role_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("access.roles.delete"))) -> dict:
    return c.set_role_active(db, ctx, role_id, True, body.row_version)


@router.delete("/roles/{role_id}", status_code=NO_CONTENT)
def delete_role(role_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("access.roles.delete"))) -> Response:
    c.delete_role(db, ctx, role_id, row_version)
    return Response(status_code=NO_CONTENT)


# ---------------------------------------------------------------- sessions and change history

@router.get("/sessions", response_model=Paginated[SessionOut])
def list_sessions(user_id: int | None = Query(None, alias="userId"),
                  active_only: bool = Query(True, alias="activeOnly"), paging: PageParams = Depends(page_params),
                  db: Db = Depends(get_db), ctx: RequestContext = Depends(require("access.sessions.view"))) -> dict:
    return c.list_sessions(db, ctx, user_id, active_only, paging)


@router.patch("/sessions/{session_id}/end", response_model=Item[EndedOut])
def end_session(session_id: int, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("access.sessions.end_session"))) -> dict:
    """Signs that device out on its next request."""
    return c.end_session(db, ctx, session_id)


@router.get("/audit", response_model=Paginated[AuditOut])
def list_audit(entity: str | None = None, entity_id: int | None = Query(None, alias="entityId"),
               paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("access.audit.view"))) -> dict:
    """Who changed which role, user, role assignment or grant, and when (ACC-15). entity: role or user."""
    return c.list_audit(db, ctx, entity, entity_id, paging)
