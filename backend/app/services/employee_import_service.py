"""Bulk employee import from a CSV file (roadmap 1.1), so a new customer does not type people in one by one.

Check first, then import: every row is checked (required columns, dates, choices, names of branches,
departments ... that exist in the company, repeated codes or e-mails) before anything is written. With any
problem nothing is imported and the answer lists each one by row and column. `dry_run` only checks.
The import itself is one transaction through the same procedure as Add Employee (hr.usp_employee_save),
so its rules, numbering and the plan's employee limit apply; if the database refuses a row, nothing stays.
"""
import csv
import io
from datetime import date
from typing import Any

from app.core.db import Db
from app.core.errors import AppError, invalid
from app.middlewares.auth import RequestContext
from app.repos import employees_repo

MAX_ROWS = 2000
# Column (as written in the file, any letter case) -> field. The first two of each are the template's.
COLUMNS: dict[str, tuple[str, bool]] = {
    "first name": ("first_name", True),
    "last name": ("last_name", True),
    "joining date": ("joining_date", True),
    "branch": ("branch", True),
    "code": ("code", False),
    "email": ("email", False),
    "phone": ("phone_1", False),
    "gender": ("gender", False),
    "date of birth": ("date_of_birth", False),
    "department": ("department", False),
    "designation": ("designation", False),
    "job title": ("job_title", False),
    "employment type": ("employment_type", False),
    "status": ("status", False),
    "line manager code": ("line_manager_code", False),
}
TEMPLATE_EXAMPLE = {"first name": "Ayesha", "last name": "Khan", "joining date": "2026-01-05", "branch": "Head Office",
                    "code": "", "email": "ayesha.khan@example.com", "phone": "+92 300 1234567", "gender": "female",
                    "date of birth": "1994-03-21", "department": "Human Resources", "designation": "Manager",
                    "job title": "HR Manager", "employment type": "Permanent", "status": "active",
                    "line manager code": ""}
GENDERS = ("male", "female", "other")
STATUSES = ("active", "probation")


def template_csv() -> str:
    out = io.StringIO()
    writer = csv.writer(out)
    writer.writerow([c.title() if c != "line manager code" else "Line Manager Code" for c in COLUMNS])
    writer.writerow([TEMPLATE_EXAMPLE[c] for c in COLUMNS])
    return out.getvalue()


def _date(value: str) -> date:
    """2026-01-05 (ISO), or 05/01/2026 as day/month/year, the way spreadsheets in Pakistan and the Gulf write it."""
    try:
        return date.fromisoformat(value)
    except ValueError:
        day, month, year = value.replace("-", "/").replace(".", "/").split("/")
        return date(int(year), int(month), int(day))


def _lookups(db: Db, company_id: int) -> dict[str, dict[str, int]]:
    branches, departments, designations, job_titles, types, codes = db.call_sets(
        "hr.usp_employee_import_lookups", company_id=company_id)

    def by_name(rows):
        return {str(r["name"]).strip().lower(): int(r["id"]) for r in rows}

    return {"branch": by_name(branches), "department": by_name(departments), "designation": by_name(designations),
            "job_title": by_name(job_titles), "employment_type": by_name(types),
            "code": {str(r["code"]).strip().lower(): int(r["id"]) for r in codes}}


