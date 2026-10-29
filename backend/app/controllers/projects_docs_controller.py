"""HTTP shape for project management Docs: envelopes, row versions as text, covers as signed links."""
from app.controllers.projects_controller import to_model
from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.projects_docs import DocArchiveIn, DocCommentIn, DocCommentOut, DocIn, DocOut
from app.services import projects_docs_service as s


def _doc(row: dict, company_id: int) -> DocOut:
    return to_model(DocOut, row, company_id)


def list_docs(db: Db, ctx: RequestContext, workspace_id: int, folder_id: int | None, list_id: int | None,
              q: str | None, include_archived: bool, paging: PageParams) -> dict:
    total, rows = s.list_docs(db, ctx, workspace_id, folder_id, list_id, q, include_archived, paging.page,
                              paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: _doc(r, ctx.company_id))


def get_doc(db: Db, ctx: RequestContext, doc_id: int) -> dict:
    return {"data": _doc(s.get_doc(db, ctx, doc_id), ctx.company_id)}


def create_doc(db: Db, ctx: RequestContext, workspace_id: int, body: DocIn) -> dict:
    return {"data": _doc(s.create_doc(db, ctx, workspace_id, body), ctx.company_id)}


def update_doc(db: Db, ctx: RequestContext, doc_id: int, body: DocIn) -> dict:
    return {"data": _doc(s.update_doc(db, ctx, doc_id, body, row_version_in(body.row_version)), ctx.company_id)}


def delete_doc(db: Db, ctx: RequestContext, doc_id: int, row_version: str | None) -> None:
    s.delete_doc(db, ctx, doc_id, row_version_in(row_version))


def archive_doc(db: Db, ctx: RequestContext, doc_id: int, body: DocArchiveIn) -> dict:
    row = s.archive_doc(db, ctx, doc_id, body.archived, row_version_in(body.row_version))
    return {"data": _doc(row, ctx.company_id)}


def duplicate_doc(db: Db, ctx: RequestContext, doc_id: int, title: str | None) -> dict:
    return {"data": _doc(s.duplicate_doc(db, ctx, doc_id, title), ctx.company_id)}


def set_doc_tasks(db: Db, ctx: RequestContext, doc_id: int, task_ids: list[int]) -> dict:
    return {"data": _doc(s.set_doc_tasks(db, ctx, doc_id, task_ids), ctx.company_id)}


def export_doc(db: Db, ctx: RequestContext, doc_id: int, fmt: str) -> None:
    s.export_doc(db, ctx, doc_id, fmt)


def list_comments(db: Db, ctx: RequestContext, doc_id: int) -> dict:
    return {"data": [to_model(DocCommentOut, r) for r in s.list_comments(db, ctx, doc_id)]}


def add_comment(db: Db, ctx: RequestContext, doc_id: int, body: DocCommentIn) -> dict:
    return {"data": to_model(DocCommentOut, s.add_comment(db, ctx, doc_id, body.body, body.parent_id))}
