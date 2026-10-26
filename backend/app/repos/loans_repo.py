"""Loans data access. The only layer that knows the loan.* procedure names and parameters."""
from datetime import date
from typing import Any

from app.core.db import Db


def list_types(db: Db, company_id: int, search: str | None, is_active: bool | None, page: int, page_size: int):
    total, rows = db.call_sets("loan.usp_loan_type_list", company_id=company_id, search=search, is_active=is_active,
                               page=page, page_size=page_size)
    return total[0]["total"], rows


def get_type(db: Db, company_id: int, type_id: int) -> dict[str, Any]:
    return db.call_one("loan.usp_loan_type_get", company_id=company_id, id=type_id)


def save_type(db: Db, company_id: int, actor_user_id: int, type_id: int | None, v: dict[str, Any],
              employment_type_ids: str, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("loan.usp_loan_type_save", company_id=company_id, actor_user_id=actor_user_id, id=type_id,
                       name=v["name"], is_active=v["is_active"], guarantor_required=v["guarantor_required"],
                       non_payable=v["non_payable"], min_experience_months=v["min_experience_months"],
                       gap_between_requests_months=v["gap_between_requests_months"], installments=v["installments"],
                       gap_between_installments_months=v["gap_between_installments_months"],
                       formula_id=v["formula_id"], deduction_pay_item_id=v["deduction_pay_item_id"],
                       description=v["description"], employment_type_ids=employment_type_ids, row_version=row_version)


def delete_type(db: Db, company_id: int, actor_user_id: int, type_id: int, row_version: bytes) -> None:
    db.call("loan.usp_loan_type_delete", company_id=company_id, actor_user_id=actor_user_id, id=type_id,
            row_version=row_version)


def list_categories(db: Db, company_id: int, search: str | None, is_active: bool | None, page: int, page_size: int):
    total, rows = db.call_sets("loan.usp_loan_category_list", company_id=company_id, search=search,
                               is_active=is_active, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_category(db: Db, company_id: int, category_id: int) -> dict[str, Any]:
    return db.call_one("loan.usp_loan_category_get", company_id=company_id, id=category_id)


def save_category(db: Db, company_id: int, actor_user_id: int, category_id: int | None, name: str, is_active: bool,
                  description: str | None, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("loan.usp_loan_category_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=category_id, name=name, is_active=is_active, description=description,
                       row_version=row_version)


def delete_category(db: Db, company_id: int, actor_user_id: int, category_id: int, row_version: bytes) -> None:
    db.call("loan.usp_loan_category_delete", company_id=company_id, actor_user_id=actor_user_id, id=category_id,
            row_version=row_version)


def list_loans(db: Db, company_id: int, actor_user_id: int, permission_code: str, view: str, status: str | None,
               loan_type_id: int | None, employee_id: int | None, search: str | None, page: int, page_size: int):
    total, rows = db.call_sets("loan.usp_loan_list", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=permission_code, view=view, status=status, loan_type_id=loan_type_id,
                               employee_id=employee_id, search=search, page=page, page_size=page_size)
    return total[0]["total"], rows


def get_loan(db: Db, company_id: int, actor_user_id: int, permission_code: str, loan_id: int):
    head, schedule, guarantors = db.call_sets("loan.usp_loan_get", company_id=company_id, actor_user_id=actor_user_id,
                                              permission_code=permission_code, id=loan_id)
    return head[0], schedule, guarantors


def list_installments(db: Db, company_id: int, actor_user_id: int, permission_code: str, month_from: date | None,
                      month_to: date | None, status: str | None, employee_id: int | None, page: int, page_size: int):
    total, rows = db.call_sets("loan.usp_loan_installment_list", company_id=company_id, actor_user_id=actor_user_id,
                               permission_code=permission_code, month_from=month_from, month_to=month_to,
                               status=status, employee_id=employee_id, page=page, page_size=page_size)
    return total[0]["total"], rows


def summary(db: Db, company_id: int, actor_user_id: int, permission_code: str, employee_id: int) -> dict[str, Any]:
    return db.call_one("loan.usp_loan_summary", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, employee_id=employee_id)