def import_csv(db: Db, ctx: RequestContext, raw: bytes, dry_run: bool) -> dict[str, Any]:
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise invalid("Save the file as CSV UTF-8 and try again.", "file") from exc
    reader = csv.DictReader(io.StringIO(text))
    if not reader.fieldnames:
        raise invalid("The file is empty.", "file")
    header = {name: (name or "").strip().lower() for name in reader.fieldnames}
    unknown = [name for name, key in header.items() if key and key not in COLUMNS]
    missing = [c.title() for c, (_, required) in COLUMNS.items() if required and c not in header.values()]
    if missing:
        raise invalid(f"These columns are missing: {', '.join(missing)}. Download the template to see them all.", "file")

    rows = list(reader)
    if not rows:
        raise invalid("The file has a header but no people.", "file")
    if len(rows) > MAX_ROWS:
        raise invalid(f"Import at most {MAX_ROWS} people at a time; split the file.", "file")

    lookups = _lookups(db, ctx.company_id)
    errors: list[dict[str, Any]] = []
    prepared: list[tuple[int, dict[str, Any], str | None]] = []
    seen_codes: dict[str, int] = {}
    seen_emails: dict[str, int] = {}
    code_column = next((k for k, key in header.items() if key == "code"), None)
    file_codes = {(r.get(code_column) or "").strip().lower() for r in rows} - {""} if code_column else set()

    for index, row in enumerate(rows, start=2):  # row 1 is the header
        values = {COLUMNS[header[k]][0]: (v or "").strip() for k, v in row.items() if k in header and header[k] in COLUMNS}

        def problem(column: str, message: str) -> None:
            errors.append({"row": index, "column": column, "message": message})

        for column, (field, required) in COLUMNS.items():
            if required and not values.get(field):
                problem(column.title(), "Required.")
        fields: dict[str, Any] = {"first_name": values.get("first_name"), "last_name": values.get("last_name"),
                                  "status": (values.get("status") or "active").lower(), "salary_frequency": "monthly"}
        if fields["status"] not in STATUSES:
            problem("Status", "Use active or probation.")
        for column, field in (("Joining Date", "joining_date"), ("Date Of Birth", "date_of_birth")):
            if values.get(field):
                try:
                    fields[field] = _date(values[field])
                except (ValueError, TypeError):
                    problem(column, "Use a date like 2026-01-05 or 05/01/2026.")
        if values.get("gender"):
            gender = values["gender"].lower()
            if gender not in GENDERS:
                problem("Gender", "Use male, female or other.")
            fields["gender"] = gender
        if values.get("email"):
            email_value = values["email"].lower()
            if "@" not in email_value or "." not in email_value.split("@")[-1]:
                problem("Email", "Not an e-mail address.")
            elif email_value in seen_emails:
                problem("Email", f"Also on row {seen_emails[email_value]}.")
            seen_emails[email_value] = index
            fields["email"] = email_value
        if values.get("phone_1"):
            fields["phone_1"] = values["phone_1"]
        if values.get("code"):
            code = values["code"].lower()
            if code in lookups["code"]:
                problem("Code", "Another employee already has this code.")
            elif code in seen_codes:
                problem("Code", f"Also on row {seen_codes[code]}.")
            seen_codes[code] = index
            fields["code"] = values["code"]
        for column, field, key in (("Branch", "branch", "branch"), ("Department", "department", "department"),
                                   ("Designation", "designation", "designation"), ("Job Title", "job_title", "job_title"),
                                   ("Employment Type", "employment_type", "employment_type")):
            name = values.get(field)
            if not name:
                continue
            found = lookups[key].get(name.lower())
            if found is None:
                problem(column, f"No {column.lower()} called \"{name}\". Add it in Settings first, or fix the name.")
            else:
                fields[f"{key}_id"] = found
        manager = values.get("line_manager_code")
        if manager:
            if manager.lower() in lookups["code"]:
                fields["line_manager_id"] = lookups["code"][manager.lower()]
            elif manager.lower() not in file_codes:
                problem("Line Manager Code", f"No employee with code \"{manager}\" here or in the file.")
            elif manager.lower() == (values.get("code") or "").lower():
                problem("Line Manager Code", "Nobody can be their own line manager.")
        prepared.append((index, fields, manager))

    allowance = db.call_one("plat.usp_plan_usage", company_id=ctx.company_id)
    if allowance and allowance["employee_limit"] is not None:
        room = allowance["employee_limit"] - allowance["employees_used"]
        if len(prepared) > room:
            errors.append({"row": None, "column": None, "message": (
                f"Your {allowance['plan_name']} plan covers {allowance['employee_limit']} employees and "
                f"{allowance['employees_used']} are on it, so {max(room, 0)} more fit; the file has {len(prepared)}.")})

    report = {"total": len(rows), "created": 0, "dry_run": dry_run, "errors": errors,
              "ignored_columns": [name for name in unknown if name]}
    if errors or dry_run:
        return report

    created_codes: dict[str, int] = {}
    with db.transaction():
        current_row = 0
        try:
            # People first, then the line managers who are new in the same file.
            later: list[tuple[int, int, str]] = []
            for current_row, fields, manager in prepared:
                row = employees_repo.save_employee(db, ctx.company_id, ctx.user_id, "employees.directory.create", None,
                                                   fields, False, None, None)
                if row.get("code"):
                    created_codes[str(row["code"]).lower()] = int(row["id"])
                if manager and "line_manager_id" not in fields:
                    later.append((current_row, int(row["id"]), manager.lower()))
            for current_row, employee_id, manager in later:
                db.call("hr.usp_employee_import_manager_set", company_id=ctx.company_id, actor_user_id=ctx.user_id,
                        id=employee_id, line_manager_id=created_codes[manager])
        except AppError as exc:
            raise AppError(exc.status, exc.code, f"Row {current_row}: {exc.message} Nothing was imported.",
                           exc.field_errors) from exc
    report["created"] = len(prepared)
    return report
