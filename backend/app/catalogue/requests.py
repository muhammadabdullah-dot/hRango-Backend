"""Permission codes and events for the Requests module: one screen per request type, the Approvals
screen and Request Settings.

Staff file and withdraw their own requests with create / cancel (own scope); HR files for others
with a wider scope ("All Requests"). Who may decide a request comes from its approval flow and
delegations, not from a permission (Mini SRS ACC-13): requests.approvals.* only opens the
Approvals screen and its buttons. Request type codes are listed in comparison/04-requests.md.
"""

# Request types with screens, in the order of the Requests menu. Promotion carries salary figures
# and Loan & Advances loan figures, so both are sensitive (ACC-9).
REQUEST_TYPES: list[tuple[str, str, bool]] = [
    ("punch", "Punch requests", False),
    ("expense", "Expense claims", False),
    ("leave", "Leave requests", False),
    ("shift_swap", "Shift requests", False),
    ("loan", "Loan & advance requests", True),
    ("work_from_home", "Work from home requests", False),
    ("official_visit", "Official visit requests", False),
    ("promotion", "Promotion requests", True),
    ("relaxation", "Relaxation requests", False),
    ("rest_day", "Rest day requests", False),
    ("travel", "Travel requests", False),
    ("air_ticket", "Air ticket claims", False),
    ("transfer", "Transfer requests", False),
    ("resignation", "Resignation requests", False),
    ("overtime", "Overtime requests", False),
    ("requisition", "Requisitions", False),
]

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    *[(f"requests.{code}", label, ("view", "create", "cancel", "export"), sensitive)
      for code, label, sensitive in REQUEST_TYPES],
    ("requests.approvals", "Request approvals", ("view", "approve", "reject", "cancel"), False),
    ("requests.settings.restrictions", "Request settings: Restrictions", ("view", "create", "edit", "delete"), False),
    ("requests.settings.delegations", "Request settings: Delegations", ("view", "create", "edit", "delete"), False),
    ("requests.settings.flows", "Request settings: Request flows", ("view", "create", "edit", "delete"), False),
    ("requests.settings.authorities", "Request settings: Authorities", ("view", "create", "edit", "delete"), False),
    ("requests.settings.expense_categories", "Request settings: Expense categories",
     ("view", "create", "edit", "delete"), False),
    ("requests.settings.reimbursement", "Request settings: Reimbursement pay items", ("view", "edit"), False),
]

# Published by the request engine (req.usp_request_publish) in the same transaction as the change.
# Payload: requestId, code, type, typeName, kind, action, status, employeeId, employeeCode,
# employeeName, departmentId, branchId, fromDate, toDate, days, amount, submittedAt, decidedAt,
# actorUserId, actorEmployeeId, remarks, currentStep {stepId, purpose, stepNo, approverKind,
# approverId, approverName, approverRoleId, isConsent} (the step waiting now, if any).
EVENTS: list[tuple[str, str]] = [
    ("requests.submitted", "A request was submitted and waits at its first step."),
    ("requests.step_decided", "An approver approved, consented or disagreed at a step; the request moved on to the "
                              "next step (action: approved, consented, disagreed)."),
    ("requests.forwarded", "An approver forwarded the current step to another employee."),
    ("requests.approved", "A request was finally approved and its effect applied (leave booked, claim passed to "
                          "payroll ...)."),
    ("requests.rejected", "A request was rejected."),
    ("requests.cancellation_requested", "Cancelling an approved request was asked for; the cancellation flow started."),
    ("requests.cancellation_rejected", "The cancellation of an approved request was rejected; it stays approved."),
    ("requests.cancelled", "A request was cancelled (action: withdrawn, deleted, cancellation_approved); an approved "
                           "request's effect was reverted."),
]
