"""Payroll Settings rules. Checks that need the database (duplicates, links in use) live in the procedures;
expression checks (syntax, unknown names, loops between pay items and formulas) and slab rules live here."""
import json
from decimal import Decimal, InvalidOperation
from typing import Any

from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.core.db import Db
from app.repos import payroll_settings_repo as repo
from app.schemas.payroll_settings import (BankIn, BenefitIn, FormulaIn, IncentiveIn, PayItemIn, PayRuleIn,
                                          PayrollSettings, PayrollSettingsIn, TaxRebateIn, TaxStructureIn)
from app.services.payroll_expression import SYSTEM_VARIABLES, Expression, ExpressionError, slug

Row = dict[str, Any]
TAX_REBATE_CODES = {"view": "payroll.settings.tax.view", "create": "payroll.settings.tax.create",
                    "edit": "payroll.settings.tax.edit", "delete": "payroll.settings.tax.delete"}


def invalid(field: str, message: str, code: str = "VALIDATION_FAILED") -> AppError:
    return AppError(422, code, message, {field: message})


# --------------------------------------------------------------------------- general settings

def _decode(rows: list[Row]) -> dict[str, Any]:
    out = {}
    for r in rows:
        try:
            out[r["setting_key"]] = json.loads(r["setting_value"]) if r["setting_value"] not in (None, "") else None
        except ValueError:
            out[r["setting_key"]] = r["setting_value"]
    return out


def load(db: Db, company_id: int) -> PayrollSettings:
    """The company's payroll settings, with defaults for anything never saved."""
    rows, _ = repo.get_settings(db, company_id)
    stored = {k: v for k, v in _decode(rows).items() if k in PayrollSettings.model_fields and v is not None}
    try:
        return PayrollSettings(**stored)
    except ValueError:  # a value saved by an older version that no longer validates
        return PayrollSettings()


def get_settings(db: Db, ctx: RequestContext) -> tuple[PayrollSettings, bytes | None]:
    rows, version = repo.get_settings(db, ctx.company_id)
    stored = {k: v for k, v in _decode(rows).items() if k in PayrollSettings.model_fields and v is not None}
    return PayrollSettings(**stored), version


def save_settings(db: Db, ctx: RequestContext, body: PayrollSettingsIn,
                  row_version: bytes | None) -> tuple[PayrollSettings, bytes | None]:
    if body.leave_year_basis == "fiscal" and (body.fiscal_year_start_month is None or body.fiscal_year_end_month is None):
        raise invalid("fiscalYearStartMonth", "Pick the fiscal year's start and end month.")
    if body.revision_on_shift_days and not body.revision_shift_days:
        raise invalid("revisionShiftDays", "Give the number of shift days after which a revision applies.")
    if body.cutoff_proration and not body.cutoff_day:
        raise invalid("cutoffDay", "Give the cut-off day.")
    values = body.model_dump(exclude={"row_version"}, mode="json", by_alias=False)
    settings_json = json.dumps({k: json.dumps(v) for k, v in values.items()})
    rows, version = repo.save_settings(db, ctx.company_id, ctx.user_id, settings_json, row_version)
    stored = {k: v for k, v in _decode(rows).items() if k in PayrollSettings.model_fields and v is not None}
    return PayrollSettings(**stored), version


# --------------------------------------------------------------------------- expressions

def _names(db: Db, company_id: int) -> tuple[list[Row], list[Row], list[Row]]:
    return repo.pay_components(db, company_id)


def variables(db: Db, ctx: RequestContext) -> list[dict]:
    """What the expression builder offers: system variables, pay items and formulas, as {reference}."""
    repo.ensure_system_items(db, ctx.company_id)
    items, formulas, _ = _names(db, ctx.company_id)
    out = [{"name": k, "reference": "{" + k + "}", "kind": "variable", "description": v} for k, v in SYSTEM_VARIABLES.items()]
    out += [{"name": i["name"], "reference": "{" + slug(i["name"]) + "}", "kind": "pay_item", "description": i["item_type"]}
            for i in items]
    out += [{"name": f["name"], "reference": "{" + slug(f["name"]) + "}", "kind": "formula", "description": f["expression"]}
            for f in formulas]
    return out


