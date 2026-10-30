"""Demo data part: leave_requests. Leave set-up (types, policies, allotment, opening balances), Request
Settings (authorities, flows, restrictions, delegations, expense categories, reimbursement pay items),
loan & advance types and categories, then four months of leave applications and requests of every kind,
filed by the employees and decided by the people their approval flows name, with items still waiting in
the managers' Approvals (Faisal Javed, Haroon Rashid, Shelley Kannes, Nadia Hussain, Imran Siddiqui).

Requests that need planned shifts (work from home, punch, relaxation, shift change) are filed only when
the time part has planned some; rest days only when a roster group exists. No resignation (off-boarding
is another part). Runs once on a database where nobody has applied for leave yet."""
import time

from scripts.demo_data import World
from scripts.demo_data._leave_requests_common import Ctx
from scripts.demo_data._leave_requests_history import (file_air_tickets, file_expenses, file_hr, file_leaves,
                                                       file_loans, file_official_visits, file_overtime,
                                                       file_requisitions, file_scheduled, file_travel,
                                                       file_update_requests)
from scripts.demo_data._leave_requests_setup import (approver_rights, finalise_leave_types, load_schedules,
                                                     setup_claims_and_loans, setup_leaves, setup_request_settings)


def seed(w: World) -> None:
    started = time.monotonic()
    if w.admin("GET", "/leaves/applications?tab=all&page=1&pageSize=1")["meta"]["total"]:
        print("leave_requests: leave applications already exist; nothing done")
        return
    c = Ctx(w)
    approver_rights(c)
    setup_leaves(c)
    setup_request_settings(c)
    setup_claims_and_loans(c)
    load_schedules(c)
    print(f"  set-up done ({time.monotonic() - started:.0f}s); shifts planned for "
          f"{sum(1 for s in c.shifts.values() if s)} employees")

    for step in (file_leaves, file_official_visits, file_overtime, file_travel, file_expenses, file_air_tickets,
                 file_requisitions, file_loans, file_scheduled, file_update_requests, file_hr):
        step(c)
    finalise_leave_types(c)

    by_type: dict[str, dict[str, int]] = {}
    for (code, status), n in sorted(c.stats.items()):
        by_type.setdefault(code, {})[status] = n
    for code, counts in by_type.items():
        print(f"  {code:20} " + ", ".join(f"{s} {n}" for s, n in counts.items()))
    for s in c.skipped:
        print(f"  skipped: {s}")
    for p in c.problems:
        print(f"  PROBLEM: {p}")
    print(f"  leave_requests: {sum(c.stats.values())} requests in {time.monotonic() - started:.0f}s"
          + (f", {len(c.problems)} problems" if c.problems else ""))
