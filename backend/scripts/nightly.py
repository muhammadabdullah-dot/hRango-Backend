"""The nightly jobs, for every company. Schedule this once a night (Windows Task Scheduler), from the
backend folder:

  .venv\\Scripts\\python.exe -m scripts.nightly

  1. attendance   re-processes yesterday's and today's time sheets (as scripts/process_attendance.py)
  2. documents    tells employees about documents expiring within 30 days, once per document
                  (hr.usp_employee_document_expiry_notify; also published as employees.document_expiring)
  3. uploads      deletes uploads no record uses, older than a week (core.usp_file_purge_unused), from the
                  database and from disk

Each job runs per company; one company failing does not stop the others. Exit code 1 if anything failed.
"""
import sys
from datetime import date, timedelta

import pyodbc

from app.core import files
from app.core.config import settings

JOBS = (
    ("attendance", "SET NOCOUNT ON; DECLARE @n INT; EXEC att.usp_timesheet_process @company_id = ?, @from_date = ?, "
                   "@to_date = ?, @quiet = 1, @processed_days = @n OUTPUT; SELECT @n;", "days processed"),
    ("documents", "SET NOCOUNT ON; EXEC hr.usp_employee_document_expiry_notify @company_id = ?, @days_ahead = 30;",
     "documents reported"),
)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    today = date.today()
    conn = pyodbc.connect(settings.db_url, autocommit=True)
    cur = conn.cursor()
    companies = cur.execute("SELECT id, name FROM org.company ORDER BY id").fetchall()
    failed = 0
    for company_id, name in companies:
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
