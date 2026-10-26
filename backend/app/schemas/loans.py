"""Bodies of the Loans module: loan & advance types and categories, loans and their installments."""
from datetime import date, datetime
from decimal import Decimal

from pydantic import Field

from app.schemas.common import ApiModel


class NamedRef(ApiModel):
    id: str
    name: str


class LoanTypeIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    is_active: bool = True
    guarantor_required: bool = False
    non_payable: bool = False
    min_experience_months: int = Field(ge=0)
    gap_between_requests_months: int | None = Field(None, ge=0)
    installments: int = Field(ge=1, le=600)
    gap_between_installments_months: int | None = Field(None, ge=0)
    formula_id: int | None = None
    deduction_pay_item_id: int | None = None
    # Employment Contract Type*: who may apply.
    employment_type_ids: list[int] = Field(min_length=1)
    description: str | None = Field(None, max_length=4000)
    row_version: str | None = None


class LoanTypeOut(ApiModel):
    id: str
    name: str
    is_active: bool
    guarantor_required: bool
    non_payable: bool
    min_experience_months: int
    gap_between_requests_months: int | None
    installments: int
    gap_between_installments_months: int | None
    formula_id: str | None
    formula_name: str | None
    deduction_pay_item_id: str | None
    deduction_pay_item_name: str | None
    description: str | None
    employment_types: list[NamedRef]
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class LoanCategoryIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    is_active: bool = True
    description: str | None = Field(None, max_length=4000)
    row_version: str | None = None


class LoanCategoryOut(ApiModel):
    id: str
    name: str
    is_active: bool
    description: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class LoanOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str
    employee_name: str | None
    department_name: str | None
    request_id: str | None
    request_code: str | None
    loan_type_id: str
    loan_type_name: str | None
    loan_category_id: str | None
    loan_category_name: str | None
    principal: Decimal
    installment_amount: Decimal | None
    installments: int | None
    gap_between_installments_months: int | None
    currency: str | None
    payment_method: str | None
    start_month: date | None
    status: str
    settled_at: datetime | None
    paid_amount: Decimal
    remaining_amount: Decimal
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class InstallmentOut(ApiModel):
    id: str
    loan_id: str
    installment_no: int
    due_month: date
    amount: Decimal
    paid_amount: Decimal | None
    payslip_id: str | None
    paid_at: datetime | None
    status: str | None
    # Repayment list only.
    employee_id: str | None = None
    employee_code: str | None = None
    employee_name: str | None = None
    loan_type_name: str | None = None


class GuarantorOut(ApiModel):
    id: str
    name: str
    cnic: str
    known_since: date
    relationship: str
    extension_no: str | None
    description: str | None
    file_id: str | None
    file_name: str | None = None
    # A signed download link that expires (FILE_LINK_MINUTES).
    file_url: str | None = None


class LoanDetailOut(LoanOut):
    schedule: list[InstallmentOut]
    guarantors: list[GuarantorOut]


class LoanSummaryOut(ApiModel):
    employee_id: str
    total_approved: Decimal
    total_repaid: Decimal
    total_remaining: Decimal
