"""Users, roles, grants and sessions (Mini SRS 3.1). ACC-11 is enforced in the procedures, where
the actor's effective grants are: nobody grants what they do not hold, changes their own roles or
grants, or switches themselves off; only a system administrator makes or changes another one.
These are company-wide administration screens, so the scope a permission is held with does not
narrow them."""
from typing import Any

from app.core.db import Db
from app.core.errors import AppError, forbidden, invalid
from app.core.permissions import CODES
from app.core.security import hash_password, verify_password
from app.middlewares.auth import RequestContext
from app.repos import access_repo, auth_repo


def _holds(db: Db, ctx: RequestContext, code: str) -> bool:
    return bool(auth_repo.permission_check(db, ctx.company_id, ctx.user_id, code)["allowed"])


def _check_password(password: str) -> None:
    if not any(ch.isalpha() for ch in password) or not any(ch.isdigit() for ch in password):
        raise invalid("Use at least 8 characters with letters and digits.", "password")


# ---------------------------------------------------------------- users

def list_users(db: Db, ctx: RequestContext, search: str | None, is_active: bool | None, role_id: int | None,
               page: int, page_size: int):
    return access_repo.list_users(db, ctx.company_id, search, is_active, role_id, page, page_size)


def get_user(db: Db, ctx: RequestContext, user_id: int):
    return access_repo.get_user(db, ctx.company_id, user_id)


def create_user(db: Db, ctx: RequestContext, f: dict[str, Any]):
    if not f.get("password"):
        raise invalid("A password is required for a new user.", "password")
    _check_password(f["password"])
    if f.get("role_ids") and not _holds(db, ctx, "access.roles.assign"):
        raise forbidden("You may not give roles to users.")
    return access_repo.save_user(db, ctx.company_id, ctx.user_id, None, f, hash_password(f["password"]), None)


def update_user(db: Db, ctx: RequestContext, user_id: int, f: dict[str, Any], row_version: bytes):
    if user_id == ctx.user_id and not f.get("is_active", True):
        raise forbidden("You cannot switch off your own account.")
    return access_repo.save_user(db, ctx.company_id, ctx.user_id, user_id, {**f, "role_ids": None}, None, row_version)


def set_user_active(db: Db, ctx: RequestContext, user_id: int, active: bool, row_version: bytes):
    """Switch a user off (their sessions end) or on again: an edit of is_active alone."""
    if user_id == ctx.user_id and not active:
        raise forbidden("You cannot switch off your own account.")
    user, _, _ = access_repo.get_user(db, ctx.company_id, user_id)
    fields = {"email": user["email"], "display_name": user["display_name"], "employee_id": user["employee_id"],
              "is_active": active, "is_system_admin": bool(user["is_system_admin"]), "company_ids": None,
              "role_ids": None}
    return access_repo.save_user(db, ctx.company_id, ctx.user_id, user_id, fields, None, row_version)


def set_user_roles(db: Db, ctx: RequestContext, user_id: int, role_ids: list[int], row_version: bytes):
    if user_id == ctx.user_id:
        raise forbidden("You cannot change your own roles.")
    return access_repo.set_user_roles(db, ctx.company_id, ctx.user_id, user_id, role_ids, row_version)


def set_user_password(db: Db, ctx: RequestContext, user_id: int, password: str) -> None:
    _check_password(password)
    access_repo.set_user_password(db, ctx.company_id, ctx.user_id, user_id, hash_password(password))


def change_own_password(db: Db, ctx: RequestContext, current: str, new: str) -> None:
    if not verify_password(current, access_repo.own_password_hash(db, ctx.user_id)):
        raise AppError(422, "VALIDATION_FAILED", "The current password is not right.",
                       {"currentPassword": "The current password is not right."})
    if current == new:
        raise invalid("Choose a password different from the current one.", "newPassword")
    try:
        _check_password(new)
    except AppError as exc:
        raise invalid(exc.message, "newPassword") from exc
    access_repo.change_own_password(db, ctx.company_id, ctx.user_id, ctx.session_id, hash_password(new))


def effective_permissions(db: Db, ctx: RequestContext, user_id: int) -> list[dict[str, Any]]:
    return access_repo.effective_permissions(db, ctx.company_id, user_id)


