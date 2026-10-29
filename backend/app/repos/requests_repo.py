"""Requests data access. The only layer that knows the req.* procedure names and parameters.
Procedures that write and may run another module's hook (submit, decide, cancel) return nothing
the caller relies on except their last result set; the service reads the request again after."""
from datetime import date, time
from typing import Any

from app.core.db import Db


def _last_id(sets: list[list[dict[str, Any]]]) -> int:
    return int(sets[-1][0]["id"])


def request_types(db: Db) -> list[dict[str, Any]]:
    return db.call("req.usp_request_type_list")


def list_requests(db: Db, company_id: int, actor_user_id: int, type_code: str, permission_code: str,
                  f: dict[str, Any], page: int, page_size: int) -> tuple[int, list[dict[str, Any]], list[dict[str, Any]]]:
    total, rows, counts = db.call_sets(
        "req.usp_request_list", company_id=company_id, actor_user_id=actor_user_id, type_code=type_code,
        permission_code=permission_code, view=f["view"], status=f["status"], search=f["search"],
        employee_id=f["employee_id"], department_id=f["department_id"], branch_id=f["branch_id"],
        location_id=f["location_id"], date_from=f["date_from"], date_to=f["date_to"], flow_step=f.get("flow_step"),
        bulk=f.get("bulk"), page=page, page_size=page_size)
    return total[0]["total"], rows, counts


def get_request(db: Db, company_id: int, actor_user_id: int, request_id: int, type_code: str | None,
                permission_code: str | None) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    head, steps, files = db.call_sets("req.usp_request_get", company_id=company_id, actor_user_id=actor_user_id,
                                      id=request_id, type_code=type_code, permission_code=permission_code)
    return head[0], steps, files


def submit(db: Db, company_id: int, actor_user_id: int, type_code: str, permission_code: str,
           employee_id: int | None, from_date: date | None, to_date: date | None, reason: str | None,
           description: str | None, application: str | None, details: str, attachments: str) -> int:
    return _last_id(db.call_sets(
        "req.usp_request_submit", company_id=company_id, actor_user_id=actor_user_id, type_code=type_code,
        permission_code=permission_code, employee_id=employee_id, from_date=from_date, to_date=to_date,
        reason=reason, description=description, application=application, details=details, attachments=attachments))


def update(db: Db, company_id: int, actor_user_id: int, request_id: int, type_code: str, permission_code: str,
           from_date: date | None, to_date: date | None, reason: str | None, description: str | None,
           application: str | None, details: str, row_version: bytes) -> None:
    db.call_sets("req.usp_request_update", company_id=company_id, actor_user_id=actor_user_id, id=request_id,
                 type_code=type_code, permission_code=permission_code, from_date=from_date, to_date=to_date,
                 reason=reason, description=description, application=application, details=details,
                 row_version=row_version)


def delete(db: Db, company_id: int, actor_user_id: int, request_id: int, type_code: str, permission_code: str,
           row_version: bytes) -> None:
    db.call("req.usp_request_delete", company_id=company_id, actor_user_id=actor_user_id, id=request_id,
            type_code=type_code, permission_code=permission_code, row_version=row_version)


def cancel(db: Db, company_id: int, actor_user_id: int, request_id: int, reason: str, row_version: bytes,
           type_code: str | None, permission_code: str | None, cancel_dates: str | None = None,
           cancel_start_time: time | None = None, cancel_end_time: time | None = None) -> None:
    db.call_sets("req.usp_request_cancel", company_id=company_id, actor_user_id=actor_user_id, id=request_id,
                 reason=reason, row_version=row_version, type_code=type_code, permission_code=permission_code,
                 cancel_dates=cancel_dates, cancel_start_time=cancel_start_time, cancel_end_time=cancel_end_time)


def add_bulk(db: Db, company_id: int, actor_user_id: int, type_code: str, request_count: int,
             reason: str | None) -> int:
    return _last_id(db.call_sets("req.usp_request_bulk_add", company_id=company_id, actor_user_id=actor_user_id,
                                 type_code=type_code, request_count=request_count, reason=reason))


def decide(db: Db, company_id: int, actor_user_id: int, request_id: int, action: str, remarks: str | None,
           details: str | None, row_version: bytes, prefill: bool = False) -> None:
    db.call_sets("req.usp_request_decide", company_id=company_id, actor_user_id=actor_user_id, id=request_id,
                 action=action, remarks=remarks, details=details, row_version=row_version, prefill=prefill)


def forward(db: Db, company_id: int, actor_user_id: int, request_id: int, to_employee_id: int, remarks: str | None,
            row_version: bytes) -> None:
    db.call("req.usp_request_forward", company_id=company_id, actor_user_id=actor_user_id, id=request_id,
            to_employee_id=to_employee_id, remarks=remarks, row_version=row_version)


