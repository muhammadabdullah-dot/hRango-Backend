"""HTTP shape for Payroll Settings: envelopes, row versions as text, rows to response models."""
from typing import Any

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.files import FileRef
from app.schemas.payroll_settings import (AccountTypeOut, BankOut, BenefitFieldOut, BenefitMemberOut, BenefitOut,
                                          FormulaOut, IncentiveOut, PayItemOut, PayRuleOut, PayrollSettingsOut,
                                          TaxRebateOut, TaxSlabOut, TaxStructureOut, VariableOut)
from app.services import payroll_settings_service as service
from app.services.payroll_expression import slug

Row = dict[str, Any]


def file_ref(file_id, name: str | None, company_id: int) -> FileRef | None:
    """An attachment as the API shows it: id, name and a signed download link."""
    return FileRef(id=str(file_id), name=name, url=file_url(file_id, company_id)) if file_id else None


def out(model, row: Row, company_id: int | None = None, **extra):
    """Row to response model. With company_id, a row's file_id / file_name also become `file` (a FileRef)."""
    data = {**row, **extra}
    if company_id is not None and "file_id" in data:
        data["file"] = file_ref(data["file_id"], data.get("file_name"), company_id)
    if "row_version" in data and isinstance(data["row_version"], (bytes, bytearray)):
        data["row_version"] = row_version_out(data["row_version"])
    return model(**data)


# --------------------------------------------------------------------------- general

def get_settings(db: Db, ctx: RequestContext) -> dict:
    settings, version = service.get_settings(db, ctx)
    return {"data": PayrollSettingsOut(**settings.model_dump(), row_version=row_version_out(version))}


def save_settings(db: Db, ctx: RequestContext, body) -> dict:
    settings, version = service.save_settings(db, ctx, body, row_version_in(body.row_version, required=False))
    return {"data": PayrollSettingsOut(**settings.model_dump(), row_version=row_version_out(version))}


def variables(db: Db, ctx: RequestContext) -> dict:
    return {"data": [VariableOut(**v) for v in service.variables(db, ctx)]}


def check_expression(db: Db, ctx: RequestContext, body) -> dict:
    return {"data": service.check_expression(db, ctx, body.expression)}


# --------------------------------------------------------------------------- tax

def _structure(head: Row, slabs: list[Row]) -> TaxStructureOut:
    return out(TaxStructureOut, head, slabs=[TaxSlabOut(**s) for s in slabs])


def list_tax_structures(db: Db, ctx: RequestContext, q: str | None, paging: PageParams) -> dict:
    total, rows = service.list_tax_structures(db, ctx, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(TaxStructureOut, r))