def _parse(text: str, field: str) -> Expression:
    try:
        return Expression(text)
    except ExpressionError as exc:
        raise invalid(field, str(exc), "EXPRESSION_INVALID") from None


def _check_graph(formulas: dict[str, Expression], item_exprs: dict[str, list[Expression]], field: str) -> None:
    """Refuses loops: a formula or pay item that, through other formulas and pay items, names itself."""
    graph: dict[str, set[str]] = {}
    for name, expr in formulas.items():
        graph[name] = set(expr.refs)
    for name, exprs in item_exprs.items():
        graph.setdefault(name, set())
        for e in exprs:
            graph[name] |= set(e.refs)
    state: dict[str, int] = {}

    def visit(n: str, path: list[str]) -> None:
        if state.get(n) == 2:
            return
        if state.get(n) == 1:
            loop = " -> ".join(path[path.index(n):] + [n])
            raise invalid(field, f"These refer to each other in a loop: {loop}.", "EXPRESSION_LOOP")
        state[n] = 1
        for m in sorted(graph.get(n, ())):
            if m in graph:
                visit(m, path + [n])
        state[n] = 2

    for n in sorted(graph):
        visit(n, [])


def _known(items: list[Row], formulas: list[Row]) -> set[str]:
    return set(SYSTEM_VARIABLES) | {slug(i["name"]) for i in items} | {slug(f["name"]) for f in formulas}


def _check_name(name: str, own_id: int | None, kind: str, items: list[Row], formulas: list[Row]) -> str:
    s = slug(name)
    if not s:
        raise invalid("name", "The name needs letters or digits.")
    if s in SYSTEM_VARIABLES:
        raise AppError(409, "NAME_RESERVED", f"{{{s}}} is a system variable; pick another name.",
                       {"name": f"{{{s}}} is a system variable; pick another name."})
    for i in items:
        if slug(i["name"]) == s and not (kind == "pay_item" and i["id"] == own_id):
            raise AppError(409, "NAME_REFERENCE_TAKEN", f"The reference {{{s}}} is already the pay item {i['name']}.",
                           {"name": f"The reference {{{s}}} is already the pay item {i['name']}."})
    for f in formulas:
        if slug(f["name"]) == s and not (kind == "formula" and f["id"] == own_id):
            raise AppError(409, "NAME_REFERENCE_TAKEN", f"The reference {{{s}}} is already the formula {f['name']}.",
                           {"name": f"The reference {{{s}}} is already the formula {f['name']}."})
    return s


def _graph_inputs(items: list[Row], formulas: list[Row]) -> tuple[dict[str, Expression], dict[str, list[Expression]]]:
    f_by_id = {f["id"]: f for f in formulas}
    fx: dict[str, Expression] = {}
    for f in formulas:
        try:
            fx[slug(f["name"])] = Expression(f["expression"])
        except ExpressionError:
            continue
    ix: dict[str, list[Expression]] = {}
    for i in items:
        exprs = []
        for fid in (i["employee_formula_id"], i["employer_formula_id"]):
            if fid in f_by_id:
                exprs.append(Expression("{" + slug(f_by_id[fid]["name"]) + "}"))
        if i["eligibility_expression"]:
            try:
                exprs.append(Expression(i["eligibility_expression"]))
            except ExpressionError:
                pass
        ix[slug(i["name"])] = exprs
    return fx, ix


