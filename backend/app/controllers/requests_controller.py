"""HTTP shape for the Requests screens: envelopes, row versions as text, rows to response models.
A request's kind-specific part arrives from the database as JSON with snake_case keys; it is sent
on with camelCase keys and ids as strings, like every other body. Files are never exposed by path:
each attachment, and each `fileId` inside the details, comes with a signed `url` / `fileUrl`."""
import csv
import io
import json
from typing import Any

from pydantic.alias_generators import to_camel

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.requests import (AttachmentIn, AttachmentOut, AuthorityIn, AuthorityOut, BulkDecisionIn,
                                  BulkResultOut, CancelIn, ColleagueOptionOut, ConsentIn, DecisionIn, DelegationIn,
                                  DelegationOut, DelegationPatch, ExpenseCategoryIn, ExpenseCategoryOut, FlowDetailOut,
                                  FlowIn, FlowNodeOut, FlowOut, ForwardIn, LeaveTypeOptionOut, LoanCategoryOptionOut,
                                  LoanTypeOptionOut, ReimbursementSettingIn, ReimbursementSettingOut,
                                  RequestDetailOut, RequestIn, RequestOut, RequestTypeOut, RestrictionIn,
                                  RestrictionOut, StepOut)
from app.services import requests_service as svc


def _camel(value: Any) -> Any:
    if isinstance(value, dict):
        return {to_camel(k): (str(v) if isinstance(v, int) and not isinstance(v, bool) and (k == "id" or k.endswith("_id"))
                              else _camel(v)) for k, v in value.items()}
    if isinstance(value, list):
        return [_camel(v) for v in value]
    return value


def _with_links(value: Any, company_id: int) -> Any:
    """Adds a signed fileUrl next to every fileId in the (camelCase) details."""
    if isinstance(value, dict):
        out = {k: _with_links(v, company_id) for k, v in value.items()}
        if "fileId" in out:
            out["fileUrl"] = file_url(out["fileId"], company_id)
        return out
    if isinstance(value, list):
        return [_with_links(v, company_id) for v in value]
    return value


def _pick(model, row: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in row.items() if k in model.model_fields}


def _request(row: dict[str, Any], company_id: int) -> RequestOut:
    details = _with_links(_camel(json.loads(row["details_json"])), company_id) if row.get("details_json") else {}
    return RequestOut(**{**_pick(RequestOut, row), "details": details,
                         "row_version": row_version_out(row["row_version"])})


def _attachment(row: dict[str, Any], company_id: int) -> AttachmentOut:
    return AttachmentOut(**{**_pick(AttachmentOut, row), "url": file_url(row["file_id"], company_id)})


def _actions(head: dict[str, Any], side: str) -> list[str]:
    """What the caller may do on the request now. side "requester": the request type's own screens
    (edit / delete / cancel for the requester side, plus the decision of a step the caller holds).
    side "approver": the Approvals screen, which offers only the decision the caller's pending step
    allows (approve / reject / forward, or consent / disagree), and edit when that flow node grants
    Can Edit; never the requester's edit, delete or cancel."""
    actions = ["view"]
    if side == "requester":
        if head["status"] == "pending" and not head["has_decisions"]:
            actions += ["edit", "delete", "cancel"]
        elif head["status"] in ("pending", "approved"):
            actions.append("cancel")
    if head["my_step_id"] is not None:
        actions += ["consent", "disagree"] if head["my_step_is_consent"] else ["approve", "reject", "forward"]
        if head["my_step_can_edit"] and "edit" not in actions:
            actions.append("edit")
    return actions


def _detail(ctx: RequestContext, parts: tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]],
            side: str = "requester") -> dict:
    head, steps, files = parts
    base = _request(head, ctx.company_id).model_dump(by_alias=False)
    return {"data": RequestDetailOut(**base, steps=[StepOut(**_pick(StepOut, s)) for s in steps],
                                     attachments=[_attachment(f, ctx.company_id) for f in files],
                                     actions=_actions(head, side))}


def _page_with_counts(ctx: RequestContext, total: int, rows, counts, paging: PageParams) -> dict:
    out = paginated(rows, total, paging.page, paging.page_size, lambda r: _request(r, ctx.company_id))
    out["counts"] = {c["status"]: c["total"] for c in counts}
    return out


