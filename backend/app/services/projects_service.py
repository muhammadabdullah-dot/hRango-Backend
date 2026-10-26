"""Project management rules for workspaces and their set-up. What a member may do inside a workspace
(their workspace role, column permissions, organizer features) is checked by the pm procedures; the
rules here are the ones that do not need the data: JSON shapes and custom field settings."""
import json
from datetime import date, datetime, timezone
from typing import Any

from app.core.db import Db
from app.core.errors import invalid
from app.middlewares.auth import RequestContext
from app.repos import projects_repo
from app.schemas.projects import (ColumnPermissionIn, CustomFieldIn, FeatureIn, FolderIn, ListIn, MemberIn, StatusIn,
                                  ViewIn, WorkspaceCreateIn, WorkspaceIn)

Rows = list[dict[str, Any]]


def dumps(value: Any) -> str:
    return json.dumps(value, default=str)


def _statuses(statuses: list[StatusIn]) -> str:
    return dumps([s.model_dump(by_alias=False) for s in statuses])


def _features(features: list[FeatureIn]) -> str:
    return dumps([f.model_dump(by_alias=False) for f in features])


def _members(members: list[MemberIn]) -> str:
    return dumps([m.model_dump(by_alias=False) for m in members])


# --------------------------------------------------------------------------- templates, people

def list_templates(db: Db, kind: str) -> tuple[Rows, Rows]:
    return projects_repo.list_templates(db, kind)


def list_people(db: Db, ctx: RequestContext, search: str | None, workspace_id: int | None, page: int,
                page_size: int) -> tuple[int, Rows]:
    return projects_repo.list_people(db, ctx.company_id, ctx.user_id, search, workspace_id, page, page_size)


# --------------------------------------------------------------------------- workspaces

def list_workspaces(db: Db, ctx: RequestContext, search: str | None, favorites_only: bool, page: int,
                    page_size: int) -> tuple[int, Rows]:
    return projects_repo.list_workspaces(db, ctx.company_id, ctx.user_id, search, favorites_only, page, page_size)


def get_workspace(db: Db, ctx: RequestContext, workspace_id: int) -> list[Rows]:
    return projects_repo.get_workspace(db, ctx.company_id, ctx.user_id, workspace_id)


def create_workspace(db: Db, ctx: RequestContext, body: WorkspaceCreateIn) -> list[Rows]:
    if body.views is not None and sum(1 for v in body.views if v.is_default) > 1:
        raise invalid("Only one view can be the default.", "views")
    return projects_repo.create_workspace(
        db, ctx.company_id, ctx.user_id, body.name, body.description, body.privacy, body.department_id,
        body.workflow_template, body.owner_id, body.status_mode, body.status_template,
        _statuses(body.statuses) if body.statuses is not None else None,
        dumps([v.model_dump(by_alias=False) for v in body.views]) if body.views is not None else None,
        _features(body.features) if body.features is not None else None,
        _members(body.members))


def save_workspace(db: Db, ctx: RequestContext, workspace_id: int, body: WorkspaceIn, row_version: bytes) -> list[Rows]:
    return projects_repo.save_workspace(db, ctx.company_id, ctx.user_id, workspace_id, body.name, body.description,
                                        body.privacy, body.department_id, body.owner_id, row_version)


def set_workspace_cover(db: Db, ctx: RequestContext, workspace_id: int, file_id: int | None,
                        row_version: bytes) -> list[Rows]:
    return projects_repo.set_workspace_cover(db, ctx.company_id, ctx.user_id, workspace_id, file_id, row_version)


def delete_workspace(db: Db, ctx: RequestContext, workspace_id: int, row_version: bytes) -> None:
    projects_repo.delete_workspace(db, ctx.company_id, ctx.user_id, workspace_id, row_version)


def save_statuses(db: Db, ctx: RequestContext, workspace_id: int, status_mode: str | None, status_template: str | None,
                  statuses: list[StatusIn], row_version: bytes) -> list[Rows]:
    return projects_repo.save_statuses(db, ctx.company_id, ctx.user_id, workspace_id, status_mode, status_template,
                                       _statuses(statuses), row_version)


