"""Permission codes for Settings -> Control Panel (organisation set-up).

Every screen here is administration, so app/core/default_roles.py keeps the whole module
(organisation.*) away from the non-admin roles. Picker lists (names and ids of branches,
departments ...) are open to any signed-in user through /api/organisation/lookups.
"""
from app.catalogue._actions import CRUD

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("organisation.general", "General settings", ("view", "edit"), False),
    ("organisation.companies", "Companies", ("view", "create", "edit"), False),
    ("organisation.locations", "Locations", CRUD, False),
    ("organisation.areas", "Areas", CRUD, False),
    ("organisation.branches", "Branches", CRUD, False),
    ("organisation.departments", "Departments", CRUD, False),
    ("organisation.divisions", "Divisions", CRUD, False),
    ("organisation.cost_centers", "Cost centers", CRUD, False),
    ("organisation.designations", "Designations", CRUD, False),
    ("organisation.job_titles", "Job titles", CRUD, False),
    ("organisation.grades", "Grades", CRUD, False),
    ("organisation.job_levels", "Job levels", CRUD, False),
    ("organisation.employee_groups", "Employee groups", CRUD, False),
    ("organisation.employment_types", "Employment types", CRUD, False),
    ("organisation.announcements", "Announcements", CRUD, False),
]