# ---------------------------------------------------------------- one request type

def list_requests(db: Db, ctx: RequestContext, type_code: str, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows, counts = svc.list_requests(db, ctx, type_code, filters, paging.page, paging.page_size)
    return _page_with_counts(ctx, total, rows, counts, paging)


def export_requests(db: Db, ctx: RequestContext, type_code: str, filters: dict[str, Any]) -> str:
    _, rows, _ = svc.list_requests(db, ctx, type_code, filters, 1, 10000)
    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(["Code", "Employee code", "Employee", "Department", "From", "To", "Count", "Status", "Submitted",
                "Next requestee", "Approving authority"])
    for r in rows:
        w.writerow([r["code"], r["employee_code"], r["employee_name"], r["department_name"], r["from_date"],
                    r["to_date"], r["days"], r["status"], r["submitted_at"], r["next_approver_name"],
                    r["final_authority_name"]])
    return out.getvalue()


def get_request(db: Db, ctx: RequestContext, type_code: str, request_id: int) -> dict:
    return _detail(ctx, svc.get_request(db, ctx, request_id, type_code, svc.perm(type_code, "view")))


def create_request(db: Db, ctx: RequestContext, type_code: str, body: RequestIn) -> dict:
    return _detail(ctx, svc.submit(db, ctx, type_code, body))


def update_request(db: Db, ctx: RequestContext, type_code: str, request_id: int, body: RequestIn) -> dict:
    return _detail(ctx, svc.update(db, ctx, type_code, request_id, body, row_version_in(body.row_version)))


def delete_request(db: Db, ctx: RequestContext, type_code: str, request_id: int, row_version: str | None) -> None:
    svc.delete(db, ctx, type_code, request_id, row_version_in(row_version))


def cancel_request(db: Db, ctx: RequestContext, type_code: str | None, request_id: int, body: CancelIn) -> dict:
    return _detail(ctx, svc.cancel(db, ctx, request_id, body.reason, row_version_in(body.row_version), type_code),
                   "requester" if type_code else "approver")


def add_attachment(db: Db, ctx: RequestContext, type_code: str, request_id: int, body: AttachmentIn) -> dict:
    row = svc.add_attachment(db, ctx, type_code, request_id, body.file_id, body.label)
    return {"data": _attachment(row, ctx.company_id)}


def delete_attachment(db: Db, ctx: RequestContext, type_code: str, request_id: int, attachment_id: int) -> None:
    svc.delete_attachment(db, ctx, type_code, request_id, attachment_id)


def request_types(db: Db) -> dict:
    return {"data": [RequestTypeOut(**_pick(RequestTypeOut, r)) for r in svc.request_types(db)]}


# ---------------------------------------------------------------- approvals

def list_approvals(db: Db, ctx: RequestContext, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows, counts = svc.list_approvals(db, ctx, filters, paging.page, paging.page_size)
    return _page_with_counts(ctx, total, rows, counts, paging)


def get_approval(db: Db, ctx: RequestContext, request_id: int) -> dict:
    return _detail(ctx, svc.get_request(db, ctx, request_id, None, None), "approver")


def decide(db: Db, ctx: RequestContext, request_id: int, action: str, body: DecisionIn) -> dict:
    details = body.details.model_dump(mode="json", by_alias=False, exclude_none=True) if body.details else None
    return _detail(ctx, svc.decide(db, ctx, request_id, action, body.remarks, details,
                                   row_version_in(body.row_version)), "approver")


def consent(db: Db, ctx: RequestContext, request_id: int, body: ConsentIn) -> dict:
    return _detail(ctx, svc.decide(db, ctx, request_id, "consent" if body.agree else "disagree", body.remarks, None,
                                   row_version_in(body.row_version)), "approver")


def forward(db: Db, ctx: RequestContext, request_id: int, body: ForwardIn) -> dict:
    return _detail(ctx, svc.forward(db, ctx, request_id, body.employee_id, body.remarks,
                                    row_version_in(body.row_version)), "approver")


def bulk(db: Db, ctx: RequestContext, action: str, body: BulkDecisionIn) -> dict:
    items = [(i.id, row_version_in(i.row_version)) for i in body.items]
    return {"data": [BulkResultOut(**r) for r in svc.bulk_decide(db, ctx, action, items, body.remarks)]}


# ---------------------------------------------------------------- settings

def _restriction(row: dict[str, Any]) -> RestrictionOut:
    return RestrictionOut(**{**_pick(RestrictionOut, row), "row_version": row_version_out(row["row_version"])})


def list_restrictions(db: Db, ctx: RequestContext, type_code, start_from, start_to, end_from, end_to,
                      paging: PageParams) -> dict:
    total, rows = svc.list_restrictions(db, ctx, type_code, start_from, start_to, end_from, end_to, paging.page,
                                        paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _restriction)


def get_restriction(db: Db, ctx: RequestContext, restriction_id: int) -> dict:
    return {"data": _restriction(svc.get_restriction(db, ctx, restriction_id))}


def create_restriction(db: Db, ctx: RequestContext, body: RestrictionIn) -> dict:
    return {"data": _restriction(svc.save_restriction(db, ctx, None, body, None))}


def update_restriction(db: Db, ctx: RequestContext, restriction_id: int, body: RestrictionIn) -> dict:
    return {"data": _restriction(svc.save_restriction(db, ctx, restriction_id, body, row_version_in(body.row_version)))}


def delete_restriction(db: Db, ctx: RequestContext, restriction_id: int, row_version: str | None) -> None:
    svc.delete_restriction(db, ctx, restriction_id, row_version_in(row_version))


def _delegation(row: dict[str, Any]) -> DelegationOut:
    return DelegationOut(**{**_pick(DelegationOut, row), "row_version": row_version_out(row["row_version"])})


def list_delegations(db: Db, ctx: RequestContext, delegator_id, delegatee_id, type_code, is_active, q,
                     paging: PageParams) -> dict:
    total, rows = svc.list_delegations(db, ctx, delegator_id, delegatee_id, type_code, is_active, q, paging.page,
                                       paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _delegation)


def get_delegation(db: Db, ctx: RequestContext, delegation_id: int) -> dict:
    return {"data": _delegation(svc.get_delegation(db, ctx, delegation_id))}


def create_delegation(db: Db, ctx: RequestContext, body: DelegationIn) -> dict:
    return {"data": _delegation(svc.save_delegation(db, ctx, body))}


def patch_delegation(db: Db, ctx: RequestContext, delegation_id: int, body: DelegationPatch) -> dict:
    return {"data": _delegation(svc.patch_delegation(db, ctx, delegation_id, body.is_active, body.description,
                                                     row_version_in(body.row_version)))}


def delete_delegation(db: Db, ctx: RequestContext, delegation_id: int, row_version: str | None) -> None:
    svc.delete_delegation(db, ctx, delegation_id, row_version_in(row_version))


def _flow(row: dict[str, Any]) -> FlowOut:
    return FlowOut(**{**_pick(FlowOut, row), "row_version": row_version_out(row["row_version"])})


def _flow_detail(parts: tuple[dict[str, Any], list[dict[str, Any]]]) -> dict:
    head, nodes = parts
    out = [FlowNodeOut(id=n["id"], step_no=n["step_no"], approver_kind=n["approver_kind"],
                       employee_id=n["approver_employee_id"], employee_name=n["approver_employee_name"],
                       role_id=n["role_id"], role_name=n["role_name"], is_condition=n["is_condition"],
                       expression=n["expression"], next=n["next_step"], if_true=n["true_step"],
                       if_false=n["false_step"], can_edit=n["can_edit"], can_disagree=n["can_disagree"],
                       is_observer=n["is_observer"]) for n in nodes]
    return {"data": FlowDetailOut(**_flow(head).model_dump(by_alias=False), nodes=out)}


def list_flows(db: Db, ctx: RequestContext, type_code, purpose, scope_type, paging: PageParams) -> dict:
    total, rows = svc.list_flows(db, ctx, type_code, purpose, scope_type, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _flow)


def get_flow(db: Db, ctx: RequestContext, flow_id: int) -> dict:
    return _flow_detail(svc.get_flow(db, ctx, flow_id))


def create_flow(db: Db, ctx: RequestContext, body: FlowIn) -> dict:
    return _flow_detail(svc.save_flow(db, ctx, None, body, None))


def update_flow(db: Db, ctx: RequestContext, flow_id: int, body: FlowIn) -> dict:
    return _flow_detail(svc.save_flow(db, ctx, flow_id, body, row_version_in(body.row_version)))


def delete_flow(db: Db, ctx: RequestContext, flow_id: int, row_version: str | None) -> None:
    svc.delete_flow(db, ctx, flow_id, row_version_in(row_version))


def _authority(row: dict[str, Any]) -> AuthorityOut:
    return AuthorityOut(**{**_pick(AuthorityOut, row), "row_version": row_version_out(row["row_version"])})


def list_authorities(db: Db, ctx: RequestContext, authority, type_code, employee_id, paging: PageParams) -> dict:
    total, rows = svc.list_authorities(db, ctx, authority, type_code, employee_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _authority)


def create_authority(db: Db, ctx: RequestContext, body: AuthorityIn) -> dict:
    return {"data": _authority(svc.save_authority(db, ctx, None, body, None))}


def update_authority(db: Db, ctx: RequestContext, authority_id: int, body: AuthorityIn) -> dict:
    return {"data": _authority(svc.save_authority(db, ctx, authority_id, body, row_version_in(body.row_version)))}


def delete_authority(db: Db, ctx: RequestContext, authority_id: int, row_version: str | None) -> None:
    svc.delete_authority(db, ctx, authority_id, row_version_in(row_version))


def _category(row: dict[str, Any]) -> ExpenseCategoryOut:
    return ExpenseCategoryOut(**{**_pick(ExpenseCategoryOut, row), "row_version": row_version_out(row["row_version"])})


def list_expense_categories(db: Db, ctx: RequestContext, q: str | None, is_active: bool | None,
                            paging: PageParams) -> dict:
    total, rows = svc.list_expense_categories(db, ctx, q, is_active, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _category)


def get_expense_category(db: Db, ctx: RequestContext, category_id: int) -> dict:
    return {"data": _category(svc.get_expense_category(db, ctx, category_id))}


def create_expense_category(db: Db, ctx: RequestContext, body: ExpenseCategoryIn) -> dict:
    return {"data": _category(svc.save_expense_category(db, ctx, None, body, None))}


def update_expense_category(db: Db, ctx: RequestContext, category_id: int, body: ExpenseCategoryIn) -> dict:
    return {"data": _category(svc.save_expense_category(db, ctx, category_id, body, row_version_in(body.row_version)))}


def delete_expense_category(db: Db, ctx: RequestContext, category_id: int, row_version: str | None) -> None:
    svc.delete_expense_category(db, ctx, category_id, row_version_in(row_version))


def get_reimbursement(db: Db, ctx: RequestContext) -> dict:
    return {"data": ReimbursementSettingOut(**_pick(ReimbursementSettingOut, svc.get_reimbursement(db, ctx)))}


def save_reimbursement(db: Db, ctx: RequestContext, body: ReimbursementSettingIn) -> dict:
    return {"data": ReimbursementSettingOut(**_pick(ReimbursementSettingOut, svc.save_reimbursement(db, ctx, body)))}


# ---------------------------------------------------------------- self-service options of the request forms

def option_leave_types(db: Db, ctx: RequestContext, employee_id: int | None, as_of) -> dict:
    return {"data": [LeaveTypeOptionOut(**_pick(LeaveTypeOptionOut, r))
                     for r in svc.option_leave_types(db, ctx, employee_id, as_of)]}


def option_loan_types(db: Db, ctx: RequestContext, employee_id: int | None) -> dict:
    return {"data": [LoanTypeOptionOut(**_pick(LoanTypeOptionOut, r))
                     for r in svc.option_loan_types(db, ctx, employee_id)]}


def option_loan_categories(db: Db, ctx: RequestContext) -> dict:
    return {"data": [LoanCategoryOptionOut(**_pick(LoanCategoryOptionOut, r))
                     for r in svc.option_loan_categories(db, ctx)]}


def option_colleagues(db: Db, ctx: RequestContext, employee_id: int | None, q: str | None, paging: PageParams) -> dict:
    total, rows = svc.option_colleagues(db, ctx, employee_id, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size,
                     lambda r: ColleagueOptionOut(**_pick(ColleagueOptionOut, r)))
