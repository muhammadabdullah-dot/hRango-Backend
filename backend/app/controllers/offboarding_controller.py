"""HTTP shape for End of Employment and the off-boarding checklist settings."""
from typing import Any

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.files import FileRef
from app.schemas.offboarding import (ActiveChecklistFieldOut, ChecklistAnswerOut, ChecklistAnswersIn,
                                     ChecklistFieldOut, ChecklistIn, ChecklistOut, EndOfEmploymentIn,
                                     EndOfEmploymentOut, EndOfEmploymentRowOut, RehireIn, WaitingItemOut)
from app.services import offboarding_service


def _rv(row: dict[str, Any]) -> dict[str, Any]:
    return {**row, "row_version": row_version_out(row["row_version"])}


def _row(row: dict[str, Any]) -> EndOfEmploymentRowOut:
    return EndOfEmploymentRowOut(**_rv(row))


def _record(record: dict[str, Any], company_id: int) -> EndOfEmploymentOut:
    file_id = record.get("file_id")
    return EndOfEmploymentOut(**{**_rv(record),
                                 "file": FileRef(id=str(file_id), name=record.get("file_name"),
                                                 url=file_url(file_id, company_id)) if file_id else None,
                                 "photo_url": file_url(record.get("photo_file_id"), company_id),
                                 "answers": [ChecklistAnswerOut(**a) for a in record["answers"]],
                                 "waiting_for": [WaitingItemOut(**w) for w in record["waiting_for"]]})


def _checklist(row: dict[str, Any]) -> ChecklistOut:
    return ChecklistOut(**{**_rv(row), "fields": [ChecklistFieldOut(**f) for f in row.get("fields", [])]})


# --- End of employment ---------------------------------------------------------------------------

def list_end_of_employment(db: Db, ctx: RequestContext, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows = offboarding_service.list_end_of_employment(db, ctx, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _row)


def get_end_of_employment(db: Db, ctx: RequestContext, record_id: int) -> dict:
    return {"data": _record(offboarding_service.get_end_of_employment(db, ctx, record_id), ctx.company_id)}


def _fields(body: EndOfEmploymentIn) -> dict[str, Any]:
    return body.model_dump(by_alias=False, exclude={"row_version"})


def create_end_of_employment(db: Db, ctx: RequestContext, body: EndOfEmploymentIn) -> dict:
    record = offboarding_service.save_end_of_employment(db, ctx, None, _fields(body), None)
    return {"data": _record(record, ctx.company_id)}


def update_end_of_employment(db: Db, ctx: RequestContext, record_id: int, body: EndOfEmploymentIn) -> dict:
    record = offboarding_service.save_end_of_employment(db, ctx, record_id, _fields(body),
                                                        row_version_in(body.row_version))
    return {"data": _record(record, ctx.company_id)}


def save_checklist_answers(db: Db, ctx: RequestContext, record_id: int, body: ChecklistAnswersIn) -> dict:
    answers = [(a.checklist_field_id, a.answer) for a in body.answers]
    record = offboarding_service.save_checklist_answers(db, ctx, record_id, answers, row_version_in(body.row_version))
    return {"data": _record(record, ctx.company_id)}


def complete_end_of_employment(db: Db, ctx: RequestContext, record_id: int, row_version: str) -> dict:
    record = offboarding_service.complete_end_of_employment(db, ctx, record_id, row_version_in(row_version))
    return {"data": _record(record, ctx.company_id)}


def rehire(db: Db, ctx: RequestContext, record_id: int, body: RehireIn) -> dict:
    record = offboarding_service.rehire(db, ctx, record_id, body.joining_date, row_version_in(body.row_version))
    return {"data": _record(record, ctx.company_id)}


def delete_end_of_employment(db: Db, ctx: RequestContext, record_id: int, row_version: str | None) -> None:
    offboarding_service.delete_end_of_employment(db, ctx, record_id, row_version_in(row_version))


def active_checklist_fields(db: Db, ctx: RequestContext) -> dict:
    return {"data": [ActiveChecklistFieldOut(**f) for f in offboarding_service.active_checklist_fields(db, ctx)]}


# --- Off-boarding checklist settings -------------------------------------------------------------

def list_checklists(db: Db, ctx: RequestContext, q: str | None, is_active: bool | None, paging: PageParams) -> dict:
    total, rows = offboarding_service.list_checklists(db, ctx, q, is_active, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _checklist)


def get_checklist(db: Db, ctx: RequestContext, checklist_id: int) -> dict:
    return {"data": _checklist(offboarding_service.get_checklist(db, ctx, checklist_id))}


def _checklist_fields(body: ChecklistIn) -> list[dict[str, Any]]:
    return [f.model_dump(by_alias=False) for f in body.fields]


def create_checklist(db: Db, ctx: RequestContext, body: ChecklistIn) -> dict:
    row = offboarding_service.save_checklist(db, ctx, None, body.name, body.description, body.is_active,
                                             _checklist_fields(body), None)
    return {"data": _checklist(row)}


def update_checklist(db: Db, ctx: RequestContext, checklist_id: int, body: ChecklistIn) -> dict:
    row = offboarding_service.save_checklist(db, ctx, checklist_id, body.name, body.description, body.is_active,
                                             _checklist_fields(body), row_version_in(body.row_version))
    return {"data": _checklist(row)}


def delete_checklist(db: Db, ctx: RequestContext, checklist_id: int, row_version: str | None) -> None:
    offboarding_service.delete_checklist(db, ctx, checklist_id, row_version_in(row_version))
