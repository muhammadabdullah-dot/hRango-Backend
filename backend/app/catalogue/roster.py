"""Permission codes for the roster module: roster groups (weekly patterns) and who is enrolled in them."""
from app.catalogue._actions import CRUD

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("roster.groups", "Roster groups", CRUD, False),
    # Enrolments are employee records: the scope of these ticks decides whose enrolments are reached.
    ("roster.enrolments", "Roster enrolment", ("view", "enroll", "edit", "delete", "export"), False),
]