def list_approvals(db: Db, company_id: int, actor_user_id: int, f: dict[str, Any], page: int,
                   page_size: int) -> tuple[int, list[dict[str, Any]], list[dict[str, Any]]]:
    total, rows, counts = db.call_sets(
        "req.usp_request_approval_list", company_id=company_id, actor_user_id=actor_user_id, box=f["box"],
        type_code=f["type_code"], status=f["status"], delegator_id=f["delegator_id"], search=f["search"],
        employee_id=f["employee_id"], department_id=f["department_id"], branch_id=f["branch_id"],
        location_id=f["location_id"], date_from=f["date_from"], date_to=f["date_to"], flow_step=f.get("flow_step"),
        page=page, page_size=page_size)
    return total[0]["total"], rows, counts


def add_attachment(db: Db, company_id: int, actor_user_id: int, request_id: int, type_code: str,
                   permission_code: str, file_id: int, label: str | None) -> dict[str, Any]:
    return db.call_sets("req.usp_request_attachment_add", company_id=company_id, actor_user_id=actor_user_id,
                        id=request_id, type_code=type_code, permission_code=permission_code, file_id=file_id,
                        label=label)[-1][0]


def delete_attachment(db: Db, company_id: int, actor_user_id: int, request_id: int, type_code: str,
                      permission_code: str, attachment_id: int) -> None:
    db.call("req.usp_request_attachment_delete", company_id=company_id, actor_user_id=actor_user_id, id=request_id,
            type_code=type_code, permission_code=permission_code, attachment_id=attachment_id)


# ---------------------------------------------------------------- settings

def list_restrictions(db: Db, company_id: int, type_code: str | None, start_from: date | None, start_to: date | None,
                      end_from: date | None, end_to: date | None, page: int, page_size: int):
    total, rows = db.call_sets("req.usp_request_restriction_list", company_id=company_id, type_code=type_code,
                               start_from=start_from, start_to=start_to, end_from=end_from, end_to=end_to,
                               page=page, page_size=page_size)
    return total[0]["total"], rows


def get_restriction(db: Db, company_id: int, restriction_id: int) -> dict[str, Any]:
    return db.call_one("req.usp_request_restriction_get", company_id=company_id, id=restriction_id)


