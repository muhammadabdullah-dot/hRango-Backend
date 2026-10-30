"""Demo data part: payroll_assets. Payroll, benefits, assets and off-boarding for Top Edge Technologies, so those
screens look like a company that has been running payroll for months:

- Payroll settings in PKR: general options, income tax slabs (previous and current tax year), pay components
  (gross broken into basic / house rent / medical / utilities, fuel by grade, a quarterly performance bonus,
  EOBI and provident fund with the employer's share, income tax), a provident fund rule and account types,
  a sales incentive, two disbursement banks (Meezan Bank, HBL).
- A salary history and a bank account for everyone; two revisions (one with its letter), a tax rebate, vouchers
  in every state, a leave encashment when the leave types allow it.
- Three closed monthly payrolls (payslips released and paid) and the current month run but not closed.
- Assets: five types, a laptop and an access card for everyone, monitors, phones and SIMs, spares, one in repair,
  one returned, one written off.
- Off-boarding: Kashif Mehmood resigns (request approved), clears his assets, the exit checklist is answered and
  his final settlement is closed, which completes his end of employment (he is "left" afterwards, so later parts
  should not give him new activity); Taha Saleem's resignation is pending.
- Benefits: plan year, four plans, an open enrolment window, elections by most people (some approved).

Works right after scripts.demo, and also after the time and leave_requests parts (the runs then read their
attendance, leave and loan instalments).
"""
import time
from datetime import timedelta

from scripts.demo_data import World
from scripts.demo_data._payroll_assets_pay import Pay, add_months, month_start
from scripts.demo_data._payroll_assets_sep import Sep

LEAVER, PENDING_LEAVER = "Kashif Mehmood", "Taha Saleem"


def seed(w: World) -> None:
    t0 = time.monotonic()
    if w.as_("Nadia Hussain").all("/payroll/disbursement-banks"):
        print("  payroll_assets: already made (disbursement banks exist); skipped")
        return
    pay, sep = Pay(w), Sep(w)

    pay.settings()
    pay.salaries()
    pay.revisions()
    sep.assets()
    sep.checklist()

    # The leaver goes in the current month: last working day well before today (the 1st at the earliest), so
    # the current run leaves him out and his final settlement pays the month up to that day.
    this_month = month_start(w.today)
    lwd = max(this_month, w.today - timedelta(days=12))
    sep.resign(LEAVER, lwd - timedelta(days=30), 30, approve=True)
    sep.resign(PENDING_LEAVER, w.days_ago(3), 30, approve=False)

    for k in (3, 2, 1):
        pay.payroll(add_months(this_month, -k), close=True, leaving=set())
    pay.leave_encashment()
    pay.vouchers()
    current = pay.payroll(this_month, close=False, leaving={LEAVER})

    sep.clear(LEAVER, "Bilal Ahmed", "Resigned for a better opportunity. Office supplies register and courier "
                                     "accounts handed over to Bilal Ahmed.")
    fs = pay.final_settlement(LEAVER)
    eoe = next(e for e in w.admin.all("/offboarding/end-of-employment") if e["employeeId"] == str(w.emp_id(LEAVER)))
    if eoe["status"] != "completed":
        detail = w.admin("GET", f"/offboarding/end-of-employment/{eoe['id']}")["data"]
        print(f"  end of employment of {LEAVER} still waits for: {[x['label'] for x in detail['waitingFor']]}")

    sep.benefits()

    counts = {**pay.counts, **sep.counts}
    print("  " + ", ".join(f"{v} {k}" for k, v in counts.items()))
    print(f"  current payroll {current['code']}: {current['payslipCount']} payslips, net Rs {current['netPayable']:,.0f}; "
          f"final settlement of {LEAVER}: {fs['status']}, net Rs {fs['netPayable'] or 0:,.0f}; "
          f"end of employment {eoe['status']}; {time.monotonic() - t0:.0f}s")
