"""Who is calling, for which company, and what they may do.

Routers depend on `require("module.screen.action")` (or `get_context` for endpoints any signed-in
user may call). The token names a session; the session row decides whether it still works.
The active company is the session's company unless the request sends X-Company-Id, which must be
one of the user's companies.

Billing access (plat.usp_subscription_access_refresh) applies to every request here: an organisation that is
read_only may look but not change anything (403 READ_ONLY on any write outside Billing, sign-in, uploads and the
inbox); one that is locked lets only its Account Owner in, to Billing (403 BILLING_LOCKED for everything else; signing
in and /auth/me still answer, so the web app can say why).
"""
from dataclasses import dataclass, field, replace

from fastapi import Depends, Header, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.db import Db, get_db
from app.core.errors import AppError, forbidden, unauthenticated
from app.core.permissions import CODES
from app.core.security import read_token
from app.repos import auth_repo

_bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class RequestContext:
    user_id: int
    company_id: int
    employee_id: int | None
    session_id: int
    name: str
    email: str
    role_name: str
    company_name: str | None = None
    company_logo_file_id: int | None = None
    photo_file_id: int | None = None
    # Scopes the checked permission is held with (own, team, department, branch, selected_units, company).
    scopes: frozenset[str] = field(default_factory=frozenset)
    is_account_owner: bool = False
    # What the organisation's subscription allows: full, read_only or locked.
    billing_access: str = "full"

    @property
    def sees_company(self) -> bool:
        """True when the checked permission reaches everyone in the company."""
        return "company" in self.scopes


# Paths (under /api) that billing access does not close: sign-in and /auth/me always; Billing and uploads (a bank
# transfer proof) for whoever may still use them; the inbox (marking notifications read) while read-only.
_ALWAYS_OPEN = ("/api/auth",)
_OPEN_WHEN_LOCKED = ("/api/auth", "/api/billing", "/api/files", "/api/organisation/plan")
_WRITES_OPEN_WHEN_READ_ONLY = ("/api/auth", "/api/billing", "/api/files", "/api/inbox", "/api/access/me")
READ_ONLY_MESSAGE = ("Your organisation is read-only because a payment is overdue. You can view and export, but changes "
                     "are paused until it is paid.")
LOCKED_MESSAGE = ("Your organisation's access is paused because a payment is overdue. The Account Owner can restore it "
                  "from Billing.")


def _under(path: str, prefixes: tuple[str, ...]) -> bool:
    return any(path == p or path.startswith(p + "/") for p in prefixes)


def _billing_gate(request: Request, access: str, is_owner: bool) -> None:
    path = request.url.path
    if access == "locked":
        if not _under(path, _OPEN_WHEN_LOCKED if is_owner else _ALWAYS_OPEN):
            raise AppError(403, "BILLING_LOCKED", LOCKED_MESSAGE)
    elif access == "read_only" and request.method not in ("GET", "HEAD", "OPTIONS"):
        if not _under(path, _WRITES_OPEN_WHEN_READ_ONLY):
            raise AppError(403, "READ_ONLY", READ_ONLY_MESSAGE)


def get_context(request: Request, creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
                x_company_id: int | None = Header(default=None), db: Db = Depends(get_db)) -> RequestContext:
    if creds is None or creds.scheme.lower() != "bearer":
        raise unauthenticated()
    ids = read_token(creds.credentials)
    if ids is None:
        raise unauthenticated()
    row = auth_repo.session_context(db, ids[0], ids[1], x_company_id)
    if row is None:
        raise unauthenticated()
    request.state.user_id = row["user_id"]
    access = row.get("billing_access") or "full"
    is_owner = bool(row.get("is_account_owner"))
    _billing_gate(request, access, is_owner)
    return RequestContext(user_id=row["user_id"], company_id=row["company_id"], employee_id=row["employee_id"],
                          session_id=ids[0], name=row["name"],
                          email=row["email"], role_name=row["role_name"], company_name=row["company_name"],
                          company_logo_file_id=row["company_logo_file_id"], photo_file_id=row["photo_file_id"],
                          is_account_owner=is_owner, billing_access=access)


def require(code: str):
    """Dependency: the caller must hold this permission. Returns the context with its scopes."""
    if code not in CODES:
        raise ValueError(f"{code} is not in the permission catalogue (app/catalogue)")

    def checker(ctx: RequestContext = Depends(get_context), db: Db = Depends(get_db)) -> RequestContext:
        row = auth_repo.permission_check(db, ctx.company_id, ctx.user_id, code)
        if not row["allowed"]:
            raise forbidden()
        return replace(ctx, scopes=frozenset((row["scopes"] or "").split(",")))

    return checker


def require_any(*codes: str):
    """Dependency: the caller must hold at least one of these permissions."""
    for code in codes:
        if code not in CODES:
            raise ValueError(f"{code} is not in the permission catalogue (app/catalogue)")

    def checker(ctx: RequestContext = Depends(get_context), db: Db = Depends(get_db)) -> RequestContext:
        scopes: set[str] = set()
        for code in codes:
            row = auth_repo.permission_check(db, ctx.company_id, ctx.user_id, code)
            if row["allowed"]:
                scopes |= set((row["scopes"] or "").split(","))
        if not scopes:
            raise forbidden()
        return replace(ctx, scopes=frozenset(scopes))

    return checker
