"""HTTP shape for project management workspaces and their set-up: envelopes, row versions as text,
JSON columns as objects, rows to response models. Shared helpers for the projects_* controllers."""
import json
from collections import defaultdict
from datetime import date
from typing import Any, TypeVar

from pydantic import BaseModel

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.files import FileRef
from app.schemas.projects import (ActivityOut, ColumnPermissionIn, ColumnPermissionOut, ColumnPermissionsOut, CoverIn,
                                  CustomFieldIn, CustomFieldOut, FavoriteIn, FavoriteOut, FeaturesIn, FolderIn,
                                  FolderOut, ListIn, ListOut, MemberIn, MemberOut, MembersIn, PersonOut, StatusesIn, TagIn,
                                  TagOut, TemplateOut, ViewIn, ViewOut, WorkspaceCreateIn, WorkspaceIn, WorkspaceOut,
                                  WorkspaceSummaryOut)
from app.services import projects_service

M = TypeVar("M", bound=BaseModel)


def to_model(model: type[M], row: dict[str, Any], company_id: int | None = None) -> M:
    """A row as a response model, with its row version as text. With company_id, a cover (cover_file_id) becomes
    `cover` (id, name, signed link) and an employee photo (photo_file_id) becomes `photoUrl`."""
    values = dict(row)
    if "row_version" in values:
        values["row_version"] = row_version_out(values["row_version"])
    if company_id is not None:
        if "cover_file_id" in values:
            cover = values["cover_file_id"]
            values["cover"] = FileRef(id=str(cover), name=values.get("cover_file_name"),
                                      url=file_url(cover, company_id)) if cover else None
        if "photo_file_id" in values:
            values["photo_url"] = file_url(values["photo_file_id"], company_id)
    return model(**values)


def loads(text: str | None) -> Any:
    return json.loads(text) if text else None


# --------------------------------------------------------------------------- templates, people

def list_templates(db: Db, kind: str) -> dict:
    templates, items = projects_service.list_templates(db, kind)
    by_template: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for item in items:
        by_template[item["template_id"]].append(item)
    out = []
    for t in templates:
        rows = by_template[t["id"]]
        out.append(TemplateOut(
            **t,
            views=[{"view_type": r["item_code"], "name": r["name"], "is_default": r["is_default"]}
                   for r in rows if r["item_type"] == "view"],
            statuses=[{"name": r["name"], "color": r["color"], "status_group": r["status_group"]}
                      for r in rows if r["item_type"] == "status"],
            features=[{"feature_code": r["item_code"], "name": r["name"]} for r in rows if r["item_type"] == "feature"]))
    return {"data": out}


def list_people(db: Db, ctx: RequestContext, q: str | None, workspace_id: int | None, paging: PageParams) -> dict:
    total, rows = projects_service.list_people(db, ctx, q, workspace_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: to_model(PersonOut, r, ctx.company_id))


# --------------------------------------------------------------------------- workspaces

def _list_out(row: dict[str, Any]) -> ListOut:
    total, closed = row["task_count"] or 0, row["closed_count"] or 0
    members = loads(row.get("members_json")) or []
    return to_model(ListOut, {**row, "progress_percent": round(100 * closed / total) if total else 0,
                              "member_ids": [m["employee_id"] for m in members]})


def _view_out(row: dict[str, Any]) -> ViewOut:
    return to_model(ViewOut, {**row, "config": loads(row.get("config"))})


def _workspace(sets: list[list[dict[str, Any]]], company_id: int) -> dict:
    ws, statuses, features, members, views, folders, lists = sets
    return {"data": to_model(WorkspaceOut, {
        **ws[0], "statuses": statuses, "features": features, "members": members,
        "views": [_view_out(v) for v in views], "folders": [to_model(FolderOut, f) for f in folders],
        "lists": [_list_out(r) for r in lists]}, company_id)}


def list_workspaces(db: Db, ctx: RequestContext, q: str | None, favorites: bool, paging: PageParams) -> dict:
    total, rows = projects_service.list_workspaces(db, ctx, q, favorites, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size,
                     lambda r: to_model(WorkspaceSummaryOut, r, ctx.company_id))


def get_workspace(db: Db, ctx: RequestContext, workspace_id: int) -> dict:
    return _workspace(projects_service.get_workspace(db, ctx, workspace_id), ctx.company_id)


