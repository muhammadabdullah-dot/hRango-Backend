"""HTTP shape for Custom Form: envelopes, rowVersion text <-> bytes, rows -> response models."""
from typing import Any, TypeVar

from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import ApiModel, paginated
from app.schemas.forms import (AssignedFormDetailOut, AssignedFormOut, FormIn, FormOut, FormSummaryOut, MyResponseOut,
                               ResponseDetailOut, ResponseIn, ResponseOut, ResponseSummaryOut)
from app.services import forms_service as svc

M = TypeVar("M", bound=ApiModel)


def _to(model: type[M], row: dict[str, Any]) -> M:
    values = dict(row)
    if "row_version" in values:
        values["row_version"] = row_version_out(values["row_version"])
    return model(**values)


def _page(result: tuple[int, list[dict[str, Any]]], paging: PageParams, model: type[ApiModel]) -> dict:
    total, rows = result
    return paginated(rows, total, paging.page, paging.page_size, lambda r: _to(model, r))


# --------------------------------------------------------------------------- forms (HR)

def list_forms(db: Db, ctx: RequestContext, q: str | None, status: str | None, paging: PageParams) -> dict:
    return _page(svc.list_forms(db, ctx, q, status, paging.page, paging.page_size), paging, FormSummaryOut)


def get_form(db: Db, ctx: RequestContext, form_id: int) -> dict:
    return {"data": _to(FormOut, svc.get_form(db, ctx, form_id))}


def create_form(db: Db, ctx: RequestContext, body: FormIn) -> dict:
    return {"data": _to(FormOut, svc.save_form(db, ctx, None, body, None))}


def update_form(db: Db, ctx: RequestContext, form_id: int, body: FormIn) -> dict:
    return {"data": _to(FormOut, svc.save_form(db, ctx, form_id, body, row_version_in(body.row_version)))}


def delete_form(db: Db, ctx: RequestContext, form_id: int, row_version: str | None) -> None:
    svc.delete_form(db, ctx, form_id, row_version_in(row_version))


def publish_form(db: Db, ctx: RequestContext, form_id: int, row_version: str | None) -> dict:
    return {"data": _to(FormOut, svc.publish_form(db, ctx, form_id, row_version_in(row_version)))}


def close_form(db: Db, ctx: RequestContext, form_id: int, row_version: str | None) -> dict:
    return {"data": _to(FormOut, svc.close_form(db, ctx, form_id, row_version_in(row_version)))}


def duplicate_form(db: Db, ctx: RequestContext, form_id: int) -> dict:
    return {"data": _to(FormOut, svc.duplicate_form(db, ctx, form_id))}


# --------------------------------------------------------------------------- filling

def list_assigned(db: Db, ctx: RequestContext, q: str | None, paging: PageParams) -> dict:
    return _page(svc.list_assigned(db, ctx, q, paging.page, paging.page_size), paging, AssignedFormOut)


def get_assigned(db: Db, ctx: RequestContext, form_id: int) -> dict:
    return {"data": _to(AssignedFormDetailOut, svc.get_assigned(db, ctx, form_id))}


def submit_response(db: Db, ctx: RequestContext, form_id: int, body: ResponseIn) -> dict:
    return {"data": _to(ResponseOut, svc.submit_response(db, ctx, form_id, body))}


def list_my_responses(db: Db, ctx: RequestContext, q: str | None, paging: PageParams) -> dict:
    return _page(svc.list_my_responses(db, ctx, q, paging.page, paging.page_size), paging, MyResponseOut)


# --------------------------------------------------------------------------- responses (HR)

def list_responses(db: Db, ctx: RequestContext, form_id: int, q: str | None, paging: PageParams) -> dict:
    return _page(svc.list_responses(db, ctx, form_id, q, paging.page, paging.page_size), paging, ResponseOut)


def response_summary(db: Db, ctx: RequestContext, form_id: int) -> dict:
    return {"data": ResponseSummaryOut(**svc.response_summary(db, ctx, form_id))}


def get_response(db: Db, ctx: RequestContext, response_id: int) -> dict:
    return {"data": _to(ResponseDetailOut, svc.get_response(db, ctx, response_id))}
