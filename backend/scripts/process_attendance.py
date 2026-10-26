"""Re-processes attendance time sheets for every company: the regular run that turns punches,
schedules, rest days, holidays and approved requests into time-sheet days.

Run it nightly (Windows Task Scheduler) from the backend folder:
  .venv\\Scripts\\python.exe -m scripts.process_attendance                 yesterday and today
  .venv\\Scripts\\python.exe -m scripts.process_attendance --days 7        the last 7 days and today
  .venv\\Scripts\\python.exe -m scripts.process_attendance --from 2026-10-01 --to 2026-10-31

Days payroll has frozen and days edited by hand are left as they are (att.usp_timesheet_process).
"""
import argparse
import sys
from datetime import date, timedelta

import pyodbc

from app.core.config import settings


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Re-process attendance time sheets.")
    p.add_argument("--days", type=int, default=1, help="how many days before today to include (default 1)")
    p.add_argument("--from", dest="from_date", type=date.fromisoformat, help="first day (YYYY-MM-DD)")
    p.add_argument("--to", dest="to_date", type=date.fromisoformat, help="last day (YYYY-MM-DD)")
    a = p.parse_args()
    to_date = a.to_date or date.today()
    from_date = a.from_date or to_date - timedelta(days=max(a.days, 0))
    if from_date > to_date:
        sys.exit("--from is after --to")

    conn = pyodbc.connect(settings.db_url, autocommit=True)
    cur = conn.cursor()
    companies = cur.execute("SELECT id, name FROM org.company ORDER BY id").fetchall()
    failed = 0
    for company_id, name in companies:
        try:
            days = cur.execute(
                "SET NOCOUNT ON; DECLARE @n INT; EXEC att.usp_timesheet_process @company_id = ?, @from_date = ?, "
                "@to_date = ?, @quiet = 1, @processed_days = @n OUTPUT; SELECT @n;",
                company_id, from_date, to_date).fetchval()
            print(f"{name}: {days or 0} days processed ({from_date} to {to_date})")
        except pyodbc.Error as exc:
            failed += 1
            print(f"{name}: FAILED {exc.args[-1] if exc.args else exc}")
    conn.close()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
