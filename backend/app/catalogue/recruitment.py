"""Permission codes and events for Recruitment: job openings, applicants, applications through the pipeline,
interviews with their evaluations, offers, hiring, the recruitment dashboard and settings
(comparison/10-recruitment.md). Offers carry salary figures, so they are sensitive."""
from app.catalogue._actions import CRUD

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("recruitment.dashboard", "Recruitment dashboard", ("view",), False),
    ("recruitment.openings", "Job openings", (*CRUD, "publish", "close", "reopen"), False),
    ("recruitment.applicants", "Applicants", CRUD, False),
    ("recruitment.applications", "Applications (applicant tracking)", (*CRUD, "reject", "hire"), False),
    ("recruitment.interviews", "Interviews",
     ("view", "create", "edit", "export", "cancel", "complete", "evaluate"), False),
    ("recruitment.offers", "Offers", (*CRUD, "submit", "respond", "cancel"), True),
    ("recruitment.settings.rejection_reasons", "Recruitment settings: rejection reasons",
     ("view", "create", "edit", "delete"), False),
]

EVENTS: list[tuple[str, str]] = [
    ("recruitment.opening_published", "A job opening was published (opened for applications)."),
    ("recruitment.opening_closed", "A job opening was closed, by hand or when its last vacancy was filled."),
    ("recruitment.application_received", "An applicant applied (or was added) to a job opening."),
    ("recruitment.stage_changed", "An application moved to another pipeline stage (fromStage, toStage)."),
    ("recruitment.interview_scheduled", "An interview was scheduled; the interviewers were notified."),
    ("recruitment.interview_rescheduled", "An interview's time, panel or place changed."),
    ("recruitment.interview_cancelled", "An interview was cancelled."),
    ("recruitment.interview_evaluated", "An interviewer recorded their rating and recommendation."),
    ("recruitment.offer_made", "An offer was sent to a candidate."),
    ("recruitment.offer_accepted", "A candidate accepted an offer; the hiring manager was notified."),
    ("recruitment.offer_declined", "A candidate declined an offer."),
    ("recruitment.offer_withdrawn", "An offer was withdrawn."),
    ("recruitment.candidate_hired", "A candidate was hired: the employee record was created from the offer."),
]
