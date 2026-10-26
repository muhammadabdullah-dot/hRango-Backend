"""HTTP shape for employee records: envelopes, row versions as text, rows to response models,
file ids to signed links."""
import json
from typing import Any

from pydantic import BaseModel
from pydantic.alias_generators import to_camel

from app.core.db import Db
from app.core.files import file_url
from app.core.paging import PageParams
from app.core.rowversion import row_version_in, row_version_out
from app.middlewares.auth import RequestContext
from app.schemas.common import paginated
from app.schemas.employees import (BankAccountIn, BankAccountOut, ChangeOut, ContractOut, DependentOut, DocumentOut,
                                   EducationOut, EmergencyContactOut, EmployeeIn, EmployeeLookupOut, EmployeeOut,
                                   EmploymentPeriodIn, EmploymentPeriodOut, ExperienceOut, HistoryOut, IdentityIn,
                                   PhotoIn, SalaryIn, SalaryOut, SkillOut, UpdateRequestIn, UpdateRequestOut)
from app.schemas.files import FileRef
from app.services import employees_service as s

# Profile tab -> its response model.
TAB_OUT: dict[str, type[BaseModel]] = {
    "emergency_contacts": EmergencyContactOut, "dependents": DependentOut, "skills": SkillOut,
    "education": EducationOut, "experience": ExperienceOut, "contracts": ContractOut, "documents": DocumentOut,
}


def _rv(row: dict[str, Any]) -> dict[str, Any]:
    return {**row, "row_version": row_version_out(row["row_version"])}


def _employee(row: dict[str, Any], company_id: int) -> EmployeeOut:
    return EmployeeOut(**_rv(row), photo_url=file_url(row.get("photo_file_id"), company_id))


def list_employees(db: Db, ctx: RequestContext, filters: dict[str, Any], paging: PageParams) -> dict:
    total, rows = s.list_employees(db, ctx, filters, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: _employee(r, ctx.company_id))


def lookup(db: Db, ctx: RequestContext, permission: str, q: str | None, branch_id: int | None,
           department_id: int | None, include_inactive: bool, page: int, page_size: int) -> dict:
    total, rows = s.lookup(db, ctx, permission, q, branch_id, department_id, include_inactive, page, page_size)
    return paginated(rows, total, page, page_size,
                     lambda r: EmployeeLookupOut(**r, photo_url=file_url(r.get("photo_file_id"), ctx.company_id)))


def get_employee(db: Db, ctx: RequestContext, employee_id: int) -> dict:
    return {"data": _employee(s.get_employee(db, ctx, employee_id), ctx.company_id)}


def create_employee(db: Db, ctx: RequestContext, body: EmployeeIn) -> dict:
    row = s.create_employee(db, ctx, body.model_dump(by_alias=False, exclude={"row_version"}))
    return {"data": _employee(row, ctx.company_id)}


def update_employee(db: Db, ctx: RequestContext, employee_id: int, body: EmployeeIn) -> dict:
    row = s.update_employee(db, ctx, employee_id, body.model_dump(by_alias=False, exclude={"row_version", "cnic"}),
                            row_version_in(body.row_version))
    return {"data": _employee(row, ctx.company_id)}


def save_identity(db: Db, ctx: RequestContext, employee_id: int, body: IdentityIn) -> dict:
    row = s.save_identity(db, ctx, employee_id, body.cnic, row_version_in(body.row_version))
    return {"data": _employee(row, ctx.company_id)}


def set_active(db: Db, ctx: RequestContext, employee_id: int, active: bool, row_version: str) -> dict:
    row = s.set_active(db, ctx, employee_id, active, row_version_in(row_version))
    return {"data": _employee(row, ctx.company_id)}


def list_periods(db: Db, ctx: RequestContext, employee_id: int) -> dict:
    return {"data": [EmploymentPeriodOut(**_rv(r)) for r in s.list_periods(db, ctx, employee_id)]}


def save_period(db: Db, ctx: RequestContext, employee_id: int, period_id: int | None, body: EmploymentPeriodIn) -> dict:
    rv = row_version_in(body.row_version) if period_id is not None else None
    return {"data": EmploymentPeriodOut(**_rv(s.save_period(db, ctx, employee_id, period_id, body.model_dump(by_alias=False), rv)))}


def list_history(db: Db, ctx: RequestContext, employee_id: int) -> dict:
    return {"data": [HistoryOut(**r) for r in s.list_history(db, ctx, employee_id)]}


def list_changes(db: Db, ctx: RequestContext, employee_id: int, paging: PageParams) -> dict:
    total, rows = s.list_changes(db, ctx, employee_id, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, lambda r: ChangeOut(**r))


