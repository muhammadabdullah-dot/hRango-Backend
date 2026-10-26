"""HTTP shape for the Training screens: envelopes, row versions as text, rows to response models, signed
links for course materials and certificates."""
import json
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.files import FileRef
from app.schemas.training import (AttendanceIn, AttendanceOut, CancelIn, CategoryIn, CategoryOut, CertificateIn,
                                  CompleteIn, DecisionIn, EnrolmentDetailOut, EnrolmentOut, FeedbackIn,
                                  FeedbackListOut, NominateIn, ProgramIn, ProgramOut, SessionIn, SessionOut,
                                  TrainingSettingsIn, TrainingSettingsOut)
from app.services import training_service as service


def _rv(row: dict[str, Any]) -> dict[str, Any]:
    return {**row, "row_version": row_version_out(row["row_version"])}


# --- Settings ------------------------------------------------------------------------------------

def get_settings(db: Db, ctx: RequestContext) -> dict:
    return {"data": TrainingSettingsOut(**_rv(service.get_settings(db, ctx)))}


def save_settings(db: Db, ctx: RequestContext, body: TrainingSettingsIn) -> dict:
    row = service.save_settings(db, ctx, body, row_version_in(body.row_version, required=False))
    return {"data": TrainingSettingsOut(**_rv(row))}


def list_categories(db: Db, ctx: RequestContext, q: str | None, is_active: bool | None, paging: PageParams) -> dict:
    total, rows = service.list_categories(db, ctx, q, is_active, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: CategoryOut(**_rv(r)))


def create_category(db: Db, ctx: RequestContext, body: CategoryIn) -> dict:
    return {"data": CategoryOut(**_rv(service.save_category(db, ctx, None, body, None)))}


def update_category(db: Db, ctx: RequestContext, category_id: int, body: CategoryIn) -> dict:
    row = service.save_category(db, ctx, category_id, body, row_version_in(body.row_version))
    return {"data": CategoryOut(**_rv(row))}


def delete_category(db: Db, ctx: RequestContext, category_id: int, row_version: str | None) -> None:
    service.delete_category(db, ctx, category_id, row_version_in(row_version))


# --- Programs ------------------------------------------------------------------------------------

def _program(ctx: RequestContext, row: dict[str, Any]) -> ProgramOut:
    materials = [{**m, "url": file_url(m["fileId"], ctx.company_id)} for m in json.loads(row["materials"] or "[]")]
    return ProgramOut(**{**_rv(row), "materials": materials})


def list_programs(db: Db, ctx: RequestContext, q: str | None, category_id: int | None, delivery_mode: str | None,
                  is_active: bool | None, paging: PageParams) -> dict:
    total, rows = service.list_programs(db, ctx, q, category_id, delivery_mode, is_active, paging.page,
                                        paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: _program(ctx, r))


def get_program(db: Db, ctx: RequestContext, program_id: int) -> dict:
    return {"data": _program(ctx, service.get_program(db, ctx, program_id))}


def create_program(db: Db, ctx: RequestContext, body: ProgramIn) -> dict:
    return {"data": _program(ctx, service.save_program(db, ctx, None, body, None))}


def update_program(db: Db, ctx: RequestContext, program_id: int, body: ProgramIn) -> dict:
    row = service.save_program(db, ctx, program_id, body, row_version_in(body.row_version))
    return {"data": _program(ctx, row)}


def delete_program(db: Db, ctx: RequestContext, program_id: int, row_version: str | None) -> None:
    service.delete_program(db, ctx, program_id, row_version_in(row_version))


def add_material(db: Db, ctx: RequestContext, program_id: int, file_id: int, label: str | None) -> dict:
    return {"data": _program(ctx, service.add_material(db, ctx, program_id, file_id, label))}


def delete_material(db: Db, ctx: RequestContext, program_id: int, attachment_id: int) -> None:
    service.delete_material(db, ctx, program_id, attachment_id)


# --- Sessions ------------------------------------------------------------------------------------

def _session(row: dict[str, Any]) -> SessionOut:
    return SessionOut(**_rv(row))


def list_sessions(db: Db, ctx: RequestContext, program_id: int | None, status: str | None, from_date: date | None,
                  to_date: date | None, q: str | None, paging: PageParams) -> dict:
    total, rows = service.list_sessions(db, ctx, program_id, status, from_date, to_date, q, paging.page,
                                        paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _session)


