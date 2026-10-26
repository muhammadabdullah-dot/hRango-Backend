"""Roster rules. Checks that need the data (overlapping enrolments, dates inside the group's period,
who the caller reaches) live in the procedures; the rest lives here."""
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import invalid
from app.middlewares.auth import RequestContext
from app.repos import roster_repo

# Enrolments are employee records; the procedures reach only the employees these permissions allow.
ENROLMENTS_VIEW = "roster.enrolments.view"
ENROLMENTS_ENROLL = "roster.enrolments.enroll"
ENROLMENTS_EDIT = "roster.enrolments.edit"
ENROLMENTS_DELETE = "roster.enrolments.delete"


def list_groups(db: Db, ctx: RequestContext, search: str | None, is_active: bool | None,
                page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return roster_repo.list_groups(db, ctx.company_id, search, is_active, page, page_size)


def get_group(db: Db, ctx: RequestContext, group_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    return roster_repo.get_group(db, ctx.company_id, group_id)


def save_group(db: Db, ctx: RequestContext, group_id: int | None, title: str, from_date: date, to_date: date | None,
               description: str | None, is_active: bool, days: list[dict[str, Any]],
               row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if to_date is not None and to_date < from_date:
        raise invalid("To date cannot be before the from date.", "toDate")
    if not any(not d["is_day_off"] for d in days):
        raise invalid("At least one day must be a working day.", "days")
    if any(not d["is_day_off"] and d["time_slot_id"] is None for d in days):
        raise invalid("Pick a time slot for each working day.", "days")
    return roster_repo.save_group(db, ctx.company_id, ctx.user_id, group_id, title, from_date, to_date, description,
                                  is_active, days, row_version)


def delete_group(db: Db, ctx: RequestContext, group_id: int, row_version: bytes) -> None:
    roster_repo.delete_group(db, ctx.company_id, ctx.user_id, group_id, row_version)


def list_enrolments(db: Db, ctx: RequestContext, group_id: int, status: str | None, search: str | None,
                    page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return roster_repo.list_enrolments(db, ctx.company_id, ctx.user_id, ENROLMENTS_VIEW, group_id, status, search,
                                       page, page_size)


def get_enrolment(db: Db, ctx: RequestContext, enrolment_id: int) -> dict[str, Any]:
    return roster_repo.get_enrolment(db, ctx.company_id, ctx.user_id, ENROLMENTS_VIEW, enrolment_id)


def enrol(db: Db, ctx: RequestContext, group_id: int, employee_ids: list[int], start_date: date,
          end_date: date | None) -> list[dict[str, Any]]:
    if end_date is not None and end_date < start_date:
        raise invalid("End date cannot be before the start date.", "endDate")
    return roster_repo.enrol(db, ctx.company_id, ctx.user_id, ENROLMENTS_ENROLL, group_id, employee_ids,
                             start_date, end_date)


def save_enrolment(db: Db, ctx: RequestContext, enrolment_id: int, start_date: date, end_date: date | None,
                   row_version: bytes) -> dict[str, Any]:
    if end_date is not None and end_date < start_date:
        raise invalid("End date cannot be before the start date.", "endDate")
    return roster_repo.save_enrolment(db, ctx.company_id, ctx.user_id, ENROLMENTS_EDIT, enrolment_id, start_date,
                                      end_date, row_version)


def discontinue(db: Db, ctx: RequestContext, enrolment_id: int, end_date: date | None,
                row_version: bytes) -> dict[str, Any]:
    """Ends the enrolment on end_date (today when blank)."""
    current = roster_repo.get_enrolment(db, ctx.company_id, ctx.user_id, ENROLMENTS_EDIT, enrolment_id)
    end_date = end_date or date.today()
    if end_date < current["start_date"]:
        raise invalid("The enrolment has not started by then. Delete it instead.", "endDate")
    return roster_repo.save_enrolment(db, ctx.company_id, ctx.user_id, ENROLMENTS_EDIT, enrolment_id,
                                      current["start_date"], end_date, row_version)


def delete_enrolment(db: Db, ctx: RequestContext, enrolment_id: int, row_version: bytes) -> None:
    roster_repo.delete_enrolment(db, ctx.company_id, ctx.user_id, ENROLMENTS_DELETE, enrolment_id, row_version)
