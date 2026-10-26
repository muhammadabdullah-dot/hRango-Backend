"""Recruitment: the recruitment dashboard, job openings (from Manpower's open positions), applicants with CVs,
applications through the pipeline, interviews with panels and evaluations, offers, hiring (which creates
the employee) and Settings -> Rejection reasons. comparison/10-recruitment.md describes the screens."""
from datetime import date

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import recruitment_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require, require_any
from app.schemas.common import Item, Paginated
from app.schemas.recruitment import (ApplicantDetailOut, ApplicantIn, ApplicantOut, ApplicationDetailOut,
                                     ApplicationIn, ApplicationOut, CompleteIn, DashboardOut, EvaluationIn, HireIn,
                                     InterviewDetailOut, InterviewIn, InterviewOut, OfferIn, OfferOut, OpeningIn,
                                     OpeningOut, RejectIn, RejectionReasonIn, RejectionReasonOut, RemarksIn,
                                     RespondIn, RowVersionIn, StageIn)

router = APIRouter(prefix="/recruitment", tags=["recruitment"])


def _no_content() -> Response:
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# The reject form lists the reasons, so whoever may reject may read them without the settings screen.
REASONS_READ = require_any("recruitment.settings.rejection_reasons.view", "recruitment.applications.reject")


# ---------------------------------------------------------------- dashboard

@router.get("/dashboard", response_model=Item[DashboardOut])
def dashboard(year: int | None = Query(None, ge=2000, le=2100), month: int | None = Query(None, ge=1, le=12),
              db: Db = Depends(get_db), ctx: RequestContext = Depends(require("recruitment.dashboard.view"))) -> dict:
    return c.dashboard(db, ctx, "recruitment.dashboard.view", year, month)


# ---------------------------------------------------------------- job openings

@router.get("/openings", response_model=Paginated[OpeningOut])
def list_openings(q: str | None = None, status_: str | None = Query(None, alias="status"),
                  department_id: int | None = Query(None, alias="departmentId"),
                  branch_id: int | None = Query(None, alias="branchId"),
                  job_title_id: int | None = Query(None, alias="jobTitleId"),
                  open_position_id: int | None = Query(None, alias="openPositionId"),
                  paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("recruitment.openings.view"))) -> dict:
    filters = {"search": q, "status": status_, "department_id": department_id, "branch_id": branch_id,
               "job_title_id": job_title_id, "open_position_id": open_position_id}
    return c.list_openings(db, ctx, "recruitment.openings.view", filters, paging)


@router.get("/openings/{opening_id}", response_model=Item[OpeningOut])
def get_opening(opening_id: int, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("recruitment.openings.view"))) -> dict:
    return c.get_opening(db, ctx, "recruitment.openings.view", opening_id)


@router.post("/openings", response_model=Item[OpeningOut], status_code=status.HTTP_201_CREATED)
def create_opening(body: OpeningIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("recruitment.openings.create"))) -> dict:
    return c.save_opening(db, ctx, "recruitment.openings.create", None, body)


@router.put("/openings/{opening_id}", response_model=Item[OpeningOut])
def update_opening(opening_id: int, body: OpeningIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("recruitment.openings.edit"))) -> dict:
    return c.save_opening(db, ctx, "recruitment.openings.edit", opening_id, body)


@router.delete("/openings/{opening_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_opening(opening_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                   db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("recruitment.openings.delete"))) -> Response:
    c.delete_opening(db, ctx, "recruitment.openings.delete", opening_id, row_version)
    return _no_content()


@router.post("/openings/{opening_id}/publish", response_model=Item[OpeningOut])
def publish_opening(opening_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("recruitment.openings.publish"))) -> dict:
    return c.opening_status(db, ctx, "recruitment.openings.publish", opening_id, "publish", body)


@router.post("/openings/{opening_id}/hold", response_model=Item[OpeningOut])
def hold_opening(opening_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("recruitment.openings.edit"))) -> dict:
    return c.opening_status(db, ctx, "recruitment.openings.edit", opening_id, "hold", body)


