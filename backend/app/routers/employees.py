"""Employee records (Talent Management): directory and picker, the employee card, employment
periods, placement history, the sensitive salary, bank and CNIC parts (ACC-9), and the profile:
photo, emergency contacts, dependents, skills, education, experience, contracts, documents and the
Update Information requests (comparison/12-employee-profile.md)."""
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import employees_controller as c
from app.core.db import Db, get_db
from app.core.paging import MAX_PAGE_SIZE, PageParams, page_params
from app.middlewares.auth import RequestContext, get_context, require
from app.schemas.common import Item, Paginated
from app.schemas.employees import (BankAccountIn, BankAccountOut, ChangeOut, ContractIn, ContractOut, DecisionIn,
                                   DependentIn, DependentOut, DocumentIn, DocumentOut, EducationIn, EducationOut,
                                   EmergencyContactIn, EmergencyContactOut, EmployeeIn, EmployeeLookupOut,
                                   EmployeeOut, EmployeeSummaryOut, EmploymentPeriodIn, EmploymentPeriodOut,
                                   ExperienceIn, ExperienceOut,
                                   HistoryOut, IdentityIn, PhotoIn, RowVersionIn, SalaryIn, SalaryOut, SkillIn,
                                   SkillOut, UpdateRequestIn, UpdateRequestOut)

router = APIRouter(prefix="/employees", tags=["employees"])
NO_CONTENT = status.HTTP_204_NO_CONTENT


def employee_filters(q: str | None = None, status_: str | None = Query(None, alias="status"),
                     include_inactive: bool = Query(False, alias="includeInactive"),
                     branch_id: int | None = Query(None, alias="branchId"),
                     location_id: int | None = Query(None, alias="locationId"),
                     area_id: int | None = Query(None, alias="areaId"),
                     department_id: int | None = Query(None, alias="departmentId"),
                     division_id: int | None = Query(None, alias="divisionId"),
                     designation_id: int | None = Query(None, alias="designationId"),
                     job_title_id: int | None = Query(None, alias="jobTitleId"),
                     grade_id: int | None = Query(None, alias="gradeId"),
                     employment_type_id: int | None = Query(None, alias="employmentTypeId"),
                     employee_group_id: int | None = Query(None, alias="employeeGroupId"),
                     line_manager_id: int | None = Query(None, alias="lineManagerId"),
                     gender: Literal["male", "female", "other"] | None = None) -> dict:
    """The directory's filter panel, shared by the list and its summary tiles."""
    return {"search": q, "status": status_, "include_inactive": include_inactive, "branch_id": branch_id,
            "location_id": location_id, "area_id": area_id, "department_id": department_id,
            "division_id": division_id, "designation_id": designation_id, "job_title_id": job_title_id,
            "grade_id": grade_id, "employment_type_id": employment_type_id,
            "employee_group_id": employee_group_id, "line_manager_id": line_manager_id, "gender": gender}


@router.get("", response_model=Paginated[EmployeeOut])
def list_employees(filters: dict = Depends(employee_filters), paging: PageParams = Depends(page_params),
                   db: Db = Depends(get_db),
                   ctx: RequestContext = Depends(require("employees.directory.view"))) -> dict:
    return c.list_employees(db, ctx, filters, paging)


@router.get("/summary", response_model=Item[EmployeeSummaryOut])
def employee_summary(filters: dict = Depends(employee_filters), db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("employees.directory.view"))) -> dict:
    """The directory's tiles: total, by gender and by status, over the people the list shows with the
    same filters (and the same scope of employees.directory.view)."""
    return c.employee_summary(db, ctx, filters)


