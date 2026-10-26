"""Dashboards (CEO, HR, My). Each figure covers the employees the dashboard permission's scope
reaches, so a Department Head's HR dashboard shows their department. Widgets whose data no
document defines, or whose tables belong to modules not built yet, are not here (see
comparison/01-organisation.md)."""
from datetime import date
from typing import Any

from app.core.db import Db
from app.middlewares.auth import RequestContext
from app.repos import dashboard_repo


def _pct(part: float, whole: float) -> float:
    return round(100.0 * part / whole, 1) if whole else 0.0


def _workforce(db: Db, ctx: RequestContext, code: str, month: date | None) -> dict[str, Any]:
    totals, dept, types, genders, ages, months, dept_gender, titles = dashboard_repo.workforce(
        db, ctx.company_id, ctx.user_id, code, month)
    t = totals[0]
    average = (t["opening_headcount"] + t["headcount"]) / 2
    bands: dict[str, dict[str, Any]] = {}
    for a in ages:
        b = bands.setdefault(a["band"], {"band": a["band"], "male": 0, "female": 0, "other": 0})
        b[a["gender"] if a["gender"] in ("male", "female") else "other"] += a["count"]
    first = months[0]["month"] if months else date.today().replace(day=1)
    return {
        "month": months[-1]["month"] if months else first,
        "headcount": t["headcount"], "women": t["women"], "men": t["men"],
        "women_percent": _pct(t["women"], t["headcount"]), "hired": t["hired"], "left": t["left_count"],
        "turnover_percent": _pct(t["left_count"], average),
        "by_department": dept, "by_employment_type": types, "by_gender": genders,
        "by_age": [bands[k] for k in sorted(bands)],
        "turnover_by_month": [{"month": m["month"], "hired": m["hired"], "left": m["left_count"]} for m in months],
        "by_department_gender": dept_gender,
        "women_by_job_title": [{**r, "women_percent": _pct(r["women"], r["total"])} for r in titles],
    }


def _attendance(db: Db, ctx: RequestContext, code: str, day: date | None, only_employee: int | None) -> dict[str, Any]:
    totals, months, rows = dashboard_repo.attendance(db, ctx.company_id, ctx.user_id, code, day, only_employee)
    t = {k: v or 0 for k, v in totals[0].items()}
    return {"day": day or date.today(), "present": t["present"], "absent": t["absent"], "on_leave": t["on_leave"],
            "absenteeism_percent": _pct(t["absent"], t["present"] + t["absent"]),
            "by_month": months, "rows": [{**r, "status": r["day_status"]} for r in rows]}


def _notices(db: Db, ctx: RequestContext) -> dict[str, list[dict[str, Any]]]:
    return {"notice_board": dashboard_repo.announcements(db, ctx.company_id, "notice", 5),
            "upcoming_events": [e for e in dashboard_repo.announcements(db, ctx.company_id, "event", 20)
                                if e["event_date"] is None or e["event_date"] >= date.today()][:5]}


def ceo(db: Db, ctx: RequestContext, month: date | None, day: date | None) -> dict[str, Any]:
    code = "dashboard.ceo.view"
    return {"workforce": _workforce(db, ctx, code, month), "attendance": _attendance(db, ctx, code, day, None),
            "leave_applications": dashboard_repo.leave_applications(db, ctx.company_id, ctx.user_id, code, None)}


def hr(db: Db, ctx: RequestContext, month: date | None, day: date | None) -> dict[str, Any]:
    code = "dashboard.hr.view"
    return {"workforce": _workforce(db, ctx, code, month), "attendance": _attendance(db, ctx, code, day, None),
            "leave_applications": dashboard_repo.leave_applications(db, ctx.company_id, ctx.user_id, code, None),
            **_notices(db, ctx)}


def mine(db: Db, ctx: RequestContext, day: date | None) -> dict[str, Any]:
    """The signed-in employee's own figures. A user with no employee record sees empty figures."""
    code = "dashboard.employee.view"
    only = ctx.employee_id or -1
    return {"employee_id": ctx.employee_id, "attendance": _attendance(db, ctx, code, day, only),
            "leave_applications": dashboard_repo.leave_applications(db, ctx.company_id, ctx.user_id, code, only),
            **_notices(db, ctx)}
