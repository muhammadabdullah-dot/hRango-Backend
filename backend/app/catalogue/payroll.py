"""Permission codes for Payroll. Every screen that shows salary or payslip figures is sensitive (ACC-9).

Settings tabs are payroll.settings.<tab> (Payroll Manager gets them, nobody else by default). Running and
recalculating is `process`, closing a run or a final settlement is `close`, Finance verifies vouchers with
`verify`. Holding and releasing payslips, and editing their lines, is `edit`; marking them paid is `process`.
"""
from app.catalogue._actions import CRUD

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("payroll.dashboard", "Payroll dashboard", ("view",), True),
    ("payroll.settings.general", "Payroll settings: general and leave configuration", ("view", "edit"), False),
    ("payroll.settings.tax", "Payroll settings: tax structures and tax rebates", CRUD, True),
    ("payroll.settings.rewards", "Payroll settings: benefits and incentives", CRUD, False),
    ("payroll.settings.pay_components", "Payroll settings: pay items, formulas and rules", CRUD, False),
    ("payroll.settings.account_types", "Payroll settings: account types", CRUD, False),
    ("payroll.settings.disbursement_banks", "Payroll settings: disbursement banks", CRUD, True),
    ("payroll.payrolls", "Monthly payrolls", (*CRUD, "process", "close"), True),
    ("payroll.daily_wages", "Daily wages payrolls", (*CRUD, "process", "close"), True),
    ("payroll.salary_sheet", "Salary sheet", ("view", "export", "print"), True),
    ("payroll.payslips", "Pay slips", ("view", "edit", "process", "download", "print", "export"), True),
    ("payroll.vouchers", "Vouchers", (*CRUD, "approve", "reject", "verify"), True),
    ("payroll.final_settlement", "Final settlement", ("view", "process", "close", "export"), True),
    ("payroll.opening_balances", "Opening balances", (*CRUD, "import"), True),
    ("payroll.employee_accounts", "Employee accounts and account statement", (*CRUD, "import"), True),
    ("payroll.salary_revision", "Salary revision", (*CRUD, "import"), True),
    ("payroll.leave_encashment", "Leave encashment", CRUD, True),
    ("payroll.reports", "Payroll reports", ("view", "export"), True),
]

# Events this module publishes (core.usp_event_publish); webhooks subscribe to them.
EVENTS: list[tuple[str, str]] = [
    ("payroll.closed", "A monthly or daily-wage payroll was closed: totals and how many payslips were released. "
     "Each employee whose payslip was released is notified (notification.created)."),
    ("payroll.voucher_decided", "A voucher was approved, rejected or verified for payment; the employee is notified."),
    ("payroll.final_settlement_closed", "A final settlement was closed and its payslip released; the employee is "
     "notified."),
]
