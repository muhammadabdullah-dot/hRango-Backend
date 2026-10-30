"""Demo data part: talent. Top Edge Technologies in the middle of its hiring and appraisal season:

- Manpower planning: this fiscal year, a plan per hiring department, their e-budgets with decisions by the
  department heads and HR, and the open positions the approved budgets release.
- Recruitment (Hamza Riaz, the recruiter; the hiring managers sit on the panels and evaluate): openings from
  those open positions plus a closed and a draft one, 22 applicants across the pipeline, interviews held and
  coming up, offers sent / declined / accepted, and one hire (a new employee).
- Performance: a rating scale, an appraisal form, KPIs per department, goals with check-ins for everyone,
  last half-year's cycle finalised with increments (one applied, one rejected) and closed, this half-year's
  cycle launched with self and manager reviews under way.
- Training: programmes, sessions held (attendance, feedback) and coming up (nominations, approvals).

Runs last, after scripts.demo alone or after the other parts. The increment is applied only to someone payroll
has given a salary; otherwise the part says so and leaves the increments proposed.
"""
import time

from scripts.demo_data import World
from scripts.demo_data import _talent_manpower, _talent_performance, _talent_recruitment, _talent_training
from scripts.demo_data._talent_common import NOTES, current


def seed(w: World) -> None:
    started = time.monotonic()
    NOTES.clear()
    # Read the people again: earlier parts transfer, promote and let people go after World was loaded.
    w.employees = {e["name"]: e for e in w.admin.all("/employees")}
    gone = sorted(n for n in w.employees if not current(w, n))
    if gone:
        print(f"   talent: leaving out {', '.join(gone)} (no longer working here)")
    manpower = _talent_manpower.seed(w)
    _talent_recruitment.seed(w, manpower)
    _talent_performance.seed(w)
    _talent_training.seed(w)
    if NOTES:
        print(f"   talent notes: {len(NOTES)} (see above)")
    print(f"   talent: done in {time.monotonic() - started:.0f}s")
