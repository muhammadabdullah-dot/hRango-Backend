from app.core.db import Db
from app.core.errors import unauthenticated
from app.core.files import file_url
from app.middlewares.auth import RequestContext
from app.schemas.auth import AuthSession, AuthUser, LoginIn, PermissionOut
from app.services import auth_service


def _user(db: Db, ctx_row: dict, company_id: int, user_id: int) -> AuthUser:
    perms = auth_service.permissions(db, company_id, user_id)
    return AuthUser(id=ctx_row["user_id"], name=ctx_row["name"], email=ctx_row["email"], role=ctx_row["role_name"],
                    avatar_url=file_url(ctx_row.get("photo_file_id"), company_id),
                    company_id=ctx_row["company_id"], company_name=ctx_row.get("company_name"),
                    company_logo_url=file_url(ctx_row.get("company_logo_file_id"), company_id),
                    employee_id=ctx_row["employee_id"],
                    permissions=[PermissionOut(code=p["code"], scope=p["scope"]) for p in perms])


def login(db: Db, body: LoginIn, device: str | None, ip_address: str | None) -> dict:
    token, session_id, user_id = auth_service.login(db, body.email, body.password, device, ip_address)
    row = auth_service.context_row(db, session_id, user_id)
    if row is None:
        raise unauthenticated()
    return {"data": AuthSession(token=token, user=_user(db, row, row["company_id"], user_id))}


def me(db: Db, ctx: RequestContext) -> dict:
    row = {"user_id": ctx.user_id, "name": ctx.name, "email": ctx.email, "role_name": ctx.role_name,
           "company_id": ctx.company_id, "employee_id": ctx.employee_id, "company_name": ctx.company_name,
           "company_logo_file_id": ctx.company_logo_file_id, "photo_file_id": ctx.photo_file_id}
    return {"data": _user(db, row, ctx.company_id, ctx.user_id)}


def logout(db: Db, ctx: RequestContext) -> None:
    auth_service.logout(db, ctx.session_id)
