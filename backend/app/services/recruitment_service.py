"""Recruitment rules. Checks that need the data (pipeline stages, live offers, vacancies, panels, scope) live in
the rec procedures; this layer checks what it can without the database, shapes the JSON the procedures
read, and runs the steps that span several procedures in one transaction: applying with a new applicant,
and hiring (rec prepare -> hr.usp_employee_save -> rec complete). `code` is the permission the endpoint
required; scoped procedures filter with it."""
import calendar
import json
from datetime import date, datetime, timedelta
from typing import Any

from app.core.db import Db
from app.core.errors import AppError, invalid
from app.middlewares.auth import RequestContext
from app.repos import recruitment_repo as repo
from app.schemas.recruitment import (ApplicantIn, ApplicationIn, CompleteIn, EvaluationIn, HireIn, InterviewIn,
                                     OfferIn, OpeningIn)

Sets = list[list[dict[str, Any]]]


def _dates(start: date | None, end: date | None, field: str) -> None:
    if start and end and end < start:
        raise invalid("This date cannot be before the start date.", field)


def add_months(day: date, months: int) -> date:
    month = day.month - 1 + months
    year, month = day.year + month // 12, month % 12 + 1
    return date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


def _local(value: datetime) -> datetime:
    """Interview times are local wall-clock times; an offset sent by a client is dropped, not converted."""
    return value.replace(tzinfo=None, microsecond=0)


# ---------------------------------------------------------------- dashboard

def dashboard(db: Db, ctx: RequestContext, code: str, year: int | None, month: int | None) -> dict[str, Any]:
    year = year or date.today().year
    tiles, months, interviews, activity = repo.dashboard(db, ctx.company_id, ctx.user_id, code, year, month)
    return {"year": year, "month": month, "tiles": tiles[0], "job_statistics": months,
            "upcoming_interviews": interviews, "recent_activity": activity}


# ---------------------------------------------------------------- job openings

def list_openings(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], page: int,
                  page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return repo.list_openings(db, ctx.company_id, ctx.user_id, code, filters, page, page_size)


def get_opening(db: Db, ctx: RequestContext, code: str, opening_id: int) -> dict[str, Any]:
    return repo.get_opening(db, ctx.company_id, ctx.user_id, code, opening_id)


def save_opening(db: Db, ctx: RequestContext, code: str, opening_id: int | None, body: OpeningIn,
                 row_version: bytes | None) -> dict[str, Any]:
    if body.experience_from_years is not None and body.experience_to_years is not None \
            and body.experience_to_years < body.experience_from_years:
        raise invalid("Experience To cannot be less than Experience From.", "experienceToYears")
    if body.salary_from is not None and body.salary_to is not None and body.salary_to < body.salary_from:
        raise invalid("Salary To cannot be less than Salary From.", "salaryTo")
    _dates(body.posted_on, body.apply_by, "applyBy")
    _dates(body.posted_on, body.close_on, "closeOn")
    if not body.title and not body.open_position_id and not body.job_title_id:
        raise invalid("Job title is required.", "title")
    fields = body.model_dump(by_alias=False, exclude={"row_version"})
    return repo.save_opening(db, ctx.company_id, ctx.user_id, code, opening_id, fields, row_version)


def delete_opening(db: Db, ctx: RequestContext, code: str, opening_id: int, row_version: bytes) -> None:
    repo.delete_opening(db, ctx.company_id, ctx.user_id, code, opening_id, row_version)


def opening_status(db: Db, ctx: RequestContext, code: str, opening_id: int, action: str,
                   row_version: bytes) -> dict[str, Any]:
    return repo.opening_status(db, ctx.company_id, ctx.user_id, code, opening_id, action, row_version)


# ---------------------------------------------------------------- applicants

def _applicant_fields(body: ApplicantIn) -> dict[str, Any]:
    return body.model_dump(by_alias=False, exclude={"row_version"})


