"""Demo data part: time. Scheduling, roster and attendance for Top Edge Technologies, so the planner, the roster,
the time sheet, the overview, the logs and the warnings look like two months of use.

Who does what:
  Shelley Kannes (HR Manager)  company time zone and week, attendance and overtime settings, overtime policies,
                               geo-fences, IP restrictions, break types, time slots, holidays, rest days,
                               biometric devices and their enrolments, warning policies and penalties
  Ayesha Khan (HR Officer)     roster groups and enrolments, schedules, the devices' punch uploads, processing the
                               time sheet, and two corrections of forgotten check-outs

Punches come from two biometric devices per office through POST /attendance/settings/devices/{id}/punches, one
person at a time with a seeded random generator, so every day differs but a rerun on the same date is the same.
"""
import random
from datetime import date, datetime, time, timedelta, timezone

from scripts.demo_data import World

HR_MANAGER = "Shelley Kannes"
HR_OFFICER = "Ayesha Khan"

PAST_DAYS = 60      # schedules and punches from this many days ago
FUTURE_DAYS = 30    # schedules up to this many days ahead
EVENING_STAFF = {"Junaid Akhtar"}   # IT support, 14:00-23:00

# ---------------------------------------------------------------- holidays
# Pakistan's public holidays. Islamic dates are approximate (moon sighting) and move about 11 days earlier a year;
# these are 2026's, shifted for other years.
FIXED_HOLIDAYS = [
    ("Kashmir Solidarity Day", (2, 5), 1, "Solidarity with the people of Kashmir."),
    ("Pakistan Day", (3, 23), 1, "Lahore Resolution, 1940."),
    ("Labour Day", (5, 1), 1, "International Workers' Day."),
    ("Independence Day", (8, 14), 1, "Independence of Pakistan, 1947."),
    ("Iqbal Day", (11, 9), 1, "Birthday of Allama Muhammad Iqbal."),
    ("Quaid-e-Azam Day", (12, 25), 1, "Birthday of Quaid-e-Azam Muhammad Ali Jinnah (and Christmas)."),
]
ISLAMIC_HOLIDAYS_2026 = [
    ("Eid ul Fitr", (3, 20), 3, "End of Ramadan. Dates subject to moon sighting."),
    ("Eid ul Adha", (5, 27), 3, "Dates subject to moon sighting."),
    ("Ashura (9th and 10th Muharram)", (6, 25), 2, "Dates subject to moon sighting."),
    ("Eid Milad un Nabi", (8, 26), 1, "12 Rabi ul Awwal. Date subject to moon sighting."),
]

