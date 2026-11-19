from datetime import datetime

from pydantic import Field

from app.schemas.billing import BillingState
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
    is_account_owner: bool = False
    # The organisation's subscription: the banner, and read-only or locked access (null: no subscription).
    billing: BillingState | None = None


class AuthSession(ApiModel):
    token: str
    user: AuthUser


# ---------------------------------------------------------------- e-mail links (forgot password, invitations)

class ForgotPasswordIn(ApiModel):
    email: str = Field(min_length=3, max_length=254)


class TokenIn(ApiModel):
    """The token from the link's #token= part."""
    token: str = Field(min_length=20, max_length=200)


class SetPasswordIn(TokenIn):
    password: str = Field(min_length=8, max_length=200)


class LinkOut(ApiModel):
    purpose: str  # password_reset or invite
    email: str
    company_name: str | None
    expires_at: datetime


class AcceptedOut(ApiModel):
    email: str


class MessageOut(ApiModel):
    message: str
