from datetime import datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel

Scope = Literal["own", "team", "department", "branch", "selected_units", "company"]
UnitType = Literal["branch", "department", "location"]


class UserIn(ApiModel):
    email: str = Field(min_length=3, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    # Shown when the user is not linked to an employee (system users).
    display_name: str | None = Field(None, max_length=200)
    employee_id: int | None = None
    # New users only; afterwards PUT /access/users/{id}/password.
    password: str | None = Field(None, min_length=8, max_length=200)
    is_active: bool = True
    # Only a system administrator may set this (ACC-11).
    is_system_admin: bool = False
    # Extra companies the user may switch to; the active company is always their home on creation.
    # Left out on an edit: unchanged.
    company_ids: list[int] | None = None
    # New users only (needs access.roles.assign); afterwards PUT /access/users/{id}/roles.
    role_ids: list[int] | None = None
    row_version: str | None = None


class RefOut(ApiModel):
    id: str
    name: str


class RoleRef(ApiModel):
    id: str
    code: str
    name: str
    is_active: bool


class UserOut(ApiModel):
    id: str
    email: str
    display_name: str | None
    name: str
    employee_id: str | None
    employee_code: str | None
    home_company_id: str
    home_company_name: str | None
    is_active: bool
    is_system_admin: bool
    last_login_at: datetime | None
    role_names: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class UserDetailOut(UserOut):
    roles: list[RoleRef]
    companies: list[RefOut]


class UserRolesIn(ApiModel):
    role_ids: list[int]
    row_version: str


class RowVersionIn(ApiModel):
    row_version: str


class PasswordIn(ApiModel):
    password: str = Field(min_length=8, max_length=200)


class OwnPasswordIn(ApiModel):
    current_password: str = Field(min_length=1, max_length=200)
    new_password: str = Field(min_length=8, max_length=200)


class EffectivePermissionOut(ApiModel):
    code: str
    module: str
    label: str
    is_sensitive: bool
    scopes: list[str]
    # Where it comes from: role names, or "grant" for a personal grant.
    sources: str | None


class PermissionOut(ApiModel):
    id: str
    code: str
    module: str
    screen: str
    action_code: str
    label: str
    hint: str | None
    is_sensitive: bool


class RoleIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = Field(None, max_length=2000)
    row_version: str | None = None


class RoleOut(ApiModel):
    id: str
    code: str
    name: str
    description: str | None
    is_system: bool
    is_active: bool
    permission_count: int
    user_count: int
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class UnitIn(ApiModel):
    unit_type: UnitType
    unit_id: int


class UnitOut(ApiModel):
    unit_type: str
    unit_id: str
    unit_name: str | None


class TickIn(ApiModel):
    code: str = Field(min_length=3, max_length=150)
    scope: Scope
    # Required when scope is selected_units.
    units: list[UnitIn] = []


class TickOut(ApiModel):
    code: str
    module: str
    screen: str
    action_code: str
    label: str
    is_sensitive: bool
    scope: str
    units: list[UnitOut]


class RoleDetailOut(RoleOut):
    permissions: list[TickOut]


class RolePermissionsIn(ApiModel):
    """Every tick the role should have; anything not listed is removed."""
    permissions: list[TickIn]
    row_version: str


class RoleCopyIn(ApiModel):
    name: str = Field(min_length=1, max_length=200)


class OverrideIn(ApiModel):
    code: str = Field(min_length=3, max_length=150)
    effect: Literal["grant", "deny"]
    # Grants only; selected_units is not offered for a personal grant.
    scope: Literal["own", "team", "department", "branch", "company"] | None = None
    reason: str | None = Field(None, max_length=1000)


class OverrideOut(ApiModel):
    id: str
    user_account_id: str
    code: str
    module: str
    label: str
    is_sensitive: bool
    effect: str
    scope: str | None
    reason: str | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class SessionOut(ApiModel):
    id: str
    user_account_id: str
    email: str
    user_name: str
    device: str | None
    ip_address: str | None
    signed_in_at: datetime
    last_seen_at: datetime | None
    expires_at: datetime | None
    revoked_at: datetime | None
    is_active: bool


class EndedOut(ApiModel):
    ended: int


class AuditOut(ApiModel):
    id: str
    entity_type: str
    entity_id: str
    entity_name: str | None
    field_name: str | None
    old_value: str | None
    new_value: str | None
    action_name: str | None
    performed_at: datetime | None
    performed_by_user_id: str | None
    performed_by_name: str | None
