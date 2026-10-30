"""The roles every company starts with. Customers rename, copy, change or retire them afterwards.

Departmental roles are one role plus a scope, not one role per department: a Department Head sees
their own department (and its sub-departments), whichever department that is.

Each role lists (pattern, scope) grants, matched against the catalogue codes with fnmatch, and
patterns to leave out. The first grant that matches a code sets its scope, so list the wider scope
first where a role has both. `no_sensitive` leaves out every code marked sensitive (salary, bank,
CNIC, loan and payslip figures, ACC-9) except for the holder's own records and the patterns in `sensitive_ok`
— for the managers and executives until open question E6 (who sees salaries) is answered. Because roles are patterns, codes a module adds later reach the
right roles on the next seed run; a code a customer removed from a role is not offered again
(auth.role_default_offer).
"""
from fnmatch import fnmatchcase

from app.core.permissions import catalogue_rows

ADMIN_AREAS = ("access.*", "organisation.*", "integrations.*")
SETTINGS = ("*.settings.*",)

# What every member of staff does for themselves.
SELF_SERVICE = [
    ("dashboard.employee.view", "own"), ("inbox.notifications.view", "own"),
    ("employees.directory.view", "own"), ("employees.history.view", "own"),
    ("employees.identity.view", "own"), ("employees.personal.view", "own"), ("employees.salary.view", "own"),
    ("employees.bank_accounts.view", "own"),
    ("employees.photo.edit", "own"), ("employees.contracts.view", "own"),
    *[(f"employees.{tab}.{action}", "own")
      for tab in ("emergency_contacts", "dependents", "skills", "education", "experience", "documents")
      for action in ("view", "edit")],
    # Personal details change through an Update Information request that HR approves.
    ("employees.update_requests.view", "own"), ("employees.update_requests.create", "own"),
    ("employees.update_requests.cancel", "own"),
    ("attendance.time_sheet.view", "own"), ("attendance.time_sheet.clock", "own"), ("attendance.logs.view", "own"),
    ("scheduling.schedules.view", "own"),
    *[(f"requests.{kind}.{action}", "own")
      for kind in ("punch", "leave", "shift_swap", "loan", "work_from_home", "official_visit", "relaxation",
                   "rest_day", "travel", "resignation", "overtime", "expense", "air_ticket", "requisition")
      for action in ("view", "create", "cancel")],
    ("leaves.applications.view", "own"), ("leaves.balances.view", "own"),
    ("loans.loans.view", "own"),
    ("payroll.payslips.view", "own"), ("payroll.payslips.download", "own"), ("payroll.payslips.print", "own"),
    ("payroll.employee_accounts.view", "own"), ("payroll.final_settlement.view", "own"),
    ("warning.warnings.view", "own"),
    ("assets.allocations.view", "own"), ("assets.clearance.view", "own"),
    ("offboarding.end_of_employment.view", "own"),
    # The approvals screen: consenting to a colleague's request, deciding as a delegate. Whether a person
    # may decide a given request comes from its flow (ACC-13), not from this permission.
    ("requests.approvals.view", "own"), ("requests.approvals.approve", "own"), ("requests.approvals.reject", "own"),
    ("benefits.plan_years.view", "own"), ("benefits.plans.view", "own"), ("benefits.enrollment_windows.view", "own"),
    ("benefits.files.view", "own"), ("benefits.files.download", "own"),
    ("benefits.elections.view", "own"), ("benefits.elections.create", "own"), ("benefits.elections.edit", "own"),
    ("benefits.health.view", "own"), ("benefits.health.create", "own"),
    # Filling in the custom forms sent to you; the form's audience decides which ones you see.
    ("forms.my_forms.view", "own"), ("forms.my_forms.submit", "own"),
    ("benefits.perks.view", "own"), ("benefits.perks.create", "own"),
    ("performance.overview.view", "own"), ("performance.goals.view", "own"), ("performance.goals.create", "own"),
    ("performance.goals.edit", "own"), ("performance.kpis.view", "own"), ("performance.reviews.view", "own"),
    ("performance.reviews.submit", "own"),
    ("training.programs.view", "own"), ("training.sessions.view", "own"), ("training.attendance.view", "own"),
    ("training.enrolments.view", "own"), ("training.enrolments.create", "own"), ("training.enrolments.cancel", "own"),
    ("training.feedback.create", "own"),
    ("engagement.feed.*", "own"), ("engagement.survey_responses.respond", "own"),
    # Inside a workspace the workspace role decides what a member may do.
    ("projects.*", "own"),
]


