"""Permission codes for scheduling: the shift planner and the scheduling settings tabs of
Attendance settings (time slots, break types, rest days, holidays)."""
from app.catalogue._actions import CRUD

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    # The planner (My / Subordinates / All). Shifts are employee records: the scope of each tick decides
    # whose shifts are reached. edit covers single edits, multi edit and swap; create covers Create
    # Scheduling and Apply Default Shift; delete covers single, multi and range deletes.
    ("scheduling.schedules", "Shift scheduling", ("view", "create", "edit", "delete", "export"), False),
    ("scheduling.settings.time_slots", "Time slots", CRUD, False),
    ("scheduling.settings.break_types", "Break types", CRUD, False),
    ("scheduling.settings.rest_days", "Rest days", CRUD, False),
    ("scheduling.settings.holidays", "Holidays", CRUD, False),
]
