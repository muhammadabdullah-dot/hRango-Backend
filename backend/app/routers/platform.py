"""The hRango platform: routes for the company's own staff (Super Admin, Admin, Support, Billing, Sales), not for
customers. They answer on the separate SaaS staff address; module switches and support access arrive in later steps.

Who works where: every role reads organisations and plans. Billing has subscriptions and invoices, Sales has the
pipeline, Support has tickets. Admin has all of those, Super Admin too, and only Super Admin changes staff."""
from fastapi import APIRouter, Depends, Query, Request, Response, status

from app.controllers import platform_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.platform_auth import StaffContext, get_staff_context, require_role
from app.schemas.common import Item, Paginated
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

router = APIRouter(prefix="/platform", tags=["platform"])
NO_CONTENT = status.HTTP_204_NO_CONTENT
SUPER_ADMIN = require_role("super_admin")
ADMINS = require_role("super_admin", "admin")
BILLING = require_role("super_admin", "admin", "billing")
SALES = require_role("super_admin", "admin", "sales")
SUPPORT = require_role("super_admin", "admin", "support")


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


@router.get("/staff/lookup", response_model=Item[list[StaffLookup]])
def staff_lookup(db: Db = Depends(get_db), _: StaffContext = Depends(get_staff_context)) -> dict:
    return c.staff_lookup(db)


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


@router.get("/dashboard", response_model=Item[DashboardOut])
def dashboard(db: Db = Depends(get_db), ctx: StaffContext = Depends(get_staff_context)) -> dict:
    return c.dashboard(db, ctx)


@router.get("/organisations", response_model=Paginated[CustomerOut])
def list_customers(q: str | None = None, status: str | None = None, paging: PageParams = Depends(page_params),
                   db: Db = Depends(get_db), _: StaffContext = Depends(get_staff_context)) -> dict:
    return c.list_customers(db, q, status, paging)


@router.post("/organisations", response_model=Item[CustomerOut], status_code=status.HTTP_201_CREATED)
def register_customer(body: CustomerRegisterIn, db: Db = Depends(get_db), ctx: StaffContext = Depends(SALES)) -> dict:
    return c.register_customer(db, ctx, body)


@router.get("/organisations/{customer_id}", response_model=Item[CustomerOut])
def get_customer(customer_id: int, db: Db = Depends(get_db), _: StaffContext = Depends(get_staff_context)) -> dict:
    return c.get_customer(db, customer_id)


@router.get("/organisations/{customer_id}/companies", response_model=Item[list[CustomerCompanyOut]])
def customer_companies(customer_id: int, db: Db = Depends(get_db),
                       _: StaffContext = Depends(get_staff_context)) -> dict:
    return c.customer_companies(db, customer_id)


@router.put("/organisations/{customer_id}", response_model=Item[CustomerOut])
def update_customer(customer_id: int, body: CustomerIn, db: Db = Depends(get_db),
                    ctx: StaffContext = Depends(SALES)) -> dict:
    return c.update_customer(db, ctx, customer_id, body)


@router.patch("/organisations/{customer_id}/status", response_model=Item[CustomerOut])
def set_customer_status(customer_id: int, body: CustomerStatusIn, db: Db = Depends(get_db),
                        ctx: StaffContext = Depends(ADMINS)) -> dict:
    return c.set_customer_status(db, ctx, customer_id, body)


@router.get("/plans", response_model=Item[list[PlanOut]])
def list_plans(db: Db = Depends(get_db), _: StaffContext = Depends(get_staff_context)) -> dict:
    return c.list_plans(db)


@router.post("/plans", response_model=Item[PlanOut], status_code=status.HTTP_201_CREATED)
def add_plan(body: PlanIn, db: Db = Depends(get_db), ctx: StaffContext = Depends(ADMINS)) -> dict:
    return c.save_plan(db, ctx, None, body)