def check_expression(db: Db, ctx: RequestContext, text: str) -> dict:
    items, formulas, _ = _names(db, ctx.company_id)
    try:
        expr = Expression(text)
        unknown = [r for r in expr.refs if r not in _known(items, formulas)]
        if unknown:
            raise ExpressionError(f"{{{unknown[0]}}} is not a variable, pay item or formula.")
    except ExpressionError as exc:
        return {"valid": False, "message": str(exc), "references": []}
    return {"valid": True, "message": None, "references": list(expr.refs)}


# --------------------------------------------------------------------------- formulas, pay items, rules

def save_formula(db: Db, ctx: RequestContext, id: int | None, body: FormulaIn, row_version: bytes | None) -> Row:
    items, formulas, _ = _names(db, ctx.company_id)
    own = _check_name(body.name, id, "formula", items, formulas)
    expr = _parse(body.expression, "expression")
    known = _known(items, [f for f in formulas if f["id"] != id]) | {own}
    unknown = [r for r in expr.refs if r not in known]
    if unknown:
        raise invalid("expression", f"{{{unknown[0]}}} is not a variable, pay item or formula.", "EXPRESSION_INVALID")
    others = [f for f in formulas if f["id"] != id] + [{"id": id, "name": body.name, "expression": body.expression}]
    fx, ix = _graph_inputs(items, others)
    _check_graph(fx, ix, "expression")
    return repo.save_formula(db, ctx.company_id, ctx.user_id, id, body.name, body.expression, body.is_salary_division,
                             body.for_integration, body.description, row_version)


def save_pay_item(db: Db, ctx: RequestContext, id: int | None, body: PayItemIn, row_version: bytes | None) -> Row:
    if body.calculation_type == "formula" and body.employee_formula_id is None:
        raise invalid("employeeFormulaId", "A formula pay item needs its formula.")
    items, formulas, _ = _names(db, ctx.company_id)
    _check_name(body.name, id, "pay_item", items, formulas)
    if body.eligibility_expression and body.eligibility_expression.strip():
        expr = _parse(body.eligibility_expression, "eligibilityExpression")
        known = _known([i for i in items if i["id"] != id] + [{"name": body.name}], formulas)
        unknown = [r for r in expr.refs if r not in known]
        if unknown:
            raise invalid("eligibilityExpression", f"{{{unknown[0]}}} is not a variable, pay item or formula.",
                          "EXPRESSION_INVALID")
    mine = {"id": id, "name": body.name, "employee_formula_id": body.employee_formula_id,
            "employer_formula_id": body.employer_formula_id, "eligibility_expression": body.eligibility_expression}
    fx, ix = _graph_inputs([i for i in items if i["id"] != id] + [mine], formulas)
    _check_graph(fx, ix, "employeeFormulaId")
    return repo.save_pay_item(db, ctx.company_id, ctx.user_id, id, body, row_version)


def save_rule(db: Db, ctx: RequestContext, id: int | None, body: PayRuleIn, row_version: bytes | None) -> Row:
    items, formulas, _ = _names(db, ctx.company_id)
    expr = _parse(body.expression, "expression")
    unknown = [r for r in expr.refs if r not in _known(items, formulas)]
    if unknown:
        raise invalid("expression", f"{{{unknown[0]}}} is not a variable, pay item or formula.", "EXPRESSION_INVALID")
    return repo.save_rule(db, ctx.company_id, ctx.user_id, id, body.name, body.expression, body.account_type_id,
                          body.description, row_version)


# --------------------------------------------------------------------------- tax, rewards

