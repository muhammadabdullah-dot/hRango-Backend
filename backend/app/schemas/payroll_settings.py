"""Payroll Settings bodies: general options, tax, rewards, pay components, account types, banks."""
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel
from app.schemas.files import FileRef

Rounding = Literal["floor", "ceil", "round", "actual"]


class PayrollSettings(ApiModel):
    """The 22 payroll options and the leave configuration (Payroll Settings -> General)."""
    exclude_final_settlement: bool = False
    disable_tax_distribution_on_final_settlement: bool = False
    hide_payslip_after_run: bool = False
    salary_report_rounding: Literal["none", "round_off", "ceil", "floor"] = "none"
    revision_on_fixed_days: bool = False
    revision_fixed_date: str | None = Field(None, pattern=r"^(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$")  # MM-DD
    revision_on_shift_days: bool = False
    revision_shift_days: int | None = Field(None, ge=1, le=3650)
    disable_revision_email: bool = False
    cutoff_proration: bool = False
    cutoff_day: int | None = Field(None, ge=1, le=28)
    hide_attendance_summary: bool = False
    show_salary_breakdown: bool = True
    payslip_color: str | None = Field(None, max_length=30)
    tax_rounding: Rounding = "actual"
    tax_positive_only: bool = False
    notes_english_enabled: bool = False
    notes_english: str | None = Field(None, max_length=1000)
    notes_other_language: str | None = Field(None, max_length=1000)
    print_signature: bool = False
    send_close_email: bool = False
    payslip_template: Literal["default", "template_1", "template_2", "template_3"] = "default"
    proration_rounding: Rounding = "actual"
    show_on_hold_amounts: bool = False
    use_shift_hours: bool = False
    show_employee_pay_items: bool = True
    # Leave configuration
    cpl_leave_type_id: str | None = None
    max_earned_cpl: Decimal | None = Field(None, ge=0)
    deduct_casual_leaves: bool = False
    deduct_sick_leaves: bool = False
    leave_year_basis: Literal["calendar", "fiscal"] = "calendar"
    fiscal_year_start_month: int | None = Field(None, ge=1, le=12)
    fiscal_year_end_month: int | None = Field(None, ge=1, le=12)


class PayrollSettingsIn(PayrollSettings):
    row_version: str | None = None


class PayrollSettingsOut(PayrollSettings):
    row_version: str | None = None


class VariableOut(ApiModel):
    name: str
    reference: str
    kind: str
    description: str | None


class ExpressionCheckIn(ApiModel):
    expression: str = Field(min_length=1, max_length=2000)
    kind: Literal["value", "condition"] = "value"


class ExpressionCheckOut(ApiModel):
    valid: bool
    message: str | None
    references: list[str]


# --------------------------------------------------------------------------- tax

class TaxSlab(ApiModel):
    min_amount: Decimal = Field(ge=0)
    max_amount: Decimal | None = Field(None, ge=0)
    fixed_amount: Decimal = Field(Decimal(0), ge=0)
    percentage: Decimal = Field(Decimal(0), ge=0, le=100)


class TaxSlabOut(ApiModel):
    id: str
    min_amount: float
    max_amount: float | None
    fixed_amount: float
    percentage: float


class TaxStructureIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    start_date: date
    end_date: date
    surcharge_type: Literal["flat", "percentage"] | None = None
    surcharge_value: Decimal | None = Field(None, ge=0)
    description: str | None = Field(None, max_length=2000)
    slabs: list[TaxSlab] = Field(min_length=1, max_length=50)
    row_version: str | None = None


class TaxStructureOut(ApiModel):
    id: str
    code: str
    name: str
    start_date: date
    end_date: date
    surcharge_type: str | None
    surcharge_value: float | None
    description: str | None
    slab_count: int
    slabs: list[TaxSlabOut] = []
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class TaxRebateIn(ApiModel):
    employee_id: int
    rebate_date: date
    amount: Decimal = Field(gt=0)
    # An uploaded file (POST /api/files): its id.
    file_id: int | None = None
    description: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class TaxRebateOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str
    employee_name: str
    rebate_date: date
    amount: float
    file_id: str | None
    # The attachment: id, name and a signed download link (expires).
    file: FileRef | None = None
    description: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# --------------------------------------------------------------------------- pay components

class FormulaIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    expression: str = Field(min_length=1, max_length=2000)
    is_salary_division: bool = False
    for_integration: bool = False
    description: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class FormulaOut(ApiModel):
    id: str
    name: str
    reference: str
    expression: str
    is_salary_division: bool
    for_integration: bool
    is_custom: bool
    description: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class PayItemIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    label: str | None = Field(None, max_length=200)
    item_type: Literal["earning", "deduction", "reimbursement", "employee_data", "other"]
    calculation_type: Literal["fixed", "manual", "formula"]
    tax_distribution: Literal["current_month", "remaining_months"]
    employee_formula_id: int | None = None
    employer_formula_id: int | None = None
    is_taxable: bool = False
    is_display_only: bool = False
    is_benefit: bool = False
    is_advance_payment: bool = False
    eligibility_expression: str | None = Field(None, max_length=2000)
    description: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class PayItemOut(ApiModel):
    id: str
    name: str
    reference: str
    label: str | None
    item_type: str
    calculation_type: str
    tax_distribution: str
    employee_formula_id: str | None
    employee_formula_name: str | None
    expression: str | None
    employer_formula_id: str | None
    employer_formula_name: str | None
    employer_expression: str | None
    is_taxable: bool
    is_display_only: bool
    is_benefit: bool
    is_advance_payment: bool
    eligibility_expression: str | None
    system_code: str | None
    description: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class PayRuleIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    expression: str = Field(min_length=1, max_length=2000)
    account_type_id: int
    description: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class PayRuleOut(ApiModel):
    id: str
    name: str
    expression: str
    account_type_id: str
    account_type_name: str
    account_category: str
    description: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class AccountTypeIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    category: Literal["benefit", "leave_quota", "custom_pay_item"]
    ref_id: int | None = None
    row_version: str | None = None


class AccountTypeOut(ApiModel):
    id: str
    code: str
    name: str
    category: str
    ref_id: str | None
    ref_name: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# --------------------------------------------------------------------------- rewards

class BenefitMember(ApiModel):
    employee_id: int | None = None
    employee_group_id: int | None = None


class BenefitMemberOut(ApiModel):
    id: str
    employee_id: str | None
    employee_name: str | None
    employee_group_id: str | None
    employee_group_name: str | None


class BenefitField(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    field_type: Literal["string", "number", "date", "boolean"]
    is_required: bool = False
    min_value: Decimal | None = None
    max_value: Decimal | None = None
    min_length: int | None = Field(None, ge=0)
    max_length: int | None = Field(None, ge=0)
    field_value: str | None = Field(None, max_length=2000)


class BenefitFieldOut(ApiModel):
    id: str
    name: str
    field_type: str
    is_required: bool
    min_value: float | None
    max_value: float | None
    min_length: int | None
    max_length: int | None
    field_value: str | None


class BenefitIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    benefit_type: Literal["allowance", "bonus", "reward", "other"]
    pay_item_id: int
    formula_id: int | None = None
    is_group: bool = False
    is_accumulative: bool = False
    description: str | None = Field(None, max_length=2000)
    members: list[BenefitMember] = Field(default_factory=list, max_length=5000)
    fields: list[BenefitField] = Field(default_factory=list, max_length=50)
    row_version: str | None = None


class BenefitOut(ApiModel):
    id: str
    name: str
    benefit_type: str
    pay_item_id: str
    pay_item_name: str
    formula_id: str | None
    formula_name: str | None
    is_group: bool
    is_accumulative: bool
    description: str | None
    member_count: int
    members: list[BenefitMemberOut] = []
    fields: list[BenefitFieldOut] = []
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class IncentiveIn(ApiModel):
    branch_id: int
    applicable_month: date
    incentive_type: Literal["reimbursement", "part_of_salary"]
    target_amount: Decimal = Field(ge=0)
    value_type: Literal["flat", "percentage"]
    reward_value: Decimal = Field(ge=0)
    description: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class IncentiveOut(ApiModel):
    id: str
    branch_id: str
    branch_name: str
    applicable_month: date
    incentive_type: str
    target_amount: float
    value_type: str
    reward_value: float
    description: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class BankIn(ApiModel):
    account_holder: str = Field(min_length=1, max_length=200)
    account_number: str = Field(min_length=1, max_length=50)
    bank_name: str = Field(min_length=1, max_length=200)
    branch_name: str | None = Field(None, max_length=200)
    branch_code: str = Field(min_length=1, max_length=30)
    branch_location: str = Field(min_length=1, max_length=200)
    tax_payer_id: str = Field(min_length=1, max_length=30)
    effective_date: date | None = None
    description: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class BankOut(ApiModel):
    id: str
    account_holder: str
    account_number: str
    bank_name: str
    branch_name: str | None
    branch_code: str
    branch_location: str
    tax_payer_id: str
    effective_date: date | None
    description: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str
