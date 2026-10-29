"""Project management Docs (Backend Dependencies T1): a workspace's docs, editing, archive, duplicate,
links to tasks, export and comments. Included by routers/projects.py under /projects."""
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import projects_docs_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.projects_docs import (DocArchiveIn, DocCommentIn, DocCommentOut, DocDuplicateIn, DocIn, DocOut,
                                       DocTasksIn)

router = APIRouter()
NO_CONTENT = status.HTTP_204_NO_CONTENT
CREATED = status.HTTP_201_CREATED

VIEW = require("projects.docs.view")
EDIT = require("projects.docs.edit")


@router.get("/workspaces/{workspace_id}/docs", response_model=Paginated[DocOut])
def list_docs(workspace_id: int, folder_id: int | None = Query(None, alias="folderId"),
              list_id: int | None = Query(None, alias="listId"), q: str | None = None,
              include_archived: bool = Query(False, alias="includeArchived"),
              paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
              ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_docs(db, ctx, workspace_id, folder_id, list_id, q, include_archived, paging)


@router.post("/workspaces/{workspace_id}/docs", response_model=Item[DocOut], status_code=CREATED)
def create_doc(workspace_id: int, body: DocIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("projects.docs.create"))) -> dict:
    return c.create_doc(db, ctx, workspace_id, body)


@router.get("/docs/{doc_id}", response_model=Item[DocOut])
def get_doc(doc_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.get_doc(db, ctx, doc_id)


@router.put("/docs/{doc_id}", response_model=Item[DocOut])
def update_doc(doc_id: int, body: DocIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.update_doc(db, ctx, doc_id, body)


@router.delete("/docs/{doc_id}", status_code=NO_CONTENT)
def delete_doc(doc_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("projects.docs.delete"))) -> Response:
    c.delete_doc(db, ctx, doc_id, row_version)
    return Response(status_code=NO_CONTENT)


@router.patch("/docs/{doc_id}/archive", response_model=Item[DocOut])
def archive_doc(doc_id: int, body: DocArchiveIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("projects.docs.archive"))) -> dict:
    return c.archive_doc(db, ctx, doc_id, body)


@router.post("/docs/{doc_id}/duplicate", response_model=Item[DocOut], status_code=CREATED)
def duplicate_doc(doc_id: int, body: DocDuplicateIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("projects.docs.create"))) -> dict:
    return c.duplicate_doc(db, ctx, doc_id, body.title)


@router.put("/docs/{doc_id}/tasks", response_model=Item[DocOut])
def set_doc_tasks(doc_id: int, body: DocTasksIn, db: Db = Depends(get_db), ctx: RequestContext = Depends(EDIT)) -> dict:
    return c.set_doc_tasks(db, ctx, doc_id, body.task_ids)


@router.get("/docs/{doc_id}/export", responses={501: {"description": "EXPORT_NOT_AVAILABLE (not built yet)"}})
def export_doc(doc_id: int, format: Literal["pdf", "docx"] = "pdf", db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("projects.docs.export"))) -> Response:
    c.export_doc(db, ctx, doc_id, format)
    return Response(status_code=NO_CONTENT)


@router.get("/docs/{doc_id}/comments", response_model=Item[list[DocCommentOut]])
def list_doc_comments(doc_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(VIEW)) -> dict:
    return c.list_comments(db, ctx, doc_id)


@router.post("/docs/{doc_id}/comments", response_model=Item[DocCommentOut], status_code=CREATED)
def add_doc_comment(doc_id: int, body: DocCommentIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("projects.comments.create"))) -> dict:
    return c.add_comment(db, ctx, doc_id, body)
