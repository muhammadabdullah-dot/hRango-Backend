from typing import Any

from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.platform_auth import StaffContext
from app.repos import platform_repo
from app.schemas.common import paginated
from app.schemas.platform import (
    CustomerCompanyOut,
    CustomerIn,
    CustomerOut,
    CustomerRegisterIn,
    CustomerStatusIn,
    DashboardOut,
    InvoiceIn,
    InvoiceOut,
    InvoiceStatusIn,
    LeadIn,
    LeadOut,
    PlanIn,
    PlanOut,
    StaffAuditOut,
    StaffIn,
    StaffLoginIn,
    StaffLookup,
    StaffMe,
    StaffOut,
    StaffPasswordIn,
    StaffSession,
    SubscriptionIn,
    SubscriptionOut,
    TicketIn,
    TicketOut,
)
from app.services import platform_service as s


def _staff(row: dict[str, Any]) -> StaffOut:
    return StaffOut(**{**row, "row_version": row_version_out(row["row_version"])})


MONEY_ROLES = ("super_admin", "admin", "billing")
PIPELINE_ROLES = ("super_admin", "admin", "sales")


def _with_version(model: type[Any]):
    def build(row: dict[str, Any]) -> Any:
        return model(**{**row, "row_version": row_version_out(row["row_version"])})
    return build


_customer = _with_version(CustomerOut)
_plan = _with_version(PlanOut)
_subscription = _with_version(SubscriptionOut)
_invoice = _with_version(InvoiceOut)
_lead = _with_version(LeadOut)
_ticket = _with_version(TicketOut)


def login(db: Db, body: StaffLoginIn, device: str | None, ip_address: str | None) -> dict:
    token, account = s.login(db, body.email, body.password, device, ip_address)
    return {"data": StaffSession(token=token, staff=StaffMe(**account))}


def me(ctx: StaffContext) -> dict:
    return {"data": StaffMe(id=ctx.staff_id, email=ctx.email, display_name=ctx.display_name, role=ctx.role)}


def logout(db: Db, ctx: StaffContext) -> None:
    platform_repo.session_end(db, ctx.session_id)
    platform_repo.audit(db, ctx.staff_id, "signed_out")


def list_staff(db: Db, q: str | None, paging: PageParams) -> dict:
    total, rows = platform_repo.list_staff(db, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _staff)


def get_staff(db: Db, staff_id: int) -> dict:
    return {"data": _staff(platform_repo.get_staff(db, staff_id))}


def add_staff(db: Db, ctx: StaffContext, body: StaffIn) -> dict:
    return {"data": _staff(s.add_staff(db, ctx.staff_id, body.model_dump(by_alias=False)))}


def update_staff(db: Db, ctx: StaffContext, staff_id: int, body: StaffIn) -> dict:
    rv = row_version_in(body.row_version)
    return {"data": _staff(s.update_staff(db, ctx.staff_id, staff_id, body.model_dump(by_alias=False), rv))}


def set_password(db: Db, ctx: StaffContext, staff_id: int, body: StaffPasswordIn) -> None:
    s.set_password(db, ctx.staff_id, staff_id, body.password)


def list_audit(db: Db, paging: PageParams) -> dict:
    total, rows = platform_repo.list_audit(db, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: StaffAuditOut(**r))


def staff_lookup(db: Db) -> dict:
    return {"data": [StaffLookup(**r) for r in platform_repo.staff_lookup(db)]}


def dashboard(db: Db, ctx: StaffContext) -> dict:
    """Everyone sees the counts; money only reaches the roles that work with it."""
    figures, months, plans, stages, renewals = platform_repo.dashboard(db)
    row = figures[0]
    money = ctx.role in MONEY_ROLES
    pipeline = ctx.role in PIPELINE_ROLES
    if not money:
        row = {**row, "monthly_revenue": None, "overdue_invoices": None, "overdue_amount": None,
               "paid_this_month": None}
    if not pipeline:
        row = {**row, "pipeline_monthly": None}
        stages = [{**r, "monthly": None} for r in stages]
    if not money:
        renewals = [{**r, "amount": None} for r in renewals]
    return {"data": DashboardOut(figures=row, months=months, plans=plans, stages=stages, renewals=renewals)}


def list_customers(db: Db, q: str | None, status: str | None, paging: PageParams) -> dict:
    total, rows = platform_repo.list_page(db, "plat.usp_customer_list", search=q, status=status, page=paging.page,
                                          page_size=paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _customer)


