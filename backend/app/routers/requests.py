"""Requests: one set of endpoints per request type (/requests/<type>, the type code with hyphens),
the Approvals screen (/requests/approvals) and Request Settings (/requests/settings/...).

Per type: requests.<type>.view lists and reads (My / Subordinates / All by scope), .create files
and edits, .cancel withdraws, deletes and cancels, .export downloads. Approvals: deciding needs
requests.approvals.approve / reject to open the buttons, but who may decide a request is set by
its flow and delegations (ACC-13)."""
from datetime import date

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import requests_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, get_context, require
from app.schemas.common import Item, Paginated
from app.schemas.requests import (TYPE_DETAILS, AttachmentIn, AttachmentOut, AuthorityIn, AuthorityOut,
                                  BulkDecisionIn, BulkResultOut, CancelIn, ColleagueOptionOut, ConsentIn, DecisionIn,
                                  DelegationIn, DelegationOut, DelegationPatch, ExpenseCategoryIn, ExpenseCategoryOut,
                                  FlowDetailOut, FlowIn, FlowOut, ForwardIn, LeaveTypeOptionOut,
                                  LoanCategoryOptionOut, LoanTypeOptionOut, ReimbursementSettingIn,
                                  ReimbursementSettingOut, RequestDetailOut, RequestIn, RequestPage, RequestTypeOut,
                                  RestrictionIn, RestrictionOut)

router = APIRouter(prefix="/requests", tags=["requests"])


def request_filters(view: str = Query("my"), status_: str | None = Query(None, alias="status"),
                    q: str | None = None, employee_id: int | None = Query(None, alias="employeeId"),
                    department_id: int | None = Query(None, alias="departmentId"),
                    branch_id: int | None = Query(None, alias="branchId"),
                    location_id: int | None = Query(None, alias="locationId"),
                    date_from: date | None = Query(None, alias="from"),
                    date_to: date | None = Query(None, alias="to")) -> dict:
    """Filters of the request lists: the My / Subordinates / All tab, status tab and filter panel."""
    return {"view": view, "status": status_, "search": q, "employee_id": employee_id, "department_id": department_id,
            "branch_id": branch_id, "location_id": location_id, "date_from": date_from, "date_to": date_to}


def approval_filters(box: str = Query("requested"), type_: str | None = Query(None, alias="type"),
                     status_: str | None = Query(None, alias="status"),
                     delegator_id: int | None = Query(None, alias="delegatorId"), q: str | None = None,
                     employee_id: int | None = Query(None, alias="employeeId"),
                     department_id: int | None = Query(None, alias="departmentId"),
                     branch_id: int | None = Query(None, alias="branchId"),
                     location_id: int | None = Query(None, alias="locationId"),
                     date_from: date | None = Query(None, alias="from"),
                     date_to: date | None = Query(None, alias="to")) -> dict:
    """Approvals: box = requested | delegates | consents | cancellations; type = a request type code."""
    return {"box": box, "type_code": type_.replace("-", "_") if type_ else None, "status": status_,
            "delegator_id": delegator_id, "search": q, "employee_id": employee_id, "department_id": department_id,
            "branch_id": branch_id, "location_id": location_id, "date_from": date_from, "date_to": date_to}


# ---------------------------------------------------------------- reference

@router.get("/types", response_model=Item[list[RequestTypeOut]])
def list_request_types(db: Db = Depends(get_db), ctx: RequestContext = Depends(get_context)) -> dict:
    return c.request_types(db)


@router.get("/expense/categories", response_model=Paginated[ExpenseCategoryOut])
def expense_category_options(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                             ctx: RequestContext = Depends(require("requests.expense.create"))) -> dict:
    """The Expense Claim Category* dropdown: active categories only."""
    return c.list_expense_categories(db, ctx, q, True, paging)


# ---------------------------------------------------------------- self-service options of the request forms
# Dropdowns staff need while filling a request. Guarded by the create permission of the request kinds
# that use them (not by the settings permissions of the full lists); ids, names and form rules only.