def save_tax_structure(db: Db, ctx: RequestContext, id: int | None, body: TaxStructureIn, row_version: bytes | None):
    if body.end_date < body.start_date:
        raise invalid("endDate", "The end date is before the start date.")
    if body.surcharge_type and body.surcharge_value is None:
        raise invalid("surchargeValue", "Give the surcharge.")
    slabs = sorted(body.slabs, key=lambda s: s.min_amount)
    for n, s in enumerate(slabs):
        if s.max_amount is not None and s.max_amount <= s.min_amount:
            raise invalid(f"slabs.{n}.maxAmount", "The maximum must be above the minimum.")
        if n + 1 < len(slabs):
            nxt = slabs[n + 1]
            if s.max_amount is None or s.max_amount > nxt.min_amount:
                raise invalid(f"slabs.{n + 1}.minAmount", "Slabs overlap; each slab starts where the one below ends.")
    slabs_json = json.dumps([{"minAmount": str(s.min_amount), "maxAmount": None if s.max_amount is None else str(s.max_amount),
                              "fixedAmount": str(s.fixed_amount), "percentage": str(s.percentage)} for s in slabs])
    return repo.save_tax_structure(db, ctx.company_id, ctx.user_id, id, body.name, body.start_date, body.end_date,
                                   body.surcharge_type, body.surcharge_value if body.surcharge_type else None,
                                   body.description, slabs_json, row_version)


def save_tax_rebate(db: Db, ctx: RequestContext, id: int | None, body: TaxRebateIn, row_version: bytes | None) -> Row:
    if ctx.employee_id is not None and body.employee_id == ctx.employee_id:
        raise AppError(403, "OWN_PAY_RECORD", "You cannot change your own pay records.")
    code = TAX_REBATE_CODES["create" if id is None else "edit"]
    return repo.save_tax_rebate(db, ctx.company_id, ctx.user_id, code, id, body.employee_id, body.rebate_date,
                                body.amount, body.file_id, body.description, row_version)


def save_benefit(db: Db, ctx: RequestContext, id: int | None, body: BenefitIn, row_version: bytes | None):
    for n, f in enumerate(body.fields):
        value = (f.field_value or "").strip()
        if f.is_required and not value:
            raise invalid(f"fields.{n}.fieldValue", f"{f.name} is required.")
        if value and f.field_type == "number":
            try:
                number = Decimal(value)
            except InvalidOperation:
                raise invalid(f"fields.{n}.fieldValue", f"{f.name} must be a number.") from None
            if (f.min_value is not None and number < f.min_value) or (f.max_value is not None and number > f.max_value):
                raise invalid(f"fields.{n}.fieldValue", f"{f.name} is outside the allowed range.")
        if value and f.field_type == "string":
            if (f.min_length is not None and len(value) < f.min_length) or (f.max_length is not None and len(value) > f.max_length):
                raise invalid(f"fields.{n}.fieldValue", f"{f.name} is not the allowed length.")
    members = [m for m in body.members if m.employee_id or m.employee_group_id]
    if body.is_group and not members:
        raise invalid("members", "Pick the members of the group.")
    members_json = json.dumps([m.model_dump(by_alias=True) for m in members])
    fields_json = json.dumps([f.model_dump(by_alias=True, mode="json") for f in body.fields])
    return repo.save_benefit(db, ctx.company_id, ctx.user_id, id, body, members_json, fields_json, row_version)


def save_incentive(db: Db, ctx: RequestContext, id: int | None, body: IncentiveIn, row_version: bytes | None) -> Row:
    if body.value_type == "percentage" and body.reward_value > 100:
        raise invalid("rewardValue", "A percentage cannot be above 100.")
    return repo.save_incentive(db, ctx.company_id, ctx.user_id, id, body, row_version)


def save_bank(db: Db, ctx: RequestContext, id: int | None, body: BankIn, row_version: bytes | None) -> Row:
    return repo.save_bank(db, ctx.company_id, ctx.user_id, id, body, row_version)


# --------------------------------------------------------------------------- reads and deletes (no rules beyond the procedures)

def ensure_system_items(db: Db, ctx: RequestContext) -> None:
    repo.ensure_system_items(db, ctx.company_id)


def list_tax_structures(db: Db, ctx: RequestContext, search, page: int, page_size: int):
    return repo.list_tax_structures(db, ctx.company_id, search, page, page_size)


