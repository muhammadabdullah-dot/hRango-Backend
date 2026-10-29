"""Custom Form data access: frm.usp_form_* (forms, filling, responses)."""
from datetime import date
from typing import Any

from app.core.db import Db

Row = dict[str, Any]
Rows = list[Row]


def _page(sets: list[Rows]) -> tuple[int, Rows]:
    return sets[0][0]["total"], sets[1]


# --------------------------------------------------------------------------- forms (HR)

def list_forms(db: Db, company_id: int, search: str | None, status: str | None, page: int,
               page_size: int) -> tuple[int, Rows]:
    return _page(db.call_sets("frm.usp_form_list", company_id=company_id, search=search, status=status, page=page,
                              page_size=page_size))


def get_form(db: Db, company_id: int, form_id: int) -> Row:
    return db.call_one("frm.usp_form_get", company_id=company_id, id=form_id)


def save_form(db: Db, company_id: int, actor_user_id: int, form_id: int | None, title: str, description: str | None,
              category: str | None, closes_on: date | None, audience_kind: str, audience_ids: str,
              one_per_person: bool, anonymous: bool, sections: str, fields: str, row_version: bytes | None) -> Row:
    return db.call_one("frm.usp_form_save", company_id=company_id, actor_user_id=actor_user_id, id=form_id, title=title,
                       description=description, category=category, closes_on=closes_on, audience_kind=audience_kind,
                       audience_ids=audience_ids, is_one_per_person=one_per_person, is_anonymous=anonymous,
                       sections=sections, fields=fields, row_version=row_version)


def delete_form(db: Db, company_id: int, actor_user_id: int, form_id: int, row_version: bytes) -> None:
    db.call("frm.usp_form_delete", company_id=company_id, actor_user_id=actor_user_id, id=form_id,
            row_version=row_version)


def form_action(db: Db, proc: str, company_id: int, actor_user_id: int, form_id: int, row_version: bytes) -> Row:
    """frm.usp_form_publish / _close."""
    return db.call_one(f"frm.usp_form_{proc}", company_id=company_id, actor_user_id=actor_user_id, id=form_id,
                       row_version=row_version)


def duplicate_form(db: Db, company_id: int, actor_user_id: int, form_id: int) -> Row:
    return db.call_one("frm.usp_form_duplicate", company_id=company_id, actor_user_id=actor_user_id, id=form_id)


# --------------------------------------------------------------------------- filling

def list_assigned(db: Db, company_id: int, actor_user_id: int, search: str | None, page: int,
                  page_size: int) -> tuple[int, Rows]:
    return _page(db.call_sets("frm.usp_form_assigned_list", company_id=company_id, actor_user_id=actor_user_id,
                              search=search, page=page, page_size=page_size))


def get_assigned(db: Db, company_id: int, actor_user_id: int, form_id: int) -> Row:
    return db.call_one("frm.usp_form_assigned_get", company_id=company_id, actor_user_id=actor_user_id, id=form_id)


def submit_response(db: Db, company_id: int, actor_user_id: int, form_id: int, answers: str) -> Row:
    return db.call_one("frm.usp_form_response_submit", company_id=company_id, actor_user_id=actor_user_id, id=form_id,
                       answers=answers)


def list_my_responses(db: Db, company_id: int, actor_user_id: int, search: str | None, page: int,
                      page_size: int) -> tuple[int, Rows]:
    return _page(db.call_sets("frm.usp_form_my_response_list", company_id=company_id, actor_user_id=actor_user_id,
                              search=search, page=page, page_size=page_size))


# --------------------------------------------------------------------------- responses (HR)

def list_responses(db: Db, company_id: int, actor_user_id: int, form_id: int, search: str | None, page: int,
                   page_size: int) -> tuple[int, Rows]:
    return _page(db.call_sets("frm.usp_form_response_list", company_id=company_id, actor_user_id=actor_user_id,
                              id=form_id, search=search, page=page, page_size=page_size))


def response_summary(db: Db, company_id: int, form_id: int) -> list[Rows]:
    return db.call_sets("frm.usp_form_response_summary", company_id=company_id, id=form_id)


def get_response(db: Db, company_id: int, actor_user_id: int, response_id: int, as_hr: bool) -> Row:
    return db.call_one("frm.usp_form_response_get", company_id=company_id, actor_user_id=actor_user_id, id=response_id,
                       as_hr=as_hr)
