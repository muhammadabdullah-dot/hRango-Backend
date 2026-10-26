"""Test-only helpers for the scheduling and roster tests: time slots, break types, roster groups and
shifts made straight through the procedures, with unique names, so a test sets up only what it needs."""
import json
from datetime import date, timedelta

from app.core.db import Db
from tests import factories

# A Monday far from today, so tests never meet "today" rules by accident.
MONDAY = date(2031, 3, 3)


def day(n: int) -> date:
    """MONDAY + n days."""
    return MONDAY + timedelta(days=n)


def break_type(db: Db, company_id: int, name: str | None = None) -> int:
    t = factories.tag()
    return db.call_one("sch.usp_break_type_save", company_id=company_id, actor_user_id=None,
                       name=name or f"Break {t}", start_identifier=f"{t} Out", end_identifier=f"{t} In")["id"]


def time_slot(db: Db, company_id: int, start: str = "09:00", end: str = "17:00", name: str | None = None,
              breaks: list[dict] | None = None, is_flexible: bool = False, workable_minutes: int | None = None) -> int:
    sets = db.call_sets("sch.usp_time_slot_save", company_id=company_id, actor_user_id=None,
                        name=name or f"Slot {factories.tag()}", start_time=start, end_time=end,
                        is_flexible=is_flexible, workable_minutes=workable_minutes,
                        breaks=json.dumps(breaks or []))
    return sets[0][0]["id"]


def roster_group(db: Db, company_id: int, days: dict[int, int | None], from_date: date = MONDAY,
                 to_date: date | None = None, title: str | None = None) -> int:
    """days: weekday (1 = Monday) -> time slot id; weekdays left out are days off."""
    week = [{"weekday": w, "is_day_off": False, "time_slot_id": s} for w, s in days.items()]
    sets = db.call_sets("sch.usp_roster_group_save", company_id=company_id, actor_user_id=None,
                        title=title or f"Roster {factories.tag()}", from_date=from_date, to_date=to_date,
                        is_active=True, days=json.dumps(week))
    return sets[0][0]["id"]


def allow_multi_shift(db: Db, company_id: int, allowed: bool = True) -> None:
    cur = db.conn.cursor()
    try:
        cur.execute("DELETE core.company_setting WHERE company_id = ? AND module = N'attendance' "
                    "AND setting_key = N'allow_multi_shift'", company_id)
        cur.execute("INSERT core.company_setting (company_id, module, setting_key, setting_value) "
                    "VALUES (?, N'attendance', N'allow_multi_shift', ?)", company_id, "true" if allowed else "false")
    finally:
        cur.close()


def scalar(db: Db, sql: str, *params):
    cur = db.conn.cursor()
    try:
        return cur.execute(sql, *params).fetchval()
    finally:
        cur.close()
