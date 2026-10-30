"""History of the leave_requests demo part: what the employees of Top Edge Technologies asked for over the
last four months and what is waiting now, each filed by the employee (HR files promotions and transfers)
and decided by the people their approval flow names. Weeks are counted back from this week (0); a
negative week is ahead."""
from datetime import date, datetime, time, timedelta

from scripts.demo_data._leave_requests_common import Ctx, first_of_next_month

LT = {"AL": "Annual Leave", "CL": "Casual Leave", "SL": "Sick Leave", "ML": "Maternity Leave",
      "PL": "Paternity Leave", "UL": "Unpaid Leave"}

# (who, type, weeks ago, first weekday 0=Mon, days, outcome, reason, extra)
# extra: half / quarter (a short leave), cert (a medical certificate), delegate, reject, cancel
LEAVES = [
    ("Areeba Hameed", "AL", 16, 0, 5, "approved", "Family trip to Hunza and Skardu.", {}),
    ("Zain Abbas", "CL", 15, 1, 1, "approved", "Bank and NADRA paperwork.", {}),
    ("Hira Shahid", "SL", 14, 2, 2, "approved", "Viral fever; doctor advised two days' rest.", {"cert": True}),
    ("Danish Iqbal", "AL", 13, 0, 3, "approved", "Sister's wedding in Faisalabad.", {}),
    ("Maham Zafar", "CL", 13, 4, 1, "approved", "Moving to a new flat.", {}),
    ("Komal Shah", "SL", 12, 0, 1, "approved", "Migraine.", {}),
    ("Taha Saleem", "AL", 12, 2, 3, "rejected", "Short trip to Murree with family.",
     {"reject": "The Q3 campaign launches that week. Please move it to the following week."}),
    ("Taha Saleem", "AL", 11, 0, 3, "approved", "Short trip to Murree with family (moved).", {}),
    ("Usman Ghani", "CL", 11, 3, 1, "approved", "Parent-teacher meeting at my son's school.", {}),
    ("Farah Naz", "SL", 10, 1, 2, "approved", "Food poisoning.", {"cert": True}),
    ("Junaid Akhtar", "AL", 10, 0, 5, "approved", "Annual family visit to Swat.", {}),
    ("Ayesha Khan", "CL", 9, 0, 1, "approved", "Personal errand.", {}),
    ("Hamza Riaz", "AL", 9, 2, 3, "approved", "Cousin's wedding in Multan.", {}),
    ("Haroon Rashid", "AL", 11, 0, 5, "approved", "Family holiday in Istanbul.", {}),
    ("Kashif Mehmood", "CL", 8, 1, 1, "approved", "Electricity meter replacement at home.", {}),
    ("Faisal Javed", "AL", 8, 0, 4, "approved", "Umrah.", {}),
    ("Rabia Anwar", "SL", 7, 3, 2, "approved", "Throat infection.", {"delegate": True}),
    ("Omer Farooq", "CL", 7, 0, 1, "approved", "Car accident paperwork with the insurer.", {}),
    ("Imran Siddiqui", "AL", 7, 0, 3, "approved", "Family time after the board meeting.", {}),
    ("Zain Abbas", "AL", 6, 0, 3, "rejected", "Trip to Lahore Fort and Walled City with friends.",
     {"reject": "Release 4.2 goes live that week; please choose another week."}),
    ("Areeba Hameed", "CL", 6, 3, 1, "approved", "Doctor's appointment in the morning.", {"half": True}),
    ("Junaid Akhtar", "PL", 6, 0, 5, "approved", "Birth of our daughter.", {}),
    ("Shelley Kannes", "CL", 6, 1, 1, "approved", "Personal work.", {}),
    ("Sana Malik", "AL", 5, 0, 2, "approved", "Graduation ceremony of my brother.", {}),
    ("Nadia Hussain", "CL", 5, 4, 1, "approved", "Family function.", {}),
    ("Bilal Ahmed", "SL", 4, 0, 1, "approved", "High fever.", {}),
    ("Hira Shahid", "CL", 4, 2, 1, "rejected+1", "Personal work.",
     {"reject": "Applied after the day without informing the team lead; it will be marked as absent per policy."}),
    ("Danish Iqbal", "SL", 3, 1, 1, "approved", "Dental surgery.", {}),
    ("Asad Mirza", "AL", 3, 0, 3, "approved", "Family holiday in Naran.", {}),
    ("Waqas Butt", "CL", 3, 3, 1, "approved", "Child's school admission test.", {}),
    ("Maham Zafar", "AL", 2, 0, 5, "cancelled", "Trip to Thailand.", {"cancel": "Visa did not come through in time."}),
    ("Usman Ghani", "UL", 2, 0, 2, "approved", "Extended family matter; casual leave used up.", {}),
    ("Saad Qureshi", "SL", 2, 2, 1, "approved", "Flu.", {}),
    ("Komal Shah", "CL", 1, 4, 1, "approved", "Personal errand.", {}),
    ("Hamza Riaz", "CL", 1, 2, 1, "approved", "Leaving two hours early for a family matter.", {"quarter": True}),
    ("Mehwish Akram", "CL", 1, 0, 1, "rejected", "Personal work.",
     {"reject": "You are in the onboarding training that day; please take another day."}),
    # This week and ahead.
    ("Junaid Akhtar", "CL", -1, 2, 1, "approved", "Car service and registration renewal.", {}),
    ("Farah Naz", "AL", -3, 0, 5, "approved", "Family wedding in Karachi.", {}),
    ("Rabia Anwar", "AL", -1, 1, 3, "cancelling", "Short holiday.",
     {"cancel": "The regression cycle moved to next week; I will re-apply later."}),
    ("Zain Abbas", "AL", -2, 0, 5, "pending", "Trip to Skardu with family.", {}),
    ("Hira Shahid", "CL", -1, 4, 1, "pending", "Cousin's mehndi.", {}),
    ("Saad Qureshi", "CL", -3, 0, 1, "pending", "University degree collection.", {}),
    ("Areeba Hameed", "AL", -5, 0, 5, "pending+1", "Year-end family holiday.", {}),
    ("Danish Iqbal", "CL", -2, 3, 1, "pending+1", "Personal work.", {}),
    ("Faisal Javed", "CL", -1, 0, 1, "pending", "Personal work at the passport office.", {}),
    ("Omer Farooq", "AL", -4, 0, 3, "pending", "Visiting parents in Peshawar.", {}),
    ("Waqas Butt", "AL", -6, 0, 5, "pending", "Year-end family holiday.", {}),
    ("Komal Shah", "AL", -3, 1, 3, "pending", "Sister's wedding.", {}),
    ("Kashif Mehmood", "AL", -2, 0, 3, "withdrawn", "Village visit.", {"cancel": "No longer travelling."}),
    ("Ayesha Khan", "ML", -8, 0, 84, "pending", "Maternity leave; doctor's certificate attached.", {"cert": True}),
]


