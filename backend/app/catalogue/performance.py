"""Permission codes and events for the Performance module (sidebar -> Performance).

Staff hold the own-scope codes for themselves: their overview, their goals (view, create, edit) and their
self review ("submit"). Managers hold the same codes with team or department scope and rate their people
("evaluate"). HR runs the cycles: launching is "process", finalising an appraisal is "approve". Increments
proposed by finalised appraisals carry salary figures, so their screen is sensitive; applying one ("process")
writes payroll's salary revision.
"""
from app.catalogue._actions import CRUD  # noqa: F401

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("performance.overview", "My Performance overview", ("view",), False),
    ("performance.goals", "Goals", ("view", "create", "edit", "delete", "export"), False),
    ("performance.kpis", "KPIs and key result areas", ("view", "create", "edit", "delete", "export"), False),
    ("performance.appraisals", "Appraisal cycles and appraisals",
     ("view", "create", "edit", "delete", "export", "process", "close", "approve"), False),
    ("performance.reviews", "Self and manager reviews", ("view", "submit", "evaluate", "export"), False),
    ("performance.increments", "Increments proposed by appraisals", ("view", "process", "reject", "export"), True),
    ("performance.settings.rating_scales", "Performance settings: Rating scales",
     ("view", "create", "edit", "delete"), False),
    ("performance.settings.forms", "Performance settings: Appraisal forms", ("view", "create", "edit", "delete"),
     False),
]

EVENTS: list[tuple[str, str]] = [
    ("performance.goal_completed", "A goal reached 100% or was marked completed."),
    ("performance.cycle_launched", "An appraisal cycle was launched; its participants can start their reviews."),
    ("performance.review_submitted", "A self review or a manager review was submitted (data.stage: self, manager)."),
    ("performance.appraisal_finalised", "An appraisal got its final score, rating and outcome."),
    ("performance.increment_proposed", "A finalised appraisal proposed an increment for payroll."),
    ("performance.increment_applied", "A proposed increment was applied as a salary revision."),
    ("performance.increment_rejected", "A proposed increment was rejected."),
    ("performance.cycle_closed", "An appraisal cycle was closed."),
]
