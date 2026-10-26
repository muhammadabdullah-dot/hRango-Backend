"""Permission codes for the Leaves module (sidebar -> Leaves).

Applying for, approving and cancelling leave are request actions (requests.* codes, POST
/api/requests/...); the Leaves screens only list leave requests. Adjusting balances is "edit" and
making an encashment is "process", so the Employee role's own-scope "create" never reaches them.
"""
from app.catalogue._actions import CRUD  # noqa: F401

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("leaves.applications", "Leave applications (My, Subordinates, All)", ("view", "export"), False),
    ("leaves.balances", "Leave balances and ledger", ("view", "edit", "export"), False),
    ("leaves.allotment", "Leave allotment and carry forward", ("process",), False),
    ("leaves.encashments", "Leave encashment", ("view", "process", "edit", "delete", "export"), False),
    ("leaves.settings.general", "Leave settings: General", ("view", "edit"), False),
    ("leaves.settings.types", "Leave settings: Leave types", ("view", "create", "edit", "delete"), False),
    ("leaves.settings.policies", "Leave settings: Leave policies", ("view", "create", "edit", "delete", "enroll"),
     False),
]

# Events this module publishes (core.usp_event_publish); webhooks subscribe to them.
EVENTS: list[tuple[str, str]] = [
    ("leaves.balance_adjusted", "An opening balance or a manual adjustment was posted to an employee's leave balance; "
     "the employee is notified."),
]