def file_leaves(c: Ctx) -> None:
    lt = c.ids["leave"]
    for who, code, wk, dow, days, outcome, reason, extra in LEAVES:
        start = c.day(wk, dow)
        end = start + timedelta(days=days - 1)
        details = {"leaveTypeId": lt[LT[code]]}
        if extra.get("half"):
            details.update(isShort=True, shortLeaveType="half_day", startTime="09:00:00", endTime="13:00:00")
        if extra.get("quarter"):
            details.update(isShort=True, shortLeaveType="quarter_day", startTime="16:00:00", endTime="18:00:00")
        body = {"fromDate": start.isoformat(), "toDate": end.isoformat(), "reason": reason, "details": details}
        if extra.get("cert"):
            f = c.upload_pdf(who, "medical-certificate.pdf",
                             ["Medical Certificate", f"Patient: {who}", f"Advised rest from {start:%d %b %Y}",
                              f"to {end:%d %b %Y}.", "Dr. S. Rehman, MBBS, FCPS"])
            body["attachments"] = [f] if f else []
        c.file(who, "leave", body, outcome, reject_remarks=extra.get("reject", "Not possible at this time."),
               cancel_reason=extra.get("cancel", "Plans changed."),
               delegates={"Haroon Rashid": "Faisal Javed"} if extra.get("delegate") else None)


# ---------------------------------------------------------------------- time requests that need no shift

