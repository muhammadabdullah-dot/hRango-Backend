"""Dashboard data access: hr.usp_dashboard_* and the current announcements."""
from datetime import date
from typing import Any

from app.core.db import Db


def workforce(db: Db, company_id: int, actor_user_id: int, permission_code: str,
              month: date | None) -> list[list[dict[str, Any]]]:
    return db.call_sets("hr.usp_dashboard_workforce", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=permission_code, month=month)


def attendance(db: Db, company_id: int, actor_user_id: int, permission_code: str, day: date | None,
               only_employee: int | None) -> list[list[dict[str, Any]]]:
    return db.call_sets("hr.usp_dashboard_attendance", company_id=company_id, actor_user_id=actor_user_id,
                        permission_code=permission_code, day=day, rows=10, only_employee=only_employee)


def leave_applications(db: Db, company_id: int, actor_user_id: int, permission_code: str,
                       only_employee: int | None) -> list[dict[str, Any]]:
    return db.call("hr.usp_dashboard_leave_applications", company_id=company_id, actor_user_id=actor_user_id,
                   permission_code=permission_code, rows=6, only_employee=only_employee)


def announcements(db: Db, company_id: int, kind: str, rows: int) -> list[dict[str, Any]]:
    _, page = db.call_sets("eng.usp_announcement_list", company_id=company_id, kind=kind, current_only=True,
                           page=1, page_size=rows)
    return page
