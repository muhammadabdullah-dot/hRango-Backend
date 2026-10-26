"""Payroll Settings: General, Tax, Rewards, Pay Components, Account Type, Disbursement Banks."""
from datetime import date

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import payroll_settings_controller as c
from app.core.db import Db, get_db
from app.core.paging import PageParams, page_params
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item, Paginated
from app.schemas.payroll_settings import (AccountTypeIn, AccountTypeOut, BankIn, BankOut, BenefitIn, BenefitOut,
                                          ExpressionCheckIn, ExpressionCheckOut, FormulaIn, FormulaOut, IncentiveIn,
                                          IncentiveOut, PayItemIn, PayItemOut, PayRuleIn, PayRuleOut, PayrollSettingsIn,
                                          PayrollSettingsOut, TaxRebateIn, TaxRebateOut, TaxStructureIn, TaxStructureOut,
                                          VariableOut)

router = APIRouter()
NO_CONTENT = status.HTTP_204_NO_CONTENT
CREATED = status.HTTP_201_CREATED
RV = Query(None, alias="rowVersion")


def gone() -> Response:
    return Response(status_code=NO_CONTENT)


# --------------------------------------------------------------------------- general

@router.get("/settings/general", response_model=Item[PayrollSettingsOut])
def get_settings(db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.settings.general.view"))):
    return c.get_settings(db, ctx)


@router.put("/settings/general", response_model=Item[PayrollSettingsOut])
def save_settings(body: PayrollSettingsIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("payroll.settings.general.edit"))):
    return c.save_settings(db, ctx, body)


@router.get("/settings/variables", response_model=Item[list[VariableOut]])
def variables(db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.settings.pay_components.view"))):
    return c.variables(db, ctx)


@router.post("/settings/expressions/check", response_model=Item[ExpressionCheckOut])
def check_expression(body: ExpressionCheckIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("payroll.settings.pay_components.view"))):
    return c.check_expression(db, ctx, body)


# --------------------------------------------------------------------------- tax structures and rebates

@router.get("/tax-structures", response_model=Paginated[TaxStructureOut])
def list_tax_structures(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("payroll.settings.tax.view"))):
    return c.list_tax_structures(db, ctx, q, paging)


@router.get("/tax-structures/{id}", response_model=Item[TaxStructureOut])
def get_tax_structure(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.settings.tax.view"))):
    return c.get_tax_structure(db, ctx, id)


@router.post("/tax-structures", response_model=Item[TaxStructureOut], status_code=CREATED)
def create_tax_structure(body: TaxStructureIn, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("payroll.settings.tax.create"))):
    return c.save_tax_structure(db, ctx, None, body)


@router.put("/tax-structures/{id}", response_model=Item[TaxStructureOut])
def update_tax_structure(id: int, body: TaxStructureIn, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("payroll.settings.tax.edit"))):
    return c.save_tax_structure(db, ctx, id, body)


@router.delete("/tax-structures/{id}", status_code=NO_CONTENT)
def delete_tax_structure(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("payroll.settings.tax.delete"))):
    c.delete_tax_structure(db, ctx, id, row_version)
    return gone()


@router.get("/tax-rebates", response_model=Paginated[TaxRebateOut])
def list_tax_rebates(q: str | None = None, employee_id: int | None = Query(None, alias="employeeId"),
                     from_date: date | None = Query(None, alias="from"), to_date: date | None = Query(None, alias="to"),
                     paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("payroll.settings.tax.view"))):
    return c.list_tax_rebates(db, ctx, q, employee_id, from_date, to_date, paging)


@router.get("/tax-rebates/{id}", response_model=Item[TaxRebateOut])
def get_tax_rebate(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.settings.tax.view"))):
    return c.get_tax_rebate(db, ctx, id)


@router.post("/tax-rebates", response_model=Item[TaxRebateOut], status_code=CREATED)
def create_tax_rebate(body: TaxRebateIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("payroll.settings.tax.create"))):
    return c.save_tax_rebate(db, ctx, None, body)


@router.put("/tax-rebates/{id}", response_model=Item[TaxRebateOut])
def update_tax_rebate(id: int, body: TaxRebateIn, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("payroll.settings.tax.edit"))):
    return c.save_tax_rebate(db, ctx, id, body)


