from pydantic import Field

from app.schemas.common import ApiModel


class LoginIn(ApiModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=200)


class PermissionOut(ApiModel):
    code: str
    scope: str


class AuthUser(ApiModel):
    id: str
    name: str
    email: str
    role: str
    avatar_url: str | None = None
    company_id: str
    # The organisation using hRango: its name and logo head the sidebar.
    company_name: str | None = None
    company_logo_url: str | None = None
    employee_id: str | None
    # Every permission the user holds in the active company; the frontend hides what is not listed.
    permissions: list[PermissionOut] = []


class AuthSession(ApiModel):
    token: str
    user: AuthUser
