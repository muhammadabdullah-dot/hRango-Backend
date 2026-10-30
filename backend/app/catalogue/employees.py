"""Permission codes for employee records (Talent Management).

Salary, bank details and CNIC are separate, sensitive permissions from seeing the employee
(Mini SRS ACC-9), and so are personal details (phones, home address, date of birth, family): the
directory alone shows a colleague's work details. Deactivating an employee is the directory's delete action.

Profile tabs (comparison/12-employee-profile.md): each tab is a screen with view and edit (edit adds,
changes and removes its rows, like bank details). Identity documents (CNIC, passport, licence) also
need employees.identity, and pay letters employees.salary, for the same employee. Contracts state pay,
so they are sensitive. "Update Information" is a request the employee files and HR approves.
"""

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("employees.directory", "Employees", ("view", "create", "edit", "delete", "export"), False),
    ("employees.identity", "CNIC and identity details", ("view", "edit"), True),
    ("employees.personal", "Personal details (phones, home address, date of birth, family)", ("view",), True),
    ("employees.salary", "Salary", ("view", "edit"), True),
    ("employees.bank_accounts", "Bank details", ("view", "edit"), True),
    ("employees.history", "Employment history", ("view", "export"), False),
    ("employees.photo", "Profile photo", ("edit",), False),
    ("employees.emergency_contacts", "Emergency contacts", ("view", "edit"), False),
    ("employees.dependents", "Dependents", ("view", "edit"), False),
    ("employees.skills", "Skills", ("view", "edit"), False),
    ("employees.education", "Education and academic records", ("view", "edit"), False),
    ("employees.experience", "Professional experience", ("view", "edit"), False),
    ("employees.documents", "Documents", ("view", "edit"), False),
    ("employees.contracts", "Contracts", ("view", "edit"), True),
    ("employees.update_requests", "Update Information requests", ("view", "create", "cancel", "approve", "reject"),
     False),
]

EVENTS: list[tuple[str, str]] = [
    ("employees.created", "An employee was added (id, code, name, status, branch, department, joining date)."),
    ("employees.updated", "An employee's record changed: the main form, CNIC, photo, an approved Update Information "
                          "request, or a promotion / transfer taking effect or being cancelled (change says which)."),
    ("employees.deactivated", "An employee was switched off; their sign-in accounts were switched off with them."),
    ("employees.reactivated", "A switched-off employee was switched back on."),
    ("employees.profile_changed", "A profile tab row was added, changed or removed (tab, action, row id, "
                                  "and whether the employee did it themselves)."),
    ("employees.update_requested", "An employee asked for their personal details to be changed (Update Information)."),
    ("employees.update_decided", "An Update Information request was approved, rejected or cancelled."),
    ("employees.document_expiring", "An employee document expires within the notice period (type, expiry date)."),
]