@router.post("/openings/{opening_id}/close", response_model=Item[OpeningOut])
def close_opening(opening_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("recruitment.openings.close"))) -> dict:
    return c.opening_status(db, ctx, "recruitment.openings.close", opening_id, "close", body)


@router.post("/openings/{opening_id}/reopen", response_model=Item[OpeningOut])
def reopen_opening(opening_id: int, body: RowVersionIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("recruitment.openings.reopen"))) -> dict:
    return c.opening_status(db, ctx, "recruitment.openings.reopen", opening_id, "reopen", body)


# ---------------------------------------------------------------- applicants

@router.get("/applicants", response_model=Paginated[ApplicantOut])
def list_applicants(q: str | None = None, source: str | None = None,
                    city_id: int | None = Query(None, alias="cityId"),
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("recruitment.applicants.view"))) -> dict:
    filters = {"search": q, "source": source, "city_id": city_id}
    return c.list_applicants(db, ctx, "recruitment.applicants.view", filters, paging)


@router.get("/applicants/{applicant_id}", response_model=Item[ApplicantDetailOut])
def get_applicant(applicant_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("recruitment.applicants.view"))) -> dict:
    return c.get_applicant(db, ctx, "recruitment.applicants.view", applicant_id)


@router.post("/applicants", response_model=Item[ApplicantOut], status_code=status.HTTP_201_CREATED)
def create_applicant(body: ApplicantIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("recruitment.applicants.create"))) -> dict:
    return c.save_applicant(db, ctx, "recruitment.applicants.create", None, body)


@router.put("/applicants/{applicant_id}", response_model=Item[ApplicantOut])
def update_applicant(applicant_id: int, body: ApplicantIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("recruitment.applicants.edit"))) -> dict:
    return c.save_applicant(db, ctx, "recruitment.applicants.edit", applicant_id, body)


@router.delete("/applicants/{applicant_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_applicant(applicant_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                     db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("recruitment.applicants.delete"))) -> Response:
    c.delete_applicant(db, ctx, "recruitment.applicants.delete", applicant_id, row_version)
    return _no_content()


# ---------------------------------------------------------------- applications (applicant tracking)

@router.get("/applications", response_model=Paginated[ApplicationOut])
def list_applications(q: str | None = None, job_opening_id: int | None = Query(None, alias="jobOpeningId"),
                      applicant_id: int | None = Query(None, alias="applicantId"),
                      stage: str | None = None, active_only: bool = Query(False, alias="activeOnly"),
                      from_date: date | None = Query(None, alias="fromDate"),
                      to_date: date | None = Query(None, alias="toDate"),
                      paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("recruitment.applications.view"))) -> dict:
    filters = {"search": q, "job_opening_id": job_opening_id, "applicant_id": applicant_id, "stage": stage,
               "active_only": active_only, "from_date": from_date, "to_date": to_date}
    return c.list_applications(db, ctx, "recruitment.applications.view", filters, paging)


@router.get("/applications/{application_id}", response_model=Item[ApplicationDetailOut])
def get_application(application_id: int, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("recruitment.applications.view"))) -> dict:
    return c.get_application(db, ctx, "recruitment.applications.view", application_id)


@router.post("/applications", response_model=Item[ApplicationDetailOut], status_code=status.HTTP_201_CREATED)
def create_application(body: ApplicationIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("recruitment.applications.create"))) -> dict:
    return c.add_application(db, ctx, "recruitment.applications.create", body)


@router.delete("/applications/{application_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_application(application_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                       db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("recruitment.applications.delete"))) -> Response:
    c.delete_application(db, ctx, "recruitment.applications.delete", application_id, row_version)
    return _no_content()


@router.patch("/applications/{application_id}/stage", response_model=Item[ApplicationDetailOut])
def move_application(application_id: int, body: StageIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("recruitment.applications.edit"))) -> dict:
    return c.move_application(db, ctx, "recruitment.applications.edit", application_id, body)


