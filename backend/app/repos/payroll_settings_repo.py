"""Payroll Settings data access. The only layer that knows these procedure names and parameters."""
from typing import Any

from app.core.db import Db

Row = dict[str, Any]


def _page(db: Db, proc: str, **params) -> tuple[int, list[Row]]:
    total, rows = db.call_sets(proc, **params)
    return total[0]["total"], rows


# --------------------------------------------------------------------------- general

def get_settings(db: Db, company_id: int) -> tuple[list[Row], bytes | None]:
    rows, version = db.call_sets("pay.usp_settings_get", company_id=company_id)
    return rows, version[0]["row_version"]


def save_settings(db: Db, company_id: int, actor_user_id: int, settings_json: str,
                  row_version: bytes | None) -> tuple[list[Row], bytes | None]:
    rows, version = db.call_sets("pay.usp_settings_save", company_id=company_id, actor_user_id=actor_user_id,
                                 settings_json=settings_json, row_version=row_version)
    return rows, version[0]["row_version"]


def pay_components(db: Db, company_id: int) -> tuple[list[Row], list[Row], list[Row]]:
    items, formulas, rules = db.call_sets("pay.usp_pay_component_all", company_id=company_id)
    return items, formulas, rules


def ensure_system_items(db: Db, company_id: int) -> None:
    db.call("pay.usp_pay_item_system_ensure", company_id=company_id)


# --------------------------------------------------------------------------- tax

def list_tax_structures(db: Db, company_id: int, search: str | None, page: int, page_size: int):
    return _page(db, "pay.usp_tax_structure_list", company_id=company_id, search=search, page=page, page_size=page_size)


def get_tax_structure(db: Db, company_id: int, id: int) -> tuple[Row, list[Row]]:
    head, slabs = db.call_sets("pay.usp_tax_structure_get", company_id=company_id, id=id)
    return head[0], slabs


def save_tax_structure(db: Db, company_id: int, actor_user_id: int, id: int | None, name: str, start_date, end_date,
                       surcharge_type, surcharge_value, description, slabs_json: str,
                       row_version: bytes | None) -> tuple[Row, list[Row]]:
    head, slabs = db.call_sets("pay.usp_tax_structure_save", company_id=company_id, actor_user_id=actor_user_id, id=id,
                               name=name, start_date=start_date, end_date=end_date, surcharge_type=surcharge_type,
                               surcharge_value=surcharge_value, description=description, slabs=slabs_json,
                               row_version=row_version)
    return head[0], slabs


def delete_tax_structure(db: Db, company_id: int, actor_user_id: int, id: int, row_version: bytes) -> None:
    db.call("pay.usp_tax_structure_delete", company_id=company_id, actor_user_id=actor_user_id, id=id,
            row_version=row_version)


def list_tax_rebates(db: Db, company_id: int, actor_user_id: int, permission_code: str, search, employee_id,
                     from_date, to_date, page: int, page_size: int):
    return _page(db, "pay.usp_tax_rebate_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=permission_code, search=search, employee_id=employee_id, from_date=from_date,
                 to_date=to_date, page=page, page_size=page_size)