@router.get("/lookup", response_model=Paginated[EmployeeLookupOut])
def lookup(permission: str = "employees.directory.view", q: str | None = None,
           branch_id: int | None = Query(None, alias="branchId"),
           department_id: int | None = Query(None, alias="departmentId"),
           include_inactive: bool = Query(False, alias="includeInactive"), limit: int = 50,
           page: int = Query(1), page_size: int | None = Query(None, alias="pageSize"),
           db: Db = Depends(get_db), ctx: RequestContext = Depends(get_context)) -> dict:
    """Picker for any screen: employees the caller reaches through `permission` (a catalogue code the
    screen itself requires, e.g. requests.leave.create). Holding nothing returns an empty list.
    Paged (`page`, `pageSize` up to 100; `q` searches code and name). Without `pageSize` a page is `limit`
    long (default 50), so callers that send no paging get the first page as before."""
    size = min(max(page_size if page_size is not None else limit, 1), MAX_PAGE_SIZE)
    return c.lookup(db, ctx, permission, q, branch_id, department_id, include_inactive, max(page, 1), size)


# ---------------------------------------------------------------- Update Information requests
# An employee asks for their date of birth, marital status, phones or home address to change; HR
# approves (the change is written then) or rejects. Static paths stay above /{employee_id}.

@router.get("/update-requests", response_model=Paginated[UpdateRequestOut])
def list_update_requests(employee_id: int | None = Query(None, alias="employeeId"),
                         status_: Literal["pending", "approved", "rejected", "cancelled"] | None = Query(None, alias="status"),
                         paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                         ctx: RequestContext = Depends(require("employees.update_requests.view"))) -> dict:
    return c.list_update_requests(db, ctx, employee_id, status_, paging)


@router.get("/update-requests/{request_id}", response_model=Item[UpdateRequestOut])
def get_update_request(request_id: int, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("employees.update_requests.view"))) -> dict:
    return c.get_update_request(db, ctx, request_id)


@router.patch("/update-requests/{request_id}/approve", response_model=Item[UpdateRequestOut])
def approve_update_request(request_id: int, body: DecisionIn, db: Db = Depends(get_db),
                           ctx: RequestContext = Depends(require("employees.update_requests.approve"))) -> dict:
    """Writes the asked values to the employee record."""
    return c.decide_update_request(db, ctx, request_id, "approved", body.remarks, body.row_version)


@router.patch("/update-requests/{request_id}/reject", response_model=Item[UpdateRequestOut])
def reject_update_request(request_id: int, body: DecisionIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("employees.update_requests.reject"))) -> dict:
    return c.decide_update_request(db, ctx, request_id, "rejected", body.remarks, body.row_version)


@router.patch("/update-requests/{request_id}/cancel", response_model=Item[UpdateRequestOut])
def cancel_update_request(request_id: int, body: DecisionIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("employees.update_requests.cancel"))) -> dict:
    return c.decide_update_request(db, ctx, request_id, "cancelled", body.remarks, body.row_version)


@router.get("/{employee_id}", response_model=Item[EmployeeOut])
def get_employee(employee_id: int, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("employees.directory.view"))) -> dict:
    return c.get_employee(db, ctx, employee_id)


@router.post("", response_model=Item[EmployeeOut], status_code=status.HTTP_201_CREATED)
def create_employee(body: EmployeeIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("employees.directory.create"))) -> dict:
    return c.create_employee(db, ctx, body)


@router.put("/{employee_id}", response_model=Item[EmployeeOut])
def update_employee(employee_id: int, body: EmployeeIn, db: Db = Depends(get_db),
                    ctx: RequestContext = Depends(require("employees.directory.edit"))) -> dict:
    return c.update_employee(db, ctx, employee_id, body)


@router.put("/{employee_id}/identity", response_model=Item[EmployeeOut])
def save_identity(employee_id: int, body: IdentityIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("employees.identity.edit"))) -> dict:
    return c.save_identity(db, ctx, employee_id, body)


@router.patch("/{employee_id}/deactivate", response_model=Item[EmployeeOut])
def deactivate(employee_id: int, body: RowVersionIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("employees.directory.delete"))) -> dict:
    """Switches the record off (status inactive) and its sign-in accounts with it."""
    return c.set_active(db, ctx, employee_id, False, body.row_version)


@router.patch("/{employee_id}/reactivate", response_model=Item[EmployeeOut])
def reactivate(employee_id: int, body: RowVersionIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("employees.directory.delete"))) -> dict:
    return c.set_active(db, ctx, employee_id, True, body.row_version)


# ---------------------------------------------------------------- employment periods and history