@router.post("/applications/{application_id}/reject", response_model=Item[ApplicationDetailOut])
def reject_application(application_id: int, body: RejectIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("recruitment.applications.reject"))) -> dict:
    return c.reject_application(db, ctx, "recruitment.applications.reject", application_id, body)


@router.post("/applications/{application_id}/withdraw", response_model=Item[ApplicationDetailOut])
def withdraw_application(application_id: int, body: RemarksIn, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("recruitment.applications.edit"))) -> dict:
    return c.withdraw_application(db, ctx, "recruitment.applications.edit", application_id, body)


@router.post("/applications/{application_id}/hire", response_model=Item[ApplicationDetailOut])
def hire(application_id: int, body: HireIn, db: Db = Depends(get_db),
         ctx: RequestContext = Depends(require("recruitment.applications.hire"))) -> dict:
    """Creates the employee (and their first employment period) from the application and its accepted offer."""
    return c.hire(db, ctx, "recruitment.applications.hire", application_id, body)


# ---------------------------------------------------------------- interviews

@router.get("/interviews", response_model=Paginated[InterviewOut])
def list_interviews(q: str | None = None, job_opening_id: int | None = Query(None, alias="jobOpeningId"),
                    application_id: int | None = Query(None, alias="applicationId"),
                    interviewer_id: int | None = Query(None, alias="interviewerId"),
                    status_: str | None = Query(None, alias="status"),
                    from_date: date | None = Query(None, alias="fromDate"),
                    to_date: date | None = Query(None, alias="toDate"),
                    mine: bool = False, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("recruitment.interviews.view"))) -> dict:
    filters = {"search": q, "job_opening_id": job_opening_id, "application_id": application_id,
               "interviewer_id": interviewer_id, "status": status_, "from_date": from_date, "to_date": to_date,
               "mine": mine}
    return c.list_interviews(db, ctx, "recruitment.interviews.view", filters, paging)


@router.get("/interviews/{interview_id}", response_model=Item[InterviewDetailOut])
def get_interview(interview_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("recruitment.interviews.view"))) -> dict:
    return c.get_interview(db, ctx, "recruitment.interviews.view", interview_id)


@router.post("/interviews", response_model=Item[InterviewDetailOut], status_code=status.HTTP_201_CREATED)
def create_interview(body: InterviewIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("recruitment.interviews.create"))) -> dict:
    return c.save_interview(db, ctx, "recruitment.interviews.create", None, body)


@router.put("/interviews/{interview_id}", response_model=Item[InterviewDetailOut])
def update_interview(interview_id: int, body: InterviewIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("recruitment.interviews.edit"))) -> dict:
    return c.save_interview(db, ctx, "recruitment.interviews.edit", interview_id, body)


@router.post("/interviews/{interview_id}/cancel", response_model=Item[InterviewDetailOut])
def cancel_interview(interview_id: int, body: RemarksIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("recruitment.interviews.cancel"))) -> dict:
    return c.cancel_interview(db, ctx, "recruitment.interviews.cancel", interview_id, body)


@router.post("/interviews/{interview_id}/complete", response_model=Item[InterviewDetailOut])
def complete_interview(interview_id: int, body: CompleteIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("recruitment.interviews.complete"))) -> dict:
    return c.complete_interview(db, ctx, "recruitment.interviews.complete", interview_id, body)


@router.post("/interviews/{interview_id}/evaluations", response_model=Item[InterviewDetailOut])
def evaluate_interview(interview_id: int, body: EvaluationIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("recruitment.interviews.evaluate"))) -> dict:
    """An interviewer's rating and recommendation (saving again replaces it)."""
    return c.evaluate_interview(db, ctx, "recruitment.interviews.evaluate", interview_id, body)


# ---------------------------------------------------------------- offers