@router.put("/plans/{plan_id}", response_model=Item[PlanOut])
def update_plan(plan_id: int, body: PlanIn, db: Db = Depends(get_db), ctx: StaffContext = Depends(ADMINS)) -> dict:
    return c.save_plan(db, ctx, plan_id, body)


@router.get("/subscriptions", response_model=Paginated[SubscriptionOut])
def list_subscriptions(q: str | None = None, status: str | None = None,
                       customer_id: int | None = Query(None, alias="customerId"),
                       paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                       _: StaffContext = Depends(BILLING)) -> dict:
    return c.list_subscriptions(db, q, status, customer_id, paging)


@router.post("/subscriptions", response_model=Item[SubscriptionOut], status_code=status.HTTP_201_CREATED)
def add_subscription(body: SubscriptionIn, db: Db = Depends(get_db), ctx: StaffContext = Depends(BILLING)) -> dict:
    return c.save_subscription(db, ctx, None, body)


@router.put("/subscriptions/{subscription_id}", response_model=Item[SubscriptionOut])
def update_subscription(subscription_id: int, body: SubscriptionIn, db: Db = Depends(get_db),
                        ctx: StaffContext = Depends(BILLING)) -> dict:
    return c.save_subscription(db, ctx, subscription_id, body)


@router.get("/invoices", response_model=Paginated[InvoiceOut])
def list_invoices(q: str | None = None, status: str | None = None,
                  customer_id: int | None = Query(None, alias="customerId"),
                  paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  _: StaffContext = Depends(BILLING)) -> dict:
    return c.list_invoices(db, q, status, customer_id, paging)


@router.post("/invoices", response_model=Item[InvoiceOut], status_code=status.HTTP_201_CREATED)
def add_invoice(body: InvoiceIn, db: Db = Depends(get_db), ctx: StaffContext = Depends(BILLING)) -> dict:
    return c.add_invoice(db, ctx, body)


@router.patch("/invoices/{invoice_id}/status", response_model=Item[InvoiceOut])
def set_invoice_status(invoice_id: int, body: InvoiceStatusIn, db: Db = Depends(get_db),
                       ctx: StaffContext = Depends(BILLING)) -> dict:
    return c.set_invoice_status(db, ctx, invoice_id, body)


@router.get("/leads", response_model=Paginated[LeadOut])
def list_leads(q: str | None = None, stage: str | None = None, paging: PageParams = Depends(page_params),
               db: Db = Depends(get_db), _: StaffContext = Depends(SALES)) -> dict:
    return c.list_leads(db, q, stage, paging)


@router.post("/leads", response_model=Item[LeadOut], status_code=status.HTTP_201_CREATED)
def add_lead(body: LeadIn, db: Db = Depends(get_db), ctx: StaffContext = Depends(SALES)) -> dict:
    return c.save_lead(db, ctx, None, body)


@router.put("/leads/{lead_id}", response_model=Item[LeadOut])
def update_lead(lead_id: int, body: LeadIn, db: Db = Depends(get_db), ctx: StaffContext = Depends(SALES)) -> dict:
    return c.save_lead(db, ctx, lead_id, body)


@router.get("/tickets", response_model=Paginated[TicketOut])
def list_tickets(q: str | None = None, status: str | None = None,
                 customer_id: int | None = Query(None, alias="customerId"),
                 paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                 _: StaffContext = Depends(SUPPORT)) -> dict:
    return c.list_tickets(db, q, status, customer_id, paging)


@router.post("/tickets", response_model=Item[TicketOut], status_code=status.HTTP_201_CREATED)
def add_ticket(body: TicketIn, db: Db = Depends(get_db), ctx: StaffContext = Depends(SUPPORT)) -> dict:
    return c.save_ticket(db, ctx, None, body)


@router.put("/tickets/{ticket_id}", response_model=Item[TicketOut])
def update_ticket(ticket_id: int, body: TicketIn, db: Db = Depends(get_db),
                  ctx: StaffContext = Depends(SUPPORT)) -> dict:
    return c.save_ticket(db, ctx, ticket_id, body)
