"""The nightly jobs, for every company. Schedule this once a night (Windows Task Scheduler), from the
backend folder:

  .venv\\Scripts\\python.exe -m scripts.nightly

  0. billing      once for the platform, before the companies: renewal invoices, trials that end, read-only and
                  locked access for unpaid invoices, and the billing e-mails (app/services/billing_service.py)
  1. attendance   re-processes yesterday's and today's time sheets (as scripts/process_attendance.py)
  2. documents    tells employees about documents expiring within 30 days, once per document
                  (hr.usp_employee_document_expiry_notify; also published as employees.document_expiring)
  3. tasks        tells the assignees of open project tasks that are due tomorrow or have become overdue
                  (pm.usp_task_due_notify; once per task and due date, so running it twice sends nothing more)
  4. uploads      deletes uploads no record uses, older than a week (core.usp_file_purge_unused), from the
                  database and from disk

Each job runs per company; one company failing does not stop the others. Exit code 1 if anything failed.
Run it after midnight: "tomorrow" and "overdue" are counted from the company's own date.
"""
import sys
from datetime import date, timedelta

import pyodbc

from app.core import files
from app.core.config import settings
from app.core.db import Db
from app.services import billing_service

JOBS = (
    ("attendance", "SET NOCOUNT ON; DECLARE @n INT; EXEC att.usp_timesheet_process @company_id = ?, @from_date = ?, "
                   "@to_date = ?, @quiet = 1, @processed_days = @n OUTPUT; SELECT @n;", "days processed"),
    ("documents", "SET NOCOUNT ON; EXEC hr.usp_employee_document_expiry_notify @company_id = ?, @days_ahead = 30;",
     "documents reported"),
    ("tasks", "SET NOCOUNT ON; EXEC pm.usp_task_due_notify @company_id = ?;", "due and overdue notices sent"),
)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    conn = pyodbc.connect(settings.db_url, autocommit=True)
    cur = conn.cursor()
    failed = 0
    # Billing first, once for the platform; a company it restricts tonight still gets tonight's jobs.
    try:
        notices = billing_service.run_daily(Db(conn))
        print(f"billing: {len(notices)} billing e-mails queued")
    except pyodbc.Error as exc:
        failed += 1
        print(f"billing: FAILED {exc.args[-1] if exc.args else exc}")
    # Companies of a suspended or cancelled organisation get no jobs (roadmap 0.3); their data stays as it was.
    companies = cur.execute("SELECT id, name FROM org.company WHERE plat.fn_company_blocked(id) = 0 ORDER BY id").fetchall()
    for company_id, name in companies:
        # "Today" is the company's own date, not this server's (a company in Dubai or London).
        today = cur.execute("SELECT CAST(att.fn_company_now(?) AS DATE)", company_id).fetchval() or date.today()
        for job, sql, what in JOBS:
            params = (company_id, today - timedelta(days=1), today) if job == "attendance" else (company_id,)
            try:
                n = cur.execute(sql, *params).fetchval()
                print(f"{name}: {job}: {n or 0} {what}")
            except pyodbc.Error as exc:
                failed += 1
                print(f"{name}: {job}: FAILED {exc.args[-1] if exc.args else exc}")
        try:
            removed = 0
            while paths := [r[0] for r in cur.execute("SET NOCOUNT ON; EXEC core.usp_file_purge_unused @company_id = ?",
                                                      company_id).fetchall()]:
                for path in paths:
                    files.remove(path)
                removed += len(paths)
            print(f"{name}: uploads: {removed} unused files removed")
        except pyodbc.Error as exc:
            failed += 1
            print(f"{name}: uploads: FAILED {exc.args[-1] if exc.args else exc}")
    conn.close()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
