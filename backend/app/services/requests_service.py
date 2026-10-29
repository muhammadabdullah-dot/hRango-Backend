"""Request rules. Checks that need the database (balances, overlaps, eligibility, who may decide)
live in the req.* procedures; rules that do not (required reasons, date order, the flow editor's
expressions and node graph) live here, as does anything that spans several procedures (bulk)."""
import json
import re
from datetime import date, datetime, time
from typing import Any

from app.core import ai
from app.core.db import Db
from app.core.errors import AppError, invalid
from app.middlewares.auth import RequestContext
from app.repos import requests_repo
from app.schemas.requests import AUTHORITIES, STRUCTURAL_APPROVERS, FlowNodeIn, OvertimeBulkIn, RequestIn

# Reason* is required on these forms (Functional Requirements: WFH, Loan, Leave, Resignation;
# Figma: Relaxation "Reason *"; Requisition: the justification, a decision of comparison/04-requests.md).
REASON_REQUIRED = {"leave", "work_from_home", "loan", "resignation", "relaxation", "requisition"}
VIEWS = ("my", "subordinates", "all")
BOXES = ("requested", "delegates", "consents", "cancellations")
STATUSES = ("pending", "approved", "rejected", "cancelling", "cancelled")
# What a request step can wait for (the flowStep filter): an approver kind of the flow editor, an authority,
# or the colleague of a shift swap.
FLOW_STEPS = (*STRUCTURAL_APPROVERS, *AUTHORITIES, "colleague")


def _check_flow_step(filters: dict[str, Any]) -> None:
    if filters.get("flow_step") is not None and filters["flow_step"] not in FLOW_STEPS:
        raise invalid("flowStep must be an approver kind or an authority code (line_manager, hr_manager ...).",
                      "flowStep")

_EXPRESSION = re.compile(
    r"^\s*(days|amount|minutes|department_id|branch_id|location_id|grade_id|designation_id|employment_type_id)"
    r"\s*(==|=|!=|<>|>=|<=|>|<)\s*(-?\d+(?:\.\d+)?)\s*$", re.I)


def perm(type_code: str, action: str) -> str:
    return f"requests.{type_code}.{action}"


# ---------------------------------------------------------------- requests of one type

def list_requests(db: Db, ctx: RequestContext, type_code: str, filters: dict[str, Any], page: int, page_size: int):
    if filters["view"] not in VIEWS:
        raise invalid("view must be my, subordinates or all.", "view")
    if filters["status"] is not None and filters["status"] not in STATUSES:
        raise invalid("Unknown status.", "status")
    _check_flow_step(filters)
    return requests_repo.list_requests(db, ctx.company_id, ctx.user_id, type_code, perm(type_code, "view"), filters,
                                       page, page_size)


def get_request(db: Db, ctx: RequestContext, request_id: int, type_code: str | None,
                permission_code: str | None):
    return requests_repo.get_request(db, ctx.company_id, ctx.user_id, request_id, type_code, permission_code)


def _check_header(type_code: str, body: RequestIn) -> None:
    if type_code in REASON_REQUIRED and not (body.reason or "").strip():
        raise invalid("Reason is required.", "reason")
    if body.from_date and body.to_date and body.to_date < body.from_date:
        raise invalid("End date must be on or after the start date.", "toDate")


def _details_json(body: RequestIn) -> str:
    return json.dumps(body.details.model_dump(mode="json", by_alias=False))


def submit(db: Db, ctx: RequestContext, type_code: str, body: RequestIn):
    _check_header(type_code, body)
    files = sorted(set(body.attachments))
    request_id = requests_repo.submit(db, ctx.company_id, ctx.user_id, type_code, perm(type_code, "create"),
                                      body.employee_id, body.from_date, body.to_date, body.reason, body.description,
                                      body.application, _details_json(body), json.dumps(files))
    return get_request(db, ctx, request_id, type_code, perm(type_code, "view"))


def update(db: Db, ctx: RequestContext, type_code: str, request_id: int, body: RequestIn, row_version: bytes):
    _check_header(type_code, body)
    requests_repo.update(db, ctx.company_id, ctx.user_id, request_id, type_code, perm(type_code, "create"),
                         body.from_date, body.to_date, body.reason, body.description, body.application,
                         _details_json(body), row_version)
    return get_request(db, ctx, request_id, type_code, perm(type_code, "view"))


def delete(db: Db, ctx: RequestContext, type_code: str, request_id: int, row_version: bytes) -> None:
    requests_repo.delete(db, ctx.company_id, ctx.user_id, request_id, type_code, perm(type_code, "cancel"), row_version)