def list_applicants(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return repo.list_applicants(db, ctx.company_id, ctx.user_id, code, filters, page, page_size)


def get_applicant(db: Db, ctx: RequestContext, code: str, applicant_id: int) -> Sets:
    return repo.get_applicant(db, ctx.company_id, ctx.user_id, code, applicant_id)


def save_applicant(db: Db, ctx: RequestContext, code: str, applicant_id: int | None, body: ApplicantIn,
                   row_version: bytes | None) -> dict[str, Any]:
    return repo.save_applicant(db, ctx.company_id, ctx.user_id, code, applicant_id, _applicant_fields(body),
                               row_version)


def delete_applicant(db: Db, ctx: RequestContext, code: str, applicant_id: int, row_version: bytes) -> None:
    repo.delete_applicant(db, ctx.company_id, ctx.user_id, code, applicant_id, row_version)


# ---------------------------------------------------------------- applications

def list_applications(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], page: int,
                      page_size: int) -> tuple[int, list[dict[str, Any]]]:
    _dates(filters.get("from_date"), filters.get("to_date"), "toDate")
    return repo.list_applications(db, ctx.company_id, ctx.user_id, code, filters, page, page_size)


def get_application(db: Db, ctx: RequestContext, code: str, application_id: int) -> Sets:
    return repo.get_application(db, ctx.company_id, ctx.user_id, code, application_id)


def add_application(db: Db, ctx: RequestContext, code: str, body: ApplicationIn) -> Sets:
    """Applies an existing applicant, or adds the applicant given and applies them, in one transaction."""
    if (body.applicant_id is None) == (body.applicant is None):
        raise AppError(422, "VALIDATION_FAILED", "Choose an applicant or enter a new one.",
                       {"applicantId": "Choose an applicant or enter a new one."})
    with db.transaction():
        applicant_id = body.applicant_id
        if body.applicant is not None:
            applicant_id = int(repo.save_applicant(db, ctx.company_id, ctx.user_id, code, None,
                                                   _applicant_fields(body.applicant), None)["id"])
        return repo.add_application(db, ctx.company_id, ctx.user_id, code, body.job_opening_id, applicant_id,
                                    body.applied_on, body.source, body.cover_letter, body.remarks)


def move_application(db: Db, ctx: RequestContext, code: str, application_id: int, stage: str, remarks: str | None,
                     row_version: bytes) -> Sets:
    return repo.move_application(db, ctx.company_id, ctx.user_id, code, application_id, stage, remarks, row_version)


def close_application(db: Db, ctx: RequestContext, code: str, application_id: int, stage: str,
                      rejection_reason_id: int | None, remarks: str | None, row_version: bytes) -> Sets:
    return repo.close_application(db, ctx.company_id, ctx.user_id, code, application_id, stage, rejection_reason_id,
                                  remarks, row_version)


def delete_application(db: Db, ctx: RequestContext, code: str, application_id: int, row_version: bytes) -> None:
    repo.delete_application(db, ctx.company_id, ctx.user_id, code, application_id, row_version)


def hire(db: Db, ctx: RequestContext, code: str, application_id: int, body: HireIn, row_version: bytes) -> Sets:
    """Creates the employee from the application and its accepted offer, as one unit: the hr employee and
    first employment period (hr.usp_employee_save), the joining salary, the documents, the filled vacancy,
    the event and the hiring manager's notification. Any refusal undoes all of it."""
    with db.transaction():
        prep = repo.hire_prepare(db, ctx.company_id, ctx.user_id, code, application_id, row_version)
        joining = body.joining_date or prep["joining_date"]
        branch_id = body.branch_id or prep["branch_id"]
        if not branch_id:
            raise invalid("Choose the station the new employee joins.", "branchId")
        months = int(prep["probation_months"] or 0)
        status = body.status or ("probation" if months > 0 else "active")
        probation_end = body.probation_end_date
        if probation_end is None and status == "probation" and months > 0:
            probation_end = add_months(joining, months) - timedelta(days=1)
        _dates(joining, probation_end, "probationEndDate")
        employee = repo.save_employee(db, ctx.company_id, ctx.user_id, code, {
            "code": body.code, "first_name": prep["first_name"], "last_name": prep["last_name"],
            "gender": prep["gender"], "date_of_birth": prep["date_of_birth"], "email": prep["email"],
            "phone_1": prep["phone"], "set_cnic": body.cnic is not None, "cnic": body.cnic,
            "branch_id": branch_id,
            "department_id": body.department_id or prep["department_id"],
            "designation_id": body.designation_id or prep["designation_id"],
            "job_title_id": body.job_title_id or prep["job_title_id"],
            "employment_type_id": body.employment_type_id or prep["employment_type_id"],
            "line_manager_id": body.line_manager_id or prep["line_manager_id"],
            "status": status, "salary_frequency": prep["salary_frequency"], "joining_date": joining,
            "probation_end_date": probation_end,
        })
        salary = body.salary if body.salary is not None else prep["offered_salary"]
        return repo.hire_complete(db, ctx.company_id, ctx.user_id, code, application_id, row_version,
                                  int(employee["id"]), salary, joining, body.remarks)


