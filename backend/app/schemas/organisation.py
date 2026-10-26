from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel

DateFormat = Literal["dd/MM/yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "dd MMM yyyy"]
WeekStart = Literal["monday", "saturday", "sunday"]
# IANA names such as Asia/Karachi or America/Argentina/Buenos_Aires, or UTC.
TIMEZONE_PATTERN = r"^(UTC|[A-Z][A-Za-z]+(/[A-Za-z0-9_+\-]+){1,2})$"
Latitude = Decimal
Longitude = Decimal


class DepartmentIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    parent_id: int | None = None
    head_id: int | None = None
    # The rowVersion from the last read. Required when editing, so two people cannot overwrite each other.
    row_version: str | None = None


class DepartmentOut(ApiModel):
    id: str
    name: str
    parent_id: str | None
    parent_name: str | None
    head_id: str | None
    head_name: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- companies and general settings

class CompanyIn(ApiModel):
    """General Settings: the organisation's name, contact details and locale."""
    organization_name: str = Field(min_length=2, max_length=200)
    legal_name: str | None = Field(None, max_length=200)
    email: str | None = Field(None, max_length=254, pattern=r"^$|^[^@\s]+@[^@\s]+\.[^@\s]+$")
    phone: str | None = Field(None, max_length=30, pattern=r"^[+\d\s()-]*$")
    website: str | None = Field(None, max_length=200, pattern=r"^$|^https?://\S+$")
    address: str | None = Field(None, max_length=500)
    country_id: int | None = None
    timezone: str = Field(pattern=TIMEZONE_PATTERN, max_length=64)
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    date_format: DateFormat = "dd/MM/yyyy"
    week_starts_on: WeekStart = "monday"
    fiscal_year_start_month: int = Field(ge=1, le=12)
    row_version: str | None = None


class CompanyOut(ApiModel):
    id: str
    organization_name: str
    legal_name: str | None
    email: str | None
    phone: str | None
    website: str | None
    address: str | None
    country_id: str | None
    country_name: str | None
    timezone: str | None
    currency: str | None
    date_format: str | None
    week_starts_on: str | None
    fiscal_year_start_month: int | None
    is_active: bool
    logo_file_id: str | None = None
    logo_url: str | None = None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class CompanyLogoIn(ApiModel):
    """The organisation's logo: an uploaded image's id, or null to remove it."""
    file_id: int | None = None


class CompanyRef(ApiModel):
    id: str
    name: str
    is_current: bool


# ---------------------------------------------------------------- locations, areas, branches

class LocationIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    employee_prefix: str | None = Field(None, max_length=10)
    description: str | None = Field(None, max_length=4000)
    latitude: Latitude | None = Field(None, ge=-90, le=90)
    longitude: Longitude | None = Field(None, ge=-180, le=180)
    row_version: str | None = None


class LocationOut(ApiModel):
    id: str
    company_id: str
    company_name: str
    name: str
    employee_prefix: str | None
    description: str | None
    latitude: float | None
    longitude: float | None
    branch_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class AreaIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    location_id: int
    description: str | None = Field(None, max_length=4000)
    row_version: str | None = None


class AreaOut(ApiModel):
    id: str
    location_id: str
    location_name: str
    name: str
    description: str | None
    branch_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class BranchIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    employee_prefix: str | None = Field(None, max_length=10)
    location_id: int
    area_id: int | None = None
    manager_id: int | None = None
    description: str | None = Field(None, max_length=4000)
    country_id: int | None = None
    state_id: int | None = None
    city_id: int | None = None
    latitude: Latitude | None = Field(None, ge=-90, le=90)
    longitude: Longitude | None = Field(None, ge=-180, le=180)
    row_version: str | None = None


class BranchOut(ApiModel):
    id: str
    company_id: str
    company_name: str
    name: str
    employee_prefix: str | None
    description: str | None
    location_id: str
    location_name: str
    area_id: str | None
    area_name: str | None
    manager_id: str | None
    manager_name: str | None
    country_id: str | None
    country_code: str | None
    country_name: str | None
    state_id: str | None
    state_code: str | None
    state_name: str | None
    city_id: str | None
    city_name: str | None
    latitude: float | None
    longitude: float | None
    employee_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- job titles and simple masters

class JobTitleIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    limit_head_count: bool = False
    # Required while limitHeadCount is on (the procedure answers with a field error otherwise).
    max_head_count: int | None = Field(None, ge=1)
    description: str | None = Field(None, max_length=4000)
    row_version: str | None = None


class JobTitleOut(ApiModel):
    id: str
    name: str
    limit_head_count: bool
    max_head_count: int | None
    description: str | None
    head_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class MasterIn(ApiModel):
    """Divisions, cost centers, designations, grades, job levels, employee groups, employment types.
    code is used by cost centers (required there); sortOrder ranks grades and job levels."""
    name: str = Field(min_length=1, max_length=200)
    code: str | None = Field(None, max_length=30)
    sort_order: int | None = Field(None, ge=0)
    row_version: str | None = None


class MasterOut(ApiModel):
    id: str
    name: str
    code: str | None = None
    sort_order: int | None = None
    employee_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


# ---------------------------------------------------------------- pickers

class LookupItem(ApiModel):
    id: str
    name: str
    code: str | None = None
    parent_id: str | None = None


class CountryOut(ApiModel):
    id: str
    code: str
    name: str


class StateOut(ApiModel):
    id: str
    code: str
    name: str
    country_id: str
    country_code: str


class CityOut(ApiModel):
    id: str
    name: str
    state_id: str
    state_code: str


# ---------------------------------------------------------------- announcements

class AnnouncementIn(ApiModel):
    kind: Literal["notice", "event"] = "notice"
    title: str = Field(min_length=1, max_length=200)
    body: str | None = Field(None, max_length=4000)
    event_date: date | None = None
    publish_from: date | None = None
    publish_to: date | None = None
    row_version: str | None = None


class AnnouncementOut(ApiModel):
    id: str
    kind: str
    title: str
    body: str | None
    event_date: date | None
    publish_from: date | None
    publish_to: date | None
    author_id: str | None
    author_name: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str
