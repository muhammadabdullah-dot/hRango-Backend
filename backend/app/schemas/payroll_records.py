"""Bodies for vouchers, final settlement, balances, salary revision and leave encashment."""
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import Field, model_validator

from app.schemas.common import ApiModel
from app.schemas.files import FileRef


class ImportResultOut(ApiModel):
    created: int
    errors: list[str]


# --------------------------------------------------------------------------- vouchers

class VoucherIn(ApiModel):
    employee_id: int
    voucher_no: str | None = Field(None, max_length=30)
    voucher_type: Literal["expense_reimbursement", "salary_advance", "bonus", "travel_allowance"]
    voucher_date: date
    currency: str | None = Field(None, min_length=3, max_length=3)
    amount: Decimal = Field(gt=0)
    payment_method: Literal["bank_transfer", "cash", "cheque", "pay_order"]
    purpose: str = Field(min_length=1, max_length=500)
    notes: str | None = Field(None, max_length=2000)
    # An uploaded file (POST /api/files): its id.
    file_id: int | None = None
    requested_by_id: int | None = None
    row_version: str | None = None


class VoucherDecisionIn(ApiModel):
    remarks: str | None = Field(None, max_length=2000)
    row_version: str


class VoucherOut(ApiModel):
    id: str
    voucher_no: str
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    designation_name: str | None
    voucher_type: str
    voucher_date: date
    currency: str | None
    amount: float
    payment_method: str | None
    purpose: str | None
    notes: str | None
    file_id: str | None
    # The attachment: id, name and a signed download link (expires).
    file: FileRef | None = None
    payroll_id: str | None
    payroll_name: str | None
    requested_by_id: str | None
    requested_by_name: str | None
    approved_by_id: str | None
    # The account that approved or rejected (kept when it has no employee record); the name falls back to
    # the account's display name.
    approved_by_user_id: str | None = None
    approved_by_name: str | None
    approved_at: datetime | None
    verified_by_id: str | None
    verified_by_user_id: str | None = None
    verified_by_name: str | None
    verified_at: datetime | None
    remarks: str | None
    status: str
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# --------------------------------------------------------------------------- final settlement

class FinalSettlementOut(ApiModel):
    id: str  # the end-of-employment record
    final_settlement_id: str | None
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    branch_name: str | None
    reason: str | None
    resignation_date: datetime | None
    last_working_date: date
    description: str | None
    status: str
    payslip_id: str | None
    total_earnings: float | None
    total_deductions: float | None
    net_payable: float | None
    closed_at: datetime | None
    # The signed settlement letter given on Close FS.
    file_id: str | None = None
    file: FileRef | None = None
    row_version: str | None


class FinalSettlementCloseIn(ApiModel):
    row_version: str
    # Optional: the signed settlement letter, uploaded first (POST /api/files, module payroll).
    file_id: int | None = None


# --------------------------------------------------------------------------- opening balances, employee accounts

class OpeningBalanceIn(ApiModel):
    employee_id: int
    balance_month: date
    pay_item_id: int
    amount: Decimal
    is_taxable: bool = False
    kind: Literal["opening", "adjustment"] = "opening"
    description: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class OpeningBalanceOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str | None = None
    employee_name: str | None = None
    balance_month: date
    pay_item_id: str
    pay_item_name: str
    item_type: str
    amount: float
    is_taxable: bool
    kind: str
    description: str | None
    is_locked: bool
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class OpeningBalanceSummaryOut(ApiModel):
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    net_amount: float
    entry_count: int
    last_month: date | None


class EmployeeCardOut(ApiModel):
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None = None
    job_title_name: str | None = None
    location_name: str | None = None
    branch_name: str | None = None


class OpeningBalanceEmployeeOut(EmployeeCardOut):
    entries: list[OpeningBalanceOut]


class _ImportIn(ApiModel):
    """Either `rows` (read from the sheet by the client) or `fileId`: an uploaded CSV whose first line names the
    columns (Employee Code, Pay Item, ... or employeeCode, payItem, ...)."""

    file_id: int | None = None

    @model_validator(mode="after")
    def _one_source(self):
        if (self.file_id is None) == (not self.rows):
            raise ValueError("Send either rows or fileId (an uploaded CSV file).")
        return self


class OpeningBalanceImportRow(ApiModel):
    employee_code: str = Field(max_length=30)
    pay_item: str = Field(max_length=200)
    month: str = Field(max_length=20)
    amount: Decimal
    taxable: bool = False
    description: str | None = Field(None, max_length=2000)


class OpeningBalanceImportIn(_ImportIn):
    rows: list[OpeningBalanceImportRow] = Field(default_factory=list, max_length=5000)


