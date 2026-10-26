"""Project management data access for workspaces and their set-up. The only layer that knows the pm
procedure names and parameters (tasks: projects_tasks_repo.py; collaboration: projects_collab_repo.py)."""
from datetime import date
from typing import Any

from app.core.db import Db

Rows = list[dict[str, Any]]


def list_templates(db: Db, template_kind: str) -> tuple[Rows, Rows]:
    templates, items = db.call_sets("pm.usp_template_list", template_kind=template_kind)
    return templates, items


def list_people(db: Db, company_id: int, actor_user_id: int, search: str | None, workspace_id: int | None,
                page: int, page_size: int) -> tuple[int, Rows]:
    total, rows = db.call_sets("pm.usp_people_list", company_id=company_id, actor_user_id=actor_user_id, search=search,
                               workspace_id=workspace_id, page=page, page_size=page_size)
    return total[0]["total"], rows


# --------------------------------------------------------------------------- workspaces

def list_workspaces(db: Db, company_id: int, actor_user_id: int, search: str | None, favorites_only: bool,
                    page: int, page_size: int) -> tuple[int, Rows]:
    total, rows = db.call_sets("pm.usp_workspace_list", company_id=company_id, actor_user_id=actor_user_id,
                               search=search, favorites_only=favorites_only, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_workspace(db: Db, company_id: int, actor_user_id: int, workspace_id: int) -> list[Rows]:
    return db.call_sets("pm.usp_workspace_get", company_id=company_id, actor_user_id=actor_user_id, id=workspace_id)


def create_workspace(db: Db, company_id: int, actor_user_id: int, name: str, description: str | None, privacy: str,
                     department_id: int, workflow_template: str, owner_id: int, status_mode: str,
                     status_template: str | None, statuses: str | None, views: str | None, features: str | None,
                     members: str) -> list[Rows]:
    return db.call_sets("pm.usp_workspace_create", company_id=company_id, actor_user_id=actor_user_id, name=name,
                        description=description, privacy=privacy, department_id=department_id,
                        workflow_template=workflow_template, owner_id=owner_id, status_mode=status_mode,
                        status_template=status_template, statuses=statuses, views=views, features=features,
                        members=members)


def save_workspace(db: Db, company_id: int, actor_user_id: int, workspace_id: int, name: str, description: str | None,
                   privacy: str, department_id: int, owner_id: int, row_version: bytes) -> list[Rows]:
    return db.call_sets("pm.usp_workspace_save", company_id=company_id, actor_user_id=actor_user_id, id=workspace_id,
                        name=name, description=description, privacy=privacy, department_id=department_id,
                        owner_id=owner_id, row_version=row_version)


def set_workspace_cover(db: Db, company_id: int, actor_user_id: int, workspace_id: int, file_id: int | None,
                        row_version: bytes) -> list[Rows]:
    return db.call_sets("pm.usp_workspace_cover_set", company_id=company_id, actor_user_id=actor_user_id,
                        id=workspace_id, file_id=file_id, row_version=row_version)


def delete_workspace(db: Db, company_id: int, actor_user_id: int, workspace_id: int, row_version: bytes) -> None:
    db.call("pm.usp_workspace_delete", company_id=company_id, actor_user_id=actor_user_id, id=workspace_id,
            row_version=row_version)


def save_statuses(db: Db, company_id: int, actor_user_id: int, workspace_id: int, status_mode: str | None,
                  status_template: str | None, statuses: str, row_version: bytes) -> list[Rows]:
    return db.call_sets("pm.usp_workspace_statuses_save", company_id=company_id, actor_user_id=actor_user_id,
                        id=workspace_id, status_mode=status_mode, status_template=status_template, statuses=statuses,
                        row_version=row_version)


def save_features(db: Db, company_id: int, actor_user_id: int, workspace_id: int, features: str,
                  row_version: bytes) -> list[Rows]:
    return db.call_sets("pm.usp_workspace_features_save", company_id=company_id, actor_user_id=actor_user_id,
                        id=workspace_id, features=features, row_version=row_version)


# --------------------------------------------------------------------------- members, column permissions

def list_members(db: Db, company_id: int, actor_user_id: int, workspace_id: int) -> Rows:
    return db.call("pm.usp_workspace_member_list", company_id=company_id, actor_user_id=actor_user_id,
                   workspace_id=workspace_id)


def save_members(db: Db, company_id: int, actor_user_id: int, workspace_id: int, members: str) -> Rows:
    return db.call("pm.usp_workspace_member_save", company_id=company_id, actor_user_id=actor_user_id,
                   workspace_id=workspace_id, members=members)


def delete_member(db: Db, company_id: int, actor_user_id: int, workspace_id: int, employee_id: int) -> None:
    db.call("pm.usp_workspace_member_delete", company_id=company_id, actor_user_id=actor_user_id,
            workspace_id=workspace_id, employee_id=employee_id)


def list_column_permissions(db: Db, company_id: int, actor_user_id: int, workspace_id: int) -> tuple[Rows, Rows]:
    rows, mine = db.call_sets("pm.usp_column_permission_list", company_id=company_id, actor_user_id=actor_user_id,
                              workspace_id=workspace_id)
    return rows, mine


def save_column_permission(db: Db, company_id: int, actor_user_id: int, workspace_id: int, column_key: str,
                           default_level: str, roles: str, members: str) -> tuple[Rows, Rows]:
    rows, mine = db.call_sets("pm.usp_column_permission_save", company_id=company_id, actor_user_id=actor_user_id,
                              workspace_id=workspace_id, column_key=column_key, default_level=default_level,
                              roles=roles, members=members)
    return rows, mine


# --------------------------------------------------------------------------- custom fields

def list_custom_fields(db: Db, company_id: int, actor_user_id: int, workspace_id: int) -> Rows:
    return db.call("pm.usp_custom_field_list", company_id=company_id, actor_user_id=actor_user_id,
                   workspace_id=workspace_id)


def save_custom_field(db: Db, company_id: int, actor_user_id: int, field_id: int | None, workspace_id: int | None,
                      name: str, field_type: str, description: str | None, config: str | None,
                      row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("pm.usp_custom_field_save", company_id=company_id, actor_user_id=actor_user_id, id=field_id,
                       workspace_id=workspace_id, name=name, field_type=field_type, description=description,
                       config=config, row_version=row_version)


def delete_custom_field(db: Db, company_id: int, actor_user_id: int, field_id: int, row_version: bytes) -> None:
    db.call("pm.usp_custom_field_delete", company_id=company_id, actor_user_id=actor_user_id, id=field_id,
            row_version=row_version)


# --------------------------------------------------------------------------- folders, lists, views

def save_folder(db: Db, company_id: int, actor_user_id: int, folder_id: int | None, workspace_id: int | None,
                name: str, sort_order: int | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("pm.usp_folder_save", company_id=company_id, actor_user_id=actor_user_id, id=folder_id,
                       workspace_id=workspace_id, name=name, sort_order=sort_order, row_version=row_version)


def delete_folder(db: Db, company_id: int, actor_user_id: int, folder_id: int, row_version: bytes) -> None:
    db.call("pm.usp_folder_delete", company_id=company_id, actor_user_id=actor_user_id, id=folder_id,
            row_version=row_version)


def save_list(db: Db, company_id: int, actor_user_id: int, list_id: int | None, workspace_id: int | None,
              values: dict[str, Any], member_ids: str | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("pm.usp_list_save", company_id=company_id, actor_user_id=actor_user_id, id=list_id,
                       workspace_id=workspace_id, folder_id=values["folder_id"], name=values["name"],
                       privacy=values["privacy"], color=values["color"], description=values["description"],
                       start_at=values["start_at"], end_at=values["end_at"], priority=values["priority"],
                       sort_order=values["sort_order"], member_ids=member_ids, row_version=row_version)


def delete_list(db: Db, company_id: int, actor_user_id: int, list_id: int, row_version: bytes) -> None:
    db.call("pm.usp_list_delete", company_id=company_id, actor_user_id=actor_user_id, id=list_id, row_version=row_version)


def save_view(db: Db, company_id: int, actor_user_id: int, view_id: int | None, workspace_id: int | None,
              values: dict[str, Any], config: str | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("pm.usp_list_view_save", company_id=company_id, actor_user_id=actor_user_id, id=view_id,
                       workspace_id=workspace_id, task_list_id=values["task_list_id"], view_type=values["view_type"],
                       name=values["name"], config=config, is_pinned=values["is_pinned"],
                       is_private=values["is_private"], is_protected=values["is_protected"],
                       is_default=values["is_default"], row_version=row_version)


def delete_view(db: Db, company_id: int, actor_user_id: int, view_id: int, row_version: bytes) -> None:
    db.call("pm.usp_list_view_delete", company_id=company_id, actor_user_id=actor_user_id, id=view_id,
            row_version=row_version)


# --------------------------------------------------------------------------- favourites, tags, history

def list_favorites(db: Db, company_id: int, actor_user_id: int, kind: str) -> Rows:
    return db.call("pm.usp_favorite_list", company_id=company_id, actor_user_id=actor_user_id, kind=kind)


def set_favorite(db: Db, company_id: int, actor_user_id: int, entity_type: str, entity_id: int, kind: str,
                 is_on: bool) -> None:
    db.call("pm.usp_favorite_set", company_id=company_id, actor_user_id=actor_user_id, entity_type=entity_type,
            entity_id=entity_id, kind=kind, is_on=is_on)


def list_tags(db: Db, company_id: int, actor_user_id: int, workspace_id: int) -> Rows:
    return db.call("pm.usp_tag_list", company_id=company_id, actor_user_id=actor_user_id, workspace_id=workspace_id)


def save_tag(db: Db, company_id: int, actor_user_id: int, tag_id: int | None, workspace_id: int | None, name: str,
             color: str | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("pm.usp_tag_save", company_id=company_id, actor_user_id=actor_user_id, id=tag_id,
                       workspace_id=workspace_id, name=name, color=color, row_version=row_version)


def delete_tag(db: Db, company_id: int, actor_user_id: int, tag_id: int, row_version: bytes) -> None:
    db.call("pm.usp_tag_delete", company_id=company_id, actor_user_id=actor_user_id, id=tag_id, row_version=row_version)


def workspace_activity(db: Db, company_id: int, actor_user_id: int, workspace_id: int, action_name: str | None,
                       from_date: date | None, to_date: date | None, search: str | None, page: int,
                       page_size: int) -> tuple[int, Rows]:
    total, rows = db.call_sets("pm.usp_workspace_activity", company_id=company_id, actor_user_id=actor_user_id,
                               workspace_id=workspace_id, action_name=action_name, from_date=from_date,
                               to_date=to_date, search=search, page=page, page_size=page_size)
    return total[0]["total"], rows
