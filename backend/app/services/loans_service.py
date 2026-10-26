"""Loan rules. Asking for a loan is a request (requests_service, type "loan"); the loan and its
schedule are made by loan.usp_request_apply_loan when that request is finally approved. This
service covers the settings and the loans themselves."""
import json
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import invalid
from app.middlewares.auth import RequestContext
from app.repos import loans_repo
from app.schemas.loans import LoanCategoryIn, LoanTypeIn

LOANS_VIEW = "loans.loans.view"
LOAN_STATUSES = ("active", "settled", "non_payable", "written_off")


def list_types(db: Db, ctx: RequestContext, search: str | None, is_active: bool | None, page: int, page_size: int):
    return loans_repo.list_types(db, ctx.company_id, search, is_active, page, page_size)


def get_type(db: Db, ctx: RequestContext, type_id: int) -> dict[str, Any]:
    return loans_repo.get_type(db, ctx.company_id, type_id)


def save_type(db: Db, ctx: RequestContext, type_id: int | None, body: LoanTypeIn, row_version: bytes | None):
    if not body.non_payable and body.deduction_pay_item_id is None:
        raise invalid("Choose the deduction pay item, or tick Non-Payable.", "deductionPayItemId")
    values = body.model_dump(by_alias=False, exclude={"employment_type_ids", "row_version"})
    return loans_repo.save_type(db, ctx.company_id, ctx.user_id, type_id, values,
                                json.dumps(sorted(set(body.employment_type_ids))), row_version)


def delete_type(db: Db, ctx: RequestContext, type_id: int, row_version: bytes) -> None:
    loans_repo.delete_type(db, ctx.company_id, ctx.user_id, type_id, row_version)


def list_categories(db: Db, ctx: RequestContext, search: str | None, is_active: bool | None, page: int,
                    page_size: int):
    return loans_repo.list_categories(db, ctx.company_id, search, is_active, page, page_size)


def get_category(db: Db, ctx: RequestContext, category_id: int) -> dict[str, Any]:
    return loans_repo.get_category(db, ctx.company_id, category_id)


def save_category(db: Db, ctx: RequestContext, category_id: int | None, body: LoanCategoryIn,
                  row_version: bytes | None) -> dict[str, Any]:
    return loans_repo.save_category(db, ctx.company_id, ctx.user_id, category_id, body.name, body.is_active,
                                    body.description, row_version)


def delete_category(db: Db, ctx: RequestContext, category_id: int, row_version: bytes) -> None:
    loans_repo.delete_category(db, ctx.company_id, ctx.user_id, category_id, row_version)


def list_loans(db: Db, ctx: RequestContext, view: str, status: str | None, loan_type_id: int | None,
               employee_id: int | None, search: str | None, page: int, page_size: int):
    if view not in ("my", "all"):
        raise invalid("view must be my or all.", "view")
    if status is not None and status not in LOAN_STATUSES:
        raise invalid("Unknown status.", "status")
    return loans_repo.list_loans(db, ctx.company_id, ctx.user_id, LOANS_VIEW, view, status, loan_type_id, employee_id,
                                 search, page, page_size)


def get_loan(db: Db, ctx: RequestContext, loan_id: int):
    return loans_repo.get_loan(db, ctx.company_id, ctx.user_id, LOANS_VIEW, loan_id)


def list_installments(db: Db, ctx: RequestContext, month_from: date | None, month_to: date | None,
                      status: str | None, employee_id: int | None, page: int, page_size: int):
    return loans_repo.list_installments(db, ctx.company_id, ctx.user_id, LOANS_VIEW, month_from, month_to, status,
                                        employee_id, page, page_size)


def summary(db: Db, ctx: RequestContext, employee_id: int | None) -> dict[str, Any]:
    employee_id = employee_id or ctx.employee_id
    if employee_id is None:
        raise invalid("Choose the employee.", "employeeId")
    return loans_repo.summary(db, ctx.company_id, ctx.user_id, LOANS_VIEW, employee_id)
