"""Loans: the loans approved loan requests made (My / All, schedule, repayments, totals) and Loan &
Advance Settings (types, categories). Asking for a loan is POST /requests/loan."""
from datetime import date

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import loans_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.loans import (InstallmentOut, LoanCategoryIn, LoanCategoryOut, LoanDetailOut, LoanOut, LoanSummaryOut,
                               LoanTypeIn, LoanTypeOut)

router = APIRouter(prefix="/loans", tags=["loans"])


# ---------------------------------------------------------------- settings: types

@router.get("/types", response_model=Paginated[LoanTypeOut])
def list_types(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
               paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("loans.settings.types.view"))) -> dict:
    return c.list_types(db, ctx, q, is_active, paging)


@router.get("/types/{type_id}", response_model=Item[LoanTypeOut])
def get_type(type_id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("loans.settings.types.view"))) -> dict:
    return c.get_type(db, ctx, type_id)


@router.post("/types", response_model=Item[LoanTypeOut], status_code=status.HTTP_201_CREATED)
def create_type(body: LoanTypeIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("loans.settings.types.create"))) -> dict:
    return c.create_type(db, ctx, body)


@router.put("/types/{type_id}", response_model=Item[LoanTypeOut])
def update_type(type_id: int, body: LoanTypeIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("loans.settings.types.edit"))) -> dict:
    return c.update_type(db, ctx, type_id, body)


@router.delete("/types/{type_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_type(type_id: int, row_version: str | None = Query(None, alias="rowVersion"), db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("loans.settings.types.delete"))) -> Response:
    c.delete_type(db, ctx, type_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- settings: categories

@router.get("/categories", response_model=Paginated[LoanCategoryOut])
def list_categories(q: str | None = None, is_active: bool | None = Query(None, alias="isActive"),
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("loans.settings.categories.view"))) -> dict:
    return c.list_categories(db, ctx, q, is_active, paging)


@router.get("/categories/{category_id}", response_model=Item[LoanCategoryOut])
def get_category(category_id: int, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("loans.settings.categories.view"))) -> dict:
    return c.get_category(db, ctx, category_id)


@router.post("/categories", response_model=Item[LoanCategoryOut], status_code=status.HTTP_201_CREATED)
def create_category(body: LoanCategoryIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("loans.settings.categories.create"))) -> dict:
    return c.create_category(db, ctx, body)


@router.put("/categories/{category_id}", response_model=Item[LoanCategoryOut])
def update_category(category_id: int, body: LoanCategoryIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("loans.settings.categories.edit"))) -> dict:
    return c.update_category(db, ctx, category_id, body)


@router.delete("/categories/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_category(category_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                    db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("loans.settings.categories.delete"))) -> Response:
    c.delete_category(db, ctx, category_id, row_version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- loans

@router.get("", response_model=Paginated[LoanOut])
def list_loans(view: str = "my", status_: str | None = Query(None, alias="status"),
               loan_type_id: int | None = Query(None, alias="loanTypeId"),
               employee_id: int | None = Query(None, alias="employeeId"), q: str | None = None,
               paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("loans.loans.view"))) -> dict:
    return c.list_loans(db, ctx, view, status_, loan_type_id, employee_id, q, paging)


@router.get("/export")
def export_loans(view: str = "all", status_: str | None = Query(None, alias="status"),
                 loan_type_id: int | None = Query(None, alias="loanTypeId"),
                 employee_id: int | None = Query(None, alias="employeeId"), q: str | None = None,
                 db: Db = Depends(get_db), ctx: RequestContext = Depends(require("loans.loans.export"))) -> Response:
    return Response(c.export_loans(db, ctx, view, status_, loan_type_id, employee_id, q), media_type="text/csv",
                    headers={"Content-Disposition": 'attachment; filename="loans.csv"'})


@router.get("/installments", response_model=Paginated[InstallmentOut])
def list_installments(month_from: date | None = Query(None, alias="monthFrom"),
                      month_to: date | None = Query(None, alias="monthTo"),
                      status_: str | None = Query(None, alias="status"),
                      employee_id: int | None = Query(None, alias="employeeId"),
                      paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("loans.loans.view"))) -> dict:
    """Settings -> Repayment: every installment the caller may see, by due month."""
    return c.list_installments(db, ctx, month_from, month_to, status_, employee_id, paging)


@router.get("/summary", response_model=Item[LoanSummaryOut])
def loan_summary(employee_id: int | None = Query(None, alias="employeeId"), db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("loans.loans.view"))) -> dict:
    """Total approved, repaid and remaining for one employee (the loan approve popup)."""
    return c.summary(db, ctx, employee_id)


@router.get("/{loan_id}", response_model=Item[LoanDetailOut])
def get_loan(loan_id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("loans.loans.view"))) -> dict:
    return c.get_loan(db, ctx, loan_id)
