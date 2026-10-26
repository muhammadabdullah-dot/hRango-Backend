"""Permission codes for the attendance module: overview, time sheet, logs and the settings tabs it owns.
The Scheduling, Rest Day, Break Types, Holidays and Time Slots tabs belong to the scheduling module."""
from app.catalogue._actions import CRUD

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("attendance.overview", "Attendance overview", ("view", "export"), False),
    # clock: the signed-in employee's own Clock In / Clock Out (web dashboard and mobile app).
    ("attendance.time_sheet", "Time sheet", ("view", "edit", "export", "process", "clock"), False),
    ("attendance.logs", "Attendance logs", (*CRUD, "import"), False),
    ("attendance.settings.basic", "Attendance settings: basic", ("view", "edit"), False),
    ("attendance.settings.overtime", "Attendance settings: overtime", ("view", "edit"), False),
    ("attendance.settings.overtime_policies", "Attendance settings: overtime policies", CRUD, False),
    ("attendance.settings.ip_restrictions", "Attendance settings: IP restrictions", CRUD, False),
    ("attendance.settings.geo_fencing", "Attendance settings: geo fencing", CRUD, False),
    ("attendance.settings.devices", "Attendance settings: biometric devices", (*CRUD, "enroll"), False),
]

# Events this module publishes (core.usp_event_publish); webhooks subscribe to them.
EVENTS: list[tuple[str, str]] = [
    ("attendance.timesheet_processed", "A time-sheet run finished (Process button or the nightly job): dates, days "
     "processed, employees. Re-processing after a punch or a request is not announced."),
]
