"""Leaves rules. Checks that need the data (duplicates, balances, enrolment conflicts) live in the
procedures; the leave type's dependent fields and slab ranges, which do not, live here.

Applying for leave, approving and cancelling are requests (the requests module); the approval effect
lv.usp_request_apply_leave and the balance function lv.fn_leave_balance are what this module gives it.
"""
import json
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.repos import leaves_repo
from app.schemas.leaves import EncashmentIn, EncashmentUpdateIn, LeavePolicyIn, LeaveTypeIn

# The permission each scoped procedure filters employees by: the code the endpoint required.
APPLICATIONS_VIEW = "leaves.applications.view"
BALANCES_VIEW = "leaves.balances.view"
BALANCES_EDIT = "leaves.balances.edit"
ALLOTMENT_PROCESS = "leaves.allotment.process"
ENCASHMENTS_VIEW = "leaves.encashments.view"
ENCASHMENTS_PROCESS = "leaves.encashments.process"
ENCASHMENTS_EDIT = "leaves.encashments.edit"


def _invalid(errors: dict[str, str]) -> AppError:
    return AppError(422, "VALIDATION_FAILED", "Some fields need your attention.", errors)


# --- General settings ------------------------------------------------------------------------------

def get_settings(db: Db, ctx: RequestContext) -> dict[str, Any]:
    return leaves_repo.get_settings(db, ctx.company_id)


def save_settings(db: Db, ctx: RequestContext, final_approval_by: str, approve_on_status: str, post_deadline: bool,
                  row_version: bytes | None) -> dict[str, Any]:
    return leaves_repo.save_settings(db, ctx.company_id, ctx.user_id, final_approval_by, approve_on_status,
                                     post_deadline, row_version)


# --- Leave types -----------------------------------------------------------------------------------

def _check_type(body: LeaveTypeIn) -> dict[str, Any]:
    """The leave type's fields as the procedure takes them, after the rules between fields.
    Fields that belong to a switch that is off are cleared, so stale values never linger."""
    errors: dict[str, str] = {}
    f = body.model_dump(by_alias=False, exclude={"experience_slabs", "short_slabs", "row_version"})
    if not body.allow_back_date:
        f["back_date_limit_days"] = None
    if body.has_future_limit and body.future_limit_days is None:
        errors["futureLimitDays"] = "Say how many days ahead leave may be applied for."
    if not body.has_future_limit:
        f["future_limit_days"] = None
    if body.attachment_required:
        f["attachment_rule"] = body.attachment_rule or "refuse"
    else:
        f["attachment_rule"] = None
    if body.allow_encashment:
        if body.encashment_min is not None and body.encashment_max is not None and body.encashment_min > body.encashment_max:
            errors["encashmentMax"] = "The maximum cannot be below the minimum."
    else:
        f["encashment_min"] = f["encashment_max"] = None
    if not body.is_sandwich:
        f["sandwich_across_types"] = False
    if body.is_earned and body.tenure == "employment":
        errors["isEarned"] = "Earned balances build up month by month; choose a yearly or monthly tenure."
    if body.balance_basis == "experience":
        if not body.experience_slabs:
            errors["experienceSlabs"] = "Add at least one experience slab."
        slabs = sorted(body.experience_slabs, key=lambda s: s.min_months)
        for i, s in enumerate(body.experience_slabs):
            if s.max_months is not None and s.max_months < s.min_months:
                errors[f"experienceSlabs.{i}.maxMonths"] = "Maximum months cannot be below minimum months."
        for a, b in zip(slabs, slabs[1:]):
            if a.max_months is None or a.max_months >= b.min_months:
                errors["experienceSlabs"] = "Experience slabs overlap."
    if body.is_short_leave:
        for i, s in enumerate(body.short_slabs):
            if s.value_type == "percentage" and s.value is not None and s.value > 100:
                errors[f"shortSlabs.{i}.value"] = "A percentage cannot be above 100."
    if errors:
        raise _invalid(errors)
    return f