def create_workspace(db: Db, ctx: RequestContext, body: WorkspaceCreateIn) -> dict:
    return _workspace(projects_service.create_workspace(db, ctx, body), ctx.company_id)


def update_workspace(db: Db, ctx: RequestContext, workspace_id: int, body: WorkspaceIn) -> dict:
    row = projects_service.save_workspace(db, ctx, workspace_id, body, row_version_in(body.row_version))
    return _workspace(row, ctx.company_id)


def set_workspace_cover(db: Db, ctx: RequestContext, workspace_id: int, body: CoverIn) -> dict:
    sets = projects_service.set_workspace_cover(db, ctx, workspace_id, body.file_id, row_version_in(body.row_version))
    return _workspace(sets, ctx.company_id)


def delete_workspace(db: Db, ctx: RequestContext, workspace_id: int, row_version: str | None) -> None:
    projects_service.delete_workspace(db, ctx, workspace_id, row_version_in(row_version))


def save_statuses(db: Db, ctx: RequestContext, workspace_id: int, body: StatusesIn) -> dict:
    return _workspace(projects_service.save_statuses(db, ctx, workspace_id, body.status_mode, body.status_template,
                                                     body.statuses, row_version_in(body.row_version)), ctx.company_id)


def save_features(db: Db, ctx: RequestContext, workspace_id: int, body: FeaturesIn) -> dict:
    return _workspace(projects_service.save_features(db, ctx, workspace_id, body.features,
                                                     row_version_in(body.row_version)), ctx.company_id)


# --------------------------------------------------------------------------- members, column permissions

def list_members(db: Db, ctx: RequestContext, workspace_id: int) -> dict:
    return {"data": [MemberOut(**r) for r in projects_service.list_members(db, ctx, workspace_id)]}


def add_members(db: Db, ctx: RequestContext, workspace_id: int, body: MembersIn) -> dict:
    return {"data": [MemberOut(**r) for r in projects_service.save_members(db, ctx, workspace_id, body.members)]}


def change_member_role(db: Db, ctx: RequestContext, workspace_id: int, employee_id: int, role: str) -> dict:
    rows = projects_service.save_members(db, ctx, workspace_id, [MemberIn(employee_id=employee_id, member_role=role)])
    return {"data": [MemberOut(**r) for r in rows]}


def delete_member(db: Db, ctx: RequestContext, workspace_id: int, employee_id: int) -> None:
    projects_service.delete_member(db, ctx, workspace_id, employee_id)


def _column_permissions(rows: list[dict[str, Any]], mine: list[dict[str, Any]]) -> dict:
    columns: dict[str, dict[str, Any]] = {}
    for r in rows:
        col = columns.setdefault(r["column_key"], {"column_key": r["column_key"], "default_level": "default",
                                                   "roles": [], "members": []})
        if r["employee_id"] is not None:
            col["members"].append({"employee_id": r["employee_id"], "employee_name": r["employee_name"],
                                   "permission_level": r["permission_level"]})
        elif r["member_role"] is not None:
            col["roles"].append({"member_role": r["member_role"], "permission_level": r["permission_level"]})
        else:
            col["default_level"] = r["permission_level"]
    return {"data": ColumnPermissionsOut(columns=[ColumnPermissionOut(**c) for c in columns.values()],
                                         my_levels={m["column_key"]: m["permission_level"] for m in mine})}


def list_column_permissions(db: Db, ctx: RequestContext, workspace_id: int) -> dict:
    return _column_permissions(*projects_service.list_column_permissions(db, ctx, workspace_id))


def save_column_permission(db: Db, ctx: RequestContext, workspace_id: int, column_key: str,
                           body: ColumnPermissionIn) -> dict:
    return _column_permissions(*projects_service.save_column_permission(db, ctx, workspace_id, column_key, body))


# --------------------------------------------------------------------------- custom fields

def _field(row: dict[str, Any]) -> CustomFieldOut:
    return to_model(CustomFieldOut, {**row, "config": loads(row.get("config"))})


def list_custom_fields(db: Db, ctx: RequestContext, workspace_id: int) -> dict:
    return {"data": [_field(r) for r in projects_service.list_custom_fields(db, ctx, workspace_id)]}


def create_custom_field(db: Db, ctx: RequestContext, workspace_id: int, body: CustomFieldIn) -> dict:
    return {"data": _field(projects_service.save_custom_field(db, ctx, None, workspace_id, body, None))}


