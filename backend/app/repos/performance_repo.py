"""Performance data access (procedures in the perf schema). The only layer that knows procedure names.

Applying an increment also calls payroll's pay.usp_salary_revision_save: the salary revision is payroll's
record and its rules (newest salary only, no closed month) must hold for increments too."""
from datetime import date
from decimal import Decimal
from typing import Any

from app.core.db import Db


def _page(db: Db, proc: str, **params: Any) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets(proc, **params)[:2]
    return total[0]["total"], rows


# --- Rating scales -------------------------------------------------------------------------------

def list_scales(db: Db, company_id: int, search: str | None, is_active: bool | None, page: int,
                page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "perf.usp_rating_scale_list", company_id=company_id, search=search, is_active=is_active, page=page,
                 page_size=page_size)


def get_scale(db: Db, company_id: int, scale_id: int) -> dict[str, Any]:
    return db.call_one("perf.usp_rating_scale_get", company_id=company_id, id=scale_id)


def save_scale(db: Db, company_id: int, actor_user_id: int, scale_id: int | None, name: str, is_default: bool,
               is_active: bool, levels: str, row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("perf.usp_rating_scale_save", company_id=company_id, actor_user_id=actor_user_id, id=scale_id,
                       name=name, is_default=is_default, is_active=is_active, levels=levels, row_version=row_version)


def delete_scale(db: Db, company_id: int, actor_user_id: int, scale_id: int, row_version: bytes) -> None:
    db.call("perf.usp_rating_scale_delete", company_id=company_id, actor_user_id=actor_user_id, id=scale_id,
            row_version=row_version)


# --- Appraisal forms -----------------------------------------------------------------------------

def list_forms(db: Db, company_id: int, search: str | None, is_active: bool | None, page: int,
               page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "perf.usp_appraisal_form_list", company_id=company_id, search=search, is_active=is_active,
                 page=page, page_size=page_size)


def get_form(db: Db, company_id: int, form_id: int) -> dict[str, Any]:
    return db.call_one("perf.usp_appraisal_form_get", company_id=company_id, id=form_id)


def save_form(db: Db, company_id: int, actor_user_id: int, form_id: int | None, name: str, description: str | None,
              rating_scale_id: int, goals_weight: Decimal, has_self_review: bool, is_active: bool, criteria: str,
              row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("perf.usp_appraisal_form_save", company_id=company_id, actor_user_id=actor_user_id, id=form_id,
                       name=name, description=description, rating_scale_id=rating_scale_id, goals_weight=goals_weight,
                       has_self_review=has_self_review, is_active=is_active, criteria=criteria,
                       row_version=row_version)


def delete_form(db: Db, company_id: int, actor_user_id: int, form_id: int, row_version: bytes) -> None:
    db.call("perf.usp_appraisal_form_delete", company_id=company_id, actor_user_id=actor_user_id, id=form_id,
            row_version=row_version)


# --- KPIs ----------------------------------------------------------------------------------------

def list_kpis(db: Db, company_id: int, search: str | None, key_result_area: str | None, department_id: int | None,
              is_active: bool | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "perf.usp_kpi_list", company_id=company_id, search=search, key_result_area=key_result_area,
                 department_id=department_id, is_active=is_active, page=page, page_size=page_size)


def get_kpi(db: Db, company_id: int, kpi_id: int) -> dict[str, Any]:
    return db.call_one("perf.usp_kpi_get", company_id=company_id, id=kpi_id)


def save_kpi(db: Db, company_id: int, actor_user_id: int, kpi_id: int | None, fields: dict[str, Any],
             row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("perf.usp_kpi_save", company_id=company_id, actor_user_id=actor_user_id, id=kpi_id, **fields,
                       row_version=row_version)


def delete_kpi(db: Db, company_id: int, actor_user_id: int, kpi_id: int, row_version: bytes) -> None:
    db.call("perf.usp_kpi_delete", company_id=company_id, actor_user_id=actor_user_id, id=kpi_id,
            row_version=row_version)


# --- Goals ---------------------------------------------------------------------------------------

def list_goals(db: Db, company_id: int, actor_user_id: int, permission_code: str, tab: str, employee_id: int | None,
               status: str | None, appraisal_cycle_id: int | None, overdue: bool | None, due_from: date | None,
               due_to: date | None, search: str | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "perf.usp_goal_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=permission_code, tab=tab, employee_id=employee_id, status=status,
                 appraisal_cycle_id=appraisal_cycle_id, overdue=overdue, due_from=due_from, due_to=due_to,
                 search=search, page=page, page_size=page_size)


def get_goal(db: Db, company_id: int, actor_user_id: int, permission_code: str,
             goal_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    goal, check_ins = db.call_sets("perf.usp_goal_get", company_id=company_id, actor_user_id=actor_user_id,
                                   permission_code=permission_code, id=goal_id)
    return goal[0], check_ins


def save_goal(db: Db, company_id: int, actor_user_id: int, permission_code: str, goal_id: int | None,
              fields: dict[str, Any], row_version: bytes | None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    goal, check_ins = db.call_sets("perf.usp_goal_save", company_id=company_id, actor_user_id=actor_user_id,
                                   permission_code=permission_code, id=goal_id, **fields, row_version=row_version)
    return goal[0], check_ins


def delete_goal(db: Db, company_id: int, actor_user_id: int, permission_code: str, goal_id: int,
                row_version: bytes) -> None:
    db.call("perf.usp_goal_delete", company_id=company_id, actor_user_id=actor_user_id,
            permission_code=permission_code, id=goal_id, row_version=row_version)


# --- Appraisal cycles ----------------------------------------------------------------------------

def list_cycles(db: Db, company_id: int, status: str | None, search: str | None, page: int,
                page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "perf.usp_appraisal_cycle_list", company_id=company_id, status=status, search=search, page=page,
                 page_size=page_size)


def get_cycle(db: Db, company_id: int, cycle_id: int) -> dict[str, Any]:
    return db.call_one("perf.usp_appraisal_cycle_get", company_id=company_id, id=cycle_id)


def save_cycle(db: Db, company_id: int, actor_user_id: int, cycle_id: int | None, fields: dict[str, Any],
               row_version: bytes | None) -> dict[str, Any]:
    return db.call_one("perf.usp_appraisal_cycle_save", company_id=company_id, actor_user_id=actor_user_id,
                       id=cycle_id, **fields, row_version=row_version)


def delete_cycle(db: Db, company_id: int, actor_user_id: int, cycle_id: int, row_version: bytes) -> None:
    db.call("perf.usp_appraisal_cycle_delete", company_id=company_id, actor_user_id=actor_user_id, id=cycle_id,
            row_version=row_version)


def add_participants(db: Db, company_id: int, actor_user_id: int, permission_code: str, cycle_id: int,
                     employee_ids: str, department_id: int | None) -> tuple[dict[str, Any], int]:
    cycle, added = db.call_sets("perf.usp_appraisal_cycle_participants_add", company_id=company_id,
                                actor_user_id=actor_user_id, permission_code=permission_code, id=cycle_id,
                                employee_ids=employee_ids, department_id=department_id)
    return cycle[0], added[0]["added"]


def launch_cycle(db: Db, company_id: int, actor_user_id: int, cycle_id: int, row_version: bytes) -> dict[str, Any]:
    return db.call_one("perf.usp_appraisal_cycle_launch", company_id=company_id, actor_user_id=actor_user_id,
                       id=cycle_id, row_version=row_version)


def close_cycle(db: Db, company_id: int, actor_user_id: int, cycle_id: int, row_version: bytes) -> dict[str, Any]:
    return db.call_one("perf.usp_appraisal_cycle_close", company_id=company_id, actor_user_id=actor_user_id,
                       id=cycle_id, row_version=row_version)


# --- Appraisals ----------------------------------------------------------------------------------

def list_appraisals(db: Db, company_id: int, actor_user_id: int, permission_code: str, tab: str,
                    appraisal_cycle_id: int | None, status: str | None, employee_id: int | None, search: str | None,
                    page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "perf.usp_appraisal_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=permission_code, tab=tab, appraisal_cycle_id=appraisal_cycle_id, status=status,
                 employee_id=employee_id, search=search, page=page, page_size=page_size)


def _detail(sets: list[list[dict[str, Any]]]) -> dict[str, Any]:
    appraisal, ratings, goals, scale, increment = sets
    return {**appraisal[0], "ratings": ratings, "goals": goals, "scale": scale,
            "increment": increment[0] if increment else None}


def get_appraisal(db: Db, company_id: int, actor_user_id: int, permission_code: str,
                  appraisal_id: int) -> dict[str, Any]:
    return _detail(db.call_sets("perf.usp_appraisal_get", company_id=company_id, actor_user_id=actor_user_id,
                                permission_code=permission_code, id=appraisal_id))


def save_review(db: Db, company_id: int, actor_user_id: int, permission_code: str, appraisal_id: int, stage: str,
                ratings: str, comments: str | None, development_needs: str | None, submit: bool,
                row_version: bytes) -> dict[str, Any]:
    return _detail(db.call_sets("perf.usp_appraisal_review_save", company_id=company_id, actor_user_id=actor_user_id,
                                permission_code=permission_code, id=appraisal_id, stage=stage, ratings=ratings,
                                comments=comments, development_needs=development_needs, submit=submit,
                                row_version=row_version))


def finalise(db: Db, company_id: int, actor_user_id: int, permission_code: str, appraisal_id: int,
             fields: dict[str, Any], row_version: bytes) -> dict[str, Any]:
    return _detail(db.call_sets("perf.usp_appraisal_finalise", company_id=company_id, actor_user_id=actor_user_id,
                                permission_code=permission_code, id=appraisal_id, **fields, row_version=row_version))


def delete_appraisal(db: Db, company_id: int, actor_user_id: int, permission_code: str, appraisal_id: int,
                     row_version: bytes) -> None:
    db.call("perf.usp_appraisal_delete", company_id=company_id, actor_user_id=actor_user_id,
            permission_code=permission_code, id=appraisal_id, row_version=row_version)


# --- Increments ----------------------------------------------------------------------------------

def list_increments(db: Db, company_id: int, actor_user_id: int, permission_code: str, status: str | None,
                    appraisal_cycle_id: int | None, employee_id: int | None, search: str | None, page: int,
                    page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return _page(db, "perf.usp_increment_list", company_id=company_id, actor_user_id=actor_user_id,
                 permission_code=permission_code, status=status, appraisal_cycle_id=appraisal_cycle_id,
                 employee_id=employee_id, search=search, page=page, page_size=page_size)


def get_increment(db: Db, company_id: int, actor_user_id: int, permission_code: str,
                  increment_id: int) -> dict[str, Any]:
    return db.call_one("perf.usp_increment_get", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=increment_id)


def decide_increment(db: Db, company_id: int, actor_user_id: int, permission_code: str, increment_id: int,
                     decision: str, employee_salary_id: int | None, remarks: str | None,
                     row_version: bytes) -> dict[str, Any]:
    return db.call_one("perf.usp_increment_decide", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, id=increment_id, decision=decision,
                       employee_salary_id=employee_salary_id, remarks=remarks, row_version=row_version)


def salary_revision_save(db: Db, company_id: int, actor_user_id: int, permission_code: str, employee_id: int,
                         effective_date: date, change_type: str, change_value: Decimal) -> dict[str, Any]:
    """Payroll's Salary Revision (pay schema): writes the hr.employee_salary row an increment becomes."""
    return db.call_one("pay.usp_salary_revision_save", company_id=company_id, actor_user_id=actor_user_id,
                       permission_code=permission_code, employee_id=employee_id, effective_date=effective_date,
                       change_type=change_type, change_value=change_value, source="revision")


# --- Overview ------------------------------------------------------------------------------------

def overview(db: Db, company_id: int, actor_user_id: int, permission_code: str,
             employee_id: int | None) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    person, upcoming, appraisals = db.call_sets("perf.usp_performance_overview", company_id=company_id,
                                                actor_user_id=actor_user_id, permission_code=permission_code,
                                                employee_id=employee_id)
    return person[0], upcoming, appraisals