# ---------------------------------------------------------------- people's habits
# arrive: mean minutes against the shift start (negative = early) and spread; late / early / ot / miss / absent:
# chance a day is a late arrival (past the 15-minute grace), an early departure, an overtime evening, a forgotten
# check-out, an unexplained absence. meal: chance of punching out and back in for the meal break.
DEFAULT_HABITS = dict(arrive=-7, spread=6, late=0.04, early=0.03, ot=0.06, miss=0.01, absent=0.008, meal=0.0)
HABITS = {
    "Imran Siddiqui": dict(arrive=-2, spread=10, late=0.06, ot=0.25, miss=0.04, early=0.05),
    "Sana Malik": dict(arrive=-15, spread=5, late=0.01, ot=0.10),
    "Shelley Kannes": dict(arrive=-12, spread=6, late=0.02, ot=0.10, meal=0.2),
    "Ayesha Khan": dict(arrive=-10, spread=5, late=0.02, ot=0.06, meal=0.3),
    "Hamza Riaz": dict(arrive=-4, spread=7, late=0.06, early=0.05),
    "Bilal Ahmed": dict(arrive=-14, spread=6, late=0.02, ot=0.08),
    "Kashif Mehmood": dict(arrive=-28, spread=5, late=0.01, ot=0.10, early=0.01),
    "Nadia Hussain": dict(arrive=-6, spread=6, late=0.03, ot=0.10),
    "Usman Ghani": dict(arrive=-5, spread=6, late=0.04, ot=0.05, meal=0.4),
    "Farah Naz": dict(arrive=-3, spread=7, late=0.07, miss=0.05),
    "Haroon Rashid": dict(arrive=0, spread=9, late=0.05, ot=0.30, miss=0.04),
    "Faisal Javed": dict(arrive=-6, spread=7, late=0.04, ot=0.22),
    "Areeba Hameed": dict(arrive=-9, spread=6, late=0.03, ot=0.14, meal=0.3),
    "Zain Abbas": dict(arrive=6, spread=8, late=0.20, ot=0.15, early=0.02),
    "Hira Shahid": dict(arrive=-3, spread=7, late=0.07, ot=0.08),
    "Saad Qureshi": dict(arrive=-16, spread=5, late=0.01, ot=0.10, absent=0.0),
    "Rabia Anwar": dict(arrive=-8, spread=6, late=0.03, ot=0.15),
    "Danish Iqbal": dict(arrive=-2, spread=8, late=0.08, early=0.08, ot=0.08),
    "Mehwish Akram": dict(arrive=-12, spread=5, late=0.02, absent=0.0),
    "Omer Farooq": dict(arrive=-4, spread=8, late=0.05, ot=0.10, meal=0.2),
    "Maham Zafar": dict(arrive=-2, spread=7, late=0.07, early=0.04),
    "Asad Mirza": dict(arrive=-3, spread=9, late=0.06, early=0.10, miss=0.04),
    "Komal Shah": dict(arrive=-5, spread=7, late=0.05, early=0.12),
    "Taha Saleem": dict(arrive=8, spread=9, late=0.24, early=0.07, ot=0.04),
    "Waqas Butt": dict(arrive=-10, spread=6, late=0.03, ot=0.15),
    "Junaid Akhtar": dict(arrive=-9, spread=6, late=0.05, ot=0.12, miss=0.04, meal=0.5),
}
# Release crunches: these departments stay late on a few evenings (dates picked from the window).
CRUNCH_DEPARTMENTS = {"Software Development", "Quality Assurance", "UI/UX Design"}
MONTH_END_DEPARTMENTS = {"Finance & Accounts"}
# A couple of unexplained absences, as (name, workdays ago, how many days).
SCRIPTED_ABSENCES = [("Hira Shahid", 17, 2), ("Danish Iqbal", 9, 1), ("Farah Naz", 26, 1)]


