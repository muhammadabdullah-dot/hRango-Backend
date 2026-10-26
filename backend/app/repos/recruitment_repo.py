"""Recruitment data access. The only layer that knows the rec procedure names and parameters (and the one
Employees procedure hiring reuses, hr.usp_employee_save). Scoped procedures take the permission code the
endpoint required."""
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from app.core.db import Db

Sets = list[list[dict[str, Any]]]


def _page(sets: Sets) -> tuple[int, list[dict[str, Any]]]:
    return sets[0][0]["total"], sets[1]


# ---------------------------------------------------------------- dashboard

def dashboard(db: Db, company_id: int, actor_user_id: int, code: str, year: int, month: int | None) -> Sets:
    return db.call_sets("rec.usp_dashboard", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
                        year=year, month=month)


# ---------------------------------------------------------------- job openings

def list_openings(db: Db, company_id: int, actor_user_id: int, code: str, filters: dict[str, Any], page: int,
                  page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("rec.usp_job_opening_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, page=page, page_size=page_size, **filters))


def get_opening(db: Db, company_id: int, actor_user_id: int, code: str, opening_id: int) -> dict[str, Any]:
    return db.call_one("rec.usp_job_opening_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=opening_id)


def save_opening(db: Db, company_id: int, actor_user_id: int, code: str, opening_id: int | None,
                 fields: dict[str, Any], row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("rec.usp_job_opening_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=opening_id, row_version=row_version, **fields)


def delete_opening(db: Db, company_id: int, actor_user_id: int, code: str, opening_id: int, row_version: bytes) -> None:
    db.call("rec.usp_job_opening_delete", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
            id=opening_id, row_version=row_version)


def opening_status(db: Db, company_id: int, actor_user_id: int, code: str, opening_id: int, action: str,
                   row_version: bytes) -> dict[str, Any]:
    return db.call_one("rec.usp_job_opening_status", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=opening_id, action=action, row_version=row_version)


# ---------------------------------------------------------------- applicants

def list_applicants(db: Db, company_id: int, actor_user_id: int, code: str, filters: dict[str, Any], page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("rec.usp_applicant_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, page=page, page_size=page_size, **filters))


def get_applicant(db: Db, company_id: int, actor_user_id: int, code: str, applicant_id: int) -> Sets:
    return db.call_sets("rec.usp_applicant_get", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, id=applicant_id)


def save_applicant(db: Db, company_id: int, actor_user_id: int, code: str, applicant_id: int | None,
                   fields: dict[str, Any], row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("rec.usp_applicant_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=applicant_id, row_version=row_version, **fields)


def delete_applicant(db: Db, company_id: int, actor_user_id: int, code: str, applicant_id: int,
                     row_version: bytes) -> None:
    db.call("rec.usp_applicant_delete", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
            id=applicant_id, row_version=row_version)


# ---------------------------------------------------------------- applications

def list_applications(db: Db, company_id: int, actor_user_id: int, code: str, filters: dict[str, Any], page: int,
                      page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("rec.usp_application_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, page=page, page_size=page_size, **filters))


def get_application(db: Db, company_id: int, actor_user_id: int, code: str, application_id: int) -> Sets:
    return db.call_sets("rec.usp_application_get", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, id=application_id)


def add_application(db: Db, company_id: int, actor_user_id: int, code: str, job_opening_id: int, applicant_id: int,
                    applied_on: date | None, source: str | None, cover_letter: str | None,
                    remarks: str | None) -> Sets:
    return db.call_sets("rec.usp_application_add", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, job_opening_id=job_opening_id, applicant_id=applicant_id,
                        applied_on=applied_on, source=source, cover_letter=cover_letter, remarks=remarks)


def move_application(db: Db, company_id: int, actor_user_id: int, code: str, application_id: int, stage: str,
                     remarks: str | None, row_version: bytes) -> Sets:
    return db.call_sets("rec.usp_application_stage", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, id=application_id, stage=stage, remarks=remarks,
                        row_version=row_version)


def close_application(db: Db, company_id: int, actor_user_id: int, code: str, application_id: int, stage: str,
                      rejection_reason_id: int | None, remarks: str | None, row_version: bytes) -> Sets:
    return db.call_sets("rec.usp_application_close", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, id=application_id, stage=stage,
                        rejection_reason_id=rejection_reason_id, remarks=remarks, row_version=row_version)


def delete_application(db: Db, company_id: int, actor_user_id: int, code: str, application_id: int,
                       row_version: bytes) -> None:
    db.call("rec.usp_application_delete", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
            id=application_id, row_version=row_version)


def hire_prepare(db: Db, company_id: int, actor_user_id: int, code: str, application_id: int,
                 row_version: bytes) -> dict[str, Any]:
    return db.call_one("rec.usp_application_hire_prepare", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=application_id, row_version=row_version)


def save_employee(db: Db, company_id: int, actor_user_id: int, code: str, fields: dict[str, Any]) -> dict[str, Any]:
    """Employees' own add-employee procedure: code, checks, first employment period, history and audit."""
    return db.call_one("hr.usp_employee_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=None, **fields)


def hire_complete(db: Db, company_id: int, actor_user_id: int, code: str, application_id: int, row_version: bytes,
                  employee_id: int, salary: Decimal | None, joining_date: date, remarks: str | None) -> Sets:
    return db.call_sets("rec.usp_application_hire_complete", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, id=application_id, row_version=row_version, employee_id=employee_id,
                        salary=salary, joining_date=joining_date, remarks=remarks)


# ---------------------------------------------------------------- interviews

def list_interviews(db: Db, company_id: int, actor_user_id: int, code: str, filters: dict[str, Any], page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("rec.usp_interview_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, page=page, page_size=page_size, **filters))


def get_interview(db: Db, company_id: int, actor_user_id: int, code: str, interview_id: int) -> Sets:
    return db.call_sets("rec.usp_interview_get", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, id=interview_id)


def save_interview(db: Db, company_id: int, actor_user_id: int, code: str, interview_id: int | None,
                   application_id: int | None, title: str | None, mode: str, scheduled_at: datetime,
                   duration_minutes: int, venue: str | None, remarks: str | None, interviewers_json: str,
                   row_version: bytes | None) -> Sets:
    return db.call_sets("rec.usp_interview_save", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, id=interview_id, application_id=application_id, title=title, mode=mode,
                        scheduled_at=scheduled_at, duration_minutes=duration_minutes, venue=venue, remarks=remarks,
                        interviewers=interviewers_json, row_version=row_version)


def cancel_interview(db: Db, company_id: int, actor_user_id: int, code: str, interview_id: int, remarks: str | None,
                     row_version: bytes) -> Sets:
    return db.call_sets("rec.usp_interview_cancel", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, id=interview_id, remarks=remarks, row_version=row_version)


def complete_interview(db: Db, company_id: int, actor_user_id: int, code: str, interview_id: int, status: str,
                       result: str | None, remarks: str | None, row_version: bytes) -> Sets:
    return db.call_sets("rec.usp_interview_complete", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, id=interview_id, status=status, result=result, remarks=remarks,
                        row_version=row_version)


def evaluate_interview(db: Db, company_id: int, actor_user_id: int, code: str, interview_id: int,
                       fields: dict[str, Any]) -> Sets:
    return db.call_sets("rec.usp_interview_evaluate", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=code, id=interview_id, **fields)


# ---------------------------------------------------------------- offers

def list_offers(db: Db, company_id: int, actor_user_id: int, code: str, filters: dict[str, Any], page: int,
                page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db.call_sets("rec.usp_offer_list", company_id=company_id, actor_user_id=actor_user_id,
                              permission_code=code, page=page, page_size=page_size, **filters))


def get_offer(db: Db, company_id: int, actor_user_id: int, code: str, offer_id: int) -> dict[str, Any]:
    return db.call_one("rec.usp_offer_get", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
                       id=offer_id)


def save_offer(db: Db, company_id: int, actor_user_id: int, code: str, offer_id: int | None, fields: dict[str, Any],
               row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("rec.usp_offer_save", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
                       id=offer_id, row_version=row_version, **fields)


def delete_offer(db: Db, company_id: int, actor_user_id: int, code: str, offer_id: int, row_version: bytes) -> None:
    db.call("rec.usp_offer_delete", company_id=company_id, actor_user_id=actor_user_id, permission_code=code,
            id=offer_id, row_version=row_version)


def offer_status(db: Db, company_id: int, actor_user_id: int, code: str, offer_id: int, action: str,
                 remarks: str | None, row_version: bytes) -> dict[str, Any]:
    return db.call_one("rec.usp_offer_status", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=code, id=offer_id, action=action, remarks=remarks, row_version=row_version)


# ---------------------------------------------------------------- settings: rejection reasons

def list_rejection_reasons(db: Db, company_id: int, search: str | None, active_only: bool) -> list[dict[str, Any]]:
    return db.call("rec.usp_rejection_reason_list", company_id=company_id, search=search, active_only=active_only)


def save_rejection_reason(db: Db, company_id: int, actor_user_id: int, reason_id: int | None, name: str,
                          is_active: bool, sort_order: int | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("rec.usp_rejection_reason_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=reason_id, name=name, is_active=is_active, sort_order=sort_order, row_version=row_version)


def delete_rejection_reason(db: Db, company_id: int, actor_user_id: int, reason_id: int, row_version: bytes) -> None:
    db.call("rec.usp_rejection_reason_delete", company_id=company_id, actor_user_id=actor_user_id, id=reason_id,
            row_version=row_version)
