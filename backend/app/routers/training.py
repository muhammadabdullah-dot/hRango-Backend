"""Training & Development: programs and their materials, sessions (schedule, cancel, complete), nominations
and enrolments (My / Team / All; nominate, approve, reject, withdraw, complete, certificate), attendance per
session day, participant feedback, and the settings (general, categories)."""
from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import training_controller as controller
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.training import (AttendanceIn, AttendanceOut, CancelIn, CategoryIn, CategoryOut, CertificateIn,
                                  CompleteIn, DecisionIn, EnrolmentDetailOut, EnrolmentOut, FeedbackIn,
                                  FeedbackListOut, MaterialIn, NominateIn, ProgramIn, ProgramOut, RowVersionIn,
                                  SessionIn, SessionOut, TrainingSettingsIn, TrainingSettingsOut)

router = APIRouter(prefix="/training", tags=["training"])

Tab = Literal["my", "team", "all"]
SessionStatus = Literal["scheduled", "completed", "cancelled"]
EnrolmentStatus = Literal["requested", "enrolled", "rejected", "withdrawn", "cancelled", "completed", "not_completed"]
NO_CONTENT = status.HTTP_204_NO_CONTENT


# --- Settings ------------------------------------------------------------------------------------

@router.get("/settings", response_model=Item[TrainingSettingsOut])
def get_settings(db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("training.settings.general.view"))) -> dict:
    return controller.get_settings(db, ctx)


@router.put("/settings", response_model=Item[TrainingSettingsOut])
def save_settings(body: TrainingSettingsIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("training.settings.general.edit"))) -> dict:
    return controller.save_settings(db, ctx, body)


@router.get("/categories", response_model=Paginated[CategoryOut])
def list_categories(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("training.settings.categories.view"))) -> dict:
    return controller.list_categories(db, ctx, q, is_active, paging)


@router.post("/categories", response_model=Item[CategoryOut], status_code=status.HTTP_201_CREATED)
def create_category(body: CategoryIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("training.settings.categories.create"))) -> dict:
    return controller.create_category(db, ctx, body)


@router.put("/categories/{category_id}", response_model=Item[CategoryOut])
def update_category(category_id: int, body: CategoryIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("training.settings.categories.edit"))) -> dict:
    return controller.update_category(db, ctx, category_id, body)


@router.delete("/categories/{category_id}", status_code=NO_CONTENT)
def delete_category(category_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                    db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("training.settings.categories.delete"))) -> Response:
    controller.delete_category(db, ctx, category_id, row_version)
    return Response(status_code=NO_CONTENT)


# --- Programs ------------------------------------------------------------------------------------

@router.get("/programs", response_model=Paginated[ProgramOut])
def list_programs(q: str | None = None, category_id: int | None = Query(None, alias="categoryId"),
                  delivery_mode: str | None = Query(None, alias="deliveryMode"),
                  is_active: bool | None = Query(None, alias="isActive"), paging: PageParams = Depends(page_params),
                  db: Db = Depends(get_db), ctx: RequestContext = Depends(require("training.programs.view"))) -> dict:
    return controller.list_programs(db, ctx, q, category_id, delivery_mode, is_active, paging)


@router.get("/programs/{program_id}", response_model=Item[ProgramOut])
def get_program(program_id: int, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("training.programs.view"))) -> dict:
    return controller.get_program(db, ctx, program_id)


@router.post("/programs", response_model=Item[ProgramOut], status_code=status.HTTP_201_CREATED)
def create_program(body: ProgramIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("training.programs.create"))) -> dict:
    return controller.create_program(db, ctx, body)


@router.put("/programs/{program_id}", response_model=Item[ProgramOut])
def update_program(program_id: int, body: ProgramIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("training.programs.edit"))) -> dict:
    return controller.update_program(db, ctx, program_id, body)


@router.delete("/programs/{program_id}", status_code=NO_CONTENT)
def delete_program(program_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                   db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("training.programs.delete"))) -> Response:
    controller.delete_program(db, ctx, program_id, row_version)
    return Response(status_code=NO_CONTENT)


@router.post("/programs/{program_id}/materials", response_model=Item[ProgramOut], status_code=status.HTTP_201_CREATED)
def add_material(program_id: int, body: MaterialIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("training.programs.edit"))) -> dict:
    return controller.add_material(db, ctx, program_id, body.file_id, body.label)


@router.delete("/programs/{program_id}/materials/{attachment_id}", status_code=NO_CONTENT)
def delete_material(program_id: int, attachment_id: int, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("training.programs.edit"))) -> Response:
    controller.delete_material(db, ctx, program_id, attachment_id)
    return Response(status_code=NO_CONTENT)


# --- Sessions ------------------------------------------------------------------------------------

@router.get("/sessions", response_model=Paginated[SessionOut])
def list_sessions(program_id: int | None = Query(None, alias="programId"),
                  session_status: SessionStatus | None = Query(None, alias="status"),
                  from_date: date | None = Query(None, alias="fromDate"),
                  to_date: date | None = Query(None, alias="toDate"),
                  q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("training.sessions.view"))) -> dict:
    return controller.list_sessions(db, ctx, program_id, session_status, from_date, to_date, q, paging)