def get_session(db: Db, ctx: RequestContext, session_id: int) -> dict:
    return {"data": _session(service.get_session(db, ctx, session_id))}


def create_session(db: Db, ctx: RequestContext, body: SessionIn) -> dict:
    return {"data": _session(service.save_session(db, ctx, None, body, None))}


def update_session(db: Db, ctx: RequestContext, session_id: int, body: SessionIn) -> dict:
    return {"data": _session(service.save_session(db, ctx, session_id, body, row_version_in(body.row_version)))}


def delete_session(db: Db, ctx: RequestContext, session_id: int, row_version: str | None) -> None:
    service.delete_session(db, ctx, session_id, row_version_in(row_version))


def cancel_session(db: Db, ctx: RequestContext, session_id: int, body: CancelIn) -> dict:
    row = service.cancel_session(db, ctx, session_id, body.reason, row_version_in(body.row_version))
    return {"data": _session(row)}


def complete_session(db: Db, ctx: RequestContext, session_id: int, row_version: str) -> dict:
    return {"data": _session(service.complete_session(db, ctx, session_id, row_version_in(row_version)))}


# --- Attendance ----------------------------------------------------------------------------------

def get_attendance(db: Db, ctx: RequestContext, session_id: int) -> dict:
    return {"data": AttendanceOut(**service.get_attendance(db, ctx, session_id))}


def save_attendance(db: Db, ctx: RequestContext, session_id: int, body: AttendanceIn) -> dict:
    return {"data": AttendanceOut(**service.save_attendance(db, ctx, session_id, body))}


# --- Enrolments ----------------------------------------------------------------------------------

def _certificate(ctx: RequestContext, row: dict[str, Any]) -> FileRef | None:
    if not row.get("certificate_file_id"):
        return None
    return FileRef(id=str(row["certificate_file_id"]), name=row["certificate_file_name"],
                   url=file_url(row["certificate_file_id"], ctx.company_id))


def _enrolment(ctx: RequestContext, row: dict[str, Any]) -> EnrolmentOut:
    return EnrolmentOut(**{**_rv(row), "certificate": _certificate(ctx, row)})


def _detail(ctx: RequestContext, row: dict[str, Any]) -> dict:
    return {"data": EnrolmentDetailOut(**{**_rv(row), "certificate": _certificate(ctx, row)})}


def list_enrolments(db: Db, ctx: RequestContext, tab: str, session_id: int | None, program_id: int | None,
                    status: str | None, employee_id: int | None, q: str | None, paging: PageParams) -> dict:
    total, rows = service.list_enrolments(db, ctx, tab, session_id, program_id, status, employee_id, q, paging.page,
                                          paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: _enrolment(ctx, r))


def get_enrolment(db: Db, ctx: RequestContext, enrolment_id: int) -> dict:
    return _detail(ctx, service.get_enrolment(db, ctx, enrolment_id))


def nominate(db: Db, ctx: RequestContext, body: NominateIn) -> dict:
    return {"data": [_enrolment(ctx, r) for r in service.nominate(db, ctx, body)]}


def decide(db: Db, ctx: RequestContext, enrolment_id: int, action: str, body: DecisionIn) -> dict:
    row = service.decide(db, ctx, enrolment_id, action, body.remarks, row_version_in(body.row_version))
    return _detail(ctx, row)


def complete(db: Db, ctx: RequestContext, enrolment_id: int, body: CompleteIn) -> dict:
    return _detail(ctx, service.complete(db, ctx, enrolment_id, body, row_version_in(body.row_version)))


def save_certificate(db: Db, ctx: RequestContext, enrolment_id: int, body: CertificateIn) -> dict:
    return _detail(ctx, service.save_certificate(db, ctx, enrolment_id, body, row_version_in(body.row_version)))


def save_feedback(db: Db, ctx: RequestContext, enrolment_id: int, body: FeedbackIn) -> dict:
    return _detail(ctx, service.save_feedback(db, ctx, enrolment_id, body))


def list_feedback(db: Db, ctx: RequestContext, session_id: int | None, program_id: int | None,
                  paging: PageParams) -> dict:
    total, rows = service.list_feedback(db, ctx, session_id, program_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: FeedbackListOut(**r))
