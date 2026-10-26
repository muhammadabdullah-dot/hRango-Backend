"""Permission codes for the Warning module (warning policies, penalties, warnings raised).

Policies, penalties and their history are settings tabs (warning.settings.<tab>). Raising warnings
from processed time sheets is "process" on the warnings list.
"""
from app.catalogue._actions import CRUD  # noqa: F401

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("warning.warnings", "Warnings raised", ("view", "process", "export"), False),
    ("warning.settings.policies", "Warning settings: Policies", ("view", "create", "edit", "delete"), False),
    ("warning.settings.penalties", "Warning settings: Penalties", ("view", "edit"), False),
    ("warning.settings.history", "Warning settings: History", ("view",), False),
]

# Events this module publishes (core.usp_event_publish); webhooks subscribe to them.
EVENTS: list[tuple[str, str]] = [
    ("warning.issued", "New attendance warnings for an employee (one event per employee per run, listing them); "
     "the employee is notified."),
]