def file_official_visits(c: Ctx) -> None:
    for who, wk, dow, start, end, outcome, reason, rej in (
            ("Komal Shah", 10, 1, "10:00", "13:30", "approved", "Product demo at a telecom client's head office.", None),
            ("Asad Mirza", 6, 2, "11:00", "16:00", "approved", "Meeting with a government procurement committee.", None),
            ("Junaid Akhtar", 2, 3, "09:30", "12:00", "approved", "Server room cabling at the client's site.", None),
            ("Taha Saleem", 1, 0, "14:00", "17:00", "rejected", "Digital marketing expo at the Expo Centre.",
             "Komal is already covering the expo for the team."),
            ("Hamza Riaz", 0, 2, "10:00", "13:00", "pending", "Campus recruitment drive at a university.", None),
            ("Zain Abbas", -1, 1, "10:00", "13:00", "pending", "User acceptance testing at the bank's office.", None)):
        d = c.day(wk, dow)
        c.file(who, "official_visit", {"fromDate": d.isoformat(), "toDate": d.isoformat(), "reason": reason,
                                       "details": {"windowDate": d.isoformat(), "startTime": f"{start}:00",
                                                   "endTime": f"{end}:00"}},
               outcome, reject_remarks=rej or "Not needed.")


def file_overtime(c: Ctx) -> None:
    def body(who, d, start, end, minutes, reason, kind="voluntary"):
        e = c.emp(who)
        return {"fromDate": d.isoformat(), "toDate": d.isoformat(), "reason": reason,
                "details": {"departmentId": int(e["departmentId"]), "branchId": int(e["branchId"]),
                            "locationId": int(e["locationId"]) if e.get("locationId") else None,
                            "overtimeDate": d.isoformat(), "startTime": f"{start}:00", "endTime": f"{end}:00",
                            "appliedMinutes": minutes, "overtimeType": kind}}

    for who, wk, dow, start, end, minutes, approved, outcome, reason in (
            ("Zain Abbas", 8, 3, "18:00", "21:00", 180, 180, "approved", "Hotfix for the payments API."),
            ("Areeba Hameed", 8, 3, "18:00", "22:00", 240, 210, "approved", "Hotfix for the payments dashboard."),
            ("Danish Iqbal", 5, 5, "10:00", "16:00", 360, 360, "approved", "Weekend regression for release 4.1."),
            ("Hira Shahid", 3, 1, "18:00", "20:30", 150, None, "rejected", "App store submission."),
            ("Junaid Akhtar", 2, 5, "10:00", "14:00", 240, 240, "approved", "Weekend network migration."),
            ("Zain Abbas", 0, 1, "18:00", "21:00", 180, None, "pending", "Database upgrade rehearsal."),
            ("Usman Ghani", 1, 4, "17:30", "20:30", 180, None, "pending", "Month-end payroll close.")):
        c.file(who, "overtime", body(who, c.day(wk, dow), start, end, minutes, reason), outcome,
               details={"approvedMinutes": approved} if approved else None,
               reject_remarks="Overtime was not agreed in advance; please plan it with me first.")

    # The QA team's release weekend, filed in bulk by HR.
    d = c.day(4, 5)
    qa = ["Rabia Anwar", "Danish Iqbal", "Mehwish Akram"]
    b = body("Danish Iqbal", d, "09:00", "15:00", 360, "Release 4.1 weekend testing.", "mandatory")
    res = c.call(c.w.admin, "POST", "/requests/overtime/bulk",
                 {"employeeIds": [c.eid(n) for n in qa], "overtimeType": "mandatory", "fromDate": d.isoformat(),
                  "reason": "Release 4.1 weekend testing (whole QA team).", "details": b["details"]})
    if res:
        for r in res["data"]["requests"]:
            name = c.name_of[int(r["employeeId"])]
            # The team's own were approved; Rabia's still waits on Haroon.
            c.walk(r, "overtime", "pending" if name == "Rabia Anwar" else "approved", requester="Shelley Kannes",
                   details={"approvedMinutes": 360})


# ---------------------------------------------------------------------- travel and claims

def _dt(d: date, hhmm: str) -> str:
    return datetime.combine(d, time.fromisoformat(hhmm)).isoformat()


