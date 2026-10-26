"""HTTP shape for the dashboards."""
from datetime import date

from app.core.db import Db
from app.middlewares.auth import RequestContext
from app.schemas.dashboard import CeoDashboard, HrDashboard, MyDashboard
from app.services import dashboard_service


def ceo(db: Db, ctx: RequestContext, month: date | None, day: date | None) -> dict:
    return {"data": CeoDashboard(**dashboard_service.ceo(db, ctx, month, day))}


def hr(db: Db, ctx: RequestContext, month: date | None, day: date | None) -> dict:
    return {"data": HrDashboard(**dashboard_service.hr(db, ctx, month, day))}


def mine(db: Db, ctx: RequestContext, day: date | None) -> dict:
    return {"data": MyDashboard(**dashboard_service.mine(db, ctx, day))}
