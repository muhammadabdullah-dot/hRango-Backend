"""Permission codes for Manpower Planning: Planning, E-Budgeting, Budget Approvals, Open Positions and
E-Budget Settings (comparison/09-manpower-benefits.md). Screens with salary figures are sensitive."""
from app.catalogue._actions import CRUD

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("manpower.planning", "Manpower planning", CRUD, True),
    ("manpower.e_budgeting", "E-Budgeting", CRUD, True),
    ("manpower.budget_approvals", "Budget approvals", ("view", "approve", "reject"), True),
    ("manpower.open_positions", "Open positions", ("view", "edit", "close", "reopen", "download", "export"), False),
    ("manpower.settings.budget_durations", "E-Budget settings: budget duration", CRUD, False),
    ("manpower.settings.position_titles", "E-Budget settings: position titles", ("view", "export"), False),
    ("manpower.settings.positions", "E-Budget settings: employee positions", (*CRUD, "import"), True),
]

# Events this module publishes (core.usp_event_publish); webhooks subscribe to them.
EVENTS: list[tuple[str, str]] = [
    ("manpower.budget_decided", "A budget was approved or rejected (Budget Approvals); whoever submitted it is "
     "notified."),
    ("manpower.position_opened", "An open position was released for hiring (budget approved) or reopened."),
    ("manpower.position_closed", "An open position was closed."),
]
