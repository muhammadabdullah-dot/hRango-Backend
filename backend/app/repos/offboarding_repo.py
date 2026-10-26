"""Off-boarding data access. The only layer that knows procedure names and parameters."""
import json
from datetime import date
from typing import Any

from app.core.db import Db


# --- End of employment ---------------------------------------------------------------------------

def list_end_of_employment(db: Db, company_id: int, actor_user_id: int, filters: dict[str, Any],
                           page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets(
        "sep.usp_end_of_employment_list", company_id=company_id, actor_user_id=actor_user_id,
        search=filters["search"], status=filters["status"], employee_id=filters["employee_id"],
        department_id=filters["department_id"], branch_id=filters["branch_id"], location_id=filters["location_id"],
        designation_id=filters["designation_id"], serve_notice=filters["serve_notice"],
        from_date=filters["from_date"], to_date=filters["to_date"], page=page, page_size=page_size)
    return total[0]["total"], rows


def _record(sets: list[list[dict[str, Any]]]) -> dict[str, Any]:
    return {**sets[0][0], "answers": sets[1] if len(sets) > 1 else [], "waiting_for": sets[2] if len(sets) > 2 else []}


def get_end_of_employment(db: Db, company_id: int, actor_user_id: int, record_id: int) -> dict[str, Any]:
    return _record(db.call_sets("sep.usp_end_of_employment_get", company_id=company_id, actor_user_id=actor_user_id,
                                id=record_id))


def save_end_of_employment(db: Db, company_id: int, actor_user_id: int, record_id: int | None,
                           fields: dict[str, Any], row_version: bytes | None) -> dict[str, Any]:
    return _record(db.call_sets(
        "sep.usp_end_of_employment_save", company_id=company_id, actor_user_id=actor_user_id, id=record_id,
        employee_id=fields["employee_id"], reason=fields["reason"], serve_notice=fields["serve_notice"],
        notice_period_days=fields["notice_period_days"], last_working_date=fields["last_working_date"],
        needs_final_settlement=fields["needs_final_settlement"], needs_asset_clearance=fields["needs_asset_clearance"],
        asset_clear_by_date=fields["asset_clear_by_date"], replacement_id=fields["replacement_id"],
        delegatee_id=fields["delegatee_id"], description=fields["description"], file_id=fields["file_id"],
        row_version=row_version))


def save_checklist_answers(db: Db, company_id: int, actor_user_id: int, record_id: int,
                           answers: list[dict[str, Any]], row_version: bytes) -> dict[str, Any]:
    return _record(db.call_sets("sep.usp_end_of_employment_checklist_save", company_id=company_id,
                                actor_user_id=actor_user_id, id=record_id, answers=json.dumps(answers),
                                row_version=row_version))


def complete_end_of_employment(db: Db, company_id: int, actor_user_id: int, record_id: int,
                               row_version: bytes) -> dict[str, Any]:
    return _record(db.call_sets("sep.usp_end_of_employment_complete", company_id=company_id,
                                actor_user_id=actor_user_id, id=record_id, row_version=row_version))


def rehire(db: Db, company_id: int, actor_user_id: int, record_id: int, joining_date: date,
           row_version: bytes) -> dict[str, Any]:
    return _record(db.call_sets("sep.usp_end_of_employment_rehire", company_id=company_id,
                                actor_user_id=actor_user_id, id=record_id, joining_date=joining_date,
                                row_version=row_version))


def delete_end_of_employment(db: Db, company_id: int, actor_user_id: int, record_id: int, row_version: bytes) -> None:
    db.call("sep.usp_end_of_employment_delete", company_id=company_id, actor_user_id=actor_user_id, id=record_id,
            row_version=row_version)


def active_checklist_fields(db: Db, company_id: int) -> list[dict[str, Any]]:
    return db.call("sep.usp_checklist_field_active_list", company_id=company_id)


# --- Off-boarding checklist settings -------------------------------------------------------------

def list_checklists(db: Db, company_id: int, search: str | None, is_active: bool | None,
                    page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    total, rows = db.call_sets("sep.usp_offboarding_checklist_list", company_id=company_id, search=search,
                               is_active=is_active, page=page, page_size=page_size)
    return total[0]["total"], rows


def _checklist(sets: list[list[dict[str, Any]]]) -> dict[str, Any]:
    return {**sets[0][0], "fields": sets[1] if len(sets) > 1 else []}


def get_checklist(db: Db, company_id: int, checklist_id: int) -> dict[str, Any]:
    return _checklist(db.call_sets("sep.usp_offboarding_checklist_get", company_id=company_id, id=checklist_id))


def save_checklist(db: Db, company_id: int, actor_user_id: int, checklist_id: int | None, name: str,
                   description: str | None, is_active: bool, fields: list[dict[str, Any]],
                   row_version: bytes | None) -> dict[str, Any]:
    return _checklist(db.call_sets("sep.usp_offboarding_checklist_save", company_id=company_id,
                                   actor_user_id=actor_user_id, id=checklist_id, name=name, description=description,
                                   is_active=is_active, fields=json.dumps(fields), row_version=row_version))


def delete_checklist(db: Db, company_id: int, actor_user_id: int, checklist_id: int, row_version: bytes) -> None:
    db.call("sep.usp_offboarding_checklist_delete", company_id=company_id, actor_user_id=actor_user_id,
            id=checklist_id, row_version=row_version)