@router.get("/offers", response_model=Paginated[OfferOut])
def list_offers(q: str | None = None, job_opening_id: int | None = Query(None, alias="jobOpeningId"),
                application_id: int | None = Query(None, alias="applicationId"),
                status_: str | None = Query(None, alias="status"),
                paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("recruitment.offers.view"))) -> dict:
    filters = {"search": q, "job_opening_id": job_opening_id, "application_id": application_id, "status": status_}
    return c.list_offers(db, ctx, "recruitment.offers.view", filters, paging)


@router.get("/offers/{offer_id}", response_model=Item[OfferOut])
def get_offer(offer_id: int, db: Db = Depends(get_db),
              ctx: RequestContext = Depends(require("recruitment.offers.view"))) -> dict:
    return c.get_offer(db, ctx, "recruitment.offers.view", offer_id)


@router.post("/offers", response_model=Item[OfferOut], status_code=status.HTTP_201_CREATED)
def create_offer(body: OfferIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("recruitment.offers.create"))) -> dict:
    return c.save_offer(db, ctx, "recruitment.offers.create", None, body)


@router.put("/offers/{offer_id}", response_model=Item[OfferOut])
def update_offer(offer_id: int, body: OfferIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("recruitment.offers.edit"))) -> dict:
    return c.save_offer(db, ctx, "recruitment.offers.edit", offer_id, body)


@router.delete("/offers/{offer_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_offer(offer_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("recruitment.offers.delete"))) -> Response:
    c.delete_offer(db, ctx, "recruitment.offers.delete", offer_id, row_version)
    return _no_content()


@router.post("/offers/{offer_id}/send", response_model=Item[OfferOut])
def send_offer(offer_id: int, body: RemarksIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("recruitment.offers.submit"))) -> dict:
    return c.offer_status(db, ctx, "recruitment.offers.submit", offer_id, "send", body)


@router.post("/offers/{offer_id}/respond", response_model=Item[OfferOut])
def respond_offer(offer_id: int, body: RespondIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("recruitment.offers.respond"))) -> dict:
    """Records the candidate's answer: accepted or declined."""
    return c.respond_offer(db, ctx, "recruitment.offers.respond", offer_id, body)


@router.post("/offers/{offer_id}/withdraw", response_model=Item[OfferOut])
def withdraw_offer(offer_id: int, body: RemarksIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("recruitment.offers.cancel"))) -> dict:
    return c.offer_status(db, ctx, "recruitment.offers.cancel", offer_id, "withdraw", body)


# ---------------------------------------------------------------- settings: rejection reasons

@router.get("/settings/rejection-reasons", response_model=Item[list[RejectionReasonOut]])
def list_rejection_reasons(q: str | None = None, active_only: bool = Query(False, alias="activeOnly"),
                           db: Db = Depends(get_db), ctx: RequestContext = Depends(REASONS_READ)) -> dict:
    return c.list_rejection_reasons(db, ctx, q, active_only)


@router.post("/settings/rejection-reasons", response_model=Item[RejectionReasonOut],
             status_code=status.HTTP_201_CREATED)
def create_rejection_reason(body: RejectionReasonIn, db: Db = Depends(get_db),
                            ctx: RequestContext = Depends(require("recruitment.settings.rejection_reasons.create"))
                            ) -> dict:
    return c.save_rejection_reason(db, ctx, None, body)


@router.put("/settings/rejection-reasons/{reason_id}", response_model=Item[RejectionReasonOut])
def update_rejection_reason(reason_id: int, body: RejectionReasonIn, db: Db = Depends(get_db),
                            ctx: RequestContext = Depends(require("recruitment.settings.rejection_reasons.edit"))
                            ) -> dict:
    return c.save_rejection_reason(db, ctx, reason_id, body)


@router.delete("/settings/rejection-reasons/{reason_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_rejection_reason(reason_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                            db: Db = Depends(get_db),
                            ctx: RequestContext = Depends(require("recruitment.settings.rejection_reasons.delete"))
                            ) -> Response:
    c.delete_rejection_reason(db, ctx, reason_id, row_version)
    return _no_content()