def file_travel(c: Ctx) -> None:
    trips = [
        ("Asad Mirza", 9, 0, 3, "approved", "Client meetings and a partner event in Karachi.", "domestic",
         "Islamabad", "Karachi", "air", 60000, "Pearl Continental Karachi, Club Road", "Karachi"),
        ("Faisal Javed", 4, 1, 2, "approved", "Requirements workshop with the Islamabad client.", "domestic",
         "Lahore", "Islamabad", "own_car", None, "Hotel One, Blue Area", "Islamabad"),
        ("Taha Saleem", 3, 2, 2, "rejected", "Marketing conference in Lahore.", "domestic",
         "Islamabad", "Lahore", "bus", 15000, None, None),
        ("Omer Farooq", -4, 0, 5, "pending+1", "Design conference and partner meetings in Dubai.", "international",
         "Lahore", "Dubai", "air", 250000, "Rove Downtown, Sheikh Mohammed bin Rashid Blvd", "Dubai"),
        ("Komal Shah", -2, 0, 2, "pending", "Client presentations in Lahore.", "domestic",
         "Islamabad", "Lahore", "train", 20000, "Avari Express, Gulberg", "Lahore"),
    ]
    for who, wk, dow, days, outcome, purpose, kind, frm, to, mode, advance, hotel, city in trips:
        start = c.day(wk, dow)
        end = start + timedelta(days=days - 1)
        hours = {"air": 2, "own_car": 5, "bus": 5, "train": 5}[mode] if kind == "domestic" else 4
        legs = [{"travelType": kind, "fromPlace": frm, "toPlace": to, "travelMode": mode,
                 "departAt": _dt(start, "07:00"), "arriveAt": _dt(start, f"{7 + hours:02d}:00"),
                 "stayRequired": bool(hotel)},
                {"travelType": kind, "fromPlace": to, "toPlace": frm, "travelMode": mode,
                 "departAt": _dt(end, "16:00"), "arriveAt": _dt(end, f"{16 + hours:02d}:00"), "stayRequired": False}]
        details = {"purpose": purpose, "extensionNo": "214", "advanceRequired": bool(advance),
                   "advances": [{"amount": advance, "currency": "PKR"}] if advance else [], "legs": legs,
                   "stays": [{"stayType": "hotel", "address": hotel, "city": city, "fromDate": start.isoformat(),
                              "toDate": end.isoformat(), "nights": days - 1, "phone": "+92 51 111 505 505",
                              "email": "reservations@example.com"}] if hotel and days > 1 else []}
        if hotel and days == 1:
            legs[0]["stayRequired"] = False
        c.file(who, "travel", {"fromDate": start.isoformat(), "toDate": end.isoformat(), "reason": purpose,
                               "details": details}, outcome,
               reject_remarks="The conference budget for this quarter is used up.")


def file_expenses(c: Ctx) -> None:
    cat = c.ids["expense"]
    receipts = {"Client Entertainment", "Tech & Software", "Training & Certification"}

    def line(who, title, wk, dow, category, amount, text):
        d = c.day(wk, dow)
        out = {"title": title, "claimDate": d.isoformat(), "expenseCategoryId": cat[category], "amount": amount,
               "description": text}
        if category in receipts:
            out["fileId"] = c.upload_pdf(who, "receipt.pdf", ["Receipt", title, f"Date: {d:%d %b %Y}",
                                                             f"Amount: PKR {amount:,}", "Paid by card"])
        return out

    claims = [
        ("Asad Mirza", "approved", [("Client dinner, Karachi", 9, 1, "Client Entertainment", 18500,
                                     "Dinner with the client's IT director and team."),
                                    ("Airport and city taxis", 9, 2, "Travel Fee", 4200, "Taxis during the Karachi trip.")]),
        ("Faisal Javed", "approved", [("Fuel, Lahore-Islamabad", 4, 2, "Fuel & Mileage", 9800,
                                       "Fuel for the client workshop trip."),
                                      ("Motorway toll", 4, 2, "Travel Fee", 1900, "M-2 toll both ways.")]),
        ("Junaid Akhtar", "approved", [("Crimping tool and connectors", 2, 4, "Equipment & Supplies", 6400,
                                        "Tools for the weekend migration."),
                                       ("Mobile data top-up", 2, 4, "Internet & Mobile", 1500, "Hotspot during migration.")]),
        ("Omer Farooq", "approved", [("UX certification exam", 6, 3, "Training & Certification", 42000,
                                      "Exam fee approved in my development plan.")]),
        ("Hamza Riaz", "rejected", [("Taxi to campus drive", 1, 2, "Travel Fee", 2600, "Return taxi to the university.")]),
        ("Areeba Hameed", "pending+1", [("IDE licence renewal", 1, 1, "Tech & Software", 28000,
                                         "Yearly licence for the frontend IDE.")]),
        ("Komal Shah", "pending", [("Mobile data, October", 0, 0, "Internet & Mobile", 3000,
                                    "Mobile data used for client calls in October.")]),
    ]
    for who, outcome, lines in claims:
        ls = [line(who, *x) for x in lines]

        def lower(r, _who=who):  # Waqas pays the tool line at the shop's quoted price.
            if _who != "Junaid Akhtar":
                return None
            items = r["details"].get("lines") or []
            return {"lines": [{"id": int(x["id"]), "approvedAmount": 5800 if i == 0 else float(x["amount"])}
                              for i, x in enumerate(items)]} if items else None
        c.file(who, "expense", {"reason": lines[0][0], "details": {"lines": ls}}, outcome, details=lower,
               reject_remarks="Transport to the drive was arranged by the university.")


