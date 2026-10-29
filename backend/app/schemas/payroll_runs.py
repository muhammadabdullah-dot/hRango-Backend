"""Payroll run bodies: monthly and daily-wage payrolls, salary sheet, payslips."""
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel


class PayrollPayItemIn(ApiModel):
    pay_item_id: int
    is_taxable: bool = False
    arrear_applicable: bool = False
    final_settlement: bool = False
    calculate_only: bool = False


class PayrollPayItemOut(ApiModel):
    pay_item_id: str
    pay_item_name: str
    item_type: str
    system_code: str | None
    is_taxable: bool
    arrear_applicable: bool
    final_settlement: bool
    calculate_only: bool


class PayrollIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    payroll_month: date
    currency: str = Field(min_length=3, max_length=3)
    tax_structure_id: int
    tax_applicable: bool = True
    processing_mode: Literal["from_date", "month_end"]
    processing_date: date
    applicable_days: Literal["actual", "fixed"] = "actual"
    fixed_days: int | None = Field(None, ge=1, le=31)
    disbursement_bank_id: int
    description: str | None = Field(None, max_length=200)
    # Blank keeps the current list; on create, blank means every pay item of the company.
    pay_items: list[PayrollPayItemIn] | None = None
    row_version: str | None = None


class PayrollOut(ApiModel):
    id: str
    code: str
    name: str
    kind: str
    payroll_month: date | None
    work_date: date | None
    time_slot_id: str | None
    time_slot_name: str | None
    currency: str | None
    tax_structure_id: str | None
    tax_structure_name: str | None
    tax_applicable: bool
    processing_mode: str | None
    processing_date: date | None
    applicable_days: str | None
    fixed_days: int | None
    disbursement_bank_id: str | None
    disbursement_bank_name: str | None
    description: str | None
    status: str
    last_run_at: datetime | None
    closed_at: datetime | None
    closed_by_user_id: str | None
    employee_count: int
    payslip_count: int
    total_earnings: float
    total_deductions: float
    net_payable: float
    pay_items: list[PayrollPayItemOut] = []
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class CloseEmailSummaryOut(ApiModel):
    """What the close did about the e-mail. 'disabled': mail is not set up, nothing was sent."""
    status: Literal["none", "disabled", "queued", "sent", "failed"]
    sent_count: int
    failed_count: int


class PayrollClosedOut(PayrollOut):
    """POST /payrolls/{id}/close: the run, plus its close e-mail (null for daily wages)."""
    email: CloseEmailSummaryOut | None = None


class CloseEmailPreviewOut(ApiModel):
    enabled: bool
    subject: str
    body_html: str
    recipient_count: int


class CloseEmailFailureOut(ApiModel):
    employee_id: str
    employee_name: str | None
    error: str | None


class CloseEmailOut(ApiModel):
    """'none' until the run is closed."""
    status: Literal["none", "disabled", "queued", "sent", "failed"]
    queued_at: datetime | None
    sent_at: datetime | None
    recipient_count: int
    sent_count: int
    failed_count: int
    failures: list[CloseEmailFailureOut]


class BankFileFormatOut(ApiModel):
    code: str
    name: str
    extension: str


class EmployeeIdsIn(ApiModel):
    employee_ids: list[int] = Field(max_length=10000)


class EmployeeFilterIn(ApiModel):
    branch_id: int | None = None
    department_id: int | None = None
    designation_id: int | None = None
    grade_id: int | None = None
    location_id: int | None = None
    employee_group_id: int | None = None
    employment_type_id: int | None = None
    employee_status: str | None = None
    joined_from: date | None = None
    joined_to: date | None = None


class EmployeeCountOut(ApiModel):
    employee_count: int
    added: int | None = None
    skipped: int | None = None


class PayrollEmployeeOut(ApiModel):
    employee_id: str
    employee_code: str
    employee_name: str
    designation_name: str | None
    department_name: str | None
    branch_name: str | None
    employee_status: str | None
    joining_date: date | None
    payslip_id: str | None
    payslip_status: str | None
    net_payable: float | None


class RowVersionIn(ApiModel):
    row_version: str


class RunLogOut(ApiModel):
    id: str
    kind: str
    started_at: datetime | None
    finished_at: datetime | None
    status: str | None
    processed_count: int | None
    error_count: int | None
    run_by_user_id: str | None = None
    run_by_name: str | None = None


class RunErrorOut(ApiModel):
    id: str
    payroll_run_log_id: str
    employee_id: str | None
    employee_code: str | None
    employee_name: str | None
    message: str | None
    started_at: datetime | None


# --------------------------------------------------------------------------- daily wages

class DailyWageIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    work_date: date
    time_slot_id: int
    employee_ids: list[int] = Field(default_factory=list, max_length=10000)


class DailyWageRowIn(ApiModel):
    employee_id: int
    total_earnings: Decimal = Field(ge=0)
    total_deductions: Decimal = Field(Decimal(0), ge=0)


class DailyWageEditIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    rows: list[DailyWageRowIn] = Field(default_factory=list, max_length=10000)
    row_version: str


class DailyWageRowOut(ApiModel):
    __local_times__ = frozenset({'check_in', 'check_out'})  # wall-clock, no zone
    employee_id: str
    employee_code: str
    employee_name: str
    check_in: datetime | None
    check_out: datetime | None
    expected_minutes: int | None
    worked_minutes: int | None
    payslip_id: str | None
    wage: float | None
    total_earnings: float | None
    total_deductions: float | None
    net_payable: float | None
    payslip_status: str | None
    payment_method: str | None
    is_manually_updated: bool | None
    voucher_id: str | None
    voucher_no: str | None
    voucher_status: str | None


class DailyWageOut(PayrollOut):
    rows: list[DailyWageRowOut] = []


class CreatedOut(ApiModel):
    created: int


# --------------------------------------------------------------------------- salary sheet

class SheetItemOut(ApiModel):
    pay_item_id: str
    pay_item_name: str
    item_type: str
    amount: float


class SalarySheetRowOut(ApiModel):
    payslip_id: str
    payroll_id: str
    payroll_name: str
    employee_id: str
    employee_code: str
    employee_name: str
    payment_method: str | None
    status: str
    gross: float
    overtime: float
    tax: float
    leave_deduction: float
    short_deduction: float
    absent_deduction: float
    total_earnings: float
    total_reimbursements: float
    total_deductions: float
    net_payable: float
    items: list[SheetItemOut]


class SheetColumnOut(ApiModel):
    pay_item_id: str
    pay_item_name: str
    item_type: str


class SheetTotalsOut(ApiModel):
    gross: float
    overtime: float
    tax: float
    leave_deduction: float
    short_deduction: float
    absent_deduction: float
    total_earnings: float
    total_reimbursements: float
    total_deductions: float
    net_payable: float


class SalarySheetOut(ApiModel):
    rounding: str
    print_signature: bool
    columns: list[SheetColumnOut]
    rows: list[SalarySheetRowOut]
    totals: SheetTotalsOut


# --------------------------------------------------------------------------- payslips

class PayslipOut(ApiModel):
    id: str
    payroll_id: str | None
    payroll_code: str | None
    payroll_name: str | None
    payroll_kind: str | None
    payroll_status: str | None
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    branch_name: str | None
    payslip_month: date
    gross: float | None
    total_earnings: float | None
    total_deductions: float | None
    total_reimbursements: float | None
    net_payable: float | None
    tax_amount: float | None
    status: str
    payment_method: str | None
    released_at: datetime | None
    paid_at: datetime | None
    is_final_settlement: bool
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class PayslipLineOut(ApiModel):
    id: str
    pay_item_id: str
    pay_item_name: str
    pay_item_label: str | None
    item_type: str
    system_code: str | None
    amount: float
    employer_contribution: float | None
    is_taxable: bool
    is_manually_updated: bool
    is_display_only: bool
    calculate_only: bool


class PayslipDisplayOut(ApiModel):
    template: str
    color: str | None
    show_salary_breakdown: bool
    hide_attendance_summary: bool
    show_employee_pay_items: bool
    tax_positive_only: bool
    notes_english: str | None
    notes_other_language: str | None


class PayslipDetailOut(PayslipOut):
    designation_name: str | None
    job_title_name: str | None
    location_name: str | None
    joining_date: date | None
    bank_name: str | None
    account_number: str | None
    currency: str | None
    applicable_days: float | None
    worked_days: float | None
    worked_minutes: int | None
    expected_minutes: int | None
    leave_days: float | None
    absent_days: float | None
    overtime_minutes: int | None
    taxable_income: float | None
    is_manually_updated: bool
    lines: list[PayslipLineOut]
    display: PayslipDisplayOut


class PayslipLineIn(ApiModel):
    pay_item_id: int
    amount: Decimal
    employer_contribution: Decimal | None = None


class PayslipEditIn(ApiModel):
    lines: list[PayslipLineIn] = Field(min_length=1, max_length=200)
    row_version: str


class IdsIn(ApiModel):
    ids: list[int] = Field(min_length=1, max_length=5000)


class ChangedOut(ApiModel):
    changed: int
    errors: list[str] = []


class PayslipHistoryOut(ApiModel):
    id: str
    field_name: str | None
    old_value: str | None
    new_value: str | None
    action_name: str
    performed_at: datetime
    performed_by_user_id: str | None
    performed_by_name: str | None


class AccountBalanceOut(ApiModel):
    account_type_id: str
    account_name: str
    category: str
    credit: float
    debit: float
    balance: float


class AccountSummaryOut(ApiModel):
    employee_id: str
    employee_code: str
    employee_name: str
    outstanding_loan: float | None
    advances_paid: float | None
    accounts: list[AccountBalanceOut]