def get_tax_rebate(db: Db, company_id: int, actor_user_id: int, permission_code: str, id: int) -> Row:
    return db.call_one("pay.usp_tax_rebate_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=id)


def save_tax_rebate(db: Db, company_id: int, actor_user_id: int, permission_code: str, id: int | None, employee_id: int,
                    rebate_date, amount, file_id, description, row_version: bytes | None) -> Row:
    return db.call_one("pay.usp_tax_rebate_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=id, employee_id=employee_id, rebate_date=rebate_date,
                       amount=amount, file_id=file_id, description=description, row_version=row_version)


def delete_tax_rebate(db: Db, company_id: int, actor_user_id: int, permission_code: str, id: int,
                      row_version: bytes) -> None:
    db.call("pay.usp_tax_rebate_delete", company_id=company_id, actor_user_id=actor_user_id,
            permission_code=permission_code, id=id, row_version=row_version)


# --------------------------------------------------------------------------- formulas, pay items, rules

def list_formulas(db: Db, company_id: int, search: str | None, page: int, page_size: int):
    return _page(db, "pay.usp_formula_list", company_id=company_id, search=search, page=page, page_size=page_size)


def get_formula(db: Db, company_id: int, id: int) -> Row:
    return db.call_one("pay.usp_formula_get", company_id=company_id, id=id)


def save_formula(db: Db, company_id: int, actor_user_id: int, id: int | None, name: str, expression: str,
                 is_salary_division: bool, for_integration: bool, description, row_version: bytes | None) -> Row:
    return db.call_one("pay.usp_formula_save", company_id=company_id, actor_user_id=actor_user_id, id=id, name=name,
                       expression=expression, is_salary_division=is_salary_division, for_integration=for_integration,
                       description=description, row_version=row_version)


def delete_formula(db: Db, company_id: int, actor_user_id: int, id: int, row_version: bytes) -> None:
    db.call("pay.usp_formula_delete", company_id=company_id, actor_user_id=actor_user_id, id=id, row_version=row_version)


def list_pay_items(db: Db, company_id: int, search: str | None, item_type: str | None, page: int, page_size: int):
    return _page(db, "pay.usp_pay_item_list", company_id=company_id, search=search, item_type=item_type, page=page,
                 page_size=page_size)


def get_pay_item(db: Db, company_id: int, id: int) -> Row:
    return db.call_one("pay.usp_pay_item_get", company_id=company_id, id=id)


def save_pay_item(db: Db, company_id: int, actor_user_id: int, id: int | None, body, row_version: bytes | None) -> Row:
    return db.call_one("pay.usp_pay_item_save", company_id=company_id, actor_user_id=actor_user_id, id=id,
                       name=body.name, label=body.label, item_type=body.item_type,
                       calculation_type=body.calculation_type, tax_distribution=body.tax_distribution,
                       employee_formula_id=body.employee_formula_id, employer_formula_id=body.employer_formula_id,
                       is_taxable=body.is_taxable, is_display_only=body.is_display_only, is_benefit=body.is_benefit,
                       is_advance_payment=body.is_advance_payment, eligibility_expression=body.eligibility_expression,
                       description=body.description, row_version=row_version)


def delete_pay_item(db: Db, company_id: int, actor_user_id: int, id: int, row_version: bytes) -> None:
    db.call("pay.usp_pay_item_delete", company_id=company_id, actor_user_id=actor_user_id, id=id, row_version=row_version)


def list_rules(db: Db, company_id: int, search: str | None, page: int, page_size: int):
    return _page(db, "pay.usp_pay_rule_list", company_id=company_id, search=search, page=page, page_size=page_size)


def get_rule(db: Db, company_id: int, id: int) -> Row:
    return db.call_one("pay.usp_pay_rule_get", company_id=company_id, id=id)


def save_rule(db: Db, company_id: int, actor_user_id: int, id: int | None, name: str, expression: str,
              account_type_id: int, description, row_version: bytes | None) -> Row:
    return db.call_one("pay.usp_pay_rule_save", company_id=company_id, actor_user_id=actor_user_id, id=id, name=name,
                       expression=expression, account_type_id=account_type_id, description=description,
                       row_version=row_version)


def delete_rule(db: Db, company_id: int, actor_user_id: int, id: int, row_version: bytes) -> None:
    db.call("pay.usp_pay_rule_delete", company_id=company_id, actor_user_id=actor_user_id, id=id, row_version=row_version)


# --------------------------------------------------------------------------- account types, rewards, banks

def list_account_types(db: Db, company_id: int, search, category, page: int, page_size: int):
    return _page(db, "pay.usp_account_type_list", company_id=company_id, search=search, category=category, page=page,
                 page_size=page_size)


def get_account_type(db: Db, company_id: int, id: int) -> Row:
    return db.call_one("pay.usp_account_type_get", company_id=company_id, id=id)


def save_account_type(db: Db, company_id: int, actor_user_id: int, id: int | None, name: str, category: str,
                      ref_id: int | None, row_version: bytes | None) -> Row:
    return db.call_one("pay.usp_account_type_save", company_id=company_id, actor_user_id=actor_user_id, id=id, name=name,
                       category=category, ref_id=ref_id, row_version=row_version)


def delete_account_type(db: Db, company_id: int, actor_user_id: int, id: int, row_version: bytes) -> None:
    db.call("pay.usp_account_type_delete", company_id=company_id, actor_user_id=actor_user_id, id=id,
            row_version=row_version)


def list_benefits(db: Db, company_id: int, search, page: int, page_size: int):
    return _page(db, "pay.usp_reward_benefit_list", company_id=company_id, search=search, page=page, page_size=page_size)


def get_benefit(db: Db, company_id: int, id: int) -> tuple[Row, list[Row], list[Row]]:
    head, members, fields = db.call_sets("pay.usp_reward_benefit_get", company_id=company_id, id=id)
    return head[0], members, fields


def save_benefit(db: Db, company_id: int, actor_user_id: int, id: int | None, body, members_json: str, fields_json: str,
                 row_version: bytes | None) -> tuple[Row, list[Row], list[Row]]:
    head, members, fields = db.call_sets(
        "pay.usp_reward_benefit_save", company_id=company_id, actor_user_id=actor_user_id, id=id, name=body.name,
        benefit_type=body.benefit_type, pay_item_id=body.pay_item_id, formula_id=body.formula_id, is_group=body.is_group,
        is_accumulative=body.is_accumulative, description=body.description, members=members_json, fields=fields_json,
        row_version=row_version)
    return head[0], members, fields


def delete_benefit(db: Db, company_id: int, actor_user_id: int, id: int, row_version: bytes) -> None:
    db.call("pay.usp_reward_benefit_delete", company_id=company_id, actor_user_id=actor_user_id, id=id,
            row_version=row_version)


def list_incentives(db: Db, company_id: int, branch_id, month, page: int, page_size: int):
    return _page(db, "pay.usp_sales_incentive_list", company_id=company_id, branch_id=branch_id, month=month, page=page,
                 page_size=page_size)


def get_incentive(db: Db, company_id: int, id: int) -> Row:
    return db.call_one("pay.usp_sales_incentive_get", company_id=company_id, id=id)


def save_incentive(db: Db, company_id: int, actor_user_id: int, id: int | None, body, row_version: bytes | None) -> Row:
    return db.call_one("pay.usp_sales_incentive_save", company_id=company_id, actor_user_id=actor_user_id, id=id,
                       branch_id=body.branch_id, applicable_month=body.applicable_month,
                       incentive_type=body.incentive_type, target_amount=body.target_amount,
                       value_type=body.value_type, reward_value=body.reward_value, description=body.description,
                       row_version=row_version)


def delete_incentive(db: Db, company_id: int, actor_user_id: int, id: int, row_version: bytes) -> None:
    db.call("pay.usp_sales_incentive_delete", company_id=company_id, actor_user_id=actor_user_id, id=id,
            row_version=row_version)


def list_banks(db: Db, company_id: int, search, page: int, page_size: int):
    return _page(db, "pay.usp_disbursement_bank_list", company_id=company_id, search=search, page=page,
                 page_size=page_size)


def get_bank(db: Db, company_id: int, id: int) -> Row:
    return db.call_one("pay.usp_disbursement_bank_get", company_id=company_id, id=id)


def save_bank(db: Db, company_id: int, actor_user_id: int, id: int | None, body, row_version: bytes | None) -> Row:
    return db.call_one("pay.usp_disbursement_bank_save", company_id=company_id, actor_user_id=actor_user_id, id=id,
                       account_holder=body.account_holder, account_number=body.account_number,
                       bank_name=body.bank_name, branch_name=body.branch_name, branch_code=body.branch_code,
                       branch_location=body.branch_location, tax_payer_id=body.tax_payer_id,
                       effective_date=body.effective_date, description=body.description, row_version=row_version)


def delete_bank(db: Db, company_id: int, actor_user_id: int, id: int, row_version: bytes) -> None:
    db.call("pay.usp_disbursement_bank_delete", company_id=company_id, actor_user_id=actor_user_id, id=id,
            row_version=row_version)