# ---------------------------------------------------------------- interviews

def list_interviews(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    _dates(filters.get("from_date"), filters.get("to_date"), "toDate")
    return repo.list_interviews(db, ctx.company_id, ctx.user_id, code, filters, page, page_size)


def get_interview(db: Db, ctx: RequestContext, code: str, interview_id: int) -> Sets:
    return repo.get_interview(db, ctx.company_id, ctx.user_id, code, interview_id)


def save_interview(db: Db, ctx: RequestContext, code: str, interview_id: int | None, body: InterviewIn,
                   row_version: bytes | None) -> Sets:
    if interview_id is None and body.application_id is None:
        raise invalid("Choose the application.", "applicationId")
    return repo.save_interview(db, ctx.company_id, ctx.user_id, code, interview_id, body.application_id, body.title,
                               body.mode, _local(body.scheduled_at), body.duration_minutes, body.venue, body.remarks,
                               json.dumps(sorted(set(body.interviewer_ids))), row_version)


def cancel_interview(db: Db, ctx: RequestContext, code: str, interview_id: int, remarks: str | None,
                     row_version: bytes) -> Sets:
    return repo.cancel_interview(db, ctx.company_id, ctx.user_id, code, interview_id, remarks, row_version)


def complete_interview(db: Db, ctx: RequestContext, code: str, interview_id: int, body: CompleteIn,
                       row_version: bytes) -> Sets:
    if body.status == "no_show" and body.result:
        raise invalid("A no show has no result.", "result")
    return repo.complete_interview(db, ctx.company_id, ctx.user_id, code, interview_id, body.status, body.result,
                                   body.remarks, row_version)


def evaluate_interview(db: Db, ctx: RequestContext, code: str, interview_id: int, body: EvaluationIn) -> Sets:
    return repo.evaluate_interview(db, ctx.company_id, ctx.user_id, code, interview_id,
                                   body.model_dump(by_alias=False))


# ---------------------------------------------------------------- offers

def list_offers(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], page: int,
                page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return repo.list_offers(db, ctx.company_id, ctx.user_id, code, filters, page, page_size)


def get_offer(db: Db, ctx: RequestContext, code: str, offer_id: int) -> dict[str, Any]:
    return repo.get_offer(db, ctx.company_id, ctx.user_id, code, offer_id)


def save_offer(db: Db, ctx: RequestContext, code: str, offer_id: int | None, body: OfferIn,
               row_version: bytes | None) -> dict[str, Any]:
    if offer_id is None and body.application_id is None:
        raise invalid("Choose the application.", "applicationId")
    if body.expires_on and body.expires_on > body.joining_date:
        raise invalid("The offer should expire on or before the joining date.", "expiresOn")
    fields = body.model_dump(by_alias=False, exclude={"row_version"})
    return repo.save_offer(db, ctx.company_id, ctx.user_id, code, offer_id, fields, row_version)


def delete_offer(db: Db, ctx: RequestContext, code: str, offer_id: int, row_version: bytes) -> None:
    repo.delete_offer(db, ctx.company_id, ctx.user_id, code, offer_id, row_version)


def offer_status(db: Db, ctx: RequestContext, code: str, offer_id: int, action: str, remarks: str | None,
                 row_version: bytes) -> dict[str, Any]:
    return repo.offer_status(db, ctx.company_id, ctx.user_id, code, offer_id, action, remarks, row_version)


# ---------------------------------------------------------------- settings: rejection reasons

def list_rejection_reasons(db: Db, ctx: RequestContext, search: str | None, active_only: bool) -> list[dict[str, Any]]:
    return repo.list_rejection_reasons(db, ctx.company_id, search, active_only)


def save_rejection_reason(db: Db, ctx: RequestContext, reason_id: int | None, name: str, is_active: bool,
                          sort_order: int | None, row_version: bytes | None) -> dict[str, Any]:
    return repo.save_rejection_reason(db, ctx.company_id, ctx.user_id, reason_id, name, is_active, sort_order,
                                      row_version)


def delete_rejection_reason(db: Db, ctx: RequestContext, reason_id: int, row_version: bytes) -> None:
    repo.delete_rejection_reason(db, ctx.company_id, ctx.user_id, reason_id, row_version)