def cancel(db: Db, ctx: RequestContext, request_id: int, reason: str, row_version: bytes, type_code: str | None,
           dates: list[date] | None = None, start_time: time | None = None, end_time: time | None = None):
    """dates / start_time / end_time: a work from home cancellation's days and time range (R2). Stored with
    the cancellation and returned; they change nothing yet.
    TODO(R2): what cancelling a WFH day from-to a time means is an open product question; until it is
    answered the whole request is cancelled as before (usp_request_cancel also refuses them for other types,
    which covers the Approvals route where the type is not in the URL)."""
    given = bool(dates) or start_time is not None or end_time is not None
    if given and type_code is not None and type_code != "work_from_home":
        raise invalid("Dates and times can only be given when cancelling a work from home request.", "dates")
    if start_time is not None and end_time is not None and end_time <= start_time:
        raise invalid("End time must be after the start time.", "endTime")
    requests_repo.cancel(db, ctx.company_id, ctx.user_id, request_id, reason, row_version, type_code,
                         perm(type_code, "cancel") if type_code else None,
                         json.dumps(sorted({d.isoformat() for d in dates})) if dates else None, start_time, end_time)
    return get_request(db, ctx, request_id, type_code, perm(type_code, "view") if type_code else None)


def add_attachment(db: Db, ctx: RequestContext, type_code: str, request_id: int, file_id: int, label: str | None):
    return requests_repo.add_attachment(db, ctx.company_id, ctx.user_id, request_id, type_code,
                                        perm(type_code, "create"), file_id, label)


def delete_attachment(db: Db, ctx: RequestContext, type_code: str, request_id: int, attachment_id: int) -> None:
    requests_repo.delete_attachment(db, ctx.company_id, ctx.user_id, request_id, type_code, perm(type_code, "create"),
                                    attachment_id)


# ---------------------------------------------------------------- approvals

def list_approvals(db: Db, ctx: RequestContext, filters: dict[str, Any], page: int, page_size: int):
    if filters["box"] not in BOXES:
        raise invalid("box must be requested, delegates, consents or cancellations.", "box")
    if filters["status"] is not None and filters["status"] not in STATUSES:
        raise invalid("Unknown status.", "status")
    _check_flow_step(filters)
    return requests_repo.list_approvals(db, ctx.company_id, ctx.user_id, filters, page, page_size)


def decide(db: Db, ctx: RequestContext, request_id: int, action: str, remarks: str | None,
           details: dict[str, Any] | None, row_version: bytes):
    requests_repo.decide(db, ctx.company_id, ctx.user_id, request_id, action, remarks,
                         json.dumps(details) if details else None, row_version)
    return get_request(db, ctx, request_id, None, None)


def forward(db: Db, ctx: RequestContext, request_id: int, employee_id: int, remarks: str | None, row_version: bytes):
    requests_repo.forward(db, ctx.company_id, ctx.user_id, request_id, employee_id, remarks, row_version)
    return get_request(db, ctx, request_id, None, None)


def bulk_decide(db: Db, ctx: RequestContext, action: str, items: list[tuple[int, bytes, dict[str, Any] | None]],
                remarks: str | None) -> list[dict[str, Any]]:
    """Each request is decided on its own; one refusal does not stop the others (APR-9). An item's details
    are what the single approve takes (overtime approvedMinutes ...)."""
    results = []
    for request_id, row_version, details in items:
        try:
            # What the item does not give, the procedure prefills as the approval form would (a loan's amount,
            # payment method and repayment date).
            requests_repo.decide(db, ctx.company_id, ctx.user_id, request_id, action, remarks,
                                 json.dumps(details) if details else None, row_version, prefill=True)
            head, _, _ = get_request(db, ctx, request_id, None, None)
            results.append({"id": request_id, "ok": True, "status": head["status"]})
        except AppError as e:
            results.append({"id": request_id, "ok": False, "code": e.code, "message": e.message})
    return results


# ---------------------------------------------------------------- writing the application with AI (R1)