def get_tax_structure(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": _structure(*service.get_tax_structure(db, ctx, id))}


def save_tax_structure(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    rv = row_version_in(body.row_version) if id is not None else None
    return {"data": _structure(*service.save_tax_structure(db, ctx, id, body, rv))}


def delete_tax_structure(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_tax_structure(db, ctx, id, row_version_in(row_version))


def list_tax_rebates(db: Db, ctx: RequestContext, q, employee_id, from_date, to_date, paging: PageParams) -> dict:
    total, rows = service.list_tax_rebates(db, ctx, q, employee_id,
                                        from_date, to_date, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(TaxRebateOut, r, ctx.company_id))


def get_tax_rebate(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": out(TaxRebateOut, service.get_tax_rebate(db, ctx, id), ctx.company_id)}


def save_tax_rebate(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    rv = row_version_in(body.row_version) if id is not None else None
    return {"data": out(TaxRebateOut, service.save_tax_rebate(db, ctx, id, body, rv), ctx.company_id)}


def delete_tax_rebate(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_tax_rebate(db, ctx, id,
                           row_version_in(row_version))


# --------------------------------------------------------------------------- formulas, pay items, rules

def _formula(r: Row) -> FormulaOut:
    return out(FormulaOut, r, reference="{" + slug(r["name"]) + "}")


def _item(r: Row) -> PayItemOut:
    return out(PayItemOut, r, reference="{" + slug(r["name"]) + "}")


def list_formulas(db: Db, ctx: RequestContext, q, paging: PageParams) -> dict:
    service.ensure_system_items(db, ctx)
    total, rows = service.list_formulas(db, ctx, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _formula)


def get_formula(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": _formula(service.get_formula(db, ctx, id))}


def save_formula(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    rv = row_version_in(body.row_version) if id is not None else None
    return {"data": _formula(service.save_formula(db, ctx, id, body, rv))}


def delete_formula(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_formula(db, ctx, id, row_version_in(row_version))


def list_pay_items(db: Db, ctx: RequestContext, q, item_type, paging: PageParams) -> dict:
    service.ensure_system_items(db, ctx)
    total, rows = service.list_pay_items(db, ctx, q, item_type, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _item)


def get_pay_item(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": _item(service.get_pay_item(db, ctx, id))}


def save_pay_item(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    rv = row_version_in(body.row_version) if id is not None else None
    return {"data": _item(service.save_pay_item(db, ctx, id, body, rv))}


def delete_pay_item(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_pay_item(db, ctx, id, row_version_in(row_version))


def list_rules(db: Db, ctx: RequestContext, q, paging: PageParams) -> dict:
    total, rows = service.list_rules(db, ctx, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(PayRuleOut, r))


def get_rule(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": out(PayRuleOut, service.get_rule(db, ctx, id))}


def save_rule(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    rv = row_version_in(body.row_version) if id is not None else None
    return {"data": out(PayRuleOut, service.save_rule(db, ctx, id, body, rv))}


def delete_rule(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_rule(db, ctx, id, row_version_in(row_version))


# --------------------------------------------------------------------------- account types, rewards, banks

def list_account_types(db: Db, ctx: RequestContext, q, category, paging: PageParams) -> dict:
    total, rows = service.list_account_types(db, ctx, q, category, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(AccountTypeOut, r))


def get_account_type(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": out(AccountTypeOut, service.get_account_type(db, ctx, id))}


def save_account_type(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    rv = row_version_in(body.row_version) if id is not None else None
    return {"data": out(AccountTypeOut, service.save_account_type(db, ctx, id, body.name,
                                                               body.category, body.ref_id, rv))}


def delete_account_type(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_account_type(db, ctx, id, row_version_in(row_version))


def _benefit(head: Row, members: list[Row], fields: list[Row]) -> BenefitOut:
    return out(BenefitOut, head, members=[BenefitMemberOut(**m) for m in members],
               fields=[BenefitFieldOut(**f) for f in fields])


def list_benefits(db: Db, ctx: RequestContext, q, paging: PageParams) -> dict:
    total, rows = service.list_benefits(db, ctx, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(BenefitOut, r))


def get_benefit(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": _benefit(*service.get_benefit(db, ctx, id))}


def save_benefit(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    rv = row_version_in(body.row_version) if id is not None else None
    return {"data": _benefit(*service.save_benefit(db, ctx, id, body, rv))}


def delete_benefit(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_benefit(db, ctx, id, row_version_in(row_version))


def list_incentives(db: Db, ctx: RequestContext, branch_id, month, paging: PageParams) -> dict:
    total, rows = service.list_incentives(db, ctx, branch_id, month, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(IncentiveOut, r))


def get_incentive(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": out(IncentiveOut, service.get_incentive(db, ctx, id))}


def save_incentive(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    rv = row_version_in(body.row_version) if id is not None else None
    return {"data": out(IncentiveOut, service.save_incentive(db, ctx, id, body, rv))}


def delete_incentive(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_incentive(db, ctx, id, row_version_in(row_version))


def list_banks(db: Db, ctx: RequestContext, q, paging: PageParams) -> dict:
    total, rows = service.list_banks(db, ctx, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: out(BankOut, r))


def get_bank(db: Db, ctx: RequestContext, id: int) -> dict:
    return {"data": out(BankOut, service.get_bank(db, ctx, id))}


def save_bank(db: Db, ctx: RequestContext, id: int | None, body) -> dict:
    rv = row_version_in(body.row_version) if id is not None else None
    return {"data": out(BankOut, service.save_bank(db, ctx, id, body, rv))}


def delete_bank(db: Db, ctx: RequestContext, id: int, row_version: str | None) -> None:
    service.delete_bank(db, ctx, id, row_version_in(row_version))
