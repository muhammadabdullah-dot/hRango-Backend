"""Project management: templates, people picker, workspaces (Create Workspace wizard), members,
statuses, organizer features, column permissions, custom fields, folders, lists, views, tags,
favourites and workspace history. Included by routers/projects.py under /projects."""
from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import projects_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.projects import (ActivityOut, ColumnPermissionIn, ColumnPermissionsOut, CoverIn, CustomFieldIn,
                                  CustomFieldOut, FavoriteIn, FavoriteOut, FeaturesIn, FolderIn, FolderOut, ListIn, ListOut, MemberOut,
                                  MemberRoleIn, MembersIn, PersonOut, StatusesIn, TagIn, TagOut, TemplateOut, ViewIn,
                                  ViewOut, WorkspaceCreateIn, WorkspaceIn, WorkspaceOut, WorkspaceSummaryOut)

router = APIRouter()
NO_CONTENT = status.HTTP_204_NO_CONTENT
CREATED = status.HTTP_201_CREATED

VIEW = require("projects.workspaces.view")
CREATE = require("projects.workspaces.create")
EDIT = require("projects.workspaces.edit")


# --------------------------------------------------------------------------- templates, people

@router.get("/templates", response_model=Item[list[TemplateOut]])
def list_templates(kind: Literal["workflow", "status"] = "workflow", db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_templates(db, kind)


@router.get("/people", response_model=Paginated[PersonOut])
def list_people(q: str | None = None, workspace_id: int | None = Query(None, alias="workspaceId"),
                paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_people(db, ctx, q, workspace_id, paging)


# --------------------------------------------------------------------------- workspaces

@router.get("/workspaces", response_model=Paginated[WorkspaceSummaryOut])
def list_workspaces(q: str | None = None, favorites: bool = False, paging: PageParams = Depends(page_params),
                    db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_workspaces(db, ctx, q, favorites, paging)


@router.post("/workspaces", response_model=Item[WorkspaceOut], status_code=CREATED)
def create_workspace(body: WorkspaceCreateIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(CREATE)) -> dict:
    return c.create_workspace(db, ctx, body)


@router.get("/workspaces/{workspace_id}", response_model=Item[WorkspaceOut])
def get_workspace(workspace_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.get_workspace(db, ctx, workspace_id)


@router.put("/workspaces/{workspace_id}", response_model=Item[WorkspaceOut])
def update_workspace(workspace_id: int, body: WorkspaceIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.update_workspace(db, ctx, workspace_id, body)


@router.put("/workspaces/{workspace_id}/cover", response_model=Item[WorkspaceOut])
def set_workspace_cover(workspace_id: int, body: CoverIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(EDIT)) -> dict:
    """Sets (fileId) or removes (fileId null) the workspace banner, uploaded first through POST /api/files."""
    return c.set_workspace_cover(db, ctx, workspace_id, body)


@router.delete("/workspaces/{workspace_id}", status_code=NO_CONTENT)
def delete_workspace(workspace_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                     db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("projects.workspaces.delete"))) -> Response:
    c.delete_workspace(db, ctx, workspace_id, row_version)
    return Response(status_code=NO_CONTENT)


@router.put("/workspaces/{workspace_id}/statuses", response_model=Item[WorkspaceOut])
def save_statuses(workspace_id: int, body: StatusesIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.save_statuses(db, ctx, workspace_id, body)


@router.put("/workspaces/{workspace_id}/features", response_model=Item[WorkspaceOut])
def save_features(workspace_id: int, body: FeaturesIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.save_features(db, ctx, workspace_id, body)


# --------------------------------------------------------------------------- members

@router.get("/workspaces/{workspace_id}/members", response_model=Item[list[MemberOut]])
def list_members(workspace_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_members(db, ctx, workspace_id)


@router.post("/workspaces/{workspace_id}/members", response_model=Item[list[MemberOut]])
def add_members(workspace_id: int, body: MembersIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.add_members(db, ctx, workspace_id, body)


@router.patch("/workspaces/{workspace_id}/members/{employee_id}", response_model=Item[list[MemberOut]])
def change_member_role(workspace_id: int, employee_id: int, body: MemberRoleIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.change_member_role(db, ctx, workspace_id, employee_id, body.member_role)


@router.delete("/workspaces/{workspace_id}/members/{employee_id}", status_code=NO_CONTENT)
def delete_member(workspace_id: int, employee_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(EDIT)) -> Response:
    c.delete_member(db, ctx, workspace_id, employee_id)
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- column permissions

@router.get("/workspaces/{workspace_id}/column-permissions", response_model=Item[ColumnPermissionsOut])
def list_column_permissions(workspace_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_column_permissions(db, ctx, workspace_id)


@router.put("/workspaces/{workspace_id}/column-permissions/{column_key}", response_model=Item[ColumnPermissionsOut])
def save_column_permission(workspace_id: int, column_key: str, body: ColumnPermissionIn, db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.save_column_permission(db, ctx, workspace_id, column_key, body)


# --------------------------------------------------------------------------- custom fields

@router.get("/workspaces/{workspace_id}/custom-fields", response_model=Item[list[CustomFieldOut]])
def list_custom_fields(workspace_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_custom_fields(db, ctx, workspace_id)


@router.post("/workspaces/{workspace_id}/custom-fields", response_model=Item[CustomFieldOut], status_code=CREATED)
def create_custom_field(workspace_id: int, body: CustomFieldIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.create_custom_field(db, ctx, workspace_id, body)


@router.put("/custom-fields/{field_id}", response_model=Item[CustomFieldOut])
def update_custom_field(field_id: int, body: CustomFieldIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.update_custom_field(db, ctx, field_id, body)


@router.delete("/custom-fields/{field_id}", status_code=NO_CONTENT)
def delete_custom_field(field_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                        db: Db = Depends(get_db), ctx: RequestContext = Depends(EDIT)) -> Response:
    c.delete_custom_field(db, ctx, field_id, row_version)
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- folders and lists

@router.post("/workspaces/{workspace_id}/folders", response_model=Item[FolderOut], status_code=CREATED)
def create_folder(workspace_id: int, body: FolderIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("projects.lists.create"))) -> dict:
    return c.create_folder(db, ctx, workspace_id, body)


@router.put("/folders/{folder_id}", response_model=Item[FolderOut])
def update_folder(folder_id: int, body: FolderIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("projects.lists.edit"))) -> dict:
    return c.update_folder(db, ctx, folder_id, body)


@router.delete("/folders/{folder_id}", status_code=NO_CONTENT)
def delete_folder(folder_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("projects.lists.delete"))) -> Response:
    c.delete_folder(db, ctx, folder_id, row_version)
    return Response(status_code=NO_CONTENT)


@router.post("/workspaces/{workspace_id}/lists", response_model=Item[ListOut], status_code=CREATED)
def create_list(workspace_id: int, body: ListIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("projects.lists.create"))) -> dict:
    return c.create_list(db, ctx, workspace_id, body)


@router.put("/lists/{list_id}", response_model=Item[ListOut])
def update_list(list_id: int, body: ListIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("projects.lists.edit"))) -> dict:
    return c.update_list(db, ctx, list_id, body)


@router.delete("/lists/{list_id}", status_code=NO_CONTENT)
def delete_list(list_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("projects.lists.delete"))) -> Response:
    c.delete_list(db, ctx, list_id, row_version)
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- views
# Saving a view is a reading preference: shared views are limited to workspace admins and HR by the
# procedures; anyone who can open the workspace keeps private views.

@router.get("/workspaces/{workspace_id}/views", response_model=Item[list[ViewOut]])
def list_views(workspace_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_views(db, ctx, workspace_id)


@router.post("/workspaces/{workspace_id}/views", response_model=Item[ViewOut], status_code=CREATED)
def create_view(workspace_id: int, body: ViewIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.create_view(db, ctx, workspace_id, body)


@router.put("/views/{view_id}", response_model=Item[ViewOut])
def update_view(view_id: int, body: ViewIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.update_view(db, ctx, view_id, body)


@router.delete("/views/{view_id}", status_code=NO_CONTENT)
def delete_view(view_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(VIEW)) -> Response:
    c.delete_view(db, ctx, view_id, row_version)
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- favourites

@router.get("/favorites", response_model=Item[list[FavoriteOut]])
def list_favorites(kind: Literal["favorite", "hidden"] = "favorite", db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_favorites(db, ctx, kind)


@router.put("/favorites", status_code=NO_CONTENT)
def set_favorite(body: FavoriteIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> Response:
    c.set_favorite(db, ctx, body)
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- tags

@router.get("/workspaces/{workspace_id}/tags", response_model=Item[list[TagOut]])
def list_tags(workspace_id: int, db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("projects.tasks.view"))) -> dict:
    return c.list_tags(db, ctx, workspace_id)


@router.post("/workspaces/{workspace_id}/tags", response_model=Item[TagOut], status_code=CREATED)
def create_tag(workspace_id: int, body: TagIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("projects.tasks.edit"))) -> dict:
    return c.create_tag(db, ctx, workspace_id, body)


@router.put("/tags/{tag_id}", response_model=Item[TagOut])
def update_tag(tag_id: int, body: TagIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("projects.tasks.edit"))) -> dict:
    return c.update_tag(db, ctx, tag_id, body)


@router.delete("/tags/{tag_id}", status_code=NO_CONTENT)
def delete_tag(tag_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("projects.tasks.edit"))) -> Response:
    c.delete_tag(db, ctx, tag_id, row_version)
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- history

@router.get("/workspaces/{workspace_id}/activity", response_model=Paginated[ActivityOut])
def workspace_activity(workspace_id: int, action: str | None = None,
                       from_date: date | None = Query(None, alias="fromDate"),
                       to_date: date | None = Query(None, alias="toDate"), q: str | None = None,
                       paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("projects.history.view"))) -> dict:
    return c.workspace_activity(db, ctx, workspace_id, action, from_date, to_date, q, paging)