@router.delete("/tax-rebates/{id}", status_code=NO_CONTENT)
def delete_tax_rebate(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                      ctx: RequestContext = Depends(require("payroll.settings.tax.delete"))):
    c.delete_tax_rebate(db, ctx, id, row_version)
    return gone()


# --------------------------------------------------------------------------- pay components

@router.get("/pay-items", response_model=Paginated[PayItemOut])
def list_pay_items(q: str | None = None, item_type: str | None = Query(None, alias="itemType"),
                   paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.settings.pay_components.view"))):
    return c.list_pay_items(db, ctx, q, item_type, paging)


@router.get("/pay-items/{id}", response_model=Item[PayItemOut])
def get_pay_item(id: int, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("payroll.settings.pay_components.view"))):
    return c.get_pay_item(db, ctx, id)


@router.post("/pay-items", response_model=Item[PayItemOut], status_code=CREATED)
def create_pay_item(body: PayItemIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("payroll.settings.pay_components.create"))):
    return c.save_pay_item(db, ctx, None, body)


@router.put("/pay-items/{id}", response_model=Item[PayItemOut])
def update_pay_item(id: int, body: PayItemIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("payroll.settings.pay_components.edit"))):
    return c.save_pay_item(db, ctx, id, body)


@router.delete("/pay-items/{id}", status_code=NO_CONTENT)
def delete_pay_item(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("payroll.settings.pay_components.delete"))):
    c.delete_pay_item(db, ctx, id, row_version)
    return gone()


@router.get("/formulas", response_model=Paginated[FormulaOut])
def list_formulas(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("payroll.settings.pay_components.view"))):
    return c.list_formulas(db, ctx, q, paging)


@router.get("/formulas/{id}", response_model=Item[FormulaOut])
def get_formula(id: int, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("payroll.settings.pay_components.view"))):
    return c.get_formula(db, ctx, id)


@router.post("/formulas", response_model=Item[FormulaOut], status_code=CREATED)
def create_formula(body: FormulaIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.settings.pay_components.create"))):
    return c.save_formula(db, ctx, None, body)


@router.put("/formulas/{id}", response_model=Item[FormulaOut])
def update_formula(id: int, body: FormulaIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.settings.pay_components.edit"))):
    return c.save_formula(db, ctx, id, body)


@router.delete("/formulas/{id}", status_code=NO_CONTENT)
def delete_formula(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.settings.pay_components.delete"))):
    c.delete_formula(db, ctx, id, row_version)
    return gone()


@router.get("/rules", response_model=Paginated[PayRuleOut])
def list_rules(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("payroll.settings.pay_components.view"))):
    return c.list_rules(db, ctx, q, paging)


@router.get("/rules/{id}", response_model=Item[PayRuleOut])
def get_rule(id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("payroll.settings.pay_components.view"))):
    return c.get_rule(db, ctx, id)


@router.post("/rules", response_model=Item[PayRuleOut], status_code=CREATED)
def create_rule(body: PayRuleIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("payroll.settings.pay_components.create"))):
    return c.save_rule(db, ctx, None, body)


@router.put("/rules/{id}", response_model=Item[PayRuleOut])
def update_rule(id: int, body: PayRuleIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("payroll.settings.pay_components.edit"))):
    return c.save_rule(db, ctx, id, body)


@router.delete("/rules/{id}", status_code=NO_CONTENT)
def delete_rule(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("payroll.settings.pay_components.delete"))):
    c.delete_rule(db, ctx, id, row_version)
    return gone()


# --------------------------------------------------------------------------- account types

@router.get("/account-types", response_model=Paginated[AccountTypeOut])
def list_account_types(q: str | None = None, category: str | None = None, paging: PageParams = Depends(page_params),
                       db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.settings.account_types.view"))):
    return c.list_account_types(db, ctx, q, category, paging)


@router.get("/account-types/{id}", response_model=Item[AccountTypeOut])
def get_account_type(id: int, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("payroll.settings.account_types.view"))):
    return c.get_account_type(db, ctx, id)


