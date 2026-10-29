from datetime import date, datetime
from decimal import Decimal
from typing import Any, Literal

from pydantic import Field

from app.schemas.common import ApiModel
from app.schemas.files import FileRef

Gender = Literal["male", "female", "other"]
MaritalStatus = Literal["single", "married", "divorced", "widowed"]
# left and inactive are reached through separation and switch-off, not the form; the procedure
# accepts them only when the employee already has that status.
Status = Literal["active", "probation", "notice", "left", "inactive"]
SalaryFrequency = Literal["monthly", "daily", "hourly"]


class EmployeeIn(ApiModel):
    # Left blank on a new employee: generated from the branch (or location) prefix, e.g. LHR-0007.
    code: str | None = Field(None, max_length=30)
    first_name: str = Field(min_length=1, max_length=200)
    last_name: str = Field(min_length=1, max_length=200)
    parent_name: str | None = Field(None, max_length=200)
    gender: Gender | None = None
    marital_status: MaritalStatus | None = None
    religion: str | None = Field(None, max_length=50)
    nationality: str | None = Field(None, max_length=50)
    date_of_birth: date | None = None
    # New employees only, and only with employees.identity.edit; afterwards PUT /employees/{id}/identity.
    cnic: str | None = Field(None, max_length=20)
    email: str | None = Field(None, max_length=254, pattern=r"^$|^[^@\s]+@[^@\s]+\.[^@\s]+$")
    phone_1: str | None = Field(None, max_length=30, pattern=r"^[+\d\s()-]*$")
    phone_2: str | None = Field(None, max_length=30, pattern=r"^[+\d\s()-]*$")
    home_address: str | None = Field(None, max_length=500)
    home_city_id: int | None = None
    branch_id: int
    location_id: int | None = None
    area_id: int | None = None
    department_id: int | None = None
    division_id: int | None = None
    cost_center_id: int | None = None
    designation_id: int | None = None
    job_title_id: int | None = None
    grade_id: int | None = None
    job_level_id: int | None = None
    employee_group_id: int | None = None
    employment_type_id: int | None = None
    line_manager_id: int | None = None
    final_authority_id: int | None = None
    status: Status = "active"
    salary_frequency: SalaryFrequency = "monthly"
    # New employees: their first employment period. Later periods: /employees/{id}/employment-periods.
    joining_date: date | None = None
    probation_end_date: date | None = None
    confirmation_date: date | None = None
    row_version: str | None = None


class GenderCountsOut(ApiModel):
    male: int
    female: int
    other: int
    # No gender recorded.
    unspecified: int = 0


class StatusCountsOut(ApiModel):
    active: int
    probation: int
    notice: int
    left: int
    inactive: int


class EmployeeSummaryOut(ApiModel):
    """GET /employees/summary: the directory's tiles over the same people and filters as the list."""
    total: int
    by_gender: GenderCountsOut
    by_status: StatusCountsOut


class EmployeeOut(ApiModel):
    id: str
    code: str
    first_name: str
    last_name: str
    name: str
    parent_name: str | None
    gender: str | None
    marital_status: str | None
    religion: str | None
    nationality: str | None
    date_of_birth: date | None
    # Present only for holders of employees.identity.view (canSeeIdentity).
    cnic: str | None
    can_see_identity: bool
    email: str | None
    phone_1: str | None
    phone_2: str | None
    home_address: str | None
    home_city_id: str | None
    home_city_name: str | None
    # Profile photo: the file id and a signed link that expires (null without a photo).
    photo_file_id: str | None
    photo_url: str | None
    branch_id: str
    branch_name: str
    location_id: str | None
    location_name: str | None
    area_id: str | None
    area_name: str | None
    department_id: str | None
    department_name: str | None
    division_id: str | None
    division_name: str | None
    cost_center_id: str | None
    cost_center_name: str | None
    designation_id: str | None
    designation_name: str | None
    job_title_id: str | None
    job_title_name: str | None
    grade_id: str | None
    grade_name: str | None
    job_level_id: str | None
    job_level_name: str | None
    employee_group_id: str | None
    employee_group_name: str | None
    employment_type_id: str | None
    employment_type_name: str | None
    line_manager_id: str | None
    line_manager_name: str | None
    final_authority_id: str | None
    final_authority_name: str | None
    status: str
    salary_frequency: str | None
    joining_date: date | None
    confirmation_date: date | None
    probation_end_date: date | None
    end_date: date | None
    # Whole months in the current employment period (Personal tab "Tenure").
    tenure_months: int | None
    # The primary emergency contact (Personal tab "Emergency Contact #").
    emergency_contact_name: str | None
    emergency_contact_phone: str | None
    direct_report_count: int
    user_account_id: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class EmployeeLookupOut(ApiModel):
    id: str
    code: str
    name: str
    designation_name: str | None
    job_title_name: str | None
    department_id: str | None = None
    department_name: str | None
    branch_id: str | None = None
    branch_name: str
    status: str
    photo_url: str | None = None


