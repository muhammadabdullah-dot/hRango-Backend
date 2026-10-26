"""Permission codes for End of Employment and Settings -> Off Boarding Checklist.

Rehire is its own screen with the "process" action, so only HR roles get it by default.
"""
from app.catalogue._actions import CRUD

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("offboarding.end_of_employment", "End of employment", CRUD, False),
    ("offboarding.rehire", "Rehire", ("process",), False),
    ("offboarding.settings.checklist", "Off-boarding checklist", CRUD, False),
]

# Events this module publishes (core.usp_event_publish); webhooks subscribe to them.
EVENTS: list[tuple[str, str]] = [
    ("offboarding.started", "An end of employment was started (by HR, or by an approved resignation); the delegatee "
     "is notified."),
    ("offboarding.completed", "An end of employment was completed: the employee has left (employees.deactivated "
     "is published too)."),
    ("offboarding.rehired", "A former employee was rehired from their completed end of employment "
     "(employees.reactivated is published too)."),
]