def save_restriction(db: Db, company_id: int, actor_user_id: int, restriction_id: int | None, type_code: str,
                     start_date: date, end_date: date, description: str | None,
                     row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("req.usp_request_restriction_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=restriction_id, type_code=type_code, start_date=start_date, end_date=end_date,
                       description=description, row_version=row_version)


def delete_restriction(db: Db, company_id: int, actor_user_id: int, restriction_id: int, row_version: bytes) -> None:
    db.call("req.usp_request_restriction_delete", company_id=company_id, actor_user_id=actor_user_id,
            id=restriction_id, row_version=row_version)


def list_delegations(db: Db, company_id: int, delegator_id: int | None, delegatee_id: int | None,
                     type_code: str | None, is_active: bool | None, search: str | None, page: int, page_size: int):
    total, rows = db.call_sets("req.usp_delegation_list", company_id=company_id, delegator_id=delegator_id,
                               delegatee_id=delegatee_id, type_code=type_code, is_active=is_active, search=search,
                               page=page, page_size=page_size)
    return total[0]["total"], rows


def get_delegation(db: Db, company_id: int, delegation_id: int) -> dict[str, Any]:
    return db.call_one("req.usp_delegation_get", company_id=company_id, id=delegation_id)


def save_delegation(db: Db, company_id: int, actor_user_id: int, delegation_id: int | None, delegator_id: int | None,
                    delegatee_id: int | None, type_code: str | None, description: str | None, is_active: bool,
                    row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("req.usp_delegation_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=delegation_id, delegator_id=delegator_id, delegatee_id=delegatee_id, type_code=type_code,
                       description=description, is_active=is_active, row_version=row_version)


def delete_delegation(db: Db, company_id: int, actor_user_id: int, delegation_id: int, row_version: bytes) -> None:
    db.call("req.usp_delegation_delete", company_id=company_id, actor_user_id=actor_user_id, id=delegation_id,
            row_version=row_version)


# ---------------------------------------------------------------- self-service options of the request forms

def option_leave_types(db: Db, company_id: int, actor_user_id: int, employee_id: int | None, permission_code: str,
                       as_of: date | None) -> list[dict[str, Any]]:
    return db.call("req.usp_request_option_leave_types", company_id=company_id, actor_user_id=actor_user_id,
                   employee_id=employee_id, permission_code=permission_code, as_of=as_of)


def option_loan_types(db: Db, company_id: int, employee_id: int | None) -> list[dict[str, Any]]:
    return db.call("req.usp_request_option_loan_types", company_id=company_id, employee_id=employee_id)


def option_loan_categories(db: Db, company_id: int) -> list[dict[str, Any]]:
    return db.call("req.usp_request_option_loan_categories", company_id=company_id)


def option_colleagues(db: Db, company_id: int, employee_id: int | None, search: str | None, page: int,
                      page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("req.usp_request_option_colleagues", company_id=company_id, employee_id=employee_id,
                               search=search, page=page, page_size=page_size)
    return total[0]["total"], rows


def list_flows(db: Db, company_id: int, type_code: str | None, purpose: str | None, scope_type: str | None,
               page: int, page_size: int):
    total, rows = db.call_sets("req.usp_approval_flow_list", company_id=company_id, type_code=type_code,
                               purpose=purpose, scope_type=scope_type, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_flow(db: Db, company_id: int, flow_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    head, nodes = db.call_sets("req.usp_approval_flow_get", company_id=company_id, id=flow_id)
    return head[0], nodes


def save_flow(db: Db, company_id: int, actor_user_id: int, flow_id: int | None, type_code: str, purpose: str,
              name: str, scope_type: str, scope_id: int | None, description: str | None, is_active: bool,
              nodes: str, row_version: bytes | None) -> int:
    return _last_id(db.call_sets(
        "req.usp_approval_flow_save", company_id=company_id, actor_user_id=actor_user_id, id=flow_id,
        type_code=type_code, purpose=purpose, name=name, scope_type=scope_type, scope_id=scope_id,
        description=description, is_active=is_active, nodes=nodes, row_version=row_version))


def delete_flow(db: Db, company_id: int, actor_user_id: int, flow_id: int, row_version: bytes) -> None:
    db.call("req.usp_approval_flow_delete", company_id=company_id, actor_user_id=actor_user_id, id=flow_id,
            row_version=row_version)


def list_authorities(db: Db, company_id: int, authority: str | None, type_code: str | None, employee_id: int | None,
                     page: int, page_size: int):
    total, rows = db.call_sets("req.usp_approval_authority_list", company_id=company_id, authority=authority,
                               type_code=type_code, employee_id=employee_id, page=page, page_size=page_size)
    return total[0]["total"], rows


def save_authority(db: Db, company_id: int, actor_user_id: int, authority_id: int | None, authority: str,
                   employee_id: int, type_code: str | None, branch_id: int | None, department_id: int | None,
                   description: str | None, is_active: bool, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("req.usp_approval_authority_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=authority_id, authority=authority, employee_id=employee_id, type_code=type_code,
                       branch_id=branch_id, department_id=department_id, description=description,
                       is_active=is_active, row_version=row_version)


def delete_authority(db: Db, company_id: int, actor_user_id: int, authority_id: int, row_version: bytes) -> None:
    db.call("req.usp_approval_authority_delete", company_id=company_id, actor_user_id=actor_user_id,
            id=authority_id, row_version=row_version)


def list_expense_categories(db: Db, company_id: int, search: str | None, is_active: bool | None, page: int,
                            page_size: int):
    total, rows = db.call_sets("req.usp_expense_category_list", company_id=company_id, search=search,
                               is_active=is_active, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_expense_category(db: Db, company_id: int, category_id: int) -> dict[str, Any]:
    return db.call_one("req.usp_expense_category_get", company_id=company_id, id=category_id)


def save_expense_category(db: Db, company_id: int, actor_user_id: int, category_id: int | None, name: str,
                          pay_item_id: int | None, max_amount, receipt_required: bool, is_active: bool,
                          description: str | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_sets("req.usp_expense_category_save", company_id=company_id, actor_user_id=actor_user_id,
                        id=category_id, name=name, pay_item_id=pay_item_id, max_amount=max_amount,
                        receipt_required=receipt_required, is_active=is_active, description=description,
                        row_version=row_version)[-1][0]


def delete_expense_category(db: Db, company_id: int, actor_user_id: int, category_id: int, row_version: bytes) -> None:
    db.call("req.usp_expense_category_delete", company_id=company_id, actor_user_id=actor_user_id, id=category_id,
            row_version=row_version)


def get_reimbursement(db: Db, company_id: int) -> dict[str, Any]:
    return db.call_one("req.usp_reimbursement_setting_get", company_id=company_id)


def save_reimbursement(db: Db, company_id: int, actor_user_id: int, expense_pay_item_id: int | None,
                       air_ticket_pay_item_id: int | None) -> dict[str, Any]:
    return db.call_sets("req.usp_reimbursement_setting_save", company_id=company_id, actor_user_id=actor_user_id,
                        expense_pay_item_id=expense_pay_item_id,
                        air_ticket_pay_item_id=air_ticket_pay_item_id)[-1][0]