def list_salary(db: Db, ctx: RequestContext, employee_id: int) -> dict:
    return {"data": [SalaryOut(**_rv(r)) for r in s.list_salary(db, ctx, employee_id)]}


def save_salary(db: Db, ctx: RequestContext, employee_id: int, salary_id: int | None, body: SalaryIn) -> dict:
    rv = row_version_in(body.row_version) if salary_id is not None else None
    return {"data": SalaryOut(**_rv(s.save_salary(db, ctx, employee_id, salary_id, body.model_dump(by_alias=False), rv)))}


def delete_salary(db: Db, ctx: RequestContext, employee_id: int, salary_id: int, row_version: str | None) -> None:
    s.delete_salary(db, ctx, employee_id, salary_id, row_version_in(row_version))


def list_bank_accounts(db: Db, ctx: RequestContext, employee_id: int) -> dict:
    return {"data": [BankAccountOut(**_rv(r)) for r in s.list_bank_accounts(db, ctx, employee_id)]}


def save_bank_account(db: Db, ctx: RequestContext, employee_id: int, account_id: int | None,
                      body: BankAccountIn) -> dict:
    rv = row_version_in(body.row_version) if account_id is not None else None
    row = s.save_bank_account(db, ctx, employee_id, account_id, body.model_dump(by_alias=False), rv)
    return {"data": BankAccountOut(**_rv(row))}


def delete_bank_account(db: Db, ctx: RequestContext, employee_id: int, account_id: int, row_version: str | None) -> None:
    s.delete_bank_account(db, ctx, employee_id, account_id, row_version_in(row_version))


# ---------------------------------------------------------------- profile

def save_photo(db: Db, ctx: RequestContext, employee_id: int, body: PhotoIn) -> dict:
    row = s.save_photo(db, ctx, employee_id, body.file_id, row_version_in(body.row_version))
    return {"data": _employee(row, ctx.company_id)}


def _tab_row(tab: str, row: dict[str, Any], company_id: int) -> BaseModel:
    out = _rv(row)
    if "file_id" in row:
        fid = row["file_id"]
        out["file"] = FileRef(id=fid, name=row.get("file_name"), url=file_url(fid, company_id)) if fid else None
    return TAB_OUT[tab](**out)


def list_tab(db: Db, ctx: RequestContext, tab: str, employee_id: int) -> dict:
    return {"data": [_tab_row(tab, r, ctx.company_id) for r in s.list_tab(db, ctx, tab, employee_id)]}


def save_tab(db: Db, ctx: RequestContext, tab: str, employee_id: int, row_id: int | None, body: BaseModel) -> dict:
    fields = body.model_dump(by_alias=False, exclude={"row_version"})
    rv = row_version_in(body.row_version) if row_id is not None else None
    return {"data": _tab_row(tab, s.save_tab(db, ctx, tab, employee_id, row_id, fields, rv), ctx.company_id)}


def delete_tab(db: Db, ctx: RequestContext, tab: str, employee_id: int, row_id: int, row_version: str | None) -> None:
    s.delete_tab(db, ctx, tab, employee_id, row_id, row_version_in(row_version))


# ---------------------------------------------------------------- Update Information requests

def _camel(values: dict[str, Any]) -> dict[str, Any]:
    return {to_camel(k): (str(v) if k.endswith("_id") and v is not None else v) for k, v in values.items()}


def _update_request(row: dict[str, Any]) -> UpdateRequestOut:
    changes = json.loads(row["changes"] or "{}")
    previous = json.loads(row["previous_values"] or "{}")
    return UpdateRequestOut(**{**_rv(row), "changes": _camel(changes),
                               "previous": _camel({k: previous.get(k) for k in changes})})


def list_update_requests(db: Db, ctx: RequestContext, employee_id: int | None, status: str | None,
                         paging: PageParams) -> dict:
    total, rows = s.list_update_requests(db, ctx, employee_id, status, paging.page, paging.page_size)
    return paginated(rows, total, paging.page, paging.page_size, _update_request)


def get_update_request(db: Db, ctx: RequestContext, request_id: int) -> dict:
    return {"data": _update_request(s.get_update_request(db, ctx, request_id))}


def submit_update_request(db: Db, ctx: RequestContext, employee_id: int, body: UpdateRequestIn) -> dict:
    changes = body.changes.model_dump(mode="json", by_alias=False, exclude_unset=True)
    return {"data": _update_request(s.submit_update_request(db, ctx, employee_id, changes, body.remarks))}


def decide_update_request(db: Db, ctx: RequestContext, request_id: int, decision: str, remarks: str | None,
                          row_version: str) -> dict:
    row = s.decide_update_request(db, ctx, request_id, decision, remarks, row_version_in(row_version))
    return {"data": _update_request(row)}