def save_features(db: Db, ctx: RequestContext, workspace_id: int, features: list[FeatureIn],
                  row_version: bytes) -> list[Rows]:
    wip = next((f for f in features if f.feature_code == "wip_limits"), None)
    if wip is not None and wip.setting_value is not None and not wip.setting_value.isdigit():
        raise invalid("Set work in progress limits on each status (wipLimit).", "features")
    return projects_repo.save_features(db, ctx.company_id, ctx.user_id, workspace_id, _features(features), row_version)


# --------------------------------------------------------------------------- members, column permissions

def list_members(db: Db, ctx: RequestContext, workspace_id: int) -> Rows:
    return projects_repo.list_members(db, ctx.company_id, ctx.user_id, workspace_id)


def save_members(db: Db, ctx: RequestContext, workspace_id: int, members: list[MemberIn]) -> Rows:
    return projects_repo.save_members(db, ctx.company_id, ctx.user_id, workspace_id, _members(members))


def delete_member(db: Db, ctx: RequestContext, workspace_id: int, employee_id: int) -> None:
    projects_repo.delete_member(db, ctx.company_id, ctx.user_id, workspace_id, employee_id)


def list_column_permissions(db: Db, ctx: RequestContext, workspace_id: int) -> tuple[Rows, Rows]:
    return projects_repo.list_column_permissions(db, ctx.company_id, ctx.user_id, workspace_id)


def save_column_permission(db: Db, ctx: RequestContext, workspace_id: int, column_key: str,
                           body: ColumnPermissionIn) -> tuple[Rows, Rows]:
    return projects_repo.save_column_permission(
        db, ctx.company_id, ctx.user_id, workspace_id, column_key, body.default_level,
        dumps([r.model_dump(by_alias=False) for r in body.roles]),
        dumps([m.model_dump(by_alias=False) for m in body.members]))


# --------------------------------------------------------------------------- custom fields

def _field_config(field_type: str, config: dict[str, Any] | None) -> dict[str, Any] | None:
    """The settings each field type keeps (BRD "Task Custom Fields (Details)")."""
    config = config or {}
    if field_type in ("dropdown", "labels"):
        options = config.get("options")
        if not isinstance(options, list) or not options:
            raise invalid("Add at least one option.", "config")
        names = [str(o).strip() for o in options]
        if any(not n for n in names):
            raise invalid("Options need a name.", "config")
        if len({n.lower() for n in names}) != len(names):
            raise invalid("Duplicate options are not allowed.", "config")
        sort = config.get("sort", "manual")
        if sort not in ("manual", "a_z", "z_a"):
            raise invalid("Sort options manually, A-Z or Z-A.", "config")
        return {"options": names, "sort": sort}
    if field_type in ("number", "money"):
        out: dict[str, Any] = {}
        for key in ("min", "max"):
            if config.get(key) is not None:
                try:
                    out[key] = float(config[key])
                except (TypeError, ValueError):
                    raise invalid(f"{key} must be a number.", "config") from None
        if "min" in out and "max" in out and out["min"] > out["max"]:
            raise invalid("The minimum cannot be above the maximum.", "config")
        if field_type == "money":
            currency = str(config.get("currency") or "PKR").upper()
            if len(currency) != 3 or not currency.isalpha():
                raise invalid("Currency is a three-letter code.", "config")
            out["currency"] = currency
        return out or None
    if field_type == "rating":
        top = config.get("max", 5)
        if not isinstance(top, int) or not 1 <= top <= 10:
            raise invalid("A rating scale runs from 1 to at most 10.", "config")
        return {"max": top, "emoji": str(config.get("emoji") or "star")}
    if field_type == "progress_manual":
        end = config.get("end", 100)
        if not isinstance(end, int) or end < 1:
            raise invalid("The end value must be a whole number above 0.", "config")
        return {"end": end}
    if field_type == "people":
        return {"multiple": bool(config.get("multiple", True))}
    return None


def list_custom_fields(db: Db, ctx: RequestContext, workspace_id: int) -> Rows:
    return projects_repo.list_custom_fields(db, ctx.company_id, ctx.user_id, workspace_id)


def save_custom_field(db: Db, ctx: RequestContext, field_id: int | None, workspace_id: int | None, body: CustomFieldIn,
                      row_version: bytes | None) -> dict[str, Any]:
    config = _field_config(body.field_type, body.config)
    return projects_repo.save_custom_field(db, ctx.company_id, ctx.user_id, field_id, workspace_id, body.name,
                                           body.field_type, body.description, dumps(config) if config else None,
                                           row_version)