def file_air_tickets(c: Ctx) -> None:
    for who, wk, dow, frm, to, amount, outcome, title in (
            ("Asad Mirza", 9, 0, "Islamabad", "Karachi", 38500, "approved", "Return ticket, Karachi client visit"),
            ("Haroon Rashid", 6, 2, "Lahore", "Karachi", 32000, "approved", "Return ticket, data-centre audit"),
            ("Omer Farooq", -4, 0, "Lahore", "Dubai", 165000, "pending", "Return ticket, Dubai design conference")):
        travel = c.day(wk, dow)
        claim = min(travel, c.w.today)
        f = c.upload_pdf(who, "e-ticket.pdf", ["E-ticket", title, f"{frm} - {to}", f"Travel: {travel:%d %b %Y}",
                                               f"Fare: PKR {amount:,}"])
        c.file(who, "air_ticket", {"reason": title, "details": {
            "title": title, "claimDate": claim.isoformat(), "travelDate": travel.isoformat(), "fromPlace": frm,
            "toPlace": to, "amount": amount, "description": f"Economy return {frm}-{to}.", "fileId": f}},
            outcome, details={"approvedAmount": amount})


def file_requisitions(c: Ctx) -> None:
    for who, outcome, title, kind, wk, where, lines, rej in (
            ("Junaid Akhtar", "approved", "Replacement switches, 2nd floor", "it_equipment", -1, "Lahore Head Office",
             [("24-port gigabit switch", 2, "pcs", 45000), ("Cat6 patch cables", 40, "pcs", 450)], None),
            ("Bilal Ahmed", "approved", "Monthly stationery", "stationery", -1, "Lahore Head Office",
             [("A4 paper (ream)", 30, "ream", 1350), ("Whiteboard markers", 24, "pcs", 180),
              ("Spiral notebooks", 40, "pcs", 220)], None),
            ("Maham Zafar", "pending", "Drawing tablet", "it_equipment", -2, "Lahore Head Office",
             [("Pen tablet, medium", 1, "pcs", 42000)], None),
            ("Zain Abbas", "pending+1", "Second monitor", "asset", -2, "Lahore Head Office",
             [("27-inch IPS monitor", 1, "pcs", 38000)], None),
            ("Kashif Mehmood", "rejected", "Pantry supplies", "consumable", -1, "Lahore Head Office",
             [("Tea bags (box)", 10, "box", 650), ("Sugar (kg)", 10, "kg", 160)],
             "Already ordered with the monthly stationery.")):
        c.file(who, "requisition", {"reason": f"Needed: {title.lower()}.", "details": {
            "title": title, "requisitionType": kind, "neededByDate": c.day(wk, 4).isoformat(),
            "deliveryLocation": where,
            "lines": [{"itemName": n, "quantity": q, "unit": u, "estimatedUnitCost": p} for n, q, u, p in lines]}},
            outcome, reject_remarks=rej or "Not needed.")


