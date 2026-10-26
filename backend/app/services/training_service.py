"""Training rules. Seats, stages, attendance minimums and row versions are checked in the procedures; rules
between fields (dates, trainer and venue for the delivery mode) live here, and so does who a nomination
comes from: HR with company-wide reach enrols at once, anyone else's nomination waits for approval.
"""
import json
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.repos import training_repo as repo
from app.schemas.training import (AttendanceIn, CategoryIn, CompleteIn, CertificateIn, FeedbackIn, NominateIn,
                                  ProgramIn, SessionIn, TrainingSettingsIn)

# The permission each scoped procedure filters employees by: the code the endpoint required.
ENROLMENTS_VIEW = "training.enrolments.view"
ENROLMENTS_CREATE = "training.enrolments.create"
ENROLMENTS_APPROVE = "training.enrolments.approve"
ENROLMENTS_REJECT = "training.enrolments.reject"
ENROLMENTS_CANCEL = "training.enrolments.cancel"
ENROLMENTS_COMPLETE = "training.enrolments.complete"
ATTENDANCE_VIEW = "training.attendance.view"
ATTENDANCE_EDIT = "training.attendance.edit"
FEEDBACK_VIEW = "training.feedback.view"
FEEDBACK_CREATE = "training.feedback.create"

_DECIDE = {"approve": ENROLMENTS_APPROVE, "reject": ENROLMENTS_REJECT, "withdraw": ENROLMENTS_CANCEL}


def _invalid(errors: dict[str, str]) -> AppError:
    return AppError(422, "VALIDATION_FAILED", "Some fields need your attention.", errors)


# --- Settings ------------------------------------------------------------------------------------

def get_settings(db: Db, ctx: RequestContext) -> dict[str, Any]:
    return repo.get_settings(db, ctx.company_id)


def save_settings(db: Db, ctx: RequestContext, body: TrainingSettingsIn, row_version: bytes | None) -> dict[str, Any]:
    return repo.save_settings(db, ctx.company_id, ctx.user_id,
                              body.model_dump(by_alias=False, exclude={"row_version"}), row_version)