def list_types(db: Db, ctx: RequestContext, search: str | None, is_active: bool | None,
               page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return leaves_repo.list_types(db, ctx.company_id, search, is_active, page, page_size)


def get_type(db: Db, ctx: RequestContext, type_id: int) -> dict[str, Any]:
    return leaves_repo.get_type(db, ctx.company_id, type_id)


def save_type(db: Db, ctx: RequestContext, type_id: int | None, body: LeaveTypeIn,
              row_version: bytes | None) -> dict[str, Any]:
    fields = _check_type(body)
    experience = [s.model_dump(by_alias=True, mode="json") for s in body.experience_slabs] \
        if body.balance_basis == "experience" else []
    short = [s.model_dump(by_alias=True, mode="json") for s in body.short_slabs] if body.is_short_leave else []
    return leaves_repo.save_type(db, ctx.company_id, ctx.user_id, type_id, fields, json.dumps(experience),
                                 json.dumps(short), row_version)


def delete_type(db: Db, ctx: RequestContext, type_id: int, row_version: bytes) -> None:
    leaves_repo.delete_type(db, ctx.company_id, ctx.user_id, type_id, row_version)


# --- Leave policies --------------------------------------------------------------------------------

def list_policies(db: Db, ctx: RequestContext, search: str | None, kind: str | None,
                  page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return leaves_repo.list_policies(db, ctx.company_id, search, kind, page, page_size)


def get_policy(db: Db, ctx: RequestContext, policy_id: int) -> dict[str, Any]:
    return leaves_repo.get_policy(db, ctx.company_id, policy_id)


def save_policy(db: Db, ctx: RequestContext, policy_id: int | None, body: LeavePolicyIn,
                row_version: bytes | None) -> dict[str, Any]:
    if body.policy_kind == "distribution":
        if not body.types:
            raise _invalid({"types": "Choose at least one leave type."})
        types = [{"leaveTypeId": t.leave_type_id, "allowance": None if t.allowance is None else float(t.allowance)}
                 for t in body.types]
        half, short = False, False
    else:
        types, half, short = [], body.allow_half_day, body.allow_short_leave
    return leaves_repo.save_policy(db, ctx.company_id, ctx.user_id, policy_id, body.title, body.policy_kind,
                                   body.policy_level, half, short, body.is_active, json.dumps(types), row_version)


def delete_policy(db: Db, ctx: RequestContext, policy_id: int, row_version: bytes) -> None:
    leaves_repo.delete_policy(db, ctx.company_id, ctx.user_id, policy_id, row_version)


def list_enrolled(db: Db, ctx: RequestContext, policy_id: int, search: str | None,
                  page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return leaves_repo.list_enrolled(db, ctx.company_id, policy_id, search, page, page_size)


def enrol(db: Db, ctx: RequestContext, policy_id: int, employee_ids: list[int]) -> dict[str, Any]:
    return leaves_repo.enrol(db, ctx.company_id, ctx.user_id, policy_id, json.dumps([str(i) for i in employee_ids]))


def unenrol(db: Db, ctx: RequestContext, policy_id: int, employee_id: int) -> None:
    leaves_repo.unenrol(db, ctx.company_id, ctx.user_id, policy_id, employee_id)


# --- Balances and ledger ---------------------------------------------------------------------------

def list_balances(db: Db, ctx: RequestContext, employee_id: int | None, leave_type_id: int | None,
                  as_of: date | None, search: str | None, page: int, page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return leaves_repo.list_balances(db, ctx.company_id, ctx.user_id, BALANCES_VIEW, employee_id, leave_type_id,
                                     as_of, search, page, page_size)


def list_ledger(db: Db, ctx: RequestContext, employee_id: int | None, leave_type_id: int | None,
                fiscal_year: int | None, reason: str | None, page: int,
                page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return leaves_repo.list_ledger(db, ctx.company_id, ctx.user_id, BALANCES_VIEW, employee_id, leave_type_id,
                                   fiscal_year, reason, page, page_size)


def add_ledger_entry(db: Db, ctx: RequestContext, employee_id: int, leave_type_id: int, entry_date: date, days: Any,
                     reason: str, remarks: str | None) -> dict[str, Any]:
    return leaves_repo.add_ledger_entry(db, ctx.company_id, ctx.user_id, BALANCES_EDIT, employee_id, leave_type_id,
                                        entry_date, days, reason, remarks)


def process_allotment(db: Db, ctx: RequestContext, fiscal_year: int, as_of: date | None, leave_type_id: int | None,
                      employee_id: int | None) -> dict[str, Any]:
    return leaves_repo.process_allotment(db, ctx.company_id, ctx.user_id, ALLOTMENT_PROCESS, fiscal_year, as_of,
                                         leave_type_id, employee_id)


def process_carry_forward(db: Db, ctx: RequestContext, from_fiscal_year: int, leave_type_id: int | None,
                          employee_id: int | None) -> dict[str, Any]:
    return leaves_repo.process_carry_forward(db, ctx.company_id, ctx.user_id, ALLOTMENT_PROCESS, from_fiscal_year,
                                             leave_type_id, employee_id)


# --- Leave applications ----------------------------------------------------------------------------

def _app_filters(filters: dict[str, Any], with_status: bool) -> dict[str, Any]:
    if filters.get("from_date") and filters.get("to_date") and filters["to_date"] < filters["from_date"]:
        raise _invalid({"toDate": "The end date must be on or after the start date."})
    return {k: v for k, v in filters.items() if with_status or k not in ("status", "search")}


def list_applications(db: Db, ctx: RequestContext, tab: str, filters: dict[str, Any], page: int,
                      page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return leaves_repo.list_applications(db, ctx.company_id, ctx.user_id, APPLICATIONS_VIEW, tab,
                                         _app_filters(filters, True), page, page_size)


def count_applications(db: Db, ctx: RequestContext, tab: str, filters: dict[str, Any]) -> dict[str, Any]:
    return leaves_repo.count_applications(db, ctx.company_id, ctx.user_id, APPLICATIONS_VIEW, tab,
                                          _app_filters(filters, False))


def get_application(db: Db, ctx: RequestContext, application_id: int) -> dict[str, Any]:
    return leaves_repo.get_application(db, ctx.company_id, ctx.user_id, APPLICATIONS_VIEW, application_id)


# --- Leave encashment ------------------------------------------------------------------------------

def list_encashments(db: Db, ctx: RequestContext, leave_type_id: int | None, fiscal_year: int | None,
                     employee_id: int | None, mode: str | None, page: int,
                     page_size: int) -> tuple[int, list[dict[str, Any]]]:
    return leaves_repo.list_encashments(db, ctx.company_id, ctx.user_id, ENCASHMENTS_VIEW, leave_type_id,
                                        fiscal_year, employee_id, mode, page, page_size)


def get_encashment(db: Db, ctx: RequestContext, encashment_id: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    return leaves_repo.get_encashment(db, ctx.company_id, ctx.user_id, ENCASHMENTS_VIEW, encashment_id)


def create_encashment(db: Db, ctx: RequestContext, body: EncashmentIn) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if not body.applies_to_all and not body.employee_ids:
        raise _invalid({"employeeIds": "Choose the employees, or all employees."})
    ids = None if body.applies_to_all else json.dumps([str(i) for i in body.employee_ids])
    return leaves_repo.save_encashment(db, ctx.company_id, ctx.user_id, ENCASHMENTS_PROCESS, None, body.leave_type_id,
                                       body.fiscal_year, body.encashment_date, body.applies_to_all, ids, body.basis,
                                       body.amount_per_leave, body.mode, None)


def update_encashment(db: Db, ctx: RequestContext, encashment_id: int, body: EncashmentUpdateIn,
                      row_version: bytes) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    return leaves_repo.save_encashment(db, ctx.company_id, ctx.user_id, ENCASHMENTS_EDIT, encashment_id, None, None,
                                       body.encashment_date, False, None, body.basis, body.amount_per_leave, body.mode,
                                       row_version)


def delete_encashment(db: Db, ctx: RequestContext, encashment_id: int, row_version: bytes) -> None:
    leaves_repo.delete_encashment(db, ctx.company_id, ctx.user_id, encashment_id, row_version)
