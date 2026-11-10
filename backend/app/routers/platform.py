"""The hRango platform: routes for the company's own staff (Super Admin, Admin, Support, Billing), not for customers.
They answer on the separate SaaS staff address; customers, plans and support access arrive here in later steps."""
from fastapi import APIRouter, Depends, Request, Response, status

from app.controllers import platform_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.platform_auth import StaffContext, get_staff_context, require_role
from app.schemas.common import Item, Paginated
from app.schemas.platform import StaffAuditOut, StaffIn, StaffLoginIn, StaffMe, StaffOut, StaffPasswordIn, StaffSession

router = APIRouter(prefix="/platform", tags=["platform"])
NO_CONTENT = status.HTTP_204_NO_CONTENT
SUPER_ADMIN = require_role("super_admin")
ADMINS = require_role("super_admin", "admin")


@router.post("/auth/login", response_model=Item[StaffSession])
def login(body: StaffLoginIn, request: Request, db: Db = Depends(get_db)) -> dict:
    device = (request.headers.get("User-Agent") or "")[:200] or None
    return c.login(db, body, device, request.client.host if request.client else None)


@router.get("/auth/me", response_model=Item[StaffMe])
def me(ctx: StaffContext = Depends(get_staff_context)) -> dict:
    return c.me(ctx)


@router.post("/auth/logout", status_code=NO_CONTENT)
def logout(db: Db = Depends(get_db), ctx: StaffContext = Depends(get_staff_context)) -> Response:
    c.logout(db, ctx)
    return Response(status_code=NO_CONTENT)


@router.get("/staff", response_model=Paginated[StaffOut])
def list_staff(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               _: StaffContext = Depends(ADMINS)) -> dict:
    return c.list_staff(db, q, paging)


@router.get("/staff/{staff_id}", response_model=Item[StaffOut])
def get_staff(staff_id: int, db: Db = Depends(get_db), _: StaffContext = Depends(ADMINS)) -> dict:
    return c.get_staff(db, staff_id)


@router.post("/staff", response_model=Item[StaffOut], status_code=status.HTTP_201_CREATED)
def add_staff(body: StaffIn, db: Db = Depends(get_db), ctx: StaffContext = Depends(SUPER_ADMIN)) -> dict:
    return c.add_staff(db, ctx, body)


@router.put("/staff/{staff_id}", response_model=Item[StaffOut])
def update_staff(staff_id: int, body: StaffIn, db: Db = Depends(get_db),
                 ctx: StaffContext = Depends(SUPER_ADMIN)) -> dict:
    return c.update_staff(db, ctx, staff_id, body)


@router.put("/staff/{staff_id}/password", status_code=NO_CONTENT)
def set_password(staff_id: int, body: StaffPasswordIn, db: Db = Depends(get_db),
                 ctx: StaffContext = Depends(SUPER_ADMIN)) -> Response:
    c.set_password(db, ctx, staff_id, body)
    return Response(status_code=NO_CONTENT)


@router.get("/audit", response_model=Paginated[StaffAuditOut])
def list_audit(paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               _: StaffContext = Depends(ADMINS)) -> dict:
    return c.list_audit(db, paging)