def generate_application(db: Db, ctx: RequestContext, type_code: str, body) -> tuple[str, datetime]:
    """503 AI_UNAVAILABLE until a model is connected (app/core/ai.py)."""
    ai.ensure_available()
    if not any([(body.reason or "").strip(), (body.description or "").strip(), body.details, body.from_date]):
        raise invalid("Fill in the form first: there is nothing to write the application from.", "reason")
    # TODO(R1): when a provider is connected: check body.employee_id is reached by perm(type_code, "create"),
    # write the prompt from the type's fields (tone, language), call the model and keep only <p>, <ul>, <li>,
    # <strong> in the answer. Nothing is stored; the text goes into the request's `application` on save.
    raise AppError(503, "AI_UNAVAILABLE", "Writing request applications with AI is not built yet.")


# ---------------------------------------------------------------- overtime: bulk filing

class _DryRun(Exception):
    """Raised inside a transaction to roll back a trial filing."""


def bulk_overtime(db: Db, ctx: RequestContext, body: OvertimeBulkIn) -> tuple[int, list[dict[str, Any]]]:
    """Files one overtime request per person on their behalf, all or nothing. Each person is tried first
    (filed and rolled back) so every refusal is reported at once: 422 BULK_REFUSED with fieldErrors
    `employeeIds.<id>`. Then all are filed in one transaction with the bulk row (a refusal there still files
    nobody). Returns the bulk id and the new requests' rows."""
    if body.to_date is not None and body.to_date != body.from_date:
        raise invalid("A bulk overtime request is for one day: To must be the same day as From.", "toDate")
    if len(set(body.employee_ids)) != len(body.employee_ids):
        raise invalid("Each employee can be chosen once.", "employeeIds")
    if not body.reason.strip():
        raise invalid("Reason is required.", "reason")
    code, create = "overtime", perm("overtime", "create")
    details = body.details.model_dump(mode="json", by_alias=False)
    details["overtime_type"] = body.overtime_type
    files = json.dumps(sorted(set(body.attachments)))

    def file_one(employee_id: int, bulk_id: int | None) -> int:
        return requests_repo.submit(db, ctx.company_id, ctx.user_id, code, create, employee_id, body.from_date,
                                    body.from_date, body.reason, body.description, body.application,
                                    json.dumps({**details, "bulk_id": bulk_id}), files)

    refused: dict[str, str] = {}
    for employee_id in body.employee_ids:
        try:
            with db.transaction():
                file_one(employee_id, None)
                raise _DryRun
        except _DryRun:
            pass
        except AppError as e:
            refused[f"employeeIds.{employee_id}"] = e.message
    if refused:
        raise AppError(422, "BULK_REFUSED", f"{len(refused)} of the chosen people cannot have this overtime request, "
                                            "so nobody was filed.", refused)

    # A refusal here (something changed since the trial) rolls everything back: still nobody is filed.
    with db.transaction():
        bulk_id = requests_repo.add_bulk(db, ctx.company_id, ctx.user_id, code, len(body.employee_ids), body.reason)
        ids = [file_one(employee_id, bulk_id) for employee_id in body.employee_ids]
    return bulk_id, [get_request(db, ctx, i, code, create)[0] for i in ids]


# ---------------------------------------------------------------- settings: flows

def _parse_expression(text: str | None, field: str) -> tuple[str, str, float]:
    m = _EXPRESSION.match(text or "")
    if not m:
        raise invalid("A condition is written as <field> <operator> <number>, for example: days > 3. Fields: days, "
                      "amount, minutes, department_id, branch_id, location_id, grade_id, designation_id, "
                      "employment_type_id.", field)
    op = {"==": "=", "!=": "<>"}.get(m.group(2), m.group(2))
    return m.group(1).lower(), op, float(m.group(3))