def _managing(scope: str) -> list[tuple[str, str]]:
    """What a line manager (team) or department head (department) does for their people."""
    return [
        ("dashboard.employee.view", scope), ("dashboard.hr.view", scope),
        ("employees.directory.view", scope), ("employees.directory.export", scope), ("employees.history.*", scope),
        ("attendance.overview.*", scope), ("attendance.time_sheet.view", scope),
        ("attendance.time_sheet.export", scope), ("attendance.logs.view", scope), ("attendance.logs.export", scope),
        ("roster.groups.view", scope), ("roster.enrolments.view", scope),
        ("scheduling.schedules.*", scope),
        ("requests.*.view", scope), ("requests.*.export", scope),
        ("requests.approvals.view", scope), ("requests.approvals.approve", scope),
        ("requests.approvals.reject", scope),
        ("leaves.applications.*", scope), ("leaves.balances.view", scope), ("leaves.balances.export", scope),
        ("warning.warnings.view", scope), ("warning.warnings.export", scope),
        ("assets.allocations.view", scope), ("offboarding.end_of_employment.view", scope),
        ("benefits.elections.view", scope), ("benefits.perks.view", scope),
        ("payroll.vouchers.view", scope), ("payroll.vouchers.approve", scope), ("payroll.vouchers.reject", scope),
        *[(f"employees.{tab}.view", scope)
          for tab in ("emergency_contacts", "skills", "education", "experience")],
        ("performance.overview.view", scope), ("performance.goals.*", scope), ("performance.reviews.view", scope),
        ("performance.reviews.evaluate", scope), ("performance.reviews.export", scope),
        ("performance.appraisals.view", scope),
        *[(f"training.enrolments.{a}", scope) for a in ("view", "create", "approve", "reject", "cancel", "export")],
        ("training.attendance.view", scope), ("training.feedback.view", scope),
        # Interviewers see and evaluate the interviews they sit on.
        ("recruitment.interviews.view", "own"), ("recruitment.interviews.evaluate", "own"),
        ("projects.*", scope),
    ]