def get_customer(db: Db, customer_id: int) -> dict:
    return {"data": _customer(platform_repo.get_customer(db, customer_id))}


def customer_companies(db: Db, customer_id: int) -> dict:
    return {"data": [CustomerCompanyOut(**r) for r in platform_repo.customer_companies(db, customer_id)]}


def register_customer(db: Db, ctx: StaffContext, body: CustomerRegisterIn) -> dict:
    return {"data": _customer(s.register_customer(db, ctx.staff_id, body.model_dump(by_alias=False)))}


def update_customer(db: Db, ctx: StaffContext, customer_id: int, body: CustomerIn) -> dict:
    rv = row_version_in(body.row_version)
    row = platform_repo.save_customer(db, ctx.staff_id, customer_id, body.model_dump(by_alias=False), rv)
    return {"data": _customer(row)}


def set_customer_status(db: Db, ctx: StaffContext, customer_id: int, body: CustomerStatusIn) -> dict:
    row = platform_repo.set_customer_status(db, ctx.staff_id, customer_id, body.status, row_version_in(body.row_version))
    return {"data": _customer(row)}


def list_plans(db: Db) -> dict:
    return {"data": [_plan(r) for r in platform_repo.list_plans(db)]}


def save_plan(db: Db, ctx: StaffContext, plan_id: int | None, body: PlanIn) -> dict:
    rv = row_version_in(body.row_version) if plan_id else None
    return {"data": _plan(platform_repo.save_plan(db, ctx.staff_id, plan_id, body.model_dump(by_alias=False), rv))}


def list_subscriptions(db: Db, q: str | None, status: str | None, customer_id: int | None, paging: PageParams) -> dict:
    total, rows = platform_repo.list_page(db, "plat.usp_subscription_list", search=q, status=status,
                                          customer_id=customer_id, page=paging.page, page_size=paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _subscription)


def save_subscription(db: Db, ctx: StaffContext, subscription_id: int | None, body: SubscriptionIn) -> dict:
    rv = row_version_in(body.row_version) if subscription_id else None
    row = platform_repo.save_subscription(db, ctx.staff_id, subscription_id, body.model_dump(by_alias=False), rv)
    return {"data": _subscription(row)}


def list_invoices(db: Db, q: str | None, status: str | None, customer_id: int | None, paging: PageParams) -> dict:
    total, rows = platform_repo.list_page(db, "plat.usp_invoice_list", search=q, status=status,
                                          customer_id=customer_id, page=paging.page, page_size=paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _invoice)


def add_invoice(db: Db, ctx: StaffContext, body: InvoiceIn) -> dict:
    return {"data": _invoice(platform_repo.add_invoice(db, ctx.staff_id, body.model_dump(by_alias=False)))}


def set_invoice_status(db: Db, ctx: StaffContext, invoice_id: int, body: InvoiceStatusIn) -> dict:
    row = platform_repo.set_invoice_status(db, ctx.staff_id, invoice_id, body.model_dump(by_alias=False),
                                           row_version_in(body.row_version))
    return {"data": _invoice(row)}


def list_leads(db: Db, q: str | None, stage: str | None, paging: PageParams) -> dict:
    total, rows = platform_repo.list_page(db, "plat.usp_lead_list", search=q, stage=stage, page=paging.page,
                                          page_size=paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _lead)


def save_lead(db: Db, ctx: StaffContext, lead_id: int | None, body: LeadIn) -> dict:
    rv = row_version_in(body.row_version) if lead_id else None
    return {"data": _lead(platform_repo.save_lead(db, ctx.staff_id, lead_id, body.model_dump(by_alias=False), rv))}


def list_tickets(db: Db, q: str | None, status: str | None, customer_id: int | None, paging: PageParams) -> dict:
    total, rows = platform_repo.list_page(db, "plat.usp_ticket_list", search=q, status=status, customer_id=customer_id,
                                          page=paging.page, page_size=paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _ticket)


def save_ticket(db: Db, ctx: StaffContext, ticket_id: int | None, body: TicketIn) -> dict:
    rv = row_version_in(body.row_version) if ticket_id else None
    return {"data": _ticket(platform_repo.save_ticket(db, ctx.staff_id, ticket_id, body.model_dump(by_alias=False), rv))}