def list_categories(db: Db, ctx: RequestContext, search: str | None, is_active: bool | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return repo.list_categories(db, ctx.company_id, search, is_active, page, page_size)


def save_category(db: Db, ctx: RequestContext, category_id: int | None, body: CategoryIn,
                  row_version: bytes | None) -> dict[str, Any]:
    return repo.save_category(db, ctx.company_id, ctx.user_id, category_id, body.name, body.is_active, row_version)


def delete_category(db: Db, ctx: RequestContext, category_id: int, row_version: bytes) -> None:
    repo.delete_category(db, ctx.company_id, ctx.user_id, category_id, row_version)


# --- Programs ------------------------------------------------------------------------------------

def list_programs(db: Db, ctx: RequestContext, search: str | None, category_id: int | None,
                  delivery_mode: str | None, is_active: bool | None, page: int,
                  page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return repo.list_programs(db, ctx.company_id, search, category_id, delivery_mode, is_active, page, page_size)


def get_program(db: Db, ctx: RequestContext, program_id: int) -> dict[str, Any]:
    return repo.get_program(db, ctx.company_id, program_id)


def save_program(db: Db, ctx: RequestContext, program_id: int | None, body: ProgramIn,
                 row_version: bytes | None) -> dict[str, Any]:
    fields = body.model_dump(by_alias=False, exclude={"row_version"})
    if not body.issues_certificate:
        fields["certificate_validity_months"] = None
    if body.provider_type == "external" and not (body.provider_name or "").strip():
        raise _invalid({"providerName": "Name the external provider."})
    return repo.save_program(db, ctx.company_id, ctx.user_id, program_id, fields, row_version)


def delete_program(db: Db, ctx: RequestContext, program_id: int, row_version: bytes) -> None:
    repo.delete_program(db, ctx.company_id, ctx.user_id, program_id, row_version)


def add_material(db: Db, ctx: RequestContext, program_id: int, file_id: int, label: str | None) -> dict[str, Any]:
    return repo.add_material(db, ctx.company_id, ctx.user_id, program_id, file_id, label)


def delete_material(db: Db, ctx: RequestContext, program_id: int, attachment_id: int) -> None:
    repo.delete_material(db, ctx.company_id, ctx.user_id, program_id, attachment_id)


# --- Sessions ------------------------------------------------------------------------------------

def list_sessions(db: Db, ctx: RequestContext, program_id: int | None, status: str | None, from_date: date | None,
                  to_date: date | None, search: str | None, page: int,
                  page_size: int) -> tuple[int, list[dict[str, Any]]]:
    if from_date and to_date and to_date < from_date:
        raise _invalid({"toDate": "The end date must be on or after the start date."})
    return repo.list_sessions(db, ctx.company_id, program_id, status, from_date, to_date, search, page, page_size)


def get_session(db: Db, ctx: RequestContext, session_id: int) -> dict[str, Any]:
    return repo.get_session(db, ctx.company_id, session_id)


def save_session(db: Db, ctx: RequestContext, session_id: int | None, body: SessionIn,
                 row_version: bytes | None) -> dict[str, Any]:
    errors: dict[str, str] = {}
    if body.end_date < body.start_date:
        errors["endDate"] = "The session must end on or after its start."
    if body.start_time and body.end_time and body.end_time <= body.start_time and body.start_date == body.end_date:
        errors["endTime"] = "The session must end after it starts."
    if body.nomination_deadline and body.nomination_deadline > body.start_date:
        errors["nominationDeadline"] = "Nominations must close by the first day."
    if body.delivery_mode == "online" and not (body.online_link or "").strip():
        errors["onlineLink"] = "Give the link for an online session."
    if body.delivery_mode == "classroom" and not (body.venue or "").strip():
        errors["venue"] = "Give the venue for a classroom session."
    if body.trainer_type == "internal" and body.trainer_employee_id is None:
        errors["trainerEmployeeId"] = "Choose the employee who trains."
    if body.trainer_type == "external" and not (body.trainer_name or "").strip():
        errors["trainerName"] = "Name the external trainer."
    if errors:
        raise _invalid(errors)
    fields = body.model_dump(by_alias=False, exclude={"row_version"})
    if body.trainer_type == "external":
        fields["trainer_employee_id"] = None
    return repo.save_session(db, ctx.company_id, ctx.user_id, session_id, fields, row_version)


def delete_session(db: Db, ctx: RequestContext, session_id: int, row_version: bytes) -> None:
    repo.delete_session(db, ctx.company_id, ctx.user_id, session_id, row_version)


def cancel_session(db: Db, ctx: RequestContext, session_id: int, reason: str | None,
                   row_version: bytes) -> dict[str, Any]:
    return repo.cancel_session(db, ctx.company_id, ctx.user_id, session_id, reason, row_version)


def complete_session(db: Db, ctx: RequestContext, session_id: int, row_version: bytes) -> dict[str, Any]:
    return repo.complete_session(db, ctx.company_id, ctx.user_id, session_id, row_version)


# --- Attendance ----------------------------------------------------------------------------------

def _attendance(found: tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]) -> dict[str, Any]:
    session, seats, marks = found
    by_seat: dict[Any, list[dict[str, Any]]] = {}
    for m in marks:
        by_seat.setdefault(m["enrolment_id"], []).append(m)
    return {"session_id": session["id"], **session,
            "participants": [{**s, "days": by_seat.get(s["enrolment_id"], [])} for s in seats]}


def get_attendance(db: Db, ctx: RequestContext, session_id: int) -> dict[str, Any]:
    return _attendance(repo.get_attendance(db, ctx.company_id, ctx.user_id, ATTENDANCE_VIEW, session_id))


def save_attendance(db: Db, ctx: RequestContext, session_id: int, body: AttendanceIn) -> dict[str, Any]:
    ids = [m.enrolment_id for m in body.marks]
    if len(set(ids)) != len(ids):
        raise _invalid({"marks": "Someone is marked twice."})
    marks = [m.model_dump(by_alias=True, mode="json") for m in body.marks]
    return _attendance(repo.save_attendance(db, ctx.company_id, ctx.user_id, ATTENDANCE_EDIT, session_id,
                                            body.attendance_date, json.dumps(marks)))


# --- Enrolments ----------------------------------------------------------------------------------

def list_enrolments(db: Db, ctx: RequestContext, tab: str, session_id: int | None, program_id: int | None,
                    status: str | None, employee_id: int | None, search: str | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return repo.list_enrolments(db, ctx.company_id, ctx.user_id, ENROLMENTS_VIEW, tab, session_id, program_id, status,
                                employee_id, search, page, page_size)


def get_enrolment(db: Db, ctx: RequestContext, enrolment_id: int) -> dict[str, Any]:
    return repo.get_enrolment(db, ctx.company_id, ctx.user_id, ENROLMENTS_VIEW, enrolment_id)


def nominate(db: Db, ctx: RequestContext, body: NominateIn) -> list[dict[str, Any]]:
    employee_ids = list(dict.fromkeys(body.employee_ids)) or ([ctx.employee_id] if ctx.employee_id else [])
    if not employee_ids:
        raise _invalid({"employeeIds": "Choose who to nominate."})
    if ctx.sees_company:
        source = "hr"
    elif employee_ids == [ctx.employee_id]:
        source = "self"
    else:
        source = "manager"
    return repo.nominate(db, ctx.company_id, ctx.user_id, ENROLMENTS_CREATE, body.training_session_id,
                         json.dumps(employee_ids), source, body.remarks)


def decide(db: Db, ctx: RequestContext, enrolment_id: int, action: str, remarks: str | None,
           row_version: bytes) -> dict[str, Any]:
    return repo.decide(db, ctx.company_id, ctx.user_id, _DECIDE[action], enrolment_id, action, remarks, row_version)


def complete(db: Db, ctx: RequestContext, enrolment_id: int, body: CompleteIn, row_version: bytes) -> dict[str, Any]:
    return repo.complete(db, ctx.company_id, ctx.user_id, ENROLMENTS_COMPLETE, enrolment_id, body.score, body.remarks,
                         row_version)


def save_certificate(db: Db, ctx: RequestContext, enrolment_id: int, body: CertificateIn,
                     row_version: bytes) -> dict[str, Any]:
    return repo.save_certificate(db, ctx.company_id, ctx.user_id, ENROLMENTS_COMPLETE, enrolment_id, body.file_id,
                                 body.certificate_no, body.issued_date, row_version)


def save_feedback(db: Db, ctx: RequestContext, enrolment_id: int, body: FeedbackIn) -> dict[str, Any]:
    return repo.save_feedback(db, ctx.company_id, ctx.user_id, FEEDBACK_CREATE, enrolment_id,
                              body.model_dump(by_alias=False))


def list_feedback(db: Db, ctx: RequestContext, session_id: int | None, program_id: int | None, page: int,
                  page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return repo.list_feedback(db, ctx.company_id, ctx.user_id, FEEDBACK_VIEW, session_id, program_id, page, page_size)