@router.post("/account-types", response_model=Item[AccountTypeOut], status_code=CREATED)
def create_account_type(body: AccountTypeIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("payroll.settings.account_types.create"))):
    return c.save_account_type(db, ctx, None, body)


@router.put("/account-types/{id}", response_model=Item[AccountTypeOut])
def update_account_type(id: int, body: AccountTypeIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("payroll.settings.account_types.edit"))):
    return c.save_account_type(db, ctx, id, body)


@router.delete("/account-types/{id}", status_code=NO_CONTENT)
def delete_account_type(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("payroll.settings.account_types.delete"))):
    c.delete_account_type(db, ctx, id, row_version)
    return gone()


# --------------------------------------------------------------------------- rewards

@router.get("/benefits", response_model=Paginated[BenefitOut])
def list_benefits(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("payroll.settings.rewards.view"))):
    return c.list_benefits(db, ctx, q, paging)


@router.get("/benefits/{id}", response_model=Item[BenefitOut])
def get_benefit(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.settings.rewards.view"))):
    return c.get_benefit(db, ctx, id)


@router.post("/benefits", response_model=Item[BenefitOut], status_code=CREATED)
def create_benefit(body: BenefitIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.settings.rewards.create"))):
    return c.save_benefit(db, ctx, None, body)


@router.put("/benefits/{id}", response_model=Item[BenefitOut])
def update_benefit(id: int, body: BenefitIn, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.settings.rewards.edit"))):
    return c.save_benefit(db, ctx, id, body)


@router.delete("/benefits/{id}", status_code=NO_CONTENT)
def delete_benefit(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("payroll.settings.rewards.delete"))):
    c.delete_benefit(db, ctx, id, row_version)
    return gone()


@router.get("/incentives", response_model=Paginated[IncentiveOut])
def list_incentives(branch_id: int | None = Query(None, alias="branchId"), month: date | None = None,
                    paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("payroll.settings.rewards.view"))):
    return c.list_incentives(db, ctx, branch_id, month, paging)


@router.get("/incentives/{id}", response_model=Item[IncentiveOut])
def get_incentive(id: int, db: Db = Depends(get_db), ctx: RequestContext = Depends(require("payroll.settings.rewards.view"))):
    return c.get_incentive(db, ctx, id)


@router.post("/incentives", response_model=Item[IncentiveOut], status_code=CREATED)
def create_incentive(body: IncentiveIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("payroll.settings.rewards.create"))):
    return c.save_incentive(db, ctx, None, body)


@router.put("/incentives/{id}", response_model=Item[IncentiveOut])
def update_incentive(id: int, body: IncentiveIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("payroll.settings.rewards.edit"))):
    return c.save_incentive(db, ctx, id, body)


@router.delete("/incentives/{id}", status_code=NO_CONTENT)
def delete_incentive(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("payroll.settings.rewards.delete"))):
    c.delete_incentive(db, ctx, id, row_version)
    return gone()


# --------------------------------------------------------------------------- disbursement banks

@router.get("/disbursement-banks", response_model=Paginated[BankOut])
def list_banks(q: str | None = None, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("payroll.settings.disbursement_banks.view"))):
    return c.list_banks(db, ctx, q, paging)


@router.get("/disbursement-banks/{id}", response_model=Item[BankOut])
def get_bank(id: int, db: Db = Depends(get_db),
             ctx: RequestContext = Depends(require("payroll.settings.disbursement_banks.view"))):
    return c.get_bank(db, ctx, id)


@router.post("/disbursement-banks", response_model=Item[BankOut], status_code=CREATED)
def create_bank(body: BankIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("payroll.settings.disbursement_banks.create"))):
    return c.save_bank(db, ctx, None, body)


@router.put("/disbursement-banks/{id}", response_model=Item[BankOut])
def update_bank(id: int, body: BankIn, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("payroll.settings.disbursement_banks.edit"))):
    return c.save_bank(db, ctx, id, body)


@router.delete("/disbursement-banks/{id}", status_code=NO_CONTENT)
def delete_bank(id: int, row_version: str | None = RV, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("payroll.settings.disbursement_banks.delete"))):
    c.delete_bank(db, ctx, id, row_version)
    return gone()
