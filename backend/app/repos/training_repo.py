"""Training data access (procedures in the trn schema). The only layer that knows procedure names."""
from datetime import date
from typing import Any

from app.core.db import Db


def _page(db: Db, proc: str, **params: Any) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets(proc, **params)[:2]
    return total[0]["total"], rows


# --- Settings ------------------------------------------------------------------------------------

def get_settings(db: Db, company_id: int) -> dict[str, Any]:
    return db.call_one("trn.usp_training_settings_get", company_id=company_id)


def save_settings(db: Db, company_id: int, actor_user_id: int, fields: dict[str, Any],
                  row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("trn.usp_training_settings_save", company_id=company_id, actor_user_id=actor_user_id, **fields,
                       row_version=row_version)


def list_categories(db: Db, company_id: int, search: str | None, is_active: bool | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "trn.usp_training_category_list", company_id=company_id, search=search, is_active=is_active,
                 page=page, page_size=page_size)


def save_category(db: Db, company_id: int, actor_user_id: int, category_id: int | None, name: str, is_active: bool,
                  row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("trn.usp_training_category_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=category_id, name=name, is_active=is_active, row_version=row_version)


def delete_category(db: Db, company_id: int, actor_user_id: int, category_id: int, row_version: bytes) -> None:
    db.call("trn.usp_training_category_delete", company_id=company_id, actor_user_id=actor_user_id, id=category_id,
            row_version=row_version)


# --- Programs ------------------------------------------------------------------------------------

def list_programs(db: Db, company_id: int, search: str | None, category_id: int | None, delivery_mode: str | None,
                  is_active: bool | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "trn.usp_training_program_list", company_id=company_id, search=search,
                 training_category_id=category_id, delivery_mode=delivery_mode, is_active=is_active, page=page,
                 page_size=page_size)


def get_program(db: Db, company_id: int, program_id: int) -> dict[str, Any]:
    return db.call_one("trn.usp_training_program_get", company_id=company_id, id=program_id)


def save_program(db: Db, company_id: int, actor_user_id: int, program_id: int | None, fields: dict[str, Any],
                 row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("trn.usp_training_program_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=program_id, **fields, row_version=row_version)


def delete_program(db: Db, company_id: int, actor_user_id: int, program_id: int, row_version: bytes) -> None:
    db.call("trn.usp_training_program_delete", company_id=company_id, actor_user_id=actor_user_id, id=program_id,
            row_version=row_version)


def add_material(db: Db, company_id: int, actor_user_id: int, program_id: int, file_id: int,
                 label: str | None) -> dict[str, Any]:
    return db.call_one("trn.usp_training_material_add", company_id=company_id, actor_user_id=actor_user_id,
                       id=program_id, file_id=file_id, label=label)


def delete_material(db: Db, company_id: int, actor_user_id: int, program_id: int, attachment_id: int) -> None:
    db.call("trn.usp_training_material_delete", company_id=company_id, actor_user_id=actor_user_id, id=program_id,
            attachment_id=attachment_id)


# --- Sessions ------------------------------------------------------------------------------------

def list_sessions(db: Db, company_id: int, program_id: int | None, status: str | None, from_date: date | None,
                  to_date: date | None, search: str | None, page: int,
                  page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "trn.usp_training_session_list", company_id=company_id, training_program_id=program_id,
                 status=status, from_date=from_date, to_date=to_date, search=search, page=page, page_size=page_size)


def get_session(db: Db, company_id: int, session_id: int) -> dict[str, Any]:
    return db.call_one("trn.usp_training_session_get", company_id=company_id, id=session_id)


def save_session(db: Db, company_id: int, actor_user_id: int, session_id: int | None, fields: dict[str, Any],
                 row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("trn.usp_training_session_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=session_id, **fields, row_version=row_version)


def delete_session(db: Db, company_id: int, actor_user_id: int, session_id: int, row_version: bytes) -> None:
    db.call("trn.usp_training_session_delete", company_id=company_id, actor_user_id=actor_user_id, id=session_id,
            row_version=row_version)


def cancel_session(db: Db, company_id: int, actor_user_id: int, session_id: int, reason: str | None,
                   row_version: bytes) -> dict[str, Any]:
    return db.call_one("trn.usp_training_session_cancel", company_id=company_id, actor_user_id=actor_user_id,
                       id=session_id, reason=reason, row_version=row_version)


def complete_session(db: Db, company_id: int, actor_user_id: int, session_id: int,
                     row_version: bytes) -> dict[str, Any]:
    return db.call_one("trn.usp_training_session_complete", company_id=company_id, actor_user_id=actor_user_id,
                       id=session_id, row_version=row_version)


# --- Attendance ----------------------------------------------------------------------------------

def get_attendance(db: Db, company_id: int, actor_user_id: int, permission_code: str,
                   session_id: int) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    session, seats, marks = db.call_sets("trn.usp_training_attendance_get", company_id=company_id,
                                         actor_user_id=actor_user_id, permission_code=permission_code,
                                         session_id=session_id)
    return session[0], seats, marks


def save_attendance(db: Db, company_id: int, actor_user_id: int, permission_code: str, session_id: int,
                    attendance_date: date,
                    marks: str) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    session, seats, marks_out = db.call_sets("trn.usp_training_attendance_save", company_id=company_id,
                                             actor_user_id=actor_user_id, permission_code=permission_code,
                                             session_id=session_id, attendance_date=attendance_date, marks=marks)
    return session[0], seats, marks_out


# --- Enrolments ----------------------------------------------------------------------------------

def list_enrolments(db: Db, company_id: int, actor_user_id: int, permission_code: str, tab: str,
                    session_id: int | None, program_id: int | None, status: str | None, employee_id: int | None,
                    search: str | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "trn.usp_training_enrolment_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=permission_code, tab=tab, training_session_id=session_id,
                 training_program_id=program_id, status=status, employee_id=employee_id, search=search, page=page,
                 page_size=page_size)


def _detail(sets: list[list[dict[str, Any]]]) -> dict[str, Any]:
    enrolment, attendance, feedback = sets
    return {**enrolment[0], "attendance": attendance, "feedback": feedback[0] if feedback else None}


def get_enrolment(db: Db, company_id: int, actor_user_id: int, permission_code: str,
                  enrolment_id: int) -> dict[str, Any]:
    return _detail(db.call_sets("trn.usp_training_enrolment_get", company_id=company_id, actor_user_id=actor_user_id,
                                permission_code=permission_code, id=enrolment_id))


def nominate(db: Db, company_id: int, actor_user_id: int, permission_code: str, session_id: int, employee_ids: str,
             source: str, remarks: str | None) -> list[dict[str, Any]]:
    return db.call("trn.usp_training_enrolment_nominate", company_id=company_id, actor_user_id=actor_user_id,
                   permission_code=permission_code, training_session_id=session_id, employee_ids=employee_ids,
                   source=source, remarks=remarks)


def decide(db: Db, company_id: int, actor_user_id: int, permission_code: str, enrolment_id: int, action: str,
           remarks: str | None, row_version: bytes) -> dict[str, Any]:
    return _detail(db.call_sets("trn.usp_training_enrolment_decide", company_id=company_id,
                                actor_user_id=actor_user_id, permission_code=permission_code, id=enrolment_id,
                                action=action, remarks=remarks, row_version=row_version))


def complete(db: Db, company_id: int, actor_user_id: int, permission_code: str, enrolment_id: int,
             score: Any, remarks: str | None, row_version: bytes) -> dict[str, Any]:
    return _detail(db.call_sets("trn.usp_training_enrolment_complete", company_id=company_id,
                                actor_user_id=actor_user_id, permission_code=permission_code, id=enrolment_id,
                                score=score, remarks=remarks, row_version=row_version))


def save_certificate(db: Db, company_id: int, actor_user_id: int, permission_code: str, enrolment_id: int,
                     file_id: int, certificate_no: str | None, issued_date: date,
                     row_version: bytes) -> dict[str, Any]:
    return _detail(db.call_sets("trn.usp_training_certificate_save", company_id=company_id,
                                actor_user_id=actor_user_id, permission_code=permission_code, id=enrolment_id,
                                file_id=file_id, certificate_no=certificate_no, issued_date=issued_date,
                                row_version=row_version))


def save_feedback(db: Db, company_id: int, actor_user_id: int, permission_code: str, enrolment_id: int,
                  fields: dict[str, Any]) -> dict[str, Any]:
    return _detail(db.call_sets("trn.usp_training_feedback_save", company_id=company_id, actor_user_id=actor_user_id,
                                permission_code=permission_code, id=enrolment_id, **fields))


def list_feedback(db: Db, company_id: int, actor_user_id: int, permission_code: str, session_id: int | None,
                  program_id: int | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "trn.usp_training_feedback_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=permission_code, training_session_id=session_id, training_program_id=program_id,
                 page=page, page_size=page_size)