def file_loans(c: Ctx) -> None:
    ty, cat = c.ids["loan_type"], c.ids["loan_category"]
    for who, loan_type, category, amount, wk, outcome, reason, guarantor, rej in (
            ("Junaid Akhtar", "Advance Salary", "Family Emergency", 40000, 12, "approved",
             "Hospital bills of my father.", None, None),
            ("Danish Iqbal", "Personal Loan", "Marriage", 150000, 8, "approved", "My wedding in November.", None, None),
            ("Kashif Mehmood", "Advance Salary", "Family Emergency", 30000, 3, "approved",
             "Roof repair after the monsoon rains.", None, None),
            ("Taha Saleem", "Advance Salary", "Family Emergency", 50000, 2, "rejected", "Bike repair.", None,
             "Advance salary covers emergencies; please apply for a personal loan after a year of service."),
            ("Zain Abbas", "Vehicle Loan", "Vehicle", 600000, 1, "pending+2", "Buying a used car for the commute.",
             ("Faisal Javed", "Colleague and team lead"), None),
            ("Farah Naz", "Personal Loan", "Education", 200000, 0, "pending+1", "Master's degree fees.", None, None),
            ("Areeba Hameed", "Personal Loan", "House Renovation", 250000, 1, "pending+2",
             "Kitchen renovation at home.", None, None)):
        needed = c.day(wk, 0)
        details = {"loanTypeId": ty[loan_type], "loanCategoryId": cat[category], "amountRequested": amount,
                   "requiredDate": needed.isoformat(), "extensionNo": "221", "guarantors": []}
        if guarantor:
            g = c.emp(guarantor[0])
            details["guarantors"] = [{"name": guarantor[0], "cnic": g.get("cnic") or "35202-4123456-7",
                                      "knownSince": "2022-07-18", "relationship": guarantor[1], "extensionNo": "205"}]
        repay = first_of_next_month(max(needed, c.w.today) if wk <= 0 else needed)
        c.file(who, "loan", {"reason": reason, "details": details}, outcome,
               details={"approvedAmount": amount, "paymentMethod": "bank", "repaymentDate": repay.isoformat(),
                        "currency": "PKR"},
               reject_remarks=rej or "Not approved.")


# ---------------------------------------------------------------------- HR: promotions, transfers, profile

def file_hr(c: Ctx) -> None:
    admin = c.w.admin
    grades = {x["name"]: int(x["id"]) for x in admin.all("/organisation/grades")}
    desig = {x["name"]: int(x["id"]) for x in admin.all("/organisation/designations")}
    titles = {x["name"]: int(x["id"]) for x in admin.all("/organisation/job-titles")}
    levels = {x["name"]: int(x["id"]) for x in admin.all("/organisation/job-levels")}
    this_month = c.w.today.replace(day=1)
    next_month = first_of_next_month(c.w.today)
    for who, grade, designation, title, salary, eff, outcome, reason, rej in (
            ("Zain Abbas", "G3", "Senior Software Engineer", "Backend Engineer", 240000, this_month, "approved",
             "Consistently strong delivery on the payments platform; mid-year review rating A.", None),
            ("Hira Shahid", "G3", "Senior Software Engineer", "Mobile App Engineer", 215000, next_month, "pending",
             "Led the mobile app rewrite; recommended by the team lead.", None),
            ("Danish Iqbal", "G3", "Senior Software Engineer", "SQA Engineer", 200000, next_month, "rejected",
             "Automation framework ownership.", "Due at the January appraisal cycle; we will review it then.")):
        c.file(who, "promotion", {"employeeId": c.eid(who), "fromDate": eff.isoformat(), "reason": reason, "details": {
            "gradeId": grades[grade], "jobLevelId": levels.get("Professional"), "designationId": desig[designation],
            "jobTitleId": titles[title], "newSalary": salary, "effectiveDate": eff.isoformat()}},
            outcome, by="Shelley Kannes", reject_remarks=rej or "Not approved.",
            remarks="Approved as proposed; effective date confirmed.")

    branches, locations, depts = c.w.branches, c.w.locations, c.w.departments
    isb = branches.get("Islamabad Office")
    for who, branch, dept, manager, outcome, reason in (
            ("Junaid Akhtar", isb, "IT & Network Support", "Waqas Butt", "approved",
             "IT support for the growing Islamabad office."),
            ("Maham Zafar", branches.get("Lahore Head Office"), "Software Development", "Faisal Javed", "pending",
             "Moving to the web team as a UI developer.")):
        if not branch:
            continue
        c.file(who, "transfer", {"employeeId": c.eid(who), "fromDate": this_month.isoformat(), "reason": reason,
                                 "details": {"locationId": int(branch["locationId"]), "branchId": int(branch["id"]),
                                             "departmentId": int(depts[dept]["id"]),
                                             "lineManagerId": c.eid(manager),
                                             "finalAuthorityId": c.eid("Imran Siddiqui"),
                                             "effectiveDate": (this_month if outcome == "approved" else next_month).isoformat()}},
               outcome, by="Shelley Kannes", remarks="Approved; IT and Admin informed.")


