"""Permission codes for Benefits: plan years, plans, enrollment windows, employee elections, plan files,
health benefits and perks (comparison/09-manpower-benefits.md). Plan years, plans, windows and files are
company-wide records: changing them needs the permission with company scope (benefits_service)."""
from app.catalogue._actions import CRUD

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("benefits.plan_years", "Benefit plan years", CRUD, False),
    ("benefits.plans", "Benefit plans", CRUD, False),
    ("benefits.enrollment_windows", "Enrollment windows", CRUD, False),
    ("benefits.elections", "Employee elections", ("view", "create", "edit", "approve", "reject", "export"), False),
    ("benefits.files", "Benefit plan files", ("view", "create", "delete", "download"), False),
    ("benefits.health", "Health benefits", CRUD, True),
    ("benefits.perks", "Perks", CRUD, False),
]

# Events this module publishes (core.usp_event_publish); webhooks subscribe to them.
EVENTS: list[tuple[str, str]] = [
    ("benefits.election_decided", "An employee's benefit election was approved or rejected (with the plans chosen); "
     "the employee is notified."),
]
