"""Works out payslips from the inputs pay.usp_payroll_run_inputs / pay.usp_final_settlement_inputs gather.

Why here and not in SQL: pay item amounts are user-written expressions ({gross_salary} / {applicable_days}
* {absent_days} ...). Evaluating them in SQL would mean building dynamic SQL from user text; here they go
through a whitelisted AST evaluator (payroll_expression.py). Gathering the inputs and writing the results
stay set-based in the procedures.

For each person:
  1. Variables: salary, employment days in the month, time sheet counts, leave, penalties (SYSTEM_VARIABLES).
  2. Pay items in dependency order (an item's formula may name other items or formulas). An item counts
     only when its eligibility expression is true and, for items given through a group benefit, when the
     person is a member. Amount = formula (calculation type "formula") + the person's inputs (fixed amounts,
     opening balances, loan installments, leave encashment) + benefit formulas. A line edited by hand keeps
     its amount. The salary line uses the "How to Prorate Monthly" rounding when it is prorated.
  3. Tax, from the payroll's tax structure (see monthly_tax).
  4. Rules: each rule's expression is posted to its employee account (credit when positive, debit when negative).
"""
from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal
from typing import Any

from app.core.errors import AppError
from app.services.payroll_expression import (SYSTEM_VARIABLES, Expression, ExpressionError, Resolver, round_money,
                                             slug)

ZERO = Decimal(0)
CENT = Decimal("0.01")
STANDARD_DAY_MINUTES = 480
ONEOFF_SOURCES = {"opening_balance", "loan", "leave_encashment"}


@dataclass
class RunSettings:
    tax_rounding: str = "actual"
    proration_rounding: str = "actual"
    use_shift_hours: bool = False
    disable_tax_distribution_on_final_settlement: bool = False


@dataclass
class Item:
    id: int
    name: str
    slug: str
    item_type: str
    calculation_type: str
    system_code: str | None
    tax_distribution: str
    is_taxable: bool
    members_only: bool
    expression: Expression | None
    employer: Expression | None
    eligibility: Expression | None
    deps: set[str] = field(default_factory=set)


@dataclass
class Result:
    payslips: list[dict[str, Any]]
    errors: list[dict[str, Any]]


def _d(value) -> Decimal:
    if value is None:
        return ZERO
    return value if isinstance(value, Decimal) else Decimal(str(value))


def _parse(text: str | None, what: str) -> Expression | None:
    if text is None or not str(text).strip():
        return None
    try:
        return Expression(text)
    except ExpressionError as exc:
        raise AppError(422, "PAY_COMPONENT_INVALID", f"{what}: {exc}") from None


def annual_tax(income: Decimal, slabs: list[dict], surcharge_type: str | None, surcharge_value) -> Decimal:
    """The slab whose minimum the income reaches (the highest such): fixed amount + percentage of the part
    above the slab's minimum. A surcharge adds a percentage of the tax, or a flat amount when there is tax."""
    if income <= 0 or not slabs:
        return ZERO
    slab = None
    for s in sorted(slabs, key=lambda s: _d(s["min_amount"])):
        if income >= _d(s["min_amount"]):
            slab = s
    if slab is None:
        return ZERO
    tax = _d(slab["fixed_amount"]) + (income - _d(slab["min_amount"])) * _d(slab["percentage"]) / 100
    if tax > 0 and surcharge_type == "percentage":
        tax += tax * _d(surcharge_value) / 100
    elif tax > 0 and surcharge_type == "flat":
        tax += _d(surcharge_value)
    return tax


def months_remaining(month_start: date, tax_end: date | None) -> int:
    if tax_end is None:
        return 12
    return max(1, (tax_end.year - month_start.year) * 12 + tax_end.month - month_start.month + 1)


def monthly_tax(*, recurring: Decimal, oneoff_current: Decimal, oneoff_spread: Decimal, ytd_taxable: Decimal,
                ytd_tax: Decimal, rebates: Decimal, months_left: int, slabs: list[dict], surcharge_type,
                surcharge_value) -> Decimal:
    """Tax for the month on an annual projection:
         projected = taxable income already paid this tax year + this month's recurring taxable income x the
                     months left (this one included) + this month's one-off taxable amounts
         year's tax = slab tax of the projection - rebates; what is left after tax already taken is spread
                     over the months left, except the tax one-off items with "Current Month" distribution
                     cause, which is all taken now."""
    projected = ytd_taxable + recurring * months_left + oneoff_current + oneoff_spread
    full = annual_tax(projected, slabs, surcharge_type, surcharge_value)
    without_current = annual_tax(projected - oneoff_current, slabs, surcharge_type, surcharge_value)
    extra_now = max(ZERO, full - without_current)
    remaining = max(ZERO, full - rebates) - ytd_tax
    return max(ZERO, (remaining - extra_now) / months_left + extra_now)