def file_update_requests(c: Ctx) -> None:
    admin = c.w.admin
    for who, changes, remarks, decision, note in (
            ("Hira Shahid", {"phone1": "+92 321 4455667"}, "Changed my mobile number.", "approve", "Updated."),
            ("Danish Iqbal", {"dateOfBirth": "1996-11-07"}, "Date of birth is wrong on my profile.", "reject",
             "Please attach your CNIC copy; the date of birth must match the CNIC."),
            ("Zain Abbas", {"homeAddress": "Flat 12, Block C, Askari 11, Lahore"}, "Moved to a new flat.", None, None),
            ("Taha Saleem", {"maritalStatus": "married"}, "Got married last month.", None, None)):
        api = c.w.as_(who)
        res = c.call(api, "POST", f"/employees/{c.eid(who)}/update-requests", {"changes": changes, "remarks": remarks})
        if not res:
            continue
        r = res["data"]
        if decision:
            out = c.call(admin, "PATCH", f"/employees/update-requests/{r['id']}/{decision}",
                         {"remarks": note, "rowVersion": r["rowVersion"]})
            r = out["data"] if out else r
        c.stats[("update_information", r["status"])] += 1


# ---------------------------------------------------------------------- requests that need planned shifts

def _shift(c: Ctx, who: str, d: date) -> dict | None:
    return c.shifts.get(c.eid(who), {}).get(d)


def _first_shift_day(c: Ctx, who: str, wk: int, dows: list[int], not_after: date | None = None) -> date | None:
    for dow in dows + [x for x in range(5) if x not in dows]:
        d = c.day(wk, dow)
        if (not_after is None or d <= not_after) and _shift(c, who, d):
            return d
    return None