@router.get("/options/leave-types", response_model=Item[list[LeaveTypeOptionOut]])
def leave_type_options(employee_id: int | None = Query(None, alias="employeeId"),
                       as_of: date | None = Query(None, alias="asOf"), db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("requests.leave.create"))) -> dict:
    """The leave types the employee (default: the caller) may apply for, with balance and rules."""
    return c.option_leave_types(db, ctx, employee_id, as_of)


@router.get("/options/loan-types", response_model=Item[list[LoanTypeOptionOut]])
def loan_type_options(employee_id: int | None = Query(None, alias="employeeId"), db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("requests.loan.create"))) -> dict:
    """Active loan types with their terms; eligible says whether the employee's contract type may apply."""
    return c.option_loan_types(db, ctx, employee_id)


@router.get("/options/loan-categories", response_model=Item[list[LoanCategoryOptionOut]])
def loan_category_options(db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("requests.loan.create"))) -> dict:
    return c.option_loan_categories(db, ctx)


@router.get("/options/colleagues", response_model=Paginated[ColleagueOptionOut])
def colleague_options(q: str | None = None, employee_id: int | None = Query(None, alias="employeeId"),
                      paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("requests.shift_swap.create"))) -> dict:
    """Colleagues to swap a shift with: the company's current employees but the requester (employeeId,
    default the caller). Id, code, name, department and branch only."""
    return c.option_colleagues(db, ctx, employee_id, q, paging)


# ---------------------------------------------------------------- approvals

@router.get("/approvals", response_model=RequestPage)
def list_approvals(filters: dict = Depends(approval_filters), paging: PageParams = Depends(page_params),
                   db: Db = Depends(get_db), ctx: RequestContext = Depends(require("requests.approvals.view"))) -> dict:
    return c.list_approvals(db, ctx, filters, paging)


@router.post("/approvals/bulk-approve", response_model=Item[list[BulkResultOut]])
def bulk_approve(body: BulkDecisionIn, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("requests.approvals.approve"))) -> dict:
    """Approves each request on its own; the result says which went through (APR-9)."""
    return c.bulk(db, ctx, "approve", body)


@router.post("/approvals/bulk-reject", response_model=Item[list[BulkResultOut]])
def bulk_reject(body: BulkDecisionIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("requests.approvals.reject"))) -> dict:
    return c.bulk(db, ctx, "reject", body)


@router.get("/approvals/{request_id}", response_model=Item[RequestDetailOut])
def get_approval(request_id: int, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("requests.approvals.view"))) -> dict:
    return c.get_approval(db, ctx, request_id)


@router.post("/approvals/{request_id}/approve", response_model=Item[RequestDetailOut])
def approve(request_id: int, body: DecisionIn, db: Db = Depends(get_db),
            ctx: RequestContext = Depends(require("requests.approvals.approve"))) -> dict:
    return c.decide(db, ctx, request_id, "approve", body)


@router.post("/approvals/{request_id}/reject", response_model=Item[RequestDetailOut])
def reject(request_id: int, body: DecisionIn, db: Db = Depends(get_db),
           ctx: RequestContext = Depends(require("requests.approvals.reject"))) -> dict:
    return c.decide(db, ctx, request_id, "reject", body)


@router.post("/approvals/{request_id}/consent", response_model=Item[RequestDetailOut])
def consent(request_id: int, body: ConsentIn, db: Db = Depends(get_db),
            ctx: RequestContext = Depends(require("requests.approvals.view"))) -> dict:
    return c.consent(db, ctx, request_id, body)


@router.post("/approvals/{request_id}/forward", response_model=Item[RequestDetailOut])
def forward(request_id: int, body: ForwardIn, db: Db = Depends(get_db),
            ctx: RequestContext = Depends(require("requests.approvals.approve"))) -> dict:
    return c.forward(db, ctx, request_id, body)


@router.post("/approvals/{request_id}/cancel", response_model=Item[RequestDetailOut])
def cancel_as_approver(request_id: int, body: CancelIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("requests.approvals.cancel"))) -> dict:
    return c.cancel_request(db, ctx, None, request_id, body)