def get_tax_structure(db: Db, ctx: RequestContext, id: int):
    return repo.get_tax_structure(db, ctx.company_id, id)


def delete_tax_structure(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_tax_structure(db, ctx.company_id, ctx.user_id, id, row_version)


def list_tax_rebates(db: Db, ctx: RequestContext, search, employee_id, from_date, to_date, page: int, page_size: int):
    return repo.list_tax_rebates(db, ctx.company_id, ctx.user_id, TAX_REBATE_CODES["view"], search, employee_id,
                                 from_date, to_date, page, page_size)


def get_tax_rebate(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.get_tax_rebate(db, ctx.company_id, ctx.user_id, TAX_REBATE_CODES["view"], id)


def delete_tax_rebate(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_tax_rebate(db, ctx.company_id, ctx.user_id, TAX_REBATE_CODES["delete"], id, row_version)


def list_formulas(db: Db, ctx: RequestContext, search, page: int, page_size: int):
    return repo.list_formulas(db, ctx.company_id, search, page, page_size)


def get_formula(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.get_formula(db, ctx.company_id, id)


def delete_formula(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_formula(db, ctx.company_id, ctx.user_id, id, row_version)


def list_pay_items(db: Db, ctx: RequestContext, search, item_type, page: int, page_size: int):
    return repo.list_pay_items(db, ctx.company_id, search, item_type, page, page_size)


def get_pay_item(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.get_pay_item(db, ctx.company_id, id)


def delete_pay_item(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_pay_item(db, ctx.company_id, ctx.user_id, id, row_version)


def list_rules(db: Db, ctx: RequestContext, search, page: int, page_size: int):
    return repo.list_rules(db, ctx.company_id, search, page, page_size)


def get_rule(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.get_rule(db, ctx.company_id, id)


def delete_rule(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_rule(db, ctx.company_id, ctx.user_id, id, row_version)


def list_account_types(db: Db, ctx: RequestContext, search, category, page: int, page_size: int):
    return repo.list_account_types(db, ctx.company_id, search, category, page, page_size)


def get_account_type(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.get_account_type(db, ctx.company_id, id)


def save_account_type(db: Db, ctx: RequestContext, id: int | None, name: str, category: str, ref_id: int | None,
                      row_version: bytes | None) -> Row:
    if ref_id is None:
        raise invalid("refId", {"benefit": "Pick the benefit.", "leave_quota": "Pick the leave type.",
                                "custom_pay_item": "Pick the pay item."}[category])
    return repo.save_account_type(db, ctx.company_id, ctx.user_id, id, name, category, ref_id, row_version)


def delete_account_type(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_account_type(db, ctx.company_id, ctx.user_id, id, row_version)


def list_benefits(db: Db, ctx: RequestContext, search, page: int, page_size: int):
    return repo.list_benefits(db, ctx.company_id, search, page, page_size)


def get_benefit(db: Db, ctx: RequestContext, id: int):
    return repo.get_benefit(db, ctx.company_id, id)


def delete_benefit(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_benefit(db, ctx.company_id, ctx.user_id, id, row_version)


def list_incentives(db: Db, ctx: RequestContext, branch_id, month, page: int, page_size: int):
    return repo.list_incentives(db, ctx.company_id, branch_id, month, page, page_size)


def get_incentive(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.get_incentive(db, ctx.company_id, id)


def delete_incentive(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_incentive(db, ctx.company_id, ctx.user_id, id, row_version)


def list_banks(db: Db, ctx: RequestContext, search, page: int, page_size: int):
    return repo.list_banks(db, ctx.company_id, search, page, page_size)


def get_bank(db: Db, ctx: RequestContext, id: int) -> Row:
    return repo.get_bank(db, ctx.company_id, id)


def delete_bank(db: Db, ctx: RequestContext, id: int, row_version: bytes) -> None:
    repo.delete_bank(db, ctx.company_id, ctx.user_id, id, row_version)