def file_scheduled(c: Ctx) -> None:
    if not any(c.shifts.values()):
        c.skipped.append("work from home, punch, relaxation, rest day and shift requests: no shifts are planned "
                         "(they need the time part's schedules)")
        return
    today = c.w.today

    # Work from home: the ticked shift days of a week.
    for who, wk, dows, outcome, reason in (
            ("Areeba Hameed", 12, [1, 2], "approved", "Plumbing work at home; available on Slack all day."),
            ("Zain Abbas", 9, [4], "approved", "Waiting for the internet technician."),
            ("Maham Zafar", 7, [0, 1], "approved", "Recovering from a sprained ankle."),
            ("Hira Shahid", 5, [2], "rejected", "Child unwell."),
            ("Taha Saleem", 3, [3, 4], "approved", "Campaign reporting; fewer interruptions at home."),
            ("Danish Iqbal", 1, [1], "approved", "Car in the workshop."),
            ("Areeba Hameed", 0, [4], "pending", "Home renovation."),
            ("Komal Shah", -1, [0, 1], "pending", "Preparing proposals for two clients."),
            ("Junaid Akhtar", -2, [2], "pending+1", "Remote monitoring of the backup migration.")):
        days = [c.day(wk, d) for d in dows if _shift(c, who, c.day(wk, d))]
        if not days:
            c.skipped.append(f"work from home of {who} (week {wk}): no shift those days")
            continue
        c.file(who, "work_from_home", {"fromDate": days[0].isoformat(), "toDate": days[-1].isoformat(),
                                       "reason": reason, "details": {"dates": [d.isoformat() for d in days]}},
               outcome, reject_remarks="Sprint planning is in the office that day.")

    # Missing punches: inside the shift, on or before today.
    for who, wk, dow, kind, outcome, reason in (
            ("Zain Abbas", 8, 1, "check_out", "approved", "Forgot to punch out; left at the end of the shift."),
            ("Hira Shahid", 6, 0, "check_in", "approved", "The biometric device did not read my thumb."),
            ("Kashif Mehmood", 4, 3, "check_in", "approved", "Device was down in the morning."),
            ("Danish Iqbal", 3, 2, "check_out", "approved", "Left from the client site; no device there."),
            ("Taha Saleem", 2, 4, "check_in", "rejected", "Forgot to punch in."),
            ("Junaid Akhtar", 1, 0, "check_out", "approved", "Stayed for the switch replacement, forgot to punch out."),
            ("Saad Qureshi", 0, 1, "check_in", "pending", "My fingerprint is not enrolled correctly yet."),
            ("Usman Ghani", 0, 0, "check_out", "pending", "Forgot to punch out."),
            ("Areeba Hameed", 0, 2, "check_out", "pending+1", "Forgot to punch out after the release call.")):
        d = _first_shift_day(c, who, wk, [dow], not_after=today)
        s = _shift(c, who, d) if d else None
        if not s:
            c.skipped.append(f"punch of {who} (week {wk}): no shift that week")
            continue
        start, end = datetime.fromisoformat(s["startAt"]), datetime.fromisoformat(s["endAt"])
        at = start + timedelta(minutes=7) if kind == "check_in" else end - timedelta(minutes=4)
        if d == today and at.time() > datetime.now().time():
            at = start + timedelta(minutes=7)
            kind = "check_in"
        c.file(who, "punch", {"fromDate": d.isoformat(), "toDate": d.isoformat(), "reason": reason,
                              "details": {"punchDate": d.isoformat(), "punchType": kind,
                                          "punchTime": at.time().strftime("%H:%M:%S")}},
               outcome, reject_remarks="The CCTV log shows arrival at 10:40.")

    # Relaxation of a late arrival.
    for who, wk, dow, minutes, outcome, reason in (
            ("Komal Shah", 9, 2, 60, "approved", "Car broke down on the Srinagar Highway."),
            ("Hamza Riaz", 6, 1, 45, "approved", "Took my father to the hospital in the morning."),
            ("Zain Abbas", 3, 0, 30, "rejected", "Traffic jam on the canal road."),
            ("Mehwish Akram", 1, 3, 40, "approved", "Metro bus service suspended."),
            ("Hira Shahid", 0, 0, 30, "pending", "Rain and traffic.")):
        d = _first_shift_day(c, who, wk, [dow], not_after=today)
        s = _shift(c, who, d) if d else None
        if not s:
            c.skipped.append(f"relaxation of {who} (week {wk}): no shift that week")
            continue
        start = datetime.fromisoformat(s["startAt"])
        c.file(who, "relaxation", {"fromDate": d.isoformat(), "toDate": d.isoformat(), "reason": reason,
                                   "details": {"windowDate": d.isoformat(), "startTime": start.time().isoformat(),
                                               "endTime": (start + timedelta(minutes=minutes)).time().isoformat()}},
               outcome, reject_remarks="Third late arrival this month; it stays as late.",
               remarks="Approved; genuine reason.")

    # Rest days (a roster group is needed) and shift requests.
    groups = (c.call(c.w.admin, "GET", "/scheduling/options/roster-groups", quiet=True) or {}).get("data") or []
    if not groups:
        c.skipped.append("rest day requests: no roster groups")
    else:
        for who, wk, dow, outcome, reason in (
                ("Danish Iqbal", 3, 0, "approved", "Worked the release weekend."),
                ("Junaid Akhtar", -1, 4, "pending", "Compensatory rest after the weekend migration.")):
            d = c.day(wk, dow)
            c.file(who, "rest_day", {"fromDate": d.isoformat(), "toDate": d.isoformat(), "reason": reason,
                                     "details": {"departmentId": int(c.emp(who)["departmentId"]),
                                                 "rosterGroupId": int(groups[0]["id"]), "isPayable": False}},
                   outcome)

    slots = (c.call(c.w.admin, "GET", "/scheduling/options/time-slots", quiet=True) or {}).get("data") or []
    for who, wk, outcome, reason in (("Hira Shahid", -1, "pending", "Evening class that day; need the later shift."),
                                     ("Zain Abbas", -1, "approved", "Doctor's appointment in the morning.")):
        done = False
        for dow in range(5):
            d = c.day(wk, dow)
            mine = _shift(c, who, d)
            if not mine or d < today:
                continue
            mates = [n for n in c.w.in_department(c.emp(who).get("departmentName")) if n != who] + \
                [n for n in c.w.employees if n != who]
            other = next((n for n in mates if _shift(c, n, d) and (
                _shift(c, n, d)["timeSlotId"] != mine["timeSlotId"])), None)
            details = {"shiftDate": d.isoformat()}
            if other:
                details["withEmployeeId"] = c.eid(other)
            else:
                alt = next((s for s in slots if s["id"] != mine["timeSlotId"] and
                            (s.get("startTime"), s.get("endTime")) != (mine["startAt"][11:19], mine["endAt"][11:19])),
                           None)
                if not alt:
                    continue
                details["timeSlotId"] = int(alt["id"])
            c.file(who, "shift_swap", {"fromDate": d.isoformat(), "toDate": d.isoformat(), "reason": reason,
                                       "details": details}, outcome)
            done = True
            break
        if not done:
            c.skipped.append(f"shift request of {who}: no other shift to change to or swap with")