def _order(items: list[Item], item_slugs: set[str], formulas: dict[str, Expression]) -> list[Item]:
    """Pay items in an order where every item comes after the items its expressions name (through formulas too)."""
    def refs_of(expr: Expression | None, seen: set[str]) -> set[str]:
        out: set[str] = set()
        if expr is None:
            return out
        for r in expr.refs:
            if r in item_slugs:
                out.add(r)
            elif r in formulas and r not in seen:
                seen.add(r)
                out |= refs_of(formulas[r], seen)
        return out

    by_slug = {i.slug: i for i in items}
    for i in items:
        i.deps = {d for d in (refs_of(i.expression, set()) | refs_of(i.employer, set()) | refs_of(i.eligibility, set()))
                  if d in by_slug and d != i.slug}
        if i.slug in refs_of(i.expression, set()):
            raise AppError(422, "PAY_COMPONENT_LOOP", f"Pay item {i.name} refers to itself.")
    ordered, done, visiting = [], set(), set()

    def visit(i: Item) -> None:
        if i.slug in done:
            return
        if i.slug in visiting:
            raise AppError(422, "PAY_COMPONENT_LOOP", f"Pay items refer to each other in a loop ({i.name}).")
        visiting.add(i.slug)
        for d in sorted(i.deps):
            visit(by_slug[d])
        visiting.discard(i.slug)
        done.add(i.slug)
        ordered.append(i)

    for i in sorted(items, key=lambda i: (i.system_code == "tax", i.id)):
        visit(i)
    return ordered


def compute(sets: list[list[dict]], settings: RunSettings) -> Result:
    """`sets`: the result sets of the inputs procedure, in order (run, skipped, items, names, rules, slabs,
    employees, inputs, benefits, hand-edited lines, tax so far)."""
    (header_rows, skipped, item_rows, name_rows, rule_rows, slabs, employees, inputs, benefits, manual, ytd) = sets
    header = header_rows[0]
    errors = [{"employeeId": r["employee_id"], "message": r["skip_reason"]} for r in skipped]

    formulas: dict[str, Expression] = {}
    item_slugs: set[str] = set()
    for r in name_rows:
        s = slug(r["name"])
        if r["kind"] == "pay_item":
            item_slugs.add(s)
        else:
            formulas[s] = _parse(r["expression"], f"Formula {r['name']}")
    items = [Item(id=r["pay_item_id"], name=r["name"], slug=slug(r["name"]), item_type=r["item_type"],
                  calculation_type=r["calculation_type"], system_code=r["system_code"],
                  tax_distribution=r["tax_distribution"] or "current_month", is_taxable=bool(r["is_taxable"]),
                  members_only=bool(r["members_only"]),
                  expression=_parse(r["employee_expression"], f"Pay item {r['name']}")
                  if r["calculation_type"] == "formula" else None,
                  employer=_parse(r["employer_expression"], f"Pay item {r['name']} (employer contribution)"),
                  eligibility=_parse(r["eligibility_expression"], f"Pay item {r['name']} (eligibility)"))
             for r in item_rows]
    display_only = {r["pay_item_id"] for r in item_rows if r["is_display_only"]}
    tax_item = next((i for i in items if i.system_code == "tax"), None)
    ordered = _order([i for i in items if i is not tax_item], item_slugs, formulas)
    rules = [(r, _parse(r["expression"], f"Rule {r['name']}")) for r in rule_rows]

    def by_emp(rows):
        out: dict[int, list[dict]] = {}
        for r in rows:
            out.setdefault(r["employee_id"], []).append(r)
        return out

    inputs_by, benefits_by, manual_by = by_emp(inputs), by_emp(benefits), by_emp(manual)
    ytd_by = {r["employee_id"]: r for r in ytd}
    month_days = int(header["month_days"])
    applicable = Decimal(header["fixed_days"]) if header["applicable_days"] == "fixed" and header["fixed_days"] \
        else Decimal(month_days)
    is_fs = bool(header["is_final_settlement"])
    tax_on = bool(header["tax_applicable"]) and tax_item is not None and bool(slabs)

    payslips: list[dict] = []
    for emp in employees:
        eid = emp["employee_id"]
        try:
            payslips.append(_employee(emp, header, ordered, tax_item if tax_on else None, formulas, item_slugs, rules,
                                      inputs_by.get(eid, []), benefits_by.get(eid, []), manual_by.get(eid, []),
                                      ytd_by.get(eid), slabs, applicable, month_days, is_fs, settings, display_only))
        except ExpressionError as exc:
            errors.append({"employeeId": eid, "message": str(exc)})
        except _Skip as exc:
            errors.append({"employeeId": eid, "message": str(exc)})
    return Result(payslips=payslips, errors=errors)