# ---------------------------------------------------------------- settings: restrictions

@router.get("/settings/restrictions", response_model=Paginated[RestrictionOut])
def list_restrictions(type_: str | None = Query(None, alias="requestType"),
                      start_from: date | None = Query(None, alias="startFrom"),
                      start_to: date | None = Query(None, alias="startTo"),
                      end_from: date | None = Query(None, alias="endFrom"), end_to: date | None = Query(None, alias="endTo"),
                      paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("requests.settings.restrictions.view"))) -> dict:
    return c.list_restrictions(db, ctx, type_, start_from, start_to, end_from, end_to, paging)


@router.get("/settings/restrictions/{restriction_id}", response_model=Item[RestrictionOut])
def get_restriction(restriction_id: int, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("requests.settings.restrictions.view"))) -> dict:
    return c.get_restriction(db, ctx, restriction_id)


@router.post("/settings/restrictions", response_model=Item[RestrictionOut], status_code=status.HTTP_201_CREATED)
def create_restriction(body: RestrictionIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("requests.settings.restrictions.create"))) -> dict:
    return c.create_restriction(db, ctx, body)


@router.put("/settings/restrictions/{restriction_id}", response_model=Item[RestrictionOut])
def update_restriction(restriction_id: int, body: RestrictionIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("requests.settings.restrictions.edit"))) -> dict:
    """Edits a restriction with the rowVersion last read."""
    return c.update_restriction(db, ctx, restriction_id, body)


@router.delete("/settings/restrictions/{restriction_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_restriction(restriction_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                       db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("requests.settings.restrictions.delete"))) -> Response:
    c.delete_restriction(db, ctx, restriction_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- settings: delegations

@router.get("/settings/delegations", response_model=Paginated[DelegationOut])
def list_delegations(delegator_id: int | None = Query(None, alias="delegatorId"),
                     delegatee_id: int | None = Query(None, alias="delegateeId"),
                     type_: str | None = Query(None, alias="requestType"),
                     is_active: bool | None = Query(None, alias="isActive"), q: str | None = None,
                     paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("requests.settings.delegations.view"))) -> dict:
    return c.list_delegations(db, ctx, delegator_id, delegatee_id, type_, is_active, q, paging)


@router.get("/settings/delegations/{delegation_id}", response_model=Item[DelegationOut])
def get_delegation(delegation_id: int, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("requests.settings.delegations.view"))) -> dict:
    return c.get_delegation(db, ctx, delegation_id)


@router.post("/settings/delegations", response_model=Item[DelegationOut], status_code=status.HTTP_201_CREATED)
def create_delegation(body: DelegationIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("requests.settings.delegations.create"))) -> dict:
    return c.create_delegation(db, ctx, body)


@router.patch("/settings/delegations/{delegation_id}", response_model=Item[DelegationOut])
def patch_delegation(delegation_id: int, body: DelegationPatch, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("requests.settings.delegations.edit"))) -> dict:
    return c.patch_delegation(db, ctx, delegation_id, body)


@router.delete("/settings/delegations/{delegation_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_delegation(delegation_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                      db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("requests.settings.delegations.delete"))) -> Response:
    c.delete_delegation(db, ctx, delegation_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- settings: flows

@router.get("/settings/flows", response_model=Paginated[FlowOut])
def list_flows(type_: str | None = Query(None, alias="requestType"), purpose: str | None = None,
               scope_type: str | None = Query(None, alias="scopeType"), paging: PageParams = Depends(page_params),
               db: Db = Depends(get_db), ctx: RequestContext = Depends(require("requests.settings.flows.view"))) -> dict:
    return c.list_flows(db, ctx, type_, purpose, scope_type, paging)


@router.get("/settings/flows/{flow_id}", response_model=Item[FlowDetailOut])
def get_flow(flow_id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("requests.settings.flows.view"))) -> dict:
    return c.get_flow(db, ctx, flow_id)


@router.post("/settings/flows", response_model=Item[FlowDetailOut], status_code=status.HTTP_201_CREATED)
def create_flow(body: FlowIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("requests.settings.flows.create"))) -> dict:
    return c.create_flow(db, ctx, body)


