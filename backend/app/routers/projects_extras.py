"""Project management extras: Notepad (T3), overdue settings (T5), recents and dashboards (T7) and the
Personal List (T11). Notes, the Personal List and recents are the caller's own: any signed-in person who
opens Project Management (projects.workspaces.view) uses them. Included by routers/projects.py under
/projects."""
from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import projects_extras_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.projects_extras import (HomeDashboardOut, NoteArchiveIn, NoteConvertedOut, NoteConvertIn, NoteIn,
                                         NoteOut, NoteVersionOut, OverdueSettingsIn, OverdueSettingsOut,
                                         PersonalItemDoneIn, PersonalItemIn, PersonalItemOut, RecentIn, RecentOut,
                                         ScopeDashboardOut)

router = APIRouter()
NO_CONTENT = status.HTTP_204_NO_CONTENT
CREATED = status.HTTP_201_CREATED

# The caller's own records (notes, personal list, recents).
OWN = require("projects.workspaces.view")
DASHBOARD = require("projects.tasks.view")


# --------------------------------------------------------------------------- notepad

@router.get("/notes", response_model=Paginated[NoteOut])
def list_notes(archived: bool = False, q: str | None = None, paging: PageParams = Depends(page_params),
               db: Db = Depends(get_db), ctx: RequestContext = Depends(OWN)) -> dict:
    return c.list_notes(db, ctx, archived, q, paging)


@router.post("/notes", response_model=Item[NoteOut], status_code=CREATED)
def create_note(body: NoteIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(OWN)) -> dict:
    return c.create_note(db, ctx, body)


@router.put("/notes/{note_id}", response_model=Item[NoteOut])
def update_note(note_id: int, body: NoteIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(OWN)) -> dict:
    return c.update_note(db, ctx, note_id, body)


@router.patch("/notes/{note_id}/archive", response_model=Item[NoteOut])
def archive_note(note_id: int, body: NoteArchiveIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(OWN)) -> dict:
    return c.archive_note(db, ctx, note_id, body)


@router.delete("/notes/{note_id}", status_code=NO_CONTENT)
def delete_note(note_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(OWN)) -> Response:
    c.delete_note(db, ctx, note_id, row_version)
    return Response(status_code=NO_CONTENT)


@router.get("/notes/{note_id}/history", response_model=Item[list[NoteVersionOut]])
def note_history(note_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(OWN)) -> dict:
    return c.note_history(db, ctx, note_id)


@router.post("/notes/{note_id}/convert", response_model=Item[NoteConvertedOut])
def convert_note(note_id: int, body: NoteConvertIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(OWN)) -> dict:
    """Also needs projects.tasks.create (to a task) or projects.docs.create (to a doc)."""
    return c.convert_note(db, ctx, note_id, body)


# --------------------------------------------------------------------------- personal list

@router.get("/personal-list", response_model=Item[list[PersonalItemOut]])
def list_personal(db: Db = Depends(get_db), ctx: RequestContext = Depends(OWN)) -> dict:
    return c.list_personal(db, ctx)


@router.post("/personal-list", response_model=Item[PersonalItemOut], status_code=CREATED)
def add_personal(body: PersonalItemIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(OWN)) -> dict:
    return c.add_personal(db, ctx, body.title, body.due_date)


@router.patch("/personal-list/{item_id}", response_model=Item[PersonalItemOut])
def set_personal_done(item_id: int, body: PersonalItemDoneIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(OWN)) -> dict:
    return c.set_personal_done(db, ctx, item_id, body.done, body.row_version)


@router.delete("/personal-list/{item_id}", status_code=NO_CONTENT)
def delete_personal(item_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(OWN)) -> Response:
    c.delete_personal(db, ctx, item_id, row_version)
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- recents

@router.get("/recents", response_model=Item[list[RecentOut]])
def list_recents(workspace_id: int | None = Query(None, alias="workspaceId"),
                 folder_id: int | None = Query(None, alias="folderId"), limit: int = Query(8, ge=1, le=50),
                 db: Db = Depends(get_db), ctx: RequestContext = Depends(OWN)) -> dict:
    return c.list_recents(db, ctx, workspace_id, folder_id, limit)


@router.post("/recents", status_code=NO_CONTENT)
def record_recent(body: RecentIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(OWN)) -> Response:
    c.record_recent(db, ctx, body.entity_type, body.entity_id)
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- dashboards

@router.get("/dashboard/home", response_model=Item[HomeDashboardOut])
def home_dashboard(db: Db = Depends(get_db), ctx: RequestContext = Depends(DASHBOARD)) -> dict:
    return c.home_dashboard(db, ctx)


@router.get("/workspaces/{workspace_id}/dashboard", response_model=Item[ScopeDashboardOut])
def workspace_dashboard(workspace_id: int, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(DASHBOARD)) -> dict:
    return c.scope_dashboard(db, ctx, workspace_id, None)


@router.get("/folders/{folder_id}/dashboard", response_model=Item[ScopeDashboardOut])
def folder_dashboard(folder_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(DASHBOARD)) -> dict:
    return c.scope_dashboard(db, ctx, None, folder_id)


# --------------------------------------------------------------------------- overdue settings

@router.get("/workspaces/{workspace_id}/settings/overdue", response_model=Item[OverdueSettingsOut])
def get_overdue_settings(workspace_id: int, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("projects.workspaces.view"))) -> dict:
    return c.get_overdue_settings(db, ctx, workspace_id)


@router.put("/workspaces/{workspace_id}/settings/overdue", response_model=Item[OverdueSettingsOut])
def save_overdue_settings(workspace_id: int, body: OverdueSettingsIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("projects.workspaces.edit"))) -> dict:
    return c.save_overdue_settings(db, ctx, workspace_id, body)