class _Skip(Exception):
    pass


def _employee(emp, header, ordered, tax_item, formulas, item_slugs, rules, inputs, benefits, manual, ytd, slabs,
              applicable, month_days, is_fs, settings: RunSettings, display_only) -> dict:
    if emp["gross_salary"] is None:
        raise _Skip("No salary on record (Salary Revision).")
    gross = _d(emp["gross_salary"])
    month_start: date = emp["month_start"]
    start = max(month_start, emp["joining_date"] or month_start)
    ends = [d for d in (emp["period_end"], emp["employment_end_date"], emp["last_working_date"]) if d]
    end = min(ends)
    include = bool(emp["include_salary"])
    employed = Decimal(max(0, (end - start).days + 1)) if include else ZERO
    if include and employed == 0 and not is_fs:
        raise _Skip("Not employed during this month.")

    def att(name: str) -> Decimal:
        return _d(emp[name]) if include else ZERO

    absent, half, unpaid = att("absent_days"), att("half_days"), att("unpaid_leave_days")
    shift_minutes = emp["day_minutes"] if settings.use_shift_hours and emp["day_minutes"] else STANDARD_DAY_MINUTES
    loan_total = sum((_d(r["amount"]) for r in inputs if r["source"] == "loan"), ZERO)
    encash_total = sum((_d(r["amount"]) for r in inputs if r["source"] == "leave_encashment"), ZERO)
    fs_encash = (_d(emp["fs_encash_days"]) * gross / month_days).quantize(CENT) if _d(emp["fs_encash_days"]) else ZERO
    variables = {
        "gross_salary": gross, "month_days": Decimal(month_days), "applicable_days": applicable, "employed_days": employed,
        "worked_days": max(ZERO, employed - absent - unpaid - half / 2), "present_days": att("present_days"),
        "absent_days": absent, "half_days": half, "short_days": att("short_days"), "holiday_days": att("holiday_days"),
        "leave_days": att("leave_days"), "unpaid_leave_days": unpaid, "late_days": att("late_days"),
        "late_minutes": att("late_minutes"), "early_left_days": att("early_left_days"),
        "early_left_minutes": att("early_left_minutes"),
        "short_minutes": att("late_minutes") + att("early_left_minutes"), "overtime_minutes": att("overtime_minutes"),
        "worked_minutes": att("worked_minutes"), "expected_minutes": att("expected_minutes"),
        "day_minutes": Decimal(shift_minutes), "penalty_days": att("penalty_days"), "loan_installment": loan_total,
        "leave_encashment": encash_total + fs_encash,
        "service_months": Decimal(max(0, _months_between(emp["joining_date"], end)) if emp["joining_date"] else 0),
    }
    for k in ("branch_id", "department_id", "designation_id", "grade_id", "employment_type_id", "employee_group_id",
              "location_id"):
        variables[k] = _d(emp[k])
    assert set(variables) == set(SYSTEM_VARIABLES)

    values: dict[str, Decimal] = {}
    resolver = Resolver(variables, formulas, lambda s: values.get(s, ZERO) if s in item_slugs else None)
    manual_by_item = {r["pay_item_id"]: r for r in manual}
    member_items = {r["pay_item_id"] for r in benefits if r["is_group"]}
    lines: list[dict] = []
    recurring = oneoff_current = oneoff_spread = ZERO

    def add_line(item: Item, amount: Decimal, employer: Decimal | None, is_manual: bool, oneoff_part: Decimal) -> None:
        nonlocal recurring, oneoff_current, oneoff_spread
        values[item.slug] = amount
        if amount == 0 and not employer and not is_manual:
            return
        lines.append({"payItemId": item.id, "amount": str(amount), "employerContribution": str(employer) if employer else None,
                      "isTaxable": item.is_taxable, "isManual": is_manual})
        if not item.is_taxable or item.id in display_only or item.item_type not in ("earning", "deduction"):
            return
        sign = 1 if item.item_type == "earning" else -1
        oneoff = amount if (item.calculation_type == "manual" or item.system_code == "leave_encashment") else \
            max(min(oneoff_part, amount), ZERO) if amount >= 0 else ZERO
        if item.tax_distribution == "current_month":
            oneoff_current += sign * oneoff
        else:
            oneoff_spread += sign * oneoff
        recurring += sign * (amount - oneoff)

    for item in ordered:
        try:
            if item.eligibility is not None and not item.eligibility.evaluate(resolver):
                continue
            if item.members_only and item.id not in member_items:
                continue
            own = [r for r in inputs if r["pay_item_id"] == item.id]
            oneoff_part = sum((_d(r["amount"]) for r in own if r["source"] in ONEOFF_SOURCES), ZERO)
            amount = item.expression.evaluate(resolver) if item.expression is not None else ZERO
            amount += sum((_d(r["amount"]) for r in own), ZERO)
            if item.system_code == "leave_encashment":
                amount += fs_encash
            for b in benefits:
                if b["pay_item_id"] == item.id and b["expression"]:
                    amount += Expression(b["expression"]).evaluate(resolver)
            if item.system_code == "salary" and employed < month_days:
                amount = round_money(amount, settings.proration_rounding)
            else:
                amount = amount.quantize(CENT)
            employer = item.employer.evaluate(resolver).quantize(CENT) if item.employer is not None else None
        except ExpressionError as exc:
            raise ExpressionError(f"{item.name}: {exc}") from None
        hand = manual_by_item.get(item.id)
        if hand is not None:
            amount = _d(hand["amount"])
            employer = _d(hand["employer_contribution"]) if hand["employer_contribution"] is not None else employer
        add_line(item, amount, employer, hand is not None, oneoff_part)

    for item_id, hand in manual_by_item.items():  # hand-edited lines of items not worked out above
        if not any(l["payItemId"] == item_id for l in lines) and (tax_item is None or item_id != tax_item.id):
            lines.append({"payItemId": item_id, "amount": str(_d(hand["amount"])),
                          "employerContribution": str(hand["employer_contribution"]) if hand["employer_contribution"] is not None else None,
                          "isTaxable": False, "isManual": True})

    taxable = recurring + oneoff_current + oneoff_spread
    if tax_item is not None:
        hand = manual_by_item.get(tax_item.id)
        if hand is not None:
            tax = _d(hand["amount"])
        else:
            months_left = 1 if is_fs and not settings.disable_tax_distribution_on_final_settlement \
                else months_remaining(emp["month_start"], header["tax_end_date"])
            y = ytd or {}
            tax = round_money(monthly_tax(recurring=recurring, oneoff_current=oneoff_current, oneoff_spread=oneoff_spread,
                                          ytd_taxable=_d(y.get("ytd_taxable")), ytd_tax=_d(y.get("ytd_tax")),
                                          rebates=_d(y.get("rebates")), months_left=months_left, slabs=slabs,
                                          surcharge_type=header["surcharge_type"], surcharge_value=header["surcharge_value"]),
                              settings.tax_rounding)
        values[tax_item.slug] = tax
        if tax or hand is not None:
            lines.append({"payItemId": tax_item.id, "amount": str(tax), "employerContribution": None, "isTaxable": False,
                          "isManual": hand is not None})

    postings = []
    for rule, expr in rules:
        try:
            v = expr.evaluate(resolver).quantize(CENT) if expr is not None else ZERO
        except ExpressionError as exc:
            raise ExpressionError(f"Rule {rule['name']}: {exc}") from None
        if v:
            postings.append({"payRuleId": rule["id"], "accountTypeId": rule["account_type_id"],
                             "credit": str(v) if v > 0 else "0", "debit": str(-v) if v < 0 else "0",
                             "description": rule["name"]})

    return {"employeeId": emp["employee_id"], "applicableDays": str(applicable), "workedDays": str(variables["worked_days"]),
            "workedMinutes": int(variables["worked_minutes"]), "expectedMinutes": int(variables["expected_minutes"]),
            "leaveDays": str(variables["leave_days"]), "absentDays": str(absent + half / 2),
            "overtimeMinutes": int(variables["overtime_minutes"]), "taxableIncome": str(taxable.quantize(CENT)),
            "paymentMethod": emp["payment_method"], "lines": lines, "postings": postings}


def _months_between(a: date, b: date) -> int:
    return (b.year - a.year) * 12 + b.month - a.month - (1 if b.day < a.day else 0)
