"""Dashboards: CEO, HR and My (employee) dashboard. Figures follow the permission's scope."""
from datetime import date

from fastapi import APIRouter, Depends

from app.controllers import dashboard_controller as c
from app.core.db import Db, get_db
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item
from app.schemas.dashboard import CeoDashboard, HrDashboard, MyDashboard

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/ceo", response_model=Item[CeoDashboard])
def ceo(month: date | None = None, day: date | None = None, db: Db = Depends(get_db),
        ctx: RequestContext = Depends(require("dashboard.ceo.view"))) -> dict:
    """month: any day of the month the KPIs cover (default this month). day: the attendance day (default today)."""
    return c.ceo(db, ctx, month, day)


@router.get("/hr", response_model=Item[HrDashboard])
def hr(month: date | None = None, day: date | None = None, db: Db = Depends(get_db),
       ctx: RequestContext = Depends(require("dashboard.hr.view"))) -> dict:
    return c.hr(db, ctx, month, day)


@router.get("/me", response_model=Item[MyDashboard])
def mine(day: date | None = None, db: Db = Depends(get_db),
         ctx: RequestContext = Depends(require("dashboard.employee.view"))) -> dict:
    return c.mine(db, ctx, day)
