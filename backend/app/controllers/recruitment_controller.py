"""HTTP shape for recruitment screens: envelopes, row versions as text, rows to response models, and signed
links for the CV and offer-letter files of records the caller may read."""
from typing import Any, TypeVar

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import ApiModel, paginated
from app.schemas.files import FileRef
from app.schemas.recruitment import (ApplicantDetailOut, ApplicantIn, ApplicantOut, ApplicationDetailOut,
                                     ApplicationIn, ApplicationOut, CompleteIn, DashboardOut, EvaluationIn,
                                     EvaluationOut, HireIn, InterviewDetailOut, InterviewerOut, InterviewIn,
                                     InterviewOut, OfferIn, OfferOut, OpeningIn, OpeningOut, RejectIn,
                                     RejectionReasonIn, RejectionReasonOut, RemarksIn, RespondIn, RowVersionIn,
                                     StageHistoryOut, StageIn)
from app.services import recruitment_service as svc

M = TypeVar("M", bound=ApiModel)
Sets = list[list[dict[str, Any]]]


def _rv(row: dict[str, Any]) -> dict[str, Any]:
    return {**row, "row_version": row_version_out(row["row_version"])} if "row_version" in row else row


def _file(file_id: Any, name: str | None, company_id: int) -> FileRef | None:
    return FileRef(id=str(file_id), name=name, url=file_url(file_id, company_id)) if file_id else None


def _opening(row: dict[str, Any]) -> OpeningOut:
    return OpeningOut(**_rv(row))


def _applicant(ctx: RequestContext):
    def convert(row: dict[str, Any]) -> ApplicantOut:
        return ApplicantOut(**_rv(row), cv=_file(row["cv_file_id"], row["cv_file_name"], ctx.company_id))
    return convert


def _application(ctx: RequestContext):
    def convert(row: dict[str, Any]) -> ApplicationOut:
        return ApplicationOut(**_rv(row), cv=_file(row["cv_file_id"], row["cv_file_name"], ctx.company_id))
    return convert


def _interview(ctx: RequestContext):
    def convert(row: dict[str, Any]) -> InterviewOut:
        return InterviewOut(**_rv(row), cv=_file(row["cv_file_id"], None, ctx.company_id))
    return convert


def _offer(ctx: RequestContext):
    def convert(row: dict[str, Any]) -> OfferOut:
        return OfferOut(**_rv(row), offer_letter=_file(row["offer_letter_file_id"], row["offer_letter_file_name"],
                                                       ctx.company_id))
    return convert


def _application_detail(ctx: RequestContext, sets: Sets) -> ApplicationDetailOut:
    head, history, interviews, offers = sets[-4], sets[-3], sets[-2], sets[-1]
    base = _application(ctx)(head[0])
    return ApplicationDetailOut(**base.model_dump(by_alias=False),
                                history=[StageHistoryOut(**r) for r in history],
                                interviews=[_interview(ctx)(r) for r in interviews],
                                offers=[_offer(ctx)(r) for r in offers])


def _interview_detail(ctx: RequestContext, sets: Sets) -> InterviewDetailOut:
    head, panel, evaluations = sets[-3], sets[-2], sets[-1]
    base = _interview(ctx)(head[0])
    return InterviewDetailOut(**base.model_dump(by_alias=False),
                              interviewers=[InterviewerOut(**r) for r in panel],
                              evaluations=[EvaluationOut(**_rv(r)) for r in evaluations])


# ---------------------------------------------------------------- dashboard

def dashboard(db: Db, ctx: RequestContext, code: str, year: int | None, month: int | None) -> dict:
    return {"data": DashboardOut(**svc.dashboard(db, ctx, code, year, month))}


# ---------------------------------------------------------------- job openings