class IdentityIn(ApiModel):
    cnic: str | None = Field(None, max_length=20)
    row_version: str


class RowVersionIn(ApiModel):
    row_version: str


class EmploymentPeriodIn(ApiModel):
    joining_date: date
    confirmation_date: date | None = None
    probation_end_date: date | None = None
    end_date: date | None = None
    row_version: str | None = None


class EmploymentPeriodOut(ApiModel):
    id: str
    employee_id: str
    joining_date: date
    confirmation_date: date | None
    probation_end_date: date | None
    end_date: date | None
    end_of_employment_id: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class HistoryOut(ApiModel):
    id: str
    employee_id: str
    change_type: str
    effective_date: date
    location_id: str | None
    location_name: str | None
    branch_id: str | None
    branch_name: str | None
    department_id: str | None
    department_name: str | None
    designation_id: str | None
    designation_name: str | None
    job_title_id: str | None
    job_title_name: str | None
    grade_id: str | None
    grade_name: str | None
    job_level_id: str | None
    job_level_name: str | None
    line_manager_id: str | None
    line_manager_name: str | None
    final_authority_id: str | None
    final_authority_name: str | None
    source_request_id: str | None
    is_reverted: bool
    created_at: datetime
    created_by_name: str | None


class ChangeOut(ApiModel):
    id: str
    field_name: str | None
    old_value: str | None
    new_value: str | None
    action_name: str | None
    performed_at: datetime | None
    performed_by_user_id: str | None
    performed_by_name: str | None


class SalaryIn(ApiModel):
    effective_date: date
    amount: Decimal = Field(ge=0, max_digits=18, decimal_places=2)
    change_type: Literal["flat", "percent"] | None = None
    change_value: Decimal | None = Field(None, max_digits=18, decimal_places=2)
    source: Literal["joining", "revision", "import"] = "revision"
    remarks: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class SalaryOut(ApiModel):
    id: str
    employee_id: str
    effective_date: date
    amount: Decimal
    previous_amount: Decimal | None
    change_type: str | None
    change_value: Decimal | None
    source: str | None
    source_request_id: str | None
    remarks: str | None
    is_current: bool
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class BankAccountIn(ApiModel):
    account_holder: str | None = Field(None, max_length=200)
    account_number: str = Field(min_length=1, max_length=50)
    bank_name: str = Field(min_length=1, max_length=200)
    branch_name: str | None = Field(None, max_length=200)
    branch_code: str | None = Field(None, max_length=30)
    tax_payer_id: str | None = Field(None, max_length=30)
    is_primary: bool = False
    row_version: str | None = None


class BankAccountOut(ApiModel):
    id: str
    employee_id: str
    account_holder: str | None
    account_number: str
    bank_name: str
    branch_name: str | None
    branch_code: str | None
    tax_payer_id: str | None
    is_primary: bool
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- profile tabs (comparison/12-employee-profile.md)

class PhotoIn(ApiModel):
    """Sets the profile photo to an uploaded image (POST /api/files first); null removes it."""
    file_id: int | None = None
    row_version: str


class EmergencyContactIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    relation: Literal["spouse", "father", "mother", "brother", "sister", "son", "daughter", "friend", "relative",
                      "other"]
    phone: str = Field(min_length=1, max_length=30, pattern=r"^[+\d\s()-]*$")
    alt_phone: str | None = Field(None, max_length=30, pattern=r"^[+\d\s()-]*$")
    address: str | None = Field(None, max_length=500)
    is_primary: bool = False
    row_version: str | None = None


class EmergencyContactOut(ApiModel):
    id: str
    employee_id: str
    name: str
    relation: str
    phone: str
    alt_phone: str | None
    address: str | None
    is_primary: bool
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class DependentIn(ApiModel):
    first_name: str = Field(min_length=1, max_length=200)
    last_name: str | None = Field(None, max_length=200)
    relation: Literal["spouse", "son", "daughter", "father", "mother", "brother", "sister", "other"]
    occupation: str | None = Field(None, max_length=200)
    date_of_birth: date | None = None
    row_version: str | None = None


