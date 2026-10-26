"""Users, roles, grants and sessions data access (auth.usp_access_* procedures)."""
import json
from typing import Any

from app.core.db import Db


def _page(sets: list[list[dict[str, Any]]]) -> tuple[int, list[dict[str, Any]]]:
    return sets[0][0]["total"], sets[1]


def _ids(values: list[int] | None) -> str | None:
    return None if values is None else json.dumps([int(v) for v in values])


# ---------------------------------------------------------------- users

def list_users(db: Db, company_id: int, search: str | None, is_active: bool | None, role_id: int | None,
               page: int, page_size: int):
    return _page(db.call_sets("auth.usp_access_user_list", company_id=company_id, search=search, is_active=is_active,
                              role_id=role_id, page=page, page_size=page_size))


def get_user(db: Db, company_id: int, user_id: int) -> tuple[dict[str, Any], list[dict], list[dict]]:
    user, roles, companies = db.call_sets("auth.usp_access_user_get", company_id=company_id, id=user_id)
    return user[0], roles, companies


def save_user(db: Db, company_id: int, actor_user_id: int, user_id: int | None, f: dict[str, Any],
              password_hash: str | None, row_version: bytes | None) -> tuple[dict[str, Any], list[dict], list[dict]]:
    user, roles, companies = db.call_sets(
        "auth.usp_access_user_save", company_id=company_id, actor_user_id=actor_user_id, id=user_id,
        email=f["email"], display_name=f.get("display_name"), employee_id=f.get("employee_id"),
        password_hash=password_hash, is_active=f.get("is_active", True), is_system_admin=f.get("is_system_admin", False),
        company_ids=_ids(f.get("company_ids")), role_ids=_ids(f.get("role_ids")), row_version=row_version)
    return user[0], roles, companies


def set_user_roles(db: Db, company_id: int, actor_user_id: int, user_id: int, role_ids: list[int],
                   row_version: bytes) -> tuple[dict[str, Any], list[dict], list[dict]]:
    user, roles, companies = db.call_sets("auth.usp_access_user_roles_set", company_id=company_id,
                                          actor_user_id=actor_user_id, id=user_id, role_ids=_ids(role_ids),
                                          row_version=row_version)
    return user[0], roles, companies


def set_user_password(db: Db, company_id: int, actor_user_id: int, user_id: int, password_hash: str) -> None:
    db.call("auth.usp_access_user_password_set", company_id=company_id, actor_user_id=actor_user_id, id=user_id,
            password_hash=password_hash)


def own_password_hash(db: Db, user_id: int) -> str | None:
    row = db.call_one("auth.usp_access_password_get", user_id=user_id)
    return row["password_hash"] if row else None


def change_own_password(db: Db, company_id: int, user_id: int, session_id: int, password_hash: str) -> None:
    db.call("auth.usp_access_password_change", company_id=company_id, user_id=user_id, session_id=session_id,
            password_hash=password_hash)


def effective_permissions(db: Db, company_id: int, user_id: int) -> list[dict[str, Any]]:
    return db.call("auth.usp_access_user_effective_list", company_id=company_id, id=user_id)


# ---------------------------------------------------------------- roles

def list_permissions(db: Db) -> list[dict[str, Any]]:
    return db.call("auth.usp_access_permission_list")


def list_roles(db: Db, company_id: int, search: str | None, include_retired: bool, page: int, page_size: int):
    return _page(db.call_sets("auth.usp_access_role_list", company_id=company_id, search=search,
                              include_retired=include_retired, page=page, page_size=page_size))


def _role_sets(sets: list[list[dict[str, Any]]]) -> tuple[dict[str, Any], list[dict], list[dict]]:
    role, ticks, units = sets
    return role[0], ticks, units


def get_role(db: Db, company_id: int, role_id: int):
    return _role_sets(db.call_sets("auth.usp_access_role_get", company_id=company_id, id=role_id))


def save_role(db: Db, company_id: int, actor_user_id: int, role_id: int | None, name: str, description: str | None,
              row_version: bytes | None):
    return _role_sets(db.call_sets("auth.usp_access_role_save", company_id=company_id, actor_user_id=actor_user_id,
                                   id=role_id, name=name, description=description, row_version=row_version))


def save_role_permissions(db: Db, company_id: int, actor_user_id: int, role_id: int, ticks: list[dict[str, Any]],
                          row_version: bytes):
    payload = json.dumps([{"code": t["code"], "scope": t["scope"],
                           "units": [{"unitType": u["unit_type"], "unitId": int(u["unit_id"])} for u in t["units"]]}
                          for t in ticks])
    return _role_sets(db.call_sets("auth.usp_access_role_permissions_save", company_id=company_id,
                                   actor_user_id=actor_user_id, id=role_id, ticks=payload, row_version=row_version))


def copy_role(db: Db, company_id: int, actor_user_id: int, role_id: int, name: str):
    return _role_sets(db.call_sets("auth.usp_access_role_copy", company_id=company_id, actor_user_id=actor_user_id,
                                   id=role_id, name=name))


def set_role_active(db: Db, company_id: int, actor_user_id: int, role_id: int, active: bool, row_version: bytes):
    return _role_sets(db.call_sets("auth.usp_access_role_active_set", company_id=company_id,
                                   actor_user_id=actor_user_id, id=role_id, active=active, row_version=row_version))


def delete_role(db: Db, company_id: int, actor_user_id: int, role_id: int, row_version: bytes) -> None:
    db.call("auth.usp_access_role_delete", company_id=company_id, actor_user_id=actor_user_id, id=role_id,
            row_version=row_version)


# ---------------------------------------------------------------- grants and denials

def list_overrides(db: Db, company_id: int, user_id: int) -> list[dict[str, Any]]:
    return db.call("auth.usp_access_override_list", company_id=company_id, user_id=user_id)


def save_override(db: Db, company_id: int, actor_user_id: int, user_id: int, code: str, effect: str,
                  scope: str | None, reason: str | None) -> dict[str, Any]:
    return db.call_one("auth.usp_access_override_save", company_id=company_id, actor_user_id=actor_user_id,
                       user_id=user_id, code=code, effect=effect, scope=scope, reason=reason)


def delete_override(db: Db, company_id: int, actor_user_id: int, user_id: int, override_id: int,
                    row_version: bytes) -> None:
    db.call("auth.usp_access_override_delete", company_id=company_id, actor_user_id=actor_user_id, user_id=user_id,
            id=override_id, row_version=row_version)


# ---------------------------------------------------------------- sessions and history

def list_sessions(db: Db, company_id: int, user_id: int | None, active_only: bool, page: int, page_size: int):
    return _page(db.call_sets("auth.usp_access_session_list", company_id=company_id, user_id=user_id,
                              active_only=active_only, page=page, page_size=page_size))


def end_sessions(db: Db, company_id: int, actor_user_id: int, session_id: int | None, user_id: int | None) -> int:
    return db.call_one("auth.usp_access_session_end", company_id=company_id, actor_user_id=actor_user_id,
                       id=session_id, user_id=user_id)["ended"]


def list_audit(db: Db, company_id: int, entity_type: str | None, entity_id: int | None, page: int, page_size: int):
    return _page(db.call_sets("auth.usp_access_audit_list", company_id=company_id, entity_type=entity_type,
                              entity_id=entity_id, page=page, page_size=page_size))
