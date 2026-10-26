"""Off-boarding rules. Checks that need the database (one pending record per person, the waiting
list, checklist answer types and ranges) live in the procedures; rules that do not live here."""
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import forbidden, invalid
from app.middlewares.auth import RequestContext
from app.repos import offboarding_repo


def _company_level(ctx: RequestContext) -> None:
    if not (ctx.scopes - {"own", ""}):
        raise forbidden()


# --- End of employment ---------------------------------------------------------------------------

def list_end_of_employment(db: Db, ctx: RequestContext, filters: dict[str, Any],
                           page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    if filters["from_date"] and filters["to_date"] and filters["from_date"] > filters["to_date"]:
        raise invalid("From must not be after To.", "to")
    return offboarding_repo.list_end_of_employment(db, ctx.company_id, ctx.user_id, filters, page, page_size)


def get_end_of_employment(db: Db, ctx: RequestContext, record_id: int) -> dict[str, Any]:
    return offboarding_repo.get_end_of_employment(db, ctx.company_id, ctx.user_id, record_id)


def save_end_of_employment(db: Db, ctx: RequestContext, record_id: int | None, fields: dict[str, Any],
                           row_version: bytes | None) -> dict[str, Any]:
    if fields["serve_notice"] and fields["last_working_date"] is None:
        raise invalid("Last working date is required with a notice period.", "lastWorkingDate")
    if fields["replacement_id"] is not None and fields["replacement_id"] == fields["employee_id"]:
        raise invalid("Choose another employee.", "replacementId")
    if fields["delegatee_id"] is not None and fields["delegatee_id"] == fields["employee_id"]:
        raise invalid("Choose another employee.", "delegateeId")
    return offboarding_repo.save_end_of_employment(db, ctx.company_id, ctx.user_id, record_id, fields, row_version)


def _answer_text(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def save_checklist_answers(db: Db, ctx: RequestContext, record_id: int, answers: list[tuple[int, Any]],
                           row_version: bytes) -> dict[str, Any]:
    rows = [{"checklist_field_id": field_id, "answer": _answer_text(value)} for field_id, value in answers]
    return offboarding_repo.save_checklist_answers(db, ctx.company_id, ctx.user_id, record_id, rows, row_version)


def complete_end_of_employment(db: Db, ctx: RequestContext, record_id: int, row_version: bytes) -> dict[str, Any]:
    return offboarding_repo.complete_end_of_employment(db, ctx.company_id, ctx.user_id, record_id, row_version)


def rehire(db: Db, ctx: RequestContext, record_id: int, joining_date: date, row_version: bytes) -> dict[str, Any]:
    return offboarding_repo.rehire(db, ctx.company_id, ctx.user_id, record_id, joining_date, row_version)


def delete_end_of_employment(db: Db, ctx: RequestContext, record_id: int, row_version: bytes) -> None:
    offboarding_repo.delete_end_of_employment(db, ctx.company_id, ctx.user_id, record_id, row_version)


def active_checklist_fields(db: Db, ctx: RequestContext) -> list[dict[str, Any]]:
    return offboarding_repo.active_checklist_fields(db, ctx.company_id)


# --- Off-boarding checklist settings -------------------------------------------------------------

def list_checklists(db: Db, ctx: RequestContext, search: str | None, is_active: bool | None,
                    page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    _company_level(ctx)
    return offboarding_repo.list_checklists(db, ctx.company_id, search, is_active, page, page_size)


def get_checklist(db: Db, ctx: RequestContext, checklist_id: int) -> dict[str, Any]:
    _company_level(ctx)
    return offboarding_repo.get_checklist(db, ctx.company_id, checklist_id)


def save_checklist(db: Db, ctx: RequestContext, checklist_id: int | None, name: str, description: str | None,
                   is_active: bool, fields: list[dict[str, Any]], row_version: bytes | None) -> dict[str, Any]:
    _company_level(ctx)
    for i, f in enumerate(fields):
        if f["field_type"] == "number" and None not in (f["min_value"], f["max_value"]) and f["min_value"] > f["max_value"]:
            raise invalid("Max must not be less than Min.", f"fields.{i}.maxValue")
        if f["field_type"] == "string" and None not in (f["min_length"], f["max_length"]) and f["min_length"] > f["max_length"]:
            raise invalid("Max must not be less than Min.", f"fields.{i}.maxLength")
    return offboarding_repo.save_checklist(db, ctx.company_id, ctx.user_id, checklist_id, name, description,
                                           is_active, fields, row_version)


def delete_checklist(db: Db, ctx: RequestContext, checklist_id: int, row_version: bytes) -> None:
    _company_level(ctx)
    offboarding_repo.delete_checklist(db, ctx.company_id, ctx.user_id, checklist_id, row_version)