# ---------------------------------------------------------------- roles

def list_permissions(db: Db) -> list[dict[str, Any]]:
    """The catalogue as shipped; codes a release retired are kept in the table but not offered."""
    return [r for r in access_repo.list_permissions(db) if r["code"] in CODES]


def list_roles(db: Db, ctx: RequestContext, search: str | None, include_retired: bool, page: int, page_size: int):
    return access_repo.list_roles(db, ctx.company_id, search, include_retired, page, page_size)


def get_role(db: Db, ctx: RequestContext, role_id: int):
    return access_repo.get_role(db, ctx.company_id, role_id)


def save_role(db: Db, ctx: RequestContext, role_id: int | None, name: str, description: str | None,
              row_version: bytes | None):
    return access_repo.save_role(db, ctx.company_id, ctx.user_id, role_id, name, description, row_version)


def save_role_permissions(db: Db, ctx: RequestContext, role_id: int, ticks: list[dict[str, Any]], row_version: bytes):
    seen: set[str] = set()
    for t in ticks:
        if t["code"] not in CODES:
            raise invalid(f"{t['code']} is not a permission.", "permissions")
        if t["code"] in seen:
            raise invalid(f"{t['code']} is ticked twice.", "permissions")
        seen.add(t["code"])
        if t["scope"] == "selected_units" and not t["units"]:
            raise invalid(f"Pick the branches, departments or locations for {t['code']}.", "permissions")
        if t["scope"] != "selected_units":
            t["units"] = []
    return access_repo.save_role_permissions(db, ctx.company_id, ctx.user_id, role_id, ticks, row_version)


def copy_role(db: Db, ctx: RequestContext, role_id: int, name: str):
    return access_repo.copy_role(db, ctx.company_id, ctx.user_id, role_id, name)


def set_role_active(db: Db, ctx: RequestContext, role_id: int, active: bool, row_version: bytes):
    return access_repo.set_role_active(db, ctx.company_id, ctx.user_id, role_id, active, row_version)


def delete_role(db: Db, ctx: RequestContext, role_id: int, row_version: bytes) -> None:
    access_repo.delete_role(db, ctx.company_id, ctx.user_id, role_id, row_version)


# ---------------------------------------------------------------- grants and denials

def list_overrides(db: Db, ctx: RequestContext, user_id: int) -> list[dict[str, Any]]:
    return access_repo.list_overrides(db, ctx.company_id, user_id)


def save_override(db: Db, ctx: RequestContext, user_id: int, f: dict[str, Any]) -> dict[str, Any]:
    if f["code"] not in CODES:
        raise invalid("This is not a permission.", "code")
    if f["effect"] == "grant" and f.get("scope") is None:
        raise invalid("A grant needs a scope.", "scope")
    if user_id == ctx.user_id:
        raise forbidden("You cannot change your own access.")
    return access_repo.save_override(db, ctx.company_id, ctx.user_id, user_id, f["code"], f["effect"],
                                     f.get("scope") if f["effect"] == "grant" else None, f.get("reason"))


def delete_override(db: Db, ctx: RequestContext, user_id: int, override_id: int, row_version: bytes) -> None:
    access_repo.delete_override(db, ctx.company_id, ctx.user_id, user_id, override_id, row_version)


# ---------------------------------------------------------------- sessions and history

def list_sessions(db: Db, ctx: RequestContext, user_id: int | None, active_only: bool, page: int, page_size: int):
    return access_repo.list_sessions(db, ctx.company_id, user_id, active_only, page, page_size)


def end_session(db: Db, ctx: RequestContext, session_id: int) -> int:
    return access_repo.end_sessions(db, ctx.company_id, ctx.user_id, session_id, None)


def end_user_sessions(db: Db, ctx: RequestContext, user_id: int) -> int:
    return access_repo.end_sessions(db, ctx.company_id, ctx.user_id, None, user_id)


def list_audit(db: Db, ctx: RequestContext, entity: str | None, entity_id: int | None, page: int, page_size: int):
    entity_type = {"role": "auth.role", "user": "auth.user_account", None: None}.get(entity)
    if entity is not None and entity_type is None:
        raise invalid("entity is role or user.", "entity")
    return access_repo.list_audit(db, ctx.company_id, entity_type, entity_id, page, page_size)
