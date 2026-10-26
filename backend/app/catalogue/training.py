"""Permission codes and events for the Training & Development module.

Programs and sessions are company records (anyone who may view sees them all). Enrolments are employee-owned:
staff nominate themselves ("create", own scope; the request waits for approval), managers nominate their
team (also waits), HR with company scope enrols directly. Approving a nomination is "approve"; withdrawing is
"cancel"; recording a result and issuing a certificate is "complete". Attendance is marked per session day.
"""
from app.catalogue._actions import CRUD  # noqa: F401

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("training.programs", "Training programs and materials", ("view", "create", "edit", "delete", "export"), False),
    ("training.sessions", "Training sessions", ("view", "create", "edit", "delete", "export", "cancel", "complete"),
     False),
    ("training.enrolments", "Nominations and enrolments (My, Team, All)",
     ("view", "create", "approve", "reject", "cancel", "complete", "export"), False),
    ("training.attendance", "Training attendance", ("view", "edit", "export"), False),
    ("training.feedback", "Training feedback", ("view", "create", "export"), False),
    ("training.settings.general", "Training settings: General", ("view", "edit"), False),
    ("training.settings.categories", "Training settings: Categories", ("view", "create", "edit", "delete"), False),
]

EVENTS: list[tuple[str, str]] = [
    ("training.session_scheduled", "A training session was scheduled."),
    ("training.session_rescheduled", "A scheduled session's dates, times or venue changed."),
    ("training.session_cancelled", "A training session was cancelled."),
    ("training.session_completed", "A training session was closed and its participants' results recorded."),
    ("training.nominated", "Someone was nominated for a session; the nomination waits for approval."),
    ("training.enrolled", "An employee got a seat on a session."),
    ("training.nomination_rejected", "A nomination was rejected."),
    ("training.withdrawn", "A nomination or enrolment was withdrawn."),
    ("training.completed", "An employee completed a training session."),
    ("training.certificate_issued", "A certificate was attached to a completed enrolment."),
    ("training.feedback_submitted", "A participant gave feedback on a session."),
]
