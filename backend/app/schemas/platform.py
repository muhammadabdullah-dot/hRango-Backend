from datetime import datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel

StaffRole = Literal["super_admin", "admin", "support", "billing"]


class StaffLoginIn(ApiModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=200)


class StaffMe(ApiModel):
    id: str
    email: str
    display_name: str
    role: StaffRole


class StaffSession(ApiModel):
    token: str
    staff: StaffMe


class StaffIn(ApiModel):
    email: str = Field(min_length=3, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    display_name: str = Field(min_length=1, max_length=200)
    role: StaffRole
    is_active: bool = True
    # New staff only; afterwards PUT /platform/staff/{id}/password.
    password: str | None = Field(None, min_length=12, max_length=200)
    row_version: str | None = None


class StaffPasswordIn(ApiModel):
    password: str = Field(min_length=12, max_length=200)


class StaffOut(ApiModel):
    id: str
    email: str
    display_name: str
    role: StaffRole
    is_active: bool
    last_login_at: datetime | None
    created_at: datetime
    updated_at: datetime | None
    row_version: str


class StaffAuditOut(ApiModel):
    id: str
    action_name: str
    entity_type: str | None
    entity_ref: str | None
    detail: str | None
    ip_address: str | None
    staff_id: str | None
    staff_name: str | None
    created_at: datetime
