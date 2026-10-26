"""HTTP shape for the Loans screens: envelopes, row versions as text, rows to response models."""
import csv
import io
import json
from typing import Any

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.loans import (GuarantorOut, InstallmentOut, LoanCategoryIn, LoanCategoryOut, LoanDetailOut, LoanOut,
                               LoanSummaryOut, LoanTypeIn, LoanTypeOut, NamedRef)
from app.services import loans_service as svc


def _pick(model, row: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in row.items() if k in model.model_fields}


def _type(row: dict[str, Any]) -> LoanTypeOut:
    kinds = [NamedRef(**k) for k in json.loads(row["employment_types_json"] or "[]")]
    return LoanTypeOut(**{**_pick(LoanTypeOut, row), "employment_types": kinds,
                          "row_version": row_version_out(row["row_version"])})


def _category(row: dict[str, Any]) -> LoanCategoryOut:
    return LoanCategoryOut(**{**_pick(LoanCategoryOut, row), "row_version": row_version_out(row["row_version"])})


def _loan(row: dict[str, Any]) -> LoanOut:
    return LoanOut(**{**_pick(LoanOut, row), "row_version": row_version_out(row["row_version"])})


def list_types(db: Db, ctx: RequestContext, q: str | None, is_active: bool | None, paging: PageParams) -> dict:
    total, rows = svc.list_types(db, ctx, q, is_active, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _type)


def get_type(db: Db, ctx: RequestContext, type_id: int) -> dict:
    return {"data": _type(svc.get_type(db, ctx, type_id))}


def create_type(db: Db, ctx: RequestContext, body: LoanTypeIn) -> dict:
    return {"data": _type(svc.save_type(db, ctx, None, body, None))}


def update_type(db: Db, ctx: RequestContext, type_id: int, body: LoanTypeIn) -> dict:
    return {"data": _type(svc.save_type(db, ctx, type_id, body, row_version_in(body.row_version)))}


def delete_type(db: Db, ctx: RequestContext, type_id: int, row_version: str | None) -> None:
    svc.delete_type(db, ctx, type_id, row_version_in(row_version))


def list_categories(db: Db, ctx: RequestContext, q: str | None, is_active: bool | None, paging: PageParams) -> dict:
    total, rows = svc.list_categories(db, ctx, q, is_active, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _category)


def get_category(db: Db, ctx: RequestContext, category_id: int) -> dict:
    return {"data": _category(svc.get_category(db, ctx, category_id))}


def create_category(db: Db, ctx: RequestContext, body: LoanCategoryIn) -> dict:
    return {"data": _category(svc.save_category(db, ctx, None, body, None))}


def update_category(db: Db, ctx: RequestContext, category_id: int, body: LoanCategoryIn) -> dict:
    return {"data": _category(svc.save_category(db, ctx, category_id, body, row_version_in(body.row_version)))}


def delete_category(db: Db, ctx: RequestContext, category_id: int, row_version: str | None) -> None:
    svc.delete_category(db, ctx, category_id, row_version_in(row_version))


def list_loans(db: Db, ctx: RequestContext, view: str, status: str | None, loan_type_id: int | None,
               employee_id: int | None, q: str | None, paging: PageParams) -> dict:
    total, rows = svc.list_loans(db, ctx, view, status, loan_type_id, employee_id, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _loan)


def export_loans(db: Db, ctx: RequestContext, view: str, status: str | None, loan_type_id: int | None,
                 employee_id: int | None, q: str | None) -> str:
    _, rows = svc.list_loans(db, ctx, view, status, loan_type_id, employee_id, q, 1, 10000)
    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(["Request", "Employee code", "Employee", "Type", "Principal", "Installments", "Installment amount",
                "Start month", "Paid", "Remaining", "Status"])
    for r in rows:
        w.writerow([r["request_code"], r["employee_code"], r["employee_name"], r["loan_type_name"], r["principal"],
                    r["installments"], r["installment_amount"], r["start_month"], r["paid_amount"],
                    r["remaining_amount"], r["status"]])
    return out.getvalue()


def get_loan(db: Db, ctx: RequestContext, loan_id: int) -> dict:
    head, schedule, guarantors = svc.get_loan(db, ctx, loan_id)
    return {"data": LoanDetailOut(**_loan(head).model_dump(by_alias=False),
                                  schedule=[InstallmentOut(**_pick(InstallmentOut, i)) for i in schedule],
                                  guarantors=[GuarantorOut(**_pick(GuarantorOut, g),
                                                           file_url=file_url(g["file_id"], ctx.company_id))
                                              for g in guarantors])}


def list_installments(db: Db, ctx: RequestContext, month_from, month_to, status, employee_id,
                      paging: PageParams) -> dict:
    total, rows = svc.list_installments(db, ctx, month_from, month_to, status, employee_id, paging.page,
                                        paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: InstallmentOut(**_pick(InstallmentOut, r)))


def summary(db: Db, ctx: RequestContext, employee_id: int | None) -> dict:
    return {"data": LoanSummaryOut(**svc.summary(db, ctx, employee_id))}