class AccountEntryIn(ApiModel):
    employee_id: int
    account_type_id: int
    entry_month: date
    direction: Literal["credit", "debit"]
    amount: Decimal = Field(gt=0)
    is_processed: bool = False
    description: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class AccountEntryOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str
    employee_name: str
    account_type_id: str
    account_name: str
    account_category: str
    entry_month: date
    credit: float
    debit: float
    is_processed: bool
    payslip_id: str | None
    pay_rule_id: str | None
    pay_rule_name: str | None
    description: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class AccountImportRow(ApiModel):
    employee_code: str = Field(max_length=30)
    account: str = Field(max_length=200)
    month: str = Field(max_length=20)
    credit: Decimal = Field(Decimal(0), ge=0)
    debit: Decimal = Field(Decimal(0), ge=0)
    description: str | None = Field(None, max_length=2000)


class AccountImportIn(_ImportIn):
    rows: list[AccountImportRow] = Field(default_factory=list, max_length=5000)


class StatementRowOut(ApiModel):
    id: str
    employee_id: str
    employee_name: str
    account_type_id: str
    account_name: str
    entry_month: date
    credit: float
    debit: float
    is_processed: bool
    description: str | None
    balance: float


# --------------------------------------------------------------------------- salary revision

class SalaryRevisionIn(ApiModel):
    employee_id: int
    effective_date: date
    change_type: Literal["flat", "percent"]
    change_value: Decimal
    row_version: str | None = None


class SalaryRevisionOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str
    employee_name: str
    effective_date: date
    previous_amount: float | None
    amount: float
    change_type: str | None
    change_value: float | None
    source: str | None
    can_edit: bool
    department_name: str | None = None
    location_name: str | None = None
    branch_name: str | None = None
    job_title_name: str | None = None
    joining_date: date | None = None
    # The last e-mail of the revision letter; 'disabled': asked while mail is not set up.
    email_status: Literal["none", "queued", "sent", "failed", "disabled"] = "none"
    emailed_at: datetime | None = None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class SalaryRevisionEmailPreviewOut(ApiModel):
    subject: str
    body_html: str
    # The address it goes to; empty when the person has none.
    to: str


class SalaryRevisionEmailOut(ApiModel):
    status: Literal["queued", "sent", "failed", "disabled"]
    sent_at: datetime | None


class CurrentSalaryOut(ApiModel):
    employee_id: str
    employee_code: str
    employee_name: str
    department_name: str | None
    job_title_name: str | None
    joining_date: date | None
    salary: float | None
    effective_date: date | None


class SalaryImportRow(ApiModel):
    employee_code: str = Field(max_length=30)
    effective_date: date
    salary: Decimal = Field(gt=0)


class SalaryImportIn(_ImportIn):
    rows: list[SalaryImportRow] = Field(default_factory=list, max_length=5000)


# --------------------------------------------------------------------------- leave encashment

class LeaveEncashmentIn(ApiModel):
    leave_type_id: int
    fiscal_year: int = Field(ge=2000, le=2100)
    all_employees: bool = False
    employee_ids: list[int] = Field(default_factory=list, max_length=10000)
    mode: Literal["payroll", "manual"]
    basis: Literal["overtime", "earned_salary", "per_hour_rate", "overnight"]
    amount_per_leave: Decimal | None = Field(None, gt=0)
    row_version: str | None = None


class LeaveEncashmentPreviewIn(ApiModel):
    leave_type_id: int
    fiscal_year: int = Field(ge=2000, le=2100)
    all_employees: bool = False
    employee_ids: list[int] = Field(default_factory=list, max_length=10000)
    basis: Literal["overtime", "earned_salary", "per_hour_rate", "overnight"]
    amount_per_leave: Decimal | None = Field(None, gt=0)
    # The encashment being edited (its own days are given back); blank for a new one.
    id: int | None = None


class LeaveEncashmentPreviewOut(ApiModel):
    employee_id: str
    employee_name: str | None
    available_days: float
    encashable_days: float
    # 'min': below the type's minimum, left out; 'max': paid for the maximum only.
    capped_by: Literal["min", "max"] | None
    amount: float


class LeaveEncashmentRowOut(ApiModel):
    id: str
    leave_encashment_id: str | None = None
    leave_type_id: str | None = None
    leave_type_name: str | None = None
    employee_id: str
    employee_code: str
    employee_name: str
    fiscal_year: int | None = None
    encashment_date: date | None = None
    basis: str | None = None
    mode: str | None = None
    amount_per_leave: float
    days: float
    amount: float
    payslip_id: str | None
    is_paid: bool | None = None
    row_version: str | None = None


class LeaveEncashmentOut(ApiModel):
    id: str
    leave_type_id: str
    leave_type_name: str
    fiscal_year: int
    encashment_date: date
    applies_to_all: bool
    basis: str
    amount_per_leave: float
    mode: str
    total_days: float | None
    total_amount: float | None
    is_paid: bool
    employees: list[LeaveEncashmentRowOut]
    created_at: datetime
    updated_at: datetime | None
    row_version: str