ROLES = [
    {"code": "company_admin", "name": "Company Administrator",
     "description": "Everything in the company, including users, roles and organisation set-up.",
     "grants": [("*", "company")], "exclude": []},
    {"code": "hr_manager", "name": "HR Manager",
     "description": "All HR modules for the whole company. No user or role administration.",
     "grants": [("*", "company")], "exclude": ["access.*", "integrations.*"]},
    {"code": "hr_officer", "name": "HR Officer",
     "description": "Day-to-day HR work for the whole company: no settings, deletes, payroll, salaries or budgets.",
     "grants": [("*", "company")],
     "exclude": [*ADMIN_AREAS, *SETTINGS, "*.delete", "payroll.*", "loans.*", "employees.salary.*",
                 "employees.bank_accounts.*", "manpower.planning.*", "manpower.e_budgeting.*",
                 "manpower.budget_approvals.*", "benefits.health.*", "performance.increments.*"]},
    {"code": "payroll_manager", "name": "Payroll Manager",
     "description": "Payroll, loans and final settlement, including salary and bank figures.",
     "grants": [("payroll.*", "company"), ("loans.*", "company"), ("employees.directory.view", "company"),
                ("employees.identity.view", "company"), ("employees.salary.*", "company"),
                ("employees.bank_accounts.*", "company"), ("employees.history.view", "company"),
                ("attendance.*.view", "company"), ("attendance.*.export", "company"), ("leaves.*.view", "company"),
                ("leaves.encashments.*", "company"), ("requests.loan.view", "company"),
                ("offboarding.end_of_employment.view", "company"), ("performance.increments.*", "company"),
                ("performance.appraisals.view", "company"), ("requests.expense.view", "company"),
                ("requests.air_ticket.view", "company"), ("inbox.notifications.view", "own")],
     "exclude": []},
    {"code": "finance", "name": "Finance",
     "description": "Verifies vouchers and reads payroll and budgets.",
     "grants": [("payroll.*.view", "company"), ("payroll.vouchers.verify", "company"),
                ("payroll.*.export", "company"), ("manpower.*.view", "company"), ("dashboard.ceo.view", "company"),
                ("inbox.notifications.view", "own")],
     "exclude": []},
    {"code": "department_head", "name": "Department Head",
     "description": "Reads, schedules and approves for their own department and its sub-departments.",
     "grants": [*_managing("department"), ("manpower.budget_approvals.*", "department"),
                ("manpower.e_budgeting.view", "department"), ("recruitment.openings.view", "department"),
                ("recruitment.applications.view", "department"), ("recruitment.dashboard.view", "department"),
                *SELF_SERVICE],
     "exclude": [], "no_sensitive": True,
     "sensitive_ok": ["payroll.vouchers.*", "manpower.budget_approvals.*", "manpower.e_budgeting.view"]},
    {"code": "line_manager", "name": "Line Manager",
     "description": "Reads, schedules and approves for their direct and indirect reports.",
     "grants": [*_managing("team"), *SELF_SERVICE], "exclude": [], "no_sensitive": True,
     "sensitive_ok": ["payroll.vouchers.*"]},
    {"code": "recruiter", "name": "Recruiter",
     "description": "Recruitment end to end, and the open positions it fills.",
     "grants": [("recruitment.*", "company"),
                ("manpower.open_positions.*", "company"), ("manpower.settings.position_titles.view", "company"),
                ("manpower.settings.budget_durations.view", "company"),
                ("manpower.settings.positions.view", "company"), ("employees.directory.view", "company"),
                ("inbox.notifications.view", "own")],
     "exclude": []},
    {"code": "executive", "name": "Executive",
     "description": "Dashboards and read-only views for the whole company.",
     "grants": [("dashboard.*", "company"), ("*.view", "company"), ("requests.approvals.approve", "company"),
                ("requests.approvals.reject", "company")], "exclude": [*ADMIN_AREAS, *SETTINGS],
     "no_sensitive": True},
    {"code": "employee", "name": "Employee",
     "description": "Their own records: time sheet, requests, leave, payslips, assets, benefits, projects.",
     "grants": SELF_SERVICE, "exclude": []},
]


def expanded() -> list[dict]:
    """The roles with patterns turned into concrete codes, for auth.usp_role_defaults_apply."""
    rows = catalogue_rows()
    sensitive = {r["code"] for r in rows if r["is_sensitive"]}
    out = []
    for role in ROLES:
        grants = {}
        for code in (r["code"] for r in rows):
            if any(fnmatchcase(code, p) for p in role["exclude"]):
                continue
            # Sensitive figures of other people stay out unless the role is meant to see them.
            own_only = (role.get("no_sensitive") and code in sensitive
                        and not any(fnmatchcase(code, p) for p in role.get("sensitive_ok", ())))
            for pattern, scope in role["grants"]:
                if fnmatchcase(code, pattern) and (scope == "own" or not own_only):
                    grants[code] = scope
                    break
        out.append({"code": role["code"], "name": role["name"], "description": role["description"],
                    "grants": [{"code": c, "scope": s} for c, s in grants.items()]})
    return out