def seed(w: World) -> None:
    hr, officer = w.as_(HR_MANAGER), w.as_(HR_OFFICER)
    start, end = w.days_ago(PAST_DAYS), w.today + timedelta(days=FUTURE_DAYS)
    people = {f"{p['first']} {p['last']}": p for p in w.people}
    joined = {n: max(date.fromisoformat(people[n]["joined"]), start) for n in w.employees}
    branch_of = {n: people[n].get("branch", "Lahore Head Office") for n in w.employees}
    lahore, islamabad = w.branches["Lahore Head Office"], w.branches["Islamabad Office"]

    now = company_now(hr)

    # ------------------------------------------------------------ settings (HR Manager)
    attendance_settings(hr)
    policies = overtime_policies(hr)
    fences = geo_fences(w, hr)
    ips = ip_restrictions(hr, lahore, islamabad)
    breaks = {b["name"]: b for b in [
        hr("POST", "/scheduling/settings/break-types", {"name": n, "startIdentifier": s, "endIdentifier": e})["data"]
        for n, s, e in [("Meal Break", "MEAL-OUT", "MEAL-IN"), ("Prayer Break", "PRAYER-OUT", "PRAYER-IN"),
                        ("Tea Break", "TEA-OUT", "TEA-IN")]]}
    slots = time_slots(hr, breaks)
    holidays = public_holidays(hr, w.today.year, end)
    holiday_dates = {d for h in holidays for d in date_range(date.fromisoformat(h["startDate"]),
                                                              date.fromisoformat(h["endDate"]))}
    everyone = [w.emp_id(n) for n in w.employees]
    rest = hr("POST", "/scheduling/settings/rest-days", {
        "fromDate": min(start, date(w.today.year, 1, 1)).isoformat(),
        "toDate": max(end, date(w.today.year, 12, 31)).isoformat(),
        "weekdays": [6, 7], "repeatEveryWeeks": 0, "step": 1, "isPayable": True, "employeeIds": everyone})["data"]
    warnings = warning_policies(hr)

    # ------------------------------------------------------------ roster and schedules (HR Officer)
    groups = {
        "Head Office General Shift": ("General Shift", "Lahore Head Office", "09:00 to 18:00, Monday to Friday."),
        "Islamabad Office General Shift": ("General Shift", "Islamabad Office",
                                           "09:00 to 18:00, Monday to Friday, for the Islamabad sales team."),
        "IT Support Evening Shift": ("Evening Support Shift", None,
                                     "14:00 to 23:00, Monday to Friday: network and helpdesk cover after hours."),
    }
    members = {g: [] for g in groups}
    for n in w.employees:
        if n in EVENING_STAFF:
            members["IT Support Evening Shift"].append(n)
        elif branch_of[n] == "Islamabad Office":
            members["Islamabad Office General Shift"].append(n)
        else:
            members["Head Office General Shift"].append(n)
    batches, shift_count, enrolment_count = [], 0, 0
    for title, (slot, branch, description) in groups.items():
        slot_id = int(slots[slot]["id"])
        group = officer("POST", "/roster/groups", {
            "title": title, "fromDate": start.isoformat(), "description": description, "isActive": True,
            "days": [{"weekday": d, "timeSlotId": slot_id} for d in range(1, 6)]
                    + [{"weekday": d, "isDayOff": True} for d in (6, 7)]})["data"]
        by_start: dict[date, list[int]] = {}
        for n in members[title]:
            by_start.setdefault(joined[n], []).append(w.emp_id(n))
        for first_day, ids in sorted(by_start.items()):
            enrolment_count += len(officer("POST", f"/roster/groups/{group['id']}/enrolments",
                                           {"employeeIds": ids, "startDate": first_day.isoformat()})["data"])
        fence = fences.get(branch or "Lahore Head Office")
        batch = officer("POST", "/scheduling/schedules/batches", {
            "startDate": start.isoformat(), "endDate": end.isoformat(), "rosterGroupId": int(group["id"]),
            "geoFenceId": int(fence["id"]) if fence else None})["data"]
        batches.append(batch)
        shift_count += batch["createdCount"]

    # ------------------------------------------------------------ biometric devices (HR Manager)
    devices = biometric_devices(w, hr, lahore, islamabad)
    user_no, n_lhr, n_isb = {}, 0, 0
    for n in w.employees:
        if branch_of[n] == "Islamabad Office":
            n_isb += 1
            user_no[n] = str(200 + n_isb)
        else:
            n_lhr += 1
            user_no[n] = str(100 + n_lhr)
    for branch, pair in devices.items():
        rows = [{"employeeId": w.emp_id(n), "deviceUserNo": user_no[n]} for n in w.employees if branch_of[n] == branch]
        for i, dev in enumerate(pair):
            pair[i] = hr("PUT", f"/attendance/settings/devices/{dev['id']}/enrolments",
                         {"enrolments": rows, "rowVersion": dev["rowVersion"]})["data"]

    # ------------------------------------------------------------ punches (the devices, uploaded by the HR Officer)
    workdays = [d for d in w.workdays(start, w.today) if d not in holiday_dates]
    crunch = crunch_days(workdays)
    absences = scripted_absences(workdays)
    lines: dict[str, list[dict]] = {}
    missing_out: list[tuple[str, date]] = []
    for n in w.employees:
        habits = {**DEFAULT_HABITS, **HABITS.get(n, {})}
        dept = w.employees[n].get("departmentName")
        evening = n in EVENING_STAFF
        male = people[n]["gender"] == "male"
        pair = devices[branch_of[n]]
        for d in workdays:
            if d < joined[n]:
                continue
            rng = random.Random(f"{n}|{d.isoformat()}")
            if (n, d) in absences:
                continue
            day = day_punches(rng, habits, d, evening, male,
                              crunch=dept in CRUNCH_DEPARTMENTS and d in crunch,
                              month_end=dept in MONTH_END_DEPARTMENTS and d.day >= 24)
            day = [(at, kind) for at, kind in day if at <= now - timedelta(minutes=1)]
            if day and d < w.today and not any(k == "check_out" for _, k in day):
                missing_out.append((n, d))
            for at, kind in day:
                dev = pair[0] if rng.random() < (0.8 if kind == "check_in" else 0.55) else pair[1]
                lines.setdefault(dev["id"], []).append(
                    {"deviceUserNo": user_no[n], "punchedAt": at.strftime("%Y-%m-%dT%H:%M:%S"), "punchType": kind})
    created = failed = 0
    for device_id, rows in lines.items():
        rows.sort(key=lambda r: r["punchedAt"])
        for i in range(0, len(rows), 5000):
            result = officer("POST", f"/attendance/settings/devices/{device_id}/punches",
                             {"lines": rows[i:i + 5000]})["data"]
            created, failed = created + result["created"], failed + result["failed"]
            if result["failed"]:
                print(f"   punches refused on device {device_id}: {result['errors'][:3]}")

    # ------------------------------------------------------------ the time sheet, warnings, corrections
    processed = officer("POST", "/attendance/time-sheet/process",
                        {"fromDate": start.isoformat(), "toDate": w.today.isoformat()})["data"]
    raised = hr("POST", "/warning/warnings/process", {"fromDate": start.isoformat(), "toDate": w.today.isoformat()})["data"]
    corrections = correct_missing_checkouts(w, officer, missing_out, now)

    summary = officer("GET", f"/attendance/time-sheet/summary?fromDate={start}&toDate={w.today}&tab=all")["data"]
    issued = hr("GET", f"/warning/warnings?fromDate={start}&toDate={w.today}&page=1&pageSize=1")["meta"]["total"]
    print(f"   settings: {len(policies)} overtime policies, {len(fences)} geo-fences, {len(ips)} IP restrictions, "
          f"{len(breaks)} break types, {len(slots)} time slots, {len(holidays)} holidays, "
          f"rest days {rest['restDayCount']}, {len(warnings)} warning policies")
    print(f"   roster: {len(groups)} groups, {enrolment_count} enrolments, {shift_count} shifts in {len(batches)} batches "
          f"({start} to {end})")
    print(f"   devices: {sum(len(p) for p in devices.values())}, punches {created} created ({failed} refused) "
          f"over {len(workdays)} working days; {processed['processedDays']} days processed, "
          f"{corrections} check-outs corrected")
    print(f"   time sheet: present {summary['present']}, absent {summary['absent']}, late {summary['lateArrival']}, "
          f"early {summary['earlyLeft']}, missing punch {summary['missingPunch']}, overtime "
          f"{summary['overtimeMinutes'] // 60} h; warnings {issued} ({raised['penalised']} with a penalty)")