@router.get("/{employee_id}/employment-periods", response_model=Item[list[EmploymentPeriodOut]])
def list_periods(employee_id: int, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("employees.directory.view"))) -> dict:
    return c.list_periods(db, ctx, employee_id)


@router.post("/{employee_id}/employment-periods", response_model=Item[EmploymentPeriodOut],
             status_code=status.HTTP_201_CREATED)
def add_period(employee_id: int, body: EmploymentPeriodIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("employees.directory.edit"))) -> dict:
    return c.save_period(db, ctx, employee_id, None, body)


@router.put("/{employee_id}/employment-periods/{period_id}", response_model=Item[EmploymentPeriodOut])
def update_period(employee_id: int, period_id: int, body: EmploymentPeriodIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("employees.directory.edit"))) -> dict:
    return c.save_period(db, ctx, employee_id, period_id, body)


@router.get("/{employee_id}/history", response_model=Item[list[HistoryOut]])
def list_history(employee_id: int, db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("employees.history.view"))) -> dict:
    """Placement over time: joining, transfers, promotions, demotions and edits."""
    return c.list_history(db, ctx, employee_id)


@router.get("/{employee_id}/changes", response_model=Paginated[ChangeOut])
def list_changes(employee_id: int, paging: PageParams = Depends(page_params), db: Db = Depends(get_db),
                 ctx: RequestContext = Depends(require("employees.history.view"))) -> dict:
    """Field-level changes to the record (the History popup)."""
    return c.list_changes(db, ctx, employee_id, paging)


# ---------------------------------------------------------------- salary (sensitive)

@router.get("/{employee_id}/salary", response_model=Item[list[SalaryOut]])
def list_salary(employee_id: int, db: Db = Depends(get_db),
                ctx: RequestContext = Depends(require("employees.salary.view"))) -> dict:
    return c.list_salary(db, ctx, employee_id)


@router.post("/{employee_id}/salary", response_model=Item[SalaryOut], status_code=status.HTTP_201_CREATED)
def add_salary(employee_id: int, body: SalaryIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("employees.salary.edit"))) -> dict:
    return c.save_salary(db, ctx, employee_id, None, body)


@router.put("/{employee_id}/salary/{salary_id}", response_model=Item[SalaryOut])
def update_salary(employee_id: int, salary_id: int, body: SalaryIn, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("employees.salary.edit"))) -> dict:
    return c.save_salary(db, ctx, employee_id, salary_id, body)


@router.delete("/{employee_id}/salary/{salary_id}", status_code=NO_CONTENT)
def delete_salary(employee_id: int, salary_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                  db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require("employees.salary.edit"))) -> Response:
    c.delete_salary(db, ctx, employee_id, salary_id, row_version)
    return Response(status_code=NO_CONTENT)


# ---------------------------------------------------------------- bank accounts (sensitive)

@router.get("/{employee_id}/bank-accounts", response_model=Item[list[BankAccountOut]])
def list_bank_accounts(employee_id: int, db: Db = Depends(get_db),
                       ctx: RequestContext = Depends(require("employees.bank_accounts.view"))) -> dict:
    return c.list_bank_accounts(db, ctx, employee_id)


@router.post("/{employee_id}/bank-accounts", response_model=Item[BankAccountOut], status_code=status.HTTP_201_CREATED)
def add_bank_account(employee_id: int, body: BankAccountIn, db: Db = Depends(get_db),
                     ctx: RequestContext = Depends(require("employees.bank_accounts.edit"))) -> dict:
    return c.save_bank_account(db, ctx, employee_id, None, body)


@router.put("/{employee_id}/bank-accounts/{account_id}", response_model=Item[BankAccountOut])
def update_bank_account(employee_id: int, account_id: int, body: BankAccountIn, db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("employees.bank_accounts.edit"))) -> dict:
    return c.save_bank_account(db, ctx, employee_id, account_id, body)


@router.delete("/{employee_id}/bank-accounts/{account_id}", status_code=NO_CONTENT)
def delete_bank_account(employee_id: int, account_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                        db: Db = Depends(get_db),
                        ctx: RequestContext = Depends(require("employees.bank_accounts.edit"))) -> Response:
    c.delete_bank_account(db, ctx, employee_id, account_id, row_version)
    return Response(status_code=NO_CONTENT)


