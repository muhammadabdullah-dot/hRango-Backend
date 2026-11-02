"""Who is calling a /platform route: hRango's own staff, on their own tokens. A customer's token is refused
here and a staff token is refused on every customer route (app/core/security.py), so neither side can use
the other's sessions. Staff access goes by role, not by the customers' permission catalogue."""
from dataclasses import dataclass

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.db import Db, get_db
from app.core.errors import forbidden, unauthenticated
from app.core.security import read_staff_token
from app.repos import platform_repo

_bearer = HTTPBearer(auto_error=False)


@dataclass
class StaffContext:
    staff_id: int
    session_id: int
    email: str
    display_name: str
    role: str


def get_staff_context(request: Request, creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
                      db: Db = Depends(get_db)) -> StaffContext:
    if creds is None or creds.scheme.lower() != "bearer":
        raise unauthenticated()
    ids = read_staff_token(creds.credentials)
    if ids is None:
        raise unauthenticated()
    row = platform_repo.session_context(db, ids[0], ids[1])
    if row is None:
        raise unauthenticated()
    request.state.user_id = f"staff:{row['staff_id']}"
    return StaffContext(staff_id=row["staff_id"], session_id=ids[0], email=row["email"],
                        display_name=row["display_name"], role=row["role"])


def require_role(*roles: str):
    """Dependency: the staff member must hold one of these roles."""

    def check(ctx: StaffContext = Depends(get_staff_context)) -> StaffContext:
        if ctx.role not in roles:
            raise forbidden()
        return ctx

    return check