class DependentOut(ApiModel):
    id: str
    employee_id: str
    first_name: str
    last_name: str | None
    name: str
    relation: str
    occupation: str | None
    date_of_birth: date | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class SkillIn(ApiModel):
    skill_title: str = Field(min_length=1, max_length=200)
    skill_level: Literal["beginner", "intermediate", "advanced", "expert"]
    row_version: str | None = None


class SkillOut(ApiModel):
    id: str
    employee_id: str
    skill_title: str
    skill_level: str
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class EducationIn(ApiModel):
    """Add Academic: Academic Title, Institute, From / To, In Process, and the degree's file id."""
    title: str = Field(min_length=1, max_length=200)
    institute: str = Field(min_length=1, max_length=200)
    from_date: date | None = None
    to_date: date | None = None
    is_in_process: bool = False
    file_id: int | None = None
    row_version: str | None = None


class EducationOut(ApiModel):
    id: str
    employee_id: str
    title: str
    institute: str
    from_date: date | None
    to_date: date | None
    is_in_process: bool
    file: FileRef | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class ExperienceIn(ApiModel):
    """Add Professional Experience: Company Name, Job Title, From / To (no To = the current job)."""
    company_name: str = Field(min_length=1, max_length=200)
    job_title: str = Field(min_length=1, max_length=100)
    from_date: date
    to_date: date | None = None
    row_version: str | None = None


class ExperienceOut(ApiModel):
    id: str
    employee_id: str
    company_name: str
    job_title: str
    from_date: date
    to_date: date | None
    is_current: bool
    months: int | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class ContractIn(ApiModel):
    """Add Contract: Contract Type, Duration in Months (leave it empty and give To for Custom), From / To,
    attachment."""
    contract_type: Literal["permanent", "temporary", "contractual", "probation", "internship", "consultant"]
    duration_months: int | None = Field(None, ge=1, le=600)
    from_date: date
    to_date: date | None = None
    file_id: int | None = None
    remarks: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class ContractOut(ApiModel):
    id: str
    employee_id: str
    contract_type: str
    duration_months: int | None
    from_date: date
    to_date: date | None
    status: Literal["upcoming", "active", "expired"]
    file: FileRef | None
    remarks: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class DocumentIn(ApiModel):
    # Identity documents (cnic, passport, driving_licence) also need employees.identity.view for the employee;
    # pay letters (offer, promotion, appraisal, salary certificate) employees.salary.view.
    document_type: Literal["cnic", "passport", "driving_licence", "offer_letter", "promotion_letter",
                           "appraisal_letter", "salary_certificate", "experience_letter", "degree", "certificate",
                           "medical", "other"]
    title: str | None = Field(None, max_length=200)
    document_number: str | None = Field(None, max_length=100)
    issue_date: date | None = None
    expiry_date: date | None = None
    file_id: int
    remarks: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class DocumentOut(ApiModel):
    id: str
    employee_id: str
    document_type: str
    category: Literal["identity", "pay", "general"]
    title: str | None
    document_number: str | None
    issue_date: date | None
    expiry_date: date | None
    is_expired: bool
    file: FileRef
    file_mime_type: str | None
    file_size_bytes: int | None
    remarks: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- Update Information requests

class UpdateChangesIn(ApiModel):
    """Only the fields sent are asked for; send null to ask for a value to be cleared."""
    date_of_birth: date | None = None
    marital_status: MaritalStatus | None = None
    phone_1: str | None = Field(None, max_length=30, pattern=r"^[+\d\s()-]*$")
    phone_2: str | None = Field(None, max_length=30, pattern=r"^[+\d\s()-]*$")
    home_address: str | None = Field(None, max_length=500)
    home_city_id: int | None = None


class UpdateRequestIn(ApiModel):
    changes: UpdateChangesIn
    remarks: str | None = Field(None, max_length=2000)


class DecisionIn(ApiModel):
    remarks: str | None = Field(None, max_length=2000)
    row_version: str


class UpdateRequestOut(ApiModel):
    id: str
    employee_id: str
    employee_code: str
    employee_name: str
    status: Literal["pending", "approved", "rejected", "cancelled"]
    # camelCase keys, only the fields asked for; previous holds those fields as they were when asked.
    changes: dict[str, Any]
    previous: dict[str, Any]
    remarks: str | None
    decided_by_user_id: str | None
    decided_by_name: str | None
    decided_at: datetime | None
    decision_remarks: str | None
    created_at: datetime
    created_by_user_id: str | None
    created_by_name: str | None
    updated_at: datetime | None
    row_version: str
