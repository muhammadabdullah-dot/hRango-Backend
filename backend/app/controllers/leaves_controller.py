"""HTTP shape for the Leaves screens: envelopes, row versions as text, rows to response models."""
import json
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.leaves import (AllotmentIn, AllotmentOut, ApplicationCountsOut, BalanceOut, CarryForwardIn,
                                CarryForwardOut, EncashmentDetailOut, EncashmentIn, EncashmentOut,
                                EncashmentUpdateIn, EnrolledEmployeeOut, LeaveApplicationDetailOut,
                                LeaveApplicationOut, LeaveBalanceOut, LeavePolicyIn, LeavePolicyOut, LeaveSettingsIn,
                                LeaveSettingsOut, LeaveTypeIn, LeaveTypeOut, LedgerEntryIn, LedgerEntryOut)
from app.services import leaves_service


def _json_list(text: str | None) -> list[dict[str, Any]]:
    return json.loads(text) if text else []


def _versioned(row: dict[str, Any]) -> dict[str, Any]:
    return {**row, "row_version": row_version_out(row["row_version"])}


# --- General settings ------------------------------------------------------------------------------

def _settings(row: dict[str, Any]) -> LeaveSettingsOut:
    return LeaveSettingsOut(**_versioned(row))


def get_settings(db: Db, ctx: RequestContext) -> dict:
    return {"data": _settings(leaves_service.get_settings(db, ctx))}


def save_settings(db: Db, ctx: RequestContext, body: LeaveSettingsIn) -> dict:
    row = leaves_service.save_settings(db, ctx, body.final_approval_by, body.approve_on_status, body.post_deadline,
                                       row_version_in(body.row_version, required=False))
    return {"data": _settings(row)}


# --- Leave types -----------------------------------------------------------------------------------

def _type(row: dict[str, Any]) -> LeaveTypeOut:
    short = [{"name": s["name"], "balance": s.get("balance"), "value_type": s["value_type"],
              "value": s.get("slab_value")} for s in _json_list(row["short_slabs"])]
    return LeaveTypeOut(**{**_versioned(row), "experience_slabs": _json_list(row["experience_slabs"]),
                           "short_slabs": short})


def list_types(db: Db, ctx: RequestContext, q: str | None, is_active: bool | None, paging: PageParams) -> dict:
    total, rows = leaves_service.list_types(db, ctx, q, is_active, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _type)


def get_type(db: Db, ctx: RequestContext, type_id: int) -> dict:
    return {"data": _type(leaves_service.get_type(db, ctx, type_id))}


def create_type(db: Db, ctx: RequestContext, body: LeaveTypeIn) -> dict:
    return {"data": _type(leaves_service.save_type(db, ctx, None, body, None))}


def update_type(db: Db, ctx: RequestContext, type_id: int, body: LeaveTypeIn) -> dict:
    return {"data": _type(leaves_service.save_type(db, ctx, type_id, body, row_version_in(body.row_version)))}


def delete_type(db: Db, ctx: RequestContext, type_id: int, row_version: str | None) -> None:
    leaves_service.delete_type(db, ctx, type_id, row_version_in(row_version))


# --- Leave policies --------------------------------------------------------------------------------

def _policy(row: dict[str, Any]) -> LeavePolicyOut:
    return LeavePolicyOut(**{**_versioned(row), "types": _json_list(row["types"])})


def list_policies(db: Db, ctx: RequestContext, q: str | None, kind: str | None, paging: PageParams) -> dict:
    total, rows = leaves_service.list_policies(db, ctx, q, kind, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _policy)


def get_policy(db: Db, ctx: RequestContext, policy_id: int) -> dict:
    return {"data": _policy(leaves_service.get_policy(db, ctx, policy_id))}


def create_policy(db: Db, ctx: RequestContext, body: LeavePolicyIn) -> dict:
    return {"data": _policy(leaves_service.save_policy(db, ctx, None, body, None))}


def update_policy(db: Db, ctx: RequestContext, policy_id: int, body: LeavePolicyIn) -> dict:
    return {"data": _policy(leaves_service.save_policy(db, ctx, policy_id, body, row_version_in(body.row_version)))}


def delete_policy(db: Db, ctx: RequestContext, policy_id: int, row_version: str | None) -> None:
    leaves_service.delete_policy(db, ctx, policy_id, row_version_in(row_version))


def list_enrolled(db: Db, ctx: RequestContext, policy_id: int, q: str | None, paging: PageParams) -> dict:
    total, rows = leaves_service.list_enrolled(db, ctx, policy_id, q, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: EnrolledEmployeeOut(**r))