def list_openings(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows = svc.list_openings(db, ctx, code, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _opening)


def get_opening(db: Db, ctx: RequestContext, code: str, opening_id: int) -> dict:
    return {"data": _opening(svc.get_opening(db, ctx, code, opening_id))}


def save_opening(db: Db, ctx: RequestContext, code: str, opening_id: int | None, body: OpeningIn) -> dict:
    rv = row_version_in(body.row_version) if opening_id is not None else None
    return {"data": _opening(svc.save_opening(db, ctx, code, opening_id, body, rv))}


def delete_opening(db: Db, ctx: RequestContext, code: str, opening_id: int, row_version: str | None) -> None:
    svc.delete_opening(db, ctx, code, opening_id, row_version_in(row_version))


def opening_status(db: Db, ctx: RequestContext, code: str, opening_id: int, action: str, body: RowVersionIn) -> dict:
    return {"data": _opening(svc.opening_status(db, ctx, code, opening_id, action, row_version_in(body.row_version)))}


# ---------------------------------------------------------------- applicants

def list_applicants(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows = svc.list_applicants(db, ctx, code, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _applicant(ctx))


def get_applicant(db: Db, ctx: RequestContext, code: str, applicant_id: int) -> dict:
    head, applications = svc.get_applicant(db, ctx, code, applicant_id)
    base = _applicant(ctx)(head[0])
    return {"data": ApplicantDetailOut(**base.model_dump(by_alias=False),
                                       applications=[_application(ctx)(r) for r in applications])}


def save_applicant(db: Db, ctx: RequestContext, code: str, applicant_id: int | None, body: ApplicantIn) -> dict:
    rv = row_version_in(body.row_version) if applicant_id is not None else None
    return {"data": _applicant(ctx)(svc.save_applicant(db, ctx, code, applicant_id, body, rv))}


def delete_applicant(db: Db, ctx: RequestContext, code: str, applicant_id: int, row_version: str | None) -> None:
    svc.delete_applicant(db, ctx, code, applicant_id, row_version_in(row_version))


# ---------------------------------------------------------------- applications

def list_applications(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows = svc.list_applications(db, ctx, code, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _application(ctx))


def get_application(db: Db, ctx: RequestContext, code: str, application_id: int) -> dict:
    return {"data": _application_detail(ctx, svc.get_application(db, ctx, code, application_id))}


def add_application(db: Db, ctx: RequestContext, code: str, body: ApplicationIn) -> dict:
    return {"data": _application_detail(ctx, svc.add_application(db, ctx, code, body))}


def move_application(db: Db, ctx: RequestContext, code: str, application_id: int, body: StageIn) -> dict:
    sets = svc.move_application(db, ctx, code, application_id, body.stage, body.remarks,
                                row_version_in(body.row_version))
    return {"data": _application_detail(ctx, sets)}


def reject_application(db: Db, ctx: RequestContext, code: str, application_id: int, body: RejectIn) -> dict:
    sets = svc.close_application(db, ctx, code, application_id, "rejected", body.rejection_reason_id, body.remarks,
                                 row_version_in(body.row_version))
    return {"data": _application_detail(ctx, sets)}


def withdraw_application(db: Db, ctx: RequestContext, code: str, application_id: int, body: RemarksIn) -> dict:
    sets = svc.close_application(db, ctx, code, application_id, "withdrawn", None, body.remarks,
                                 row_version_in(body.row_version))
    return {"data": _application_detail(ctx, sets)}


def delete_application(db: Db, ctx: RequestContext, code: str, application_id: int, row_version: str | None) -> None:
    svc.delete_application(db, ctx, code, application_id, row_version_in(row_version))


def hire(db: Db, ctx: RequestContext, code: str, application_id: int, body: HireIn) -> dict:
    sets = svc.hire(db, ctx, code, application_id, body, row_version_in(body.row_version))
    return {"data": _application_detail(ctx, sets)}


# ---------------------------------------------------------------- interviews

def list_interviews(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows = svc.list_interviews(db, ctx, code, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _interview(ctx))


def get_interview(db: Db, ctx: RequestContext, code: str, interview_id: int) -> dict:
    return {"data": _interview_detail(ctx, svc.get_interview(db, ctx, code, interview_id))}


def save_interview(db: Db, ctx: RequestContext, code: str, interview_id: int | None, body: InterviewIn) -> dict:
    rv = row_version_in(body.row_version) if interview_id is not None else None
    return {"data": _interview_detail(ctx, svc.save_interview(db, ctx, code, interview_id, body, rv))}


def cancel_interview(db: Db, ctx: RequestContext, code: str, interview_id: int, body: RemarksIn) -> dict:
    sets = svc.cancel_interview(db, ctx, code, interview_id, body.remarks, row_version_in(body.row_version))
    return {"data": _interview_detail(ctx, sets)}


def complete_interview(db: Db, ctx: RequestContext, code: str, interview_id: int, body: CompleteIn) -> dict:
    sets = svc.complete_interview(db, ctx, code, interview_id, body, row_version_in(body.row_version))
    return {"data": _interview_detail(ctx, sets)}


def evaluate_interview(db: Db, ctx: RequestContext, code: str, interview_id: int, body: EvaluationIn) -> dict:
    return {"data": _interview_detail(ctx, svc.evaluate_interview(db, ctx, code, interview_id, body))}


# ---------------------------------------------------------------- offers

def list_offers(db: Db, ctx: RequestContext, code: str, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows = svc.list_offers(db, ctx, code, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _offer(ctx))


def get_offer(db: Db, ctx: RequestContext, code: str, offer_id: int) -> dict:
    return {"data": _offer(ctx)(svc.get_offer(db, ctx, code, offer_id))}


def save_offer(db: Db, ctx: RequestContext, code: str, offer_id: int | None, body: OfferIn) -> dict:
    rv = row_version_in(body.row_version) if offer_id is not None else None
    return {"data": _offer(ctx)(svc.save_offer(db, ctx, code, offer_id, body, rv))}


def delete_offer(db: Db, ctx: RequestContext, code: str, offer_id: int, row_version: str | None) -> None:
    svc.delete_offer(db, ctx, code, offer_id, row_version_in(row_version))


def offer_status(db: Db, ctx: RequestContext, code: str, offer_id: int, action: str, body: RemarksIn) -> dict:
    row = svc.offer_status(db, ctx, code, offer_id, action, body.remarks, row_version_in(body.row_version))
    return {"data": _offer(ctx)(row)}


def respond_offer(db: Db, ctx: RequestContext, code: str, offer_id: int, body: RespondIn) -> dict:
    action = "accept" if body.decision == "accepted" else "decline"
    row = svc.offer_status(db, ctx, code, offer_id, action, body.remarks, row_version_in(body.row_version))
    return {"data": _offer(ctx)(row)}


# ---------------------------------------------------------------- settings: rejection reasons

def list_rejection_reasons(db: Db, ctx: RequestContext, search: str | None, active_only: bool) -> dict:
    rows = svc.list_rejection_reasons(db, ctx, search, active_only)
    return {"data": [RejectionReasonOut(**_rv(r)) for r in rows]}


def save_rejection_reason(db: Db, ctx: RequestContext, reason_id: int | None, body: RejectionReasonIn) -> dict:
    rv = row_version_in(body.row_version) if reason_id is not None else None
    row = svc.save_rejection_reason(db, ctx, reason_id, body.name, body.is_active, body.sort_order, rv)
    return {"data": RejectionReasonOut(**_rv(row))}


def delete_rejection_reason(db: Db, ctx: RequestContext, reason_id: int, row_version: str | None) -> None:
    svc.delete_rejection_reason(db, ctx, reason_id, row_version_in(row_version))