# ---------------------------------------------------------------- settings

def company_now(hr) -> datetime:
    """The company's wall-clock time now (punches and schedules are local times)."""
    general = hr("GET", "/organisation/general")["data"]
    if general.get("timezone") != "Asia/Karachi" or general.get("weekStartsOn") != "monday" or not general.get("currency"):
        general = hr("PUT", "/organisation/general", {
            "organizationName": general["organizationName"], "legalName": general.get("legalName"),
            "email": general.get("email"), "phone": general.get("phone"), "website": general.get("website"),
            "address": general.get("address"),
            "countryId": int(general["countryId"]) if general.get("countryId") else None,
            "timezone": "Asia/Karachi", "currency": general.get("currency") or "PKR",
            "dateFormat": general.get("dateFormat") or "dd/MM/yyyy", "weekStartsOn": "monday",
            "fiscalYearStartMonth": general.get("fiscalYearStartMonth") or 7,
            "rowVersion": general["rowVersion"]})["data"]
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("Asia/Karachi")).replace(tzinfo=None)
    except Exception:  # no tz database on this machine: Pakistan has no daylight saving
        return datetime.now(timezone(timedelta(hours=5))).replace(tzinfo=None)


def attendance_settings(hr) -> None:
    basic = hr("GET", "/attendance/settings/basic")["data"]
    hr("PUT", "/attendance/settings/basic", {
        "ignorePunchType": False, "useCheckInOutForBreaks": False, "shortDurationOnNonFlexible": False,
        # Attendance comes from the biometric devices; Clock In / Clock Out on the dashboard stays off.
        "dashboardPunch": False, "allowMultiShift": False, "pictureOnDashboardPunch": False,
        "minimumWorkableMinutes": 240, "lateGraceMinutes": 15, "rowVersion": basic.get("rowVersion")})
    overtime = hr("GET", "/attendance/settings/overtime")["data"]
    hr("PUT", "/attendance/settings/overtime", {
        "overtimeOnCheckIn": False, "overtimeOnCheckOut": True, "overtimeApprovalRequired": False,
        "doNotAutoCreateRequests": True, "overtimeOnHolidays": True, "overtimeAfterDutyDuration": True,
        "encashmentShiftMinutes": 480, "rowVersion": overtime.get("rowVersion")})