def check_flow_nodes(nodes: list[FlowNodeIn]) -> list[dict[str, Any]]:
    """The node editor's rules: unique numbers, valid approvers and expressions, links that point
    at nodes of the flow, someone who decides, and no loop. Returns the nodes for the procedure."""
    steps = sorted(n.step_no for n in nodes)
    if len(set(steps)) != len(steps):
        raise invalid("Each node needs its own number.", "nodes")
    by_step = {n.step_no: n for n in nodes}
    out, edges = [], {}
    for i, n in enumerate(nodes):
        where = f"nodes[{i}]"
        cond = None
        if n.is_condition:
            cond = _parse_expression(n.expression, f"{where}.expression")
        else:
            kind = n.approver_kind or ""
            if kind not in STRUCTURAL_APPROVERS and kind not in AUTHORITIES:
                raise invalid("Choose who decides at this node.", f"{where}.approverKind")
            if kind == "employee" and n.employee_id is None:
                raise invalid("Choose the employee.", f"{where}.employeeId")
            if kind == "role" and n.role_id is None:
                raise invalid("Choose the role.", f"{where}.roleId")
        for link in ("next", "if_true", "if_false"):
            target = getattr(n, link)
            if target is not None and target not in by_step:
                raise invalid(f"Node {n.step_no} points at node {target}, which does not exist.", f"{where}.{link}")
        following = next((s for s in steps if s > n.step_no), None)
        if n.is_condition:
            edges[n.step_no] = [x for x in (n.if_true or following, n.if_false or following) if x is not None]
        else:
            edges[n.step_no] = [x for x in (n.next or following,) if x is not None]
        out.append({"step_no": n.step_no, "approver_kind": None if n.is_condition else n.approver_kind,
                    "approver_employee_id": n.employee_id, "role_id": n.role_id, "is_condition": n.is_condition,
                    "expression": (n.expression or "").strip() or None,
                    "condition_field": cond[0] if cond else None, "condition_operator": cond[1] if cond else None,
                    "condition_value": cond[2] if cond else None, "next_step": n.next, "true_step": n.if_true,
                    "false_step": n.if_false, "can_edit": n.can_edit, "can_disagree": n.can_disagree,
                    "is_observer": n.is_observer})
    if not any(not n.is_condition and not n.is_observer for n in nodes):
        raise invalid("A flow needs at least one node where someone decides.", "nodes")
    # Loops: a walk must always reach the end.
    state: dict[int, int] = {}

    def visit(s: int) -> None:
        state[s] = 1
        for t in edges.get(s, []):
            if state.get(t) == 1:
                raise invalid(f"The flow goes round in a loop through node {t}.", "nodes")
            if t not in state:
                visit(t)
        state[s] = 2

    for s in steps:
        if s not in state:
            visit(s)
    return out


def save_flow(db: Db, ctx: RequestContext, flow_id: int | None, body, row_version: bytes | None):
    nodes = check_flow_nodes(body.nodes)
    if body.scope_type != "company" and body.scope_id is None:
        raise invalid("Choose the branch, department or employee this flow is for.", "scopeId")
    new_id = requests_repo.save_flow(db, ctx.company_id, ctx.user_id, flow_id, body.request_type, body.purpose,
                                     body.name, body.scope_type, body.scope_id, body.description, body.is_active,
                                     json.dumps(nodes), row_version)
    return requests_repo.get_flow(db, ctx.company_id, new_id)


def save_delegation(db: Db, ctx: RequestContext, body) -> dict[str, Any]:
    if body.delegator_id == body.delegatee_id:
        raise invalid("The delegator and the delegatee cannot be the same person.", "delegateeId")
    return requests_repo.save_delegation(db, ctx.company_id, ctx.user_id, None, body.delegator_id, body.delegatee_id,
                                         body.request_type, body.description, body.is_active, None)


def patch_delegation(db: Db, ctx: RequestContext, delegation_id: int, is_active: bool, description: str | None,
                     row_version: bytes) -> dict[str, Any]:
    return requests_repo.save_delegation(db, ctx.company_id, ctx.user_id, delegation_id, None, None, None,
                                         description, is_active, row_version)


def delete_delegation(db: Db, ctx: RequestContext, delegation_id: int, row_version: bytes) -> None:
    requests_repo.delete_delegation(db, ctx.company_id, ctx.user_id, delegation_id, row_version)


def list_delegations(db: Db, ctx: RequestContext, delegator_id: int | None, delegatee_id: int | None,
                     type_code: str | None, is_active: bool | None, search: str | None, page: int, page_size: int):
    return requests_repo.list_delegations(db, ctx.company_id, delegator_id, delegatee_id, type_code, is_active,
                                          search, page, page_size)


def get_delegation(db: Db, ctx: RequestContext, delegation_id: int) -> dict[str, Any]:
    return requests_repo.get_delegation(db, ctx.company_id, delegation_id)


def request_types(db: Db) -> list[dict[str, Any]]:
    return requests_repo.request_types(db)


def list_restrictions(db: Db, ctx: RequestContext, type_code, start_from, start_to, end_from, end_to, page, page_size):
    return requests_repo.list_restrictions(db, ctx.company_id, type_code, start_from, start_to, end_from, end_to,
                                           page, page_size)


def get_restriction(db: Db, ctx: RequestContext, restriction_id: int) -> dict[str, Any]:
    return requests_repo.get_restriction(db, ctx.company_id, restriction_id)