def enrol(db: Db, ctx: RequestContext, policy_id: int, employee_ids: list[int]) -> dict:
    return {"data": _policy(leaves_service.enrol(db, ctx, policy_id, employee_ids))}


def unenrol(db: Db, ctx: RequestContext, policy_id: int, employee_id: int) -> None:
    leaves_service.unenrol(db, ctx, policy_id, employee_id)


# --- Balances and ledger ---------------------------------------------------------------------------

def list_balances(db: Db, ctx: RequestContext, employee_id: int | None, leave_type_id: int | None,
                  as_of: date | None, q: str | None, paging: PageParams) -> dict:
    total, rows = leaves_service.list_balances(db, ctx, employee_id, leave_type_id, as_of, q, paging.page,
                                               paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: BalanceOut(**r))


def list_ledger(db: Db, ctx: RequestContext, employee_id: int | None, leave_type_id: int | None,
                fiscal_year: int | None, reason: str | None, paging: PageParams) -> dict:
    total, rows = leaves_service.list_ledger(db, ctx, employee_id, leave_type_id, fiscal_year, reason, paging.page,
                                             paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: LedgerEntryOut(**r))


def add_ledger_entry(db: Db, ctx: RequestContext, body: LedgerEntryIn) -> dict:
    row = leaves_service.add_ledger_entry(db, ctx, body.employee_id, body.leave_type_id, body.entry_date, body.days,
                                          body.reason, body.remarks)
    return {"data": LedgerEntryOut(**row)}


def process_allotment(db: Db, ctx: RequestContext, body: AllotmentIn) -> dict:
    row = leaves_service.process_allotment(db, ctx, body.fiscal_year, body.as_of, body.leave_type_id,
                                           body.employee_id)
    return {"data": AllotmentOut(**row)}


def process_carry_forward(db: Db, ctx: RequestContext, body: CarryForwardIn) -> dict:
    row = leaves_service.process_carry_forward(db, ctx, body.from_fiscal_year, body.leave_type_id, body.employee_id)
    return {"data": CarryForwardOut(**row)}


# --- Leave applications ----------------------------------------------------------------------------

def list_applications(db: Db, ctx: RequestContext, tab: str, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows = leaves_service.list_applications(db, ctx, tab, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: LeaveApplicationOut(**r))


def count_applications(db: Db, ctx: RequestContext, tab: str, filters: dict[str, Any]) -> dict:
    row = leaves_service.count_applications(db, ctx, tab, filters)
    return {"data": ApplicationCountsOut(**{k: v or 0 for k, v in row.items()})}


def get_application(db: Db, ctx: RequestContext, application_id: int) -> dict:
    row = leaves_service.get_application(db, ctx, application_id)
    balance = None if row["balance_entitled"] is None else LeaveBalanceOut(
        entitled=row["balance_entitled"], used=row["balance_used"], pending=row["balance_pending"],
        available=row["balance_available"])
    return {"data": LeaveApplicationDetailOut(**row, balance=balance)}


# --- Leave encashment ------------------------------------------------------------------------------

def _encashment(head: dict[str, Any], lines: list[dict[str, Any]]) -> EncashmentDetailOut:
    return EncashmentDetailOut(**_versioned(head), lines=lines)


def list_encashments(db: Db, ctx: RequestContext, leave_type_id: int | None, fiscal_year: int | None,
                     employee_id: int | None, mode: str | None, paging: PageParams) -> dict:
    total, rows = leaves_service.list_encashments(db, ctx, leave_type_id, fiscal_year, employee_id, mode,
                                                  paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: EncashmentOut(**_versioned(r)))


def get_encashment(db: Db, ctx: RequestContext, encashment_id: int) -> dict:
    return {"data": _encashment(*leaves_service.get_encashment(db, ctx, encashment_id))}


def create_encashment(db: Db, ctx: RequestContext, body: EncashmentIn) -> dict:
    return {"data": _encashment(*leaves_service.create_encashment(db, ctx, body))}


def update_encashment(db: Db, ctx: RequestContext, encashment_id: int, body: EncashmentUpdateIn) -> dict:
    return {"data": _encashment(*leaves_service.update_encashment(db, ctx, encashment_id, body,
                                                                  row_version_in(body.row_version)))}


def delete_encashment(db: Db, ctx: RequestContext, encashment_id: int, row_version: str | None) -> None:
    leaves_service.delete_encashment(db, ctx, encashment_id, row_version_in(row_version))