def delete_custom_field(db: Db, ctx: RequestContext, field_id: int, row_version: bytes) -> None:
    projects_repo.delete_custom_field(db, ctx.company_id, ctx.user_id, field_id, row_version)


# --------------------------------------------------------------------------- folders, lists, views

def save_folder(db: Db, ctx: RequestContext, folder_id: int | None, workspace_id: int | None, body: FolderIn,
                row_version: bytes | None) -> dict[str, Any]:
    return projects_repo.save_folder(db, ctx.company_id, ctx.user_id, folder_id, workspace_id, body.name,
                                     body.sort_order, row_version)


def delete_folder(db: Db, ctx: RequestContext, folder_id: int, row_version: bytes) -> None:
    projects_repo.delete_folder(db, ctx.company_id, ctx.user_id, folder_id, row_version)


def save_list(db: Db, ctx: RequestContext, list_id: int | None, workspace_id: int | None, body: ListIn,
              row_version: bytes | None) -> dict[str, Any]:
    if body.start_at and body.end_at and body.end_at <= body.start_at:
        raise invalid("End must be after the start.", "endAt")
    values = body.model_dump(by_alias=False, exclude={"member_ids", "row_version"})
    values["start_at"], values["end_at"] = naive_utc(body.start_at), naive_utc(body.end_at)
    member_ids = dumps(body.member_ids) if body.member_ids is not None else None
    return projects_repo.save_list(db, ctx.company_id, ctx.user_id, list_id, workspace_id, values, member_ids,
                                   row_version)


def delete_list(db: Db, ctx: RequestContext, list_id: int, row_version: bytes) -> None:
    projects_repo.delete_list(db, ctx.company_id, ctx.user_id, list_id, row_version)


def save_view(db: Db, ctx: RequestContext, view_id: int | None, workspace_id: int | None, body: ViewIn,
              row_version: bytes | None) -> dict[str, Any]:
    values = body.model_dump(by_alias=False, exclude={"config", "row_version"})
    return projects_repo.save_view(db, ctx.company_id, ctx.user_id, view_id, workspace_id, values,
                                   dumps(body.config) if body.config is not None else None, row_version)


def delete_view(db: Db, ctx: RequestContext, view_id: int, row_version: bytes) -> None:
    projects_repo.delete_view(db, ctx.company_id, ctx.user_id, view_id, row_version)


# --------------------------------------------------------------------------- favourites, tags, history

def list_favorites(db: Db, ctx: RequestContext, kind: str) -> Rows:
    return projects_repo.list_favorites(db, ctx.company_id, ctx.user_id, kind)


def set_favorite(db: Db, ctx: RequestContext, entity_type: str, entity_id: int, kind: str, is_on: bool) -> None:
    projects_repo.set_favorite(db, ctx.company_id, ctx.user_id, entity_type, entity_id, kind, is_on)


def list_tags(db: Db, ctx: RequestContext, workspace_id: int) -> Rows:
    return projects_repo.list_tags(db, ctx.company_id, ctx.user_id, workspace_id)


def save_tag(db: Db, ctx: RequestContext, tag_id: int | None, workspace_id: int | None, name: str, color: str | None,
             row_version: bytes | None) -> dict[str, Any]:
    return projects_repo.save_tag(db, ctx.company_id, ctx.user_id, tag_id, workspace_id, name, color, row_version)


def delete_tag(db: Db, ctx: RequestContext, tag_id: int, row_version: bytes) -> None:
    projects_repo.delete_tag(db, ctx.company_id, ctx.user_id, tag_id, row_version)


def workspace_activity(db: Db, ctx: RequestContext, workspace_id: int, action_name: str | None, from_date: date | None,
                       to_date: date | None, search: str | None, page: int, page_size: int) -> tuple[int, Rows]:
    return projects_repo.workspace_activity(db, ctx.company_id, ctx.user_id, workspace_id, action_name, from_date,
                                            to_date, search, page, page_size)


def naive_utc(value: datetime | None) -> datetime | None:
    """Times are stored in UTC without an offset."""
    if value is None or value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)