@router.put("/settings/flows/{flow_id}", response_model=Item[FlowDetailOut])
def update_flow(flow_id: int, body: FlowIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("requests.settings.flows.edit"))) -> dict:
    """Saves a new version: the response has a new id; requests on the old version keep it."""
    return c.update_flow(db, ctx, flow_id, body)


@router.delete("/settings/flows/{flow_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_flow(flow_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("requests.settings.flows.delete"))) -> Response:
    c.delete_flow(db, ctx, flow_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- settings: expense categories

@router.get("/settings/expense-categories", response_model=Paginated[ExpenseCategoryOut])
def list_expense_categories(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
                            paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                            ctx: RequestContext = Depends(require("requests.settings.expense_categories.view"))) -> dict:
    return c.list_expense_categories(db, ctx, q, is_active, paging)


@router.get("/settings/expense-categories/{category_id}", response_model=Item[ExpenseCategoryOut])
def get_expense_category(category_id: int, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("requests.settings.expense_categories.view"))) -> dict:
    return c.get_expense_category(db, ctx, category_id)


@router.post("/settings/expense-categories", response_model=Item[ExpenseCategoryOut],
             status_code=status.HTTP_201_CREATED)
def create_expense_category(body: ExpenseCategoryIn, db: Db = Depends(get_db),
                            ctx: RequestContext = Depends(require("requests.settings.expense_categories.create"))) -> dict:
    return c.create_expense_category(db, ctx, body)


@router.put("/settings/expense-categories/{category_id}", response_model=Item[ExpenseCategoryOut])
def update_expense_category(category_id: int, body: ExpenseCategoryIn, db: Db = Depends(get_db),
                            ctx: RequestContext = Depends(require("requests.settings.expense_categories.edit"))) -> dict:
    return c.update_expense_category(db, ctx, category_id, body)


@router.delete("/settings/expense-categories/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_expense_category(category_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                            db: Db = Depends(get_db),
                            ctx: RequestContext = Depends(require("requests.settings.expense_categories.delete"))
                            ) -> Response:
    c.delete_expense_category(db, ctx, category_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- settings: reimbursement pay items

@router.get("/settings/reimbursement", response_model=Item[ReimbursementSettingOut])
def get_reimbursement(db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("requests.settings.reimbursement.view"))) -> dict:
    """The reimbursement pay items approved expense and air ticket claims are paid under through payroll."""
    return c.get_reimbursement(db, ctx)


@router.put("/settings/reimbursement", response_model=Item[ReimbursementSettingOut])
def save_reimbursement(body: ReimbursementSettingIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("requests.settings.reimbursement.edit"))) -> dict:
    return c.save_reimbursement(db, ctx, body)


# ---------------------------------------------------------------- settings: authorities

@router.get("/settings/authorities", response_model=Paginated[AuthorityOut])
def list_authorities(authority: str | None = None, type_: str | None = Query(None, alias="requestType"),
                     employee_id: int | None = Query(None, alias="employeeId"),
                     paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("requests.settings.authorities.view"))) -> dict:
    return c.list_authorities(db, ctx, authority, type_, employee_id, paging)


@router.post("/settings/authorities", response_model=Item[AuthorityOut], status_code=status.HTTP_201_CREATED)
def create_authority(body: AuthorityIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("requests.settings.authorities.create"))) -> dict:
    return c.create_authority(db, ctx, body)


@router.put("/settings/authorities/{authority_id}", response_model=Item[AuthorityOut])
def update_authority(authority_id: int, body: AuthorityIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("requests.settings.authorities.edit"))) -> dict:
    return c.update_authority(db, ctx, authority_id, body)