# ---------------------------------------------------------------- profile photo and Update Information

@router.put("/{employee_id}/photo", response_model=Item[EmployeeOut])
def save_photo(employee_id: int, body: PhotoIn, db: Db = Depends(get_db),
               ctx: RequestContext = Depends(require("employees.photo.edit"))) -> dict:
    """Upload the image with POST /api/files first, then send its id here (null removes the photo)."""
    return c.save_photo(db, ctx, employee_id, body)


@router.post("/{employee_id}/update-requests", response_model=Item[UpdateRequestOut],
             status_code=status.HTTP_201_CREATED)
def submit_update_request(employee_id: int, body: UpdateRequestIn, db: Db = Depends(get_db),
                          ctx: RequestContext = Depends(require("employees.update_requests.create"))) -> dict:
    """Update Information: only the fields sent in `changes` are asked for. HR is told in the inbox."""
    return c.submit_update_request(db, ctx, employee_id, body)


# ---------------------------------------------------------------- profile tabs
# /{employee_id}/<segment>: list, add, edit, delete, guarded by employees.<tab>.view / .edit.
# Documents also check identity / salary rights per document type; contracts are sensitive.

PROFILE_TABS: dict[str, tuple[str, type, type]] = {
    "emergency-contacts": ("emergency_contacts", EmergencyContactIn, EmergencyContactOut),
    "dependents": ("dependents", DependentIn, DependentOut),
    "skills": ("skills", SkillIn, SkillOut),
    "education": ("education", EducationIn, EducationOut),
    "experience": ("experience", ExperienceIn, ExperienceOut),
    "contracts": ("contracts", ContractIn, ContractOut),
    "documents": ("documents", DocumentIn, DocumentOut),
}


def _tab_routes(segment: str, tab: str, body_model: type, out_model: type) -> None:
    code = f"employees.{tab}"

    def list_rows(employee_id: int, db: Db = Depends(get_db),
                  ctx: RequestContext = Depends(require(f"{code}.view"))) -> dict:
        return c.list_tab(db, ctx, tab, employee_id)

    def create_row(employee_id: int, body: body_model, db: Db = Depends(get_db),  # type: ignore[valid-type]
                   ctx: RequestContext = Depends(require(f"{code}.edit"))) -> dict:
        return c.save_tab(db, ctx, tab, employee_id, None, body)

    def update_row(employee_id: int, row_id: int, body: body_model, db: Db = Depends(get_db),  # type: ignore[valid-type]
                   ctx: RequestContext = Depends(require(f"{code}.edit"))) -> dict:
        return c.save_tab(db, ctx, tab, employee_id, row_id, body)

    def delete_row(employee_id: int, row_id: int, row_version: str | None = Query(None, alias="rowVersion"),
                   db: Db = Depends(get_db), ctx: RequestContext = Depends(require(f"{code}.edit"))) -> Response:
        c.delete_tab(db, ctx, tab, employee_id, row_id, row_version)
        return Response(status_code=NO_CONTENT)

    router.add_api_route(f"/{{employee_id}}/{segment}", list_rows, methods=["GET"],
                         response_model=Item[list[out_model]], name=f"list_{tab}")  # type: ignore[valid-type]
    router.add_api_route(f"/{{employee_id}}/{segment}", create_row, methods=["POST"],
                         response_model=Item[out_model], status_code=status.HTTP_201_CREATED, name=f"create_{tab}")
    router.add_api_route(f"/{{employee_id}}/{segment}/{{row_id}}", update_row, methods=["PUT"],
                         response_model=Item[out_model], name=f"update_{tab}")
    router.add_api_route(f"/{{employee_id}}/{segment}/{{row_id}}", delete_row, methods=["DELETE"],
                         status_code=NO_CONTENT, name=f"delete_{tab}")


for _segment, (_tab, _in, _out) in PROFILE_TABS.items():
    _tab_routes(_segment, _tab, _in, _out)