def overtime_policies(hr) -> list[dict]:
    return [hr("POST", "/attendance/settings/overtime-policies", body)["data"] for body in [
        {"name": "Monthly Overtime Encashment", "period": "monthly", "isActive": True,
         "description": "Overtime worked in a month is paid as whole days: 8 to 16 hours one day, 16 to 24 hours "
                        "two days, beyond that three days (capped).",
         "slabs": [{"minMinutes": 480, "maxMinutes": 959, "encashmentType": "full_day"},
                   {"minMinutes": 960, "maxMinutes": 1439, "encashmentType": "full_day"},
                   {"minMinutes": 1440, "maxMinutes": 2880, "encashmentType": "full_day"}]},
        {"name": "Holiday and Weekend Duty", "period": "daily", "isActive": True,
         "description": "A full shift worked on a rest day or public holiday is paid as an extra day.",
         "slabs": [{"minMinutes": 360, "maxMinutes": 1440, "encashmentType": "full_day"}]},
    ]]


def geo_fences(w: World, hr) -> dict[str, dict]:
    spots = {"Lahore Head Office": (31.5102, 74.3441, 150), "Islamabad Office": (33.7104, 73.0563, 120)}
    out = {}
    for branch, (lat, lng, radius) in spots.items():
        out[branch] = hr("POST", "/attendance/settings/geo-fences", {
            "name": branch, "shape": "circle", "centerLat": lat, "centerLng": lng, "radiusM": radius,
            "appliesToAll": False, "isForShift": True, "isActive": True,
            "targets": [{"targetType": "branch", "targetId": int(w.branches[branch]["id"])}]})["data"]
    return out


def ip_restrictions(hr, lahore: dict, islamabad: dict) -> list[dict]:
    return [
        hr("POST", "/attendance/settings/ip-restrictions", {
            "ipv4": "182.180.98.0", "netmask": "255.255.255.248", "appliesToAll": False, "isActive": True,
            "targets": [{"targetType": "branch", "targetId": int(lahore["id"])}]})["data"],
        hr("POST", "/attendance/settings/ip-restrictions", {
            "rangeStart": "39.32.7.10", "rangeEnd": "39.32.7.20", "appliesToAll": False, "isActive": True,
            "targets": [{"targetType": "branch", "targetId": int(islamabad["id"])}]})["data"],
    ]


def time_slots(hr, breaks: dict) -> dict[str, dict]:
    meal = int(breaks["Meal Break"]["id"])
    bodies = [
        {"name": "General Shift", "color": "#2563EB", "startTime": "09:00", "endTime": "18:00",
         "breaks": [{"breakTypeId": meal, "startTime": "13:00", "endTime": "14:00", "isInclusive": False}]},
        {"name": "Evening Support Shift", "color": "#7C3AED", "startTime": "14:00", "endTime": "23:00",
         "breaks": [{"breakTypeId": meal, "startTime": "19:00", "endTime": "20:00", "isInclusive": False}]},
        {"name": "Ramadan Timing", "color": "#059669", "startTime": "09:00", "endTime": "15:00", "breaks": []},
        {"name": "Flexible Hours", "color": "#D97706", "startTime": "08:00", "endTime": "20:00",
         "isFlexible": True, "workableMinutes": 480, "breaks": []},
    ]
    return {b["name"]: hr("POST", "/scheduling/settings/time-slots", b)["data"] for b in bodies}