def update_custom_field(db: Db, ctx: RequestContext, field_id: int, body: CustomFieldIn) -> dict:
    return {"data": _field(projects_service.save_custom_field(db, ctx, field_id, None, body,
                                                              row_version_in(body.row_version)))}


def delete_custom_field(db: Db, ctx: RequestContext, field_id: int, row_version: str | None) -> None:
    projects_service.delete_custom_field(db, ctx, field_id, row_version_in(row_version))


# --------------------------------------------------------------------------- folders, lists, views

def create_folder(db: Db, ctx: RequestContext, workspace_id: int, body: FolderIn) -> dict:
    return {"data": to_model(FolderOut, projects_service.save_folder(db, ctx, None, workspace_id, body, None))}


def update_folder(db: Db, ctx: RequestContext, folder_id: int, body: FolderIn) -> dict:
    row = projects_service.save_folder(db, ctx, folder_id, None, body, row_version_in(body.row_version))
    return {"data": to_model(FolderOut, row)}


def delete_folder(db: Db, ctx: RequestContext, folder_id: int, row_version: str | None) -> None:
    projects_service.delete_folder(db, ctx, folder_id, row_version_in(row_version))


def create_list(db: Db, ctx: RequestContext, workspace_id: int, body: ListIn) -> dict:
    return {"data": _list_out(projects_service.save_list(db, ctx, None, workspace_id, body, None))}


def update_list(db: Db, ctx: RequestContext, list_id: int, body: ListIn) -> dict:
    return {"data": _list_out(projects_service.save_list(db, ctx, list_id, None, body, row_version_in(body.row_version)))}


def delete_list(db: Db, ctx: RequestContext, list_id: int, row_version: str | None) -> None:
    projects_service.delete_list(db, ctx, list_id, row_version_in(row_version))


def list_views(db: Db, ctx: RequestContext, workspace_id: int) -> dict:
    views = projects_service.get_workspace(db, ctx, workspace_id)[4]
    return {"data": [_view_out(v) for v in views]}


def create_view(db: Db, ctx: RequestContext, workspace_id: int, body: ViewIn) -> dict:
    return {"data": _view_out(projects_service.save_view(db, ctx, None, workspace_id, body, None))}


def update_view(db: Db, ctx: RequestContext, view_id: int, body: ViewIn) -> dict:
    return {"data": _view_out(projects_service.save_view(db, ctx, view_id, None, body, row_version_in(body.row_version)))}


def delete_view(db: Db, ctx: RequestContext, view_id: int, row_version: str | None) -> None:
    projects_service.delete_view(db, ctx, view_id, row_version_in(row_version))


# --------------------------------------------------------------------------- favourites, tags, history

def list_favorites(db: Db, ctx: RequestContext, kind: str) -> dict:
    return {"data": [FavoriteOut(**r) for r in projects_service.list_favorites(db, ctx, kind)]}


def set_favorite(db: Db, ctx: RequestContext, body: FavoriteIn) -> None:
    projects_service.set_favorite(db, ctx, body.entity_type, body.entity_id, body.kind, body.on)


def list_tags(db: Db, ctx: RequestContext, workspace_id: int) -> dict:
    return {"data": [to_model(TagOut, r) for r in projects_service.list_tags(db, ctx, workspace_id)]}


def create_tag(db: Db, ctx: RequestContext, workspace_id: int, body: TagIn) -> dict:
    return {"data": to_model(TagOut, projects_service.save_tag(db, ctx, None, workspace_id, body.name, body.color, None))}


def update_tag(db: Db, ctx: RequestContext, tag_id: int, body: TagIn) -> dict:
    row = projects_service.save_tag(db, ctx, tag_id, None, body.name, body.color, row_version_in(body.row_version))
    return {"data": to_model(TagOut, row)}


def delete_tag(db: Db, ctx: RequestContext, tag_id: int, row_version: str | None) -> None:
    projects_service.delete_tag(db, ctx, tag_id, row_version_in(row_version))


def workspace_activity(db: Db, ctx: RequestContext, workspace_id: int, action_name: str | None, from_date: date | None,
                       to_date: date | None, q: str | None, paging: PageParams) -> dict:
    total, rows = projects_service.workspace_activity(db, ctx, workspace_id, action_name, from_date, to_date, q,
                                                      paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: ActivityOut(**r))