def save_restriction(db: Db, ctx: RequestContext, restriction_id: int | None, body,
                     row_version: bytes | None) -> dict[str, Any]:
    if body.end_date < body.start_date:
        raise invalid("End date must be on or after the start date.", "endDate")
    return requests_repo.save_restriction(db, ctx.company_id, ctx.user_id, restriction_id, body.request_type,
                                          body.start_date, body.end_date, body.description, row_version)


def delete_restriction(db: Db, ctx: RequestContext, restriction_id: int, row_version: bytes) -> None:
    requests_repo.delete_restriction(db, ctx.company_id, ctx.user_id, restriction_id, row_version)


def list_flows(db: Db, ctx: RequestContext, type_code, purpose, scope_type, page, page_size):
    return requests_repo.list_flows(db, ctx.company_id, type_code, purpose, scope_type, page, page_size)


def get_flow(db: Db, ctx: RequestContext, flow_id: int):
    return requests_repo.get_flow(db, ctx.company_id, flow_id)


def delete_flow(db: Db, ctx: RequestContext, flow_id: int, row_version: bytes) -> None:
    requests_repo.delete_flow(db, ctx.company_id, ctx.user_id, flow_id, row_version)


def list_authorities(db: Db, ctx: RequestContext, authority, type_code, employee_id, page, page_size):
    return requests_repo.list_authorities(db, ctx.company_id, authority, type_code, employee_id, page, page_size)


def save_authority(db: Db, ctx: RequestContext, authority_id: int | None, body, row_version: bytes | None):
    return requests_repo.save_authority(db, ctx.company_id, ctx.user_id, authority_id, body.authority,
                                        body.employee_id, body.request_type, body.branch_id, body.department_id,
                                        body.description, body.is_active, row_version)


def delete_authority(db: Db, ctx: RequestContext, authority_id: int, row_version: bytes) -> None:
    requests_repo.delete_authority(db, ctx.company_id, ctx.user_id, authority_id, row_version)


# ---------------------------------------------------------------- settings: expense categories, reimbursement

def list_expense_categories(db: Db, ctx: RequestContext, search: str | None, is_active: bool | None, page: int,
                            page_size: int):
    return requests_repo.list_expense_categories(db, ctx.company_id, search, is_active, page, page_size)


def get_expense_category(db: Db, ctx: RequestContext, category_id: int) -> dict[str, Any]:
    return requests_repo.get_expense_category(db, ctx.company_id, category_id)


def save_expense_category(db: Db, ctx: RequestContext, category_id: int | None, body,
                          row_version: bytes | None) -> dict[str, Any]:
    return requests_repo.save_expense_category(db, ctx.company_id, ctx.user_id, category_id, body.name.strip(),
                                               body.pay_item_id, body.max_amount, body.receipt_required,
                                               body.is_active, body.description, row_version)


def delete_expense_category(db: Db, ctx: RequestContext, category_id: int, row_version: bytes) -> None:
    requests_repo.delete_expense_category(db, ctx.company_id, ctx.user_id, category_id, row_version)


def get_reimbursement(db: Db, ctx: RequestContext) -> dict[str, Any]:
    return requests_repo.get_reimbursement(db, ctx.company_id)


def save_reimbursement(db: Db, ctx: RequestContext, body) -> dict[str, Any]:
    return requests_repo.save_reimbursement(db, ctx.company_id, ctx.user_id, body.expense_pay_item_id,
                                            body.air_ticket_pay_item_id)


# ---------------------------------------------------------------- self-service options of the request forms

def option_leave_types(db: Db, ctx: RequestContext, employee_id: int | None, as_of: date | None) -> list[dict[str, Any]]:
    """Leave types the employee (the caller's own record when none is given) may apply for; the caller's
    leave create permission must reach that employee."""
    return requests_repo.option_leave_types(db, ctx.company_id, ctx.user_id, employee_id or ctx.employee_id,
                                            perm("leave", "create"), as_of)


def option_loan_types(db: Db, ctx: RequestContext, employee_id: int | None) -> list[dict[str, Any]]:
    return requests_repo.option_loan_types(db, ctx.company_id, employee_id or ctx.employee_id)


def option_loan_categories(db: Db, ctx: RequestContext) -> list[dict[str, Any]]:
    return requests_repo.option_loan_categories(db, ctx.company_id)


def option_colleagues(db: Db, ctx: RequestContext, employee_id: int | None, search: str | None, page: int,
                      page_size: int):
    """Everyone in the company but the requester (the caller when no employee is given)."""
    return requests_repo.option_colleagues(db, ctx.company_id, employee_id or ctx.employee_id, search, page, page_size)