def public_holidays(hr, year: int, end: date) -> list[dict]:
    """This year's public holidays, and next year's too when the schedules reach into it."""
    out = []
    for y in sorted({year, end.year}):
        shift = round(-10.875 * (y - 2026))
        rows = [(name, date(y, m, d), days, desc) for name, (m, d), days, desc in FIXED_HOLIDAYS]
        rows += [(name, date(2026, m, d) + timedelta(days=shift), days, desc)
                 for name, (m, d), days, desc in ISLAMIC_HOLIDAYS_2026]
        for name, first, days, desc in sorted(rows, key=lambda r: r[1]):
            if first.year != y:
                first = first.replace(year=y)
            out.append(hr("POST", "/scheduling/settings/holidays", {
                "name": name if y == year else f"{name} {y}", "holidayType": "public",
                "startDate": first.isoformat(), "endDate": (first + timedelta(days=days - 1)).isoformat(),
                "description": desc, "attendanceExempt": True})["data"])
    return out


def warning_policies(hr) -> list[dict]:
    late = hr("POST", "/warning/policies", {
        "title": "Late Arrival", "appliesTo": "late_arrival", "period": "month", "isActive": True,
        "rules": [{"clockEvent": "clock_in", "minutes": 0, "occurrenceCount": 3}]})["data"]
    late = hr("PUT", f"/warning/policies/{late['id']}/penalties", {"rowVersion": late["rowVersion"], "penalties": [
        {"afterCount": 2, "period": "month", "penaltyType": "half_day", "deduction": "payroll"},
        {"afterCount": 3, "period": "month", "penaltyType": "full_day", "deduction": "payroll"}]})["data"]
    early = hr("POST", "/warning/policies", {
        "title": "Early Departure", "appliesTo": "early_departure", "period": "month", "isActive": True,
        "rules": [{"clockEvent": "clock_out", "minutes": 15, "occurrenceCount": 3}]})["data"]
    early = hr("PUT", f"/warning/policies/{early['id']}/penalties", {"rowVersion": early["rowVersion"], "penalties": [
        {"afterCount": 2, "period": "month", "penaltyType": "percentage", "percentage": 25, "deduction": "payroll"}]})["data"]
    half = hr("POST", "/warning/policies", {
        "title": "Frequent Half Days", "appliesTo": "half_day_leave", "period": "month", "isActive": True,
        "rules": [{"clockEvent": "clock_in", "minutes": 0, "occurrenceCount": 3}]})["data"]
    return [late, early, half]


def biometric_devices(w: World, hr, lahore: dict, islamabad: dict) -> dict[str, list[dict]]:
    specs = [
        (lahore, "Head Office Main Entrance", "ZKTeco SpeedFace-V5L", "CKJ4211160012", "192.168.10.201",
         "Ground floor reception, Gulberg III"),
        (lahore, "Head Office Second Floor", "ZKTeco K40 Pro", "A8N5210460318", "192.168.10.202",
         "Second floor, development hall"),
        (islamabad, "Islamabad Reception", "ZKTeco SpeedFace-V5L", "CKJ4211160157", "192.168.20.201",
         "Reception, Blue Area"),
        (islamabad, "Islamabad Back Office", "ZKTeco MB460", "AEXF203760094", "192.168.20.202",
         "Back office, near the meeting room"),
    ]
    out: dict[str, list[dict]] = {}
    for branch, name, model, serial, ip, address in specs:
        out.setdefault(branch["name"], []).append(hr("POST", "/attendance/settings/devices", {
            "name": name, "model": model, "serialNo": serial, "ipAddress": ip, "port": 4370,
            "branchId": int(branch["id"]), "address": address, "status": "active"})["data"])
    return out


# ---------------------------------------------------------------- punches

def date_range(a: date, b: date) -> list[date]:
    return [a + timedelta(days=i) for i in range((b - a).days + 1)]