@router.get("/sessions/{session_id}", response_model=Item[SessionOut])
def get_session(session_id: int, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("training.sessions.view"))) -> dict:
    return controller.get_session(db, ctx, session_id)


@router.post("/sessions", response_model=Item[SessionOut], status_code=status.HTTP_201_CREATED)
def create_session(body: SessionIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("training.sessions.create"))) -> dict:
    return controller.create_session(db, ctx, body)


@router.put("/sessions/{session_id}", response_model=Item[SessionOut])
def update_session(session_id: int, body: SessionIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("training.sessions.edit"))) -> dict:
    return controller.update_session(db, ctx, session_id, body)


@router.delete("/sessions/{session_id}", status_code=NO_CONTENT)
def delete_session(session_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                   db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("training.sessions.delete"))) -> Response:
    controller.delete_session(db, ctx, session_id, row_version)
    return Response(status_code=NO_CONTENT)


@router.post("/sessions/{session_id}/cancel", response_model=Item[SessionOut])
def cancel_session(session_id: int, body: CancelIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("training.sessions.cancel"))) -> dict:
    return controller.cancel_session(db, ctx, session_id, body)


@router.post("/sessions/{session_id}/complete", response_model=Item[SessionOut])
def complete_session(session_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("training.sessions.complete"))) -> dict:
    return controller.complete_session(db, ctx, session_id, body.row_version)


@router.get("/sessions/{session_id}/attendance", response_model=Item[AttendanceOut])
def get_attendance(session_id: int, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("training.attendance.view"))) -> dict:
    return controller.get_attendance(db, ctx, session_id)


@router.put("/sessions/{session_id}/attendance", response_model=Item[AttendanceOut])
def save_attendance(session_id: int, body: AttendanceIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("training.attendance.edit"))) -> dict:
    return controller.save_attendance(db, ctx, session_id, body)


# --- Enrolments ----------------------------------------------------------------------------------

@router.get("/enrolments", response_model=Paginated[EnrolmentOut])
def list_enrolments(tab: Tab = "all", session_id: int | None = Query(None, alias="sessionId"),
                    program_id: int | None = Query(None, alias="programId"),
                    enrolment_status: EnrolmentStatus | None = Query(None, alias="status"),
                    employee_id: int | None = Query(None, alias="employeeId"), q: str | None = None,
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("training.enrolments.view"))) -> dict:
    return controller.list_enrolments(db, ctx, tab, session_id, program_id, enrolment_status, employee_id, q, paging)


@router.get("/enrolments/{enrolment_id}", response_model=Item[EnrolmentDetailOut])
def get_enrolment(enrolment_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("training.enrolments.view"))) -> dict:
    return controller.get_enrolment(db, ctx, enrolment_id)


@router.post("/enrolments", response_model=Item[list[EnrolmentOut]], status_code=status.HTTP_201_CREATED)
def nominate(body: NominateIn, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("training.enrolments.create"))) -> dict:
    return controller.nominate(db, ctx, body)


@router.post("/enrolments/{enrolment_id}/approve", response_model=Item[EnrolmentDetailOut])
def approve(enrolment_id: int, body: DecisionIn, db: Db = Depends(get_db),
            ctx: RequestContext = Depends(require("training.enrolments.approve"))) -> dict:
    return controller.decide(db, ctx, enrolment_id, "approve", body)


@router.post("/enrolments/{enrolment_id}/reject", response_model=Item[EnrolmentDetailOut])
def reject(enrolment_id: int, body: DecisionIn, db: Db = Depends(get_db),
           ctx: RequestContext = Depends(require("training.enrolments.reject"))) -> dict:
    return controller.decide(db, ctx, enrolment_id, "reject", body)


@router.post("/enrolments/{enrolment_id}/withdraw", response_model=Item[EnrolmentDetailOut])
def withdraw(enrolment_id: int, body: DecisionIn, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("training.enrolments.cancel"))) -> dict:
    return controller.decide(db, ctx, enrolment_id, "withdraw", body)


@router.post("/enrolments/{enrolment_id}/complete", response_model=Item[EnrolmentDetailOut])
def complete(enrolment_id: int, body: CompleteIn, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("training.enrolments.complete"))) -> dict:
    return controller.complete(db, ctx, enrolment_id, body)


@router.put("/enrolments/{enrolment_id}/certificate", response_model=Item[EnrolmentDetailOut])
def save_certificate(enrolment_id: int, body: CertificateIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("training.enrolments.complete"))) -> dict:
    return controller.save_certificate(db, ctx, enrolment_id, body)


@router.put("/enrolments/{enrolment_id}/feedback", response_model=Item[EnrolmentDetailOut])
def save_feedback(enrolment_id: int, body: FeedbackIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("training.feedback.create"))) -> dict:
    return controller.save_feedback(db, ctx, enrolment_id, body)


@router.get("/feedback", response_model=Paginated[FeedbackListOut])
def list_feedback(session_id: int | None = Query(None, alias="sessionId"),
                  program_id: int | None = Query(None, alias="programId"), paging: PageParams = Depends(page_params),
                  db: Db = Depends(get_db), ctx: RequestContext = Depends(require("training.feedback.view"))) -> dict:
    return controller.list_feedback(db, ctx, session_id, program_id, paging)
