"""Helpers shared by the talent part (manpower, recruitment, performance, training)."""
from datetime import date, datetime, time, timedelta
from typing import Any

from scripts.demo import Api
from scripts.demo_data import World

# Things the part could not do (a missing salary, a refused call); printed at the end of the part.
NOTES: list[str] = []


def note(text: str) -> None:
    NOTES.append(text)
    print(f"   note: {text}")


def data(api: Api, method: str, path: str, body: dict | None = None) -> Any:
    """The call's `data` (exits on any non-2xx, like Api)."""
    return api(method, path, body).get("data")


def attempt(api: Api, method: str, path: str, body: dict | None = None) -> tuple[int, Any]:
    """The call without exiting: (status, data or the error body)."""
    r = api.client.request(method, f"/api{path}", json=body, headers=api.headers)
    payload = r.json() if r.content else {}
    return r.status_code, (payload.get("data", payload) if r.status_code < 300 else payload)


def as_first(w: World, names: list[str], method: str, path: str, body: dict | None = None) -> tuple[str, Any]:
    """The call as the first of `names` whose permissions reach the record (403 / 404 try the next one).
    Returns (who did it, data); exits when nobody could."""
    last = None
    for name in dict.fromkeys(names):
        status, payload = attempt(w.as_(name), method, path, body)
        if status < 300:
            return name, payload
        out_of_reach = status in (403, 404) or (
            status == 422 and "employeeId" in (payload.get("fieldErrors") or {}))   # "Employee not found."
        if not out_of_reach:
            raise SystemExit(f"{method} {path} as {name} -> {status}: {payload}")
        last = (name, status, payload)
    raise SystemExit(f"{method} {path}: nobody could ({last})")


def lookup_or_create(api: Api, list_path: str, create_path: str, name: str, body: dict | None = None) -> dict:
    """A named master row: the existing one (other parts may have made it) or a new one."""
    sep = "&" if "?" in list_path else "?"
    for row in api.all(f"{list_path}{sep}q={name}"):
        if row.get("name", "").lower() == name.lower():
            return row
    return data(api, "POST", create_path, body or {"name": name})


def eid(w: World, name: str) -> int:
    return w.emp_id(name)


def current(w: World, name: str) -> bool:
    """Still working here (an earlier part may have let someone go): left / inactive people cannot sign in."""
    e = w.employees.get(name)
    return bool(e) and e.get("status") not in ("left", "inactive")


def only_current(w: World, names) -> list[str]:
    return [n for n in names if current(w, n)]


def first_of_next_month(d: date) -> date:
    return date(d.year + (d.month == 12), d.month % 12 + 1, 1)


def workdays_after(d: date, count: int, skip: int = 0) -> list[date]:
    """The next `count` Monday-Friday days after d (not d itself), skipping the first `skip` of them."""
    out, cur = [], d
    while len(out) < count + skip:
        cur += timedelta(days=1)
        if cur.weekday() < 5:
            out.append(cur)
    return out[skip:]


def workday_before(d: date) -> date:
    while d.weekday() >= 5:
        d -= timedelta(days=1)
    return d


def at(d: date, hh: int, mm: int = 0) -> str:
    return datetime.combine(d, time(hh, mm)).isoformat()


def iso(d: date | None) -> str | None:
    return d.isoformat() if d else None


def salary_of(w: World, name: str) -> float | None:
    """The person's salary in force today (None when payroll has not given them one)."""
    status, rows = attempt(w.admin, "GET", f"/employees/{eid(w, name)}/salary")
    if status != 200 or not rows:
        return None
    row = next((r for r in rows if r.get("isCurrent")), None)
    if row is None:
        current = sorted((r for r in rows if str(r.get("effectiveDate")) <= w.today.isoformat()),
                         key=lambda r: (str(r.get("effectiveDate")), int(r.get("id", 0))))
        row = current[-1] if current else None
    return float(row["amount"]) if row and row.get("amount") is not None else None