def crunch_days(workdays: list[date]) -> set[date]:
    """Release evenings: two or three consecutive days, three times in the window."""
    out, past = set(), [d for d in workdays[:-1]]
    for k in (0.2, 0.55, 0.85):
        i = int(len(past) * k)
        out.update(past[i:i + (3 if k == 0.55 else 2)])
    return out


def scripted_absences(workdays: list[date]) -> set[tuple[str, date]]:
    out = set()
    for name, ago, days in SCRIPTED_ABSENCES:
        i = len(workdays) - 1 - ago
        for d in workdays[max(i, 0):max(i, 0) + days]:
            out.add((name, d))
    return out


def day_punches(rng: random.Random, h: dict, d: date, evening: bool, male: bool, crunch: bool,
                month_end: bool) -> list[tuple[datetime, str]]:
    """One person's punches on one working day."""
    if rng.random() < h["absent"]:
        return []
    start = datetime.combine(d, time(14, 0) if evening else time(9, 0))
    end = start + timedelta(hours=9)

    def sec() -> timedelta:
        return timedelta(seconds=rng.randint(0, 59))

    if rng.random() < h["late"]:
        arrive = start + timedelta(minutes=rng.choice([rng.randint(16, 30), rng.randint(16, 30), rng.randint(31, 75)]))
    else:
        arrive = start + timedelta(minutes=round(max(-40.0, min(14.0, rng.gauss(h["arrive"], h["spread"])))))
    ot = h["ot"] + (0.55 if crunch else 0) + (0.45 if month_end else 0)
    early = 0 if crunch else h["early"] + (0.05 if d.weekday() == 4 and not evening else 0)  # Friday afternoons
    roll = rng.random()
    if roll < early:
        leave = end - timedelta(minutes=rng.choice([rng.randint(5, 15), rng.randint(20, 50), rng.randint(20, 95)]))
    elif roll < early + ot:
        leave = end + timedelta(minutes=rng.randint(55, 210))
    else:
        r = rng.random()
        leave = end + timedelta(minutes=0 if r < 0.8 else rng.randint(1, 10) if r < 0.95 else rng.randint(11, 30))
    punches = []
    forgot_in = rng.random() < 0.006
    if not forgot_in:
        punches.append((arrive + sec(), "check_in"))
    if h["meal"] and rng.random() < h["meal"]:
        meal_out = start + timedelta(hours=5 if evening else 4, minutes=rng.randint(-5, 15))
        punches.append((meal_out + sec(), "MEAL-OUT"))
        punches.append((meal_out + timedelta(minutes=rng.randint(30, 55)) + sec(), "MEAL-IN"))
    elif male and not evening and d.weekday() == 4 and rng.random() < 0.35:
        out = start + timedelta(hours=4, minutes=rng.randint(5, 20))
        punches.append((out + sec(), "PRAYER-OUT"))
        punches.append((out + timedelta(minutes=rng.randint(40, 65)) + sec(), "PRAYER-IN"))
    if forgot_in or rng.random() >= h["miss"]:
        punches.append((leave + sec(), "check_out"))
    return punches


def correct_missing_checkouts(w: World, officer, missing: list[tuple[str, date]], now: datetime) -> int:
    """HR fixes two forgotten check-outs: one with a manual punch, one by editing the day."""
    old = [(n, d) for n, d in missing if d <= now.date() - timedelta(days=3) and n not in EVENING_STAFF]
    old.sort(key=lambda x: x[1], reverse=True)
    done = 0
    if old:
        n, d = old[0]
        officer("POST", "/attendance/logs", {
            "employeeId": w.emp_id(n), "punchedAt": f"{d.isoformat()}T18:00:20", "punchType": "check_out",
            "remarks": "Forgot to punch out; left at 18:00, confirmed by the line manager."})
        done += 1
    if len(old) > 1:
        n, d = old[1]
        day = officer("GET", f"/attendance/days/{w.emp_id(n)}/{d.isoformat()}")["data"]["day"]
        officer("PUT", f"/attendance/days/{w.emp_id(n)}/{d.isoformat()}", {
            "lastOut": f"{d.isoformat()}T18:00:00", "rowVersion": day["rowVersion"],
            "comments": "Device at the exit was offline in the evening; check-out time from the gate register."})
        done += 1
    return done