@router.delete("/settings/authorities/{authority_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_authority(authority_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                     db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("requests.settings.authorities.delete"))) -> Response:
    c.delete_authority(db, ctx, authority_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- one set of endpoints per request type

def _add_type(code: str, details_model) -> None:
    slug = code.replace("_", "-")
    body_model = RequestIn[details_model]
    can_view, can_create = require(f"requests.{code}.view"), require(f"requests.{code}.create")
    can_cancel, can_export = require(f"requests.{code}.cancel"), require(f"requests.{code}.export")

    def list_requests(filters: dict = Depends(request_filters), paging: PageParams = Depends(page_params),
                      db: Db = Depends(get_db), ctx: RequestContext = Depends(can_view)) -> dict:
        return c.list_requests(db, ctx, code, filters, paging)

    def export_requests(filters: dict = Depends(request_filters), db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(can_export)) -> Response:
        return Response(c.export_requests(db, ctx, code, filters), media_type="text/csv",
                        headers={"Content-Disposition": f'attachment; filename="{slug}-requests.csv"'})

    def get_request(request_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(can_view)) -> dict:
        return c.get_request(db, ctx, code, request_id)

    def create_request(body: body_model, db: Db = Depends(get_db),  # type: ignore[valid-type]
                       ctx: RequestContext = Depends(can_create)) -> dict:
        return c.create_request(db, ctx, code, body)

    def update_request(request_id: int, body: body_model, db: Db = Depends(get_db),  # type: ignore[valid-type]
                       ctx: RequestContext = Depends(can_create)) -> dict:
        return c.update_request(db, ctx, code, request_id, body)

    def delete_request(request_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                       db: Db = Depends(get_db), ctx: RequestContext = Depends(can_cancel)) -> Response:
        c.delete_request(db, ctx, code, request_id, row_version)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    def cancel_request(request_id: int, body: CancelIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(can_cancel)) -> dict:
        return c.cancel_request(db, ctx, code, request_id, body)

    def add_attachment(request_id: int, body: AttachmentIn, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(can_create)) -> dict:
        return c.add_attachment(db, ctx, code, request_id, body)

    def delete_attachment(request_id: int, attachment_id: int, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(can_create)) -> Response:
        c.delete_attachment(db, ctx, code, request_id, attachment_id)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    tag = [f"requests: {slug}"]
    r = router.add_api_route
    r(f"/{slug}", list_requests, methods=["GET"], response_model=RequestPage, name=f"list_{code}", tags=tag)
    r(f"/{slug}/export", export_requests, methods=["GET"], name=f"export_{code}", tags=tag)
    r(f"/{slug}/{{request_id}}", get_request, methods=["GET"], response_model=Item[RequestDetailOut],
      name=f"get_{code}", tags=tag)
    r(f"/{slug}", create_request, methods=["POST"], response_model=Item[RequestDetailOut],
      status_code=status.HTTP_201_CREATED, name=f"create_{code}", tags=tag)
    r(f"/{slug}/{{request_id}}", update_request, methods=["PUT"], response_model=Item[RequestDetailOut],
      name=f"update_{code}", tags=tag)
    r(f"/{slug}/{{request_id}}", delete_request, methods=["DELETE"], status_code=status.HTTP_204_NO_CONTENT,
      name=f"delete_{code}", tags=tag)
    r(f"/{slug}/{{request_id}}/cancel", cancel_request, methods=["POST"], response_model=Item[RequestDetailOut],
      name=f"cancel_{code}", tags=tag)
    r(f"/{slug}/{{request_id}}/attachments", add_attachment, methods=["POST"], response_model=Item[AttachmentOut],
      status_code=status.HTTP_201_CREATED, name=f"add_attachment_{code}", tags=tag)
    r(f"/{slug}/{{request_id}}/attachments/{{attachment_id}}", delete_attachment, methods=["DELETE"],
      status_code=status.HTTP_204_NO_CONTENT, name=f"delete_attachment_{code}", tags=tag)


for _code, _model in TYPE_DETAILS.items():
    _add_type(_code, _model)
