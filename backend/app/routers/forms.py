"""Custom Form: HR builds forms, sends them to an audience and collects the answers.

Forms (HR, forms.forms.*), filling for everyone (forms.my_forms.*: which forms a person sees is decided
by each form's audience, not by scopes) and responses (HR, forms.responses.*). The fixed paths
(/assigned, /my-responses, /responses/{id}) are registered before /{form_id}.
"""
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import forms_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require, require_any
from app.schemas.common import Item, Paginated
from app.schemas.forms import (AssignedFormDetailOut, AssignedFormOut, FormIn, FormOut, FormSummaryOut, MyResponseOut,
                               ResponseDetailOut, ResponseIn, ResponseOut, ResponseSummaryOut, RowVersionIn)

router = APIRouter(prefix="/forms", tags=["forms"])
NO_CONTENT = status.HTTP_204_NO_CONTENT
CREATED = status.HTTP_201_CREATED


# --------------------------------------------------------------------------- filling (everyone)

@router.get("/assigned", response_model=Paginated[AssignedFormOut])
def list_assigned(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("forms.my_forms.view"))) -> dict:
    """Published and closed forms whose audience includes the caller (never drafts), open ones first."""
    return c.list_assigned(db, ctx, q, paging)


@router.get("/assigned/{form_id}", response_model=Item[AssignedFormDetailOut])
def get_assigned(form_id: int, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("forms.my_forms.view"))) -> dict:
    """One form to fill, with its sections and fields. 404 when it is not meant for the caller."""
    return c.get_assigned(db, ctx, form_id)


@router.get("/my-responses", response_model=Paginated[MyResponseOut])
def list_my_responses(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("forms.my_forms.view"))) -> dict:
    """The caller's own submissions, anonymous forms included, newest first."""
    return c.list_my_responses(db, ctx, q, paging)


@router.get("/responses/{response_id}", response_model=Item[ResponseDetailOut])
def get_response(response_id: int, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require_any("forms.responses.view", "forms.my_forms.view"))) -> dict:
    """One response with its form's questions: for HR (forms.responses.view), or for its author."""
    return c.get_response(db, ctx, response_id)


# --------------------------------------------------------------------------- forms (HR)

@router.get("", response_model=Paginated[FormSummaryOut])
def list_forms(q: str | None = None, status_: Literal["draft", "published", "closed"] | None = Query(None, alias="status"),
               paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("forms.forms.view"))) -> dict:
    """Newest change first; q matches title, category and description; status is the effective status."""
    return c.list_forms(db, ctx, q, status_, paging)


@router.post("", response_model=Item[FormOut], status_code=CREATED)
def create_form(body: FormIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("forms.forms.create"))) -> dict:
    """Saves a draft."""
    return c.create_form(db, ctx, body)


@router.get("/{form_id}", response_model=Item[FormOut])
def get_form(form_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("forms.forms.view"))) -> dict:
    return c.get_form(db, ctx, form_id)


@router.put("/{form_id}", response_model=Item[FormOut])
def update_form(form_id: int, body: FormIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("forms.forms.edit"))) -> dict:
    """The whole form. Once a question has answers it keeps its type and options and cannot be removed;
    once the form has responses its anonymity is fixed."""
    return c.update_form(db, ctx, form_id, body)


@router.delete("/{form_id}", status_code=NO_CONTENT)
def delete_form(form_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("forms.forms.delete"))) -> Response:
    """With its responses. 409 FORM_HAS_RESPONSES while it is open and has responses."""
    c.delete_form(db, ctx, form_id, row_version)
    return Response(status_code=NO_CONTENT)


@router.post("/{form_id}/publish", response_model=Item[FormOut])
def publish_form(form_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("forms.forms.publish"))) -> dict:
    """A draft, or a closed form (reopen). 409 FORM_PUBLISHED; 422 without questions or with a past closesOn."""
    return c.publish_form(db, ctx, form_id, body.row_version)


@router.post("/{form_id}/close", response_model=Item[FormOut])
def close_form(form_id: int, body: RowVersionIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("forms.forms.publish"))) -> dict:
    """No more answers; the responses stay. 409 FORM_NOT_PUBLISHED."""
    return c.close_form(db, ctx, form_id, body.row_version)


@router.post("/{form_id}/duplicate", response_model=Item[FormOut], status_code=CREATED)
def duplicate_form(form_id: int, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("forms.forms.create"))) -> dict:
    """A draft "Copy of ..." with the same questions, new ids and no responses."""
    return c.duplicate_form(db, ctx, form_id)


# --------------------------------------------------------------------------- answering and responses

@router.post("/{form_id}/responses", response_model=Item[ResponseOut], status_code=CREATED)
def submit_response(form_id: int, body: ResponseIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("forms.my_forms.submit"))) -> dict:
    """The caller's answers. 422 fieldErrors answers.<fieldId>; 409 FORM_NOT_PUBLISHED, FORM_CLOSED,
    ALREADY_RESPONDED; 404 when the form is not for the caller."""
    return c.submit_response(db, ctx, form_id, body)


@router.get("/{form_id}/responses", response_model=Paginated[ResponseOut])
def list_responses(form_id: int, q: str | None = None, paging: PageParams = Depends(page_params),
                   db: Db = Depends(get_db), ctx: RequestContext = Depends(require("forms.responses.view"))) -> dict:
    """Newest first; q matches the respondent's name or code (named forms only). Respondent null when anonymous."""
    return c.list_responses(db, ctx, form_id, q, paging)


@router.get("/{form_id}/responses/summary", response_model=Item[ResponseSummaryOut])
def response_summary(form_id: int, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("forms.responses.view"))) -> dict:
    """Counts per answer of choice, dropdown, checkbox and rating questions."""
    return c.response_summary(db, ctx, form_id)
