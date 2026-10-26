"""Recruitment: openings from Manpower open positions, applicants with CV files, the pipeline with its stage
history, interviews with a panel and evaluations, offers, hiring into an employee, permissions, scope, row
versions, the dashboard, and the events written to core.outbox_event."""
from tests import factories
from tests import factories_recruitment as rf

API = "/api/recruitment"


def _events(db, event_type: str, entity_type: str, entity_id) -> int:
    return rf.scalar(db, "SELECT COUNT(*) FROM core.outbox_event WHERE event_type = ? AND entity_type = ? AND entity_id = ?",
                     event_type, entity_type, int(entity_id))


def _notifications(db, user_id: int, entity_type: str, entity_id) -> int:
    return rf.scalar(db, "SELECT COUNT(*) FROM core.notification WHERE user_account_id = ? AND entity_type = ? "
                         "AND entity_id = ?", user_id, entity_type, int(entity_id))


def test_opening_from_open_position(client, db, company, admin):
    h = admin["headers"]
    jt = rf.job_title(db, company)
    dept = factories.department(db, company)
    branch = factories.branch(db, company)
    op = rf.open_position(db, company, 3, job_title_id=jt, department_id=dept, branch_id=branch)

    r = client.post(f"{API}/openings", json={"openPositionId": op, "salaryFrom": 80000, "salaryTo": 120000,
                                            "workMode": "hybrid", "description": "<p>Build things.</p>"}, headers=h)
    assert r.status_code == 201, r.text
    first = r.json()["data"]
    assert first["code"].startswith("JOB-") and first["status"] == "draft"
    assert (first["jobTitleId"], first["departmentId"], first["branchId"]) == (str(jt), str(dept), str(branch))
    assert first["vacancies"] == 3 and first["openPositionSeats"] == 3 and first["title"]

    # The position has no seats left for a second opening until the first asks for fewer.
    full = client.post(f"{API}/openings", json={"openPositionId": op, "vacancies": 1}, headers=h)
    assert full.status_code == 409 and full.json()["code"] == "OPEN_POSITION_SEATS"
    edited = client.put(f"{API}/openings/{first['id']}",
                        json={"openPositionId": op, "title": first["title"], "vacancies": 2,
                              "rowVersion": first["rowVersion"]}, headers=h)
    assert edited.status_code == 200 and edited.json()["data"]["vacancies"] == 2
    second = client.post(f"{API}/openings", json={"openPositionId": op, "vacancies": 1}, headers=h)
    assert second.status_code == 201
    stale = client.put(f"{API}/openings/{first['id']}", json={"title": "x", "vacancies": 1,
                                                              "rowVersion": first["rowVersion"]}, headers=h)
    assert stale.status_code == 409

    bad = client.post(f"{API}/openings", json={"title": "x", "vacancies": 1, "salaryFrom": 9, "salaryTo": 1}, headers=h)
    assert bad.status_code == 422 and "salaryTo" in bad.json()["fieldErrors"]
    dup = client.post(f"{API}/openings", json={"title": "x", "vacancies": 1, "code": first["code"]}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "OPENING_CODE_DUPLICATE"

    # A draft takes no applications; publishing opens it and publishes the event.
    draft = edited.json()["data"]
    refused = client.post(f"{API}/applications", json={"jobOpeningId": draft["id"], "applicant": rf.applicant_body()},
                          headers=h)
    assert refused.status_code == 409 and refused.json()["code"] == "OPENING_NOT_OPEN"
    published = client.post(f"{API}/openings/{draft['id']}/publish", json={"rowVersion": draft["rowVersion"]}, headers=h)
    assert published.status_code == 200
    pub = published.json()["data"]
    assert pub["status"] == "open" and pub["postedOn"] and pub["publishedAt"]
    assert _events(db, "recruitment.opening_published", "rec.job_opening", pub["id"]) == 1
    again = client.post(f"{API}/openings/{pub['id']}/publish", json={"rowVersion": pub["rowVersion"]}, headers=h)
    assert again.status_code == 409 and again.json()["code"] == "OPENING_STATUS"

    listed = client.get(f"{API}/openings", params={"openPositionId": op}, headers=h).json()
    assert listed["meta"]["total"] == 2 and listed["data"][0]["id"] == pub["id"]  # open first

    rf.apply(client, h, pub["id"])
    in_use = client.delete(f"{API}/openings/{pub['id']}", params={"rowVersion": pub["rowVersion"]}, headers=h)
    assert in_use.status_code == 409
    held = client.post(f"{API}/openings/{pub['id']}/hold", json={"rowVersion": pub["rowVersion"]}, headers=h).json()["data"]
    closed = client.post(f"{API}/openings/{pub['id']}/close", json={"rowVersion": held["rowVersion"]}, headers=h)
    assert closed.json()["data"]["status"] == "closed"
    assert _events(db, "recruitment.opening_closed", "rec.job_opening", pub["id"]) == 1
    reopened = client.post(f"{API}/openings/{pub['id']}/reopen", json={"rowVersion": closed.json()["data"]["rowVersion"]},
                           headers=h)
    assert reopened.json()["data"]["status"] == "open" and reopened.json()["data"]["closedAt"] is None

    other = second.json()["data"]
    assert client.delete(f"{API}/openings/{other['id']}", params={"rowVersion": other["rowVersion"]},
                         headers=h).status_code == 204


def test_application_with_cv_and_stage_history(client, db, company, admin):
    h = admin["headers"]
    opening = rf.opening(client, h)
    cv = rf.upload_cv(client, h, "Ayesha Khan CV.pdf")
    body = rf.applicant_body(cvFileId=cv["id"], cityId=rf.city(db), expectedSalary=150000, experienceYears=4.5)
    r = client.post(f"{API}/applications", json={"jobOpeningId": opening["id"], "applicant": body,
                                                "coverLetter": "I would like to join."}, headers=h)
    assert r.status_code == 201, r.text
    app = r.json()["data"]
    assert app["stage"] == "applied" and app["source"] == "job_board"
    assert app["cv"]["id"] == cv["id"] and app["cv"]["name"] == "Ayesha Khan CV.pdf"
    assert app["cv"]["url"].startswith(f"/api/files/{cv['id']}/download?token=")
    assert client.get(app["cv"]["url"]).status_code == 200
    assert [x["toStage"] for x in app["history"]] == ["applied"]
    assert _events(db, "recruitment.application_received", "rec.application", app["id"]) == 1

    applicant = client.get(f"{API}/applicants/{app['applicantId']}", headers=h).json()["data"]
    assert applicant["cv"]["url"] and applicant["experienceYears"] == 4.5 and applicant["cityName"]
    assert [a["id"] for a in applicant["applications"]] == [app["id"]]

    dup_email = client.post(f"{API}/applicants", json=rf.applicant_body(email=body["email"].upper()), headers=h)
    assert dup_email.status_code == 409 and dup_email.json()["code"] == "APPLICANT_DUPLICATE"
    dup_app = client.post(f"{API}/applications", json={"jobOpeningId": opening["id"], "applicantId": app["applicantId"]},
                          headers=h)
    assert dup_app.status_code == 409 and dup_app.json()["code"] == "APPLICATION_DUPLICATE"
    neither = client.post(f"{API}/applications", json={"jobOpeningId": opening["id"]}, headers=h)
    assert neither.status_code == 422

    # A file uploaded in another company is not usable here.
    other = factories.company(db)
    other_admin = factories.login_as(db, client, other, role_codes="company_admin")
    foreign = rf.upload_cv(client, other_admin["headers"])
    refused = client.post(f"{API}/applicants", json=rf.applicant_body(cvFileId=foreign["id"]), headers=h)
    assert refused.status_code == 422 and "cvFileId" in refused.json()["fieldErrors"]
    assert client.get(f"{API}/applications/{app['id']}", headers=other_admin["headers"]).status_code == 404

    # Stage moves keep a history; a stale row version or the same stage is refused.
    moved = client.patch(f"{API}/applications/{app['id']}/stage",
                         json={"stage": "screening", "rowVersion": app["rowVersion"]}, headers=h)
    assert moved.status_code == 200, moved.text
    stale = client.patch(f"{API}/applications/{app['id']}/stage",
                         json={"stage": "shortlisted", "rowVersion": app["rowVersion"]}, headers=h)
    assert stale.status_code == 409
    same = client.patch(f"{API}/applications/{app['id']}/stage",
                        json={"stage": "screening", "rowVersion": moved.json()["data"]["rowVersion"]}, headers=h)
    assert same.status_code == 409 and same.json()["code"] == "STAGE_UNCHANGED"
    short = client.patch(f"{API}/applications/{app['id']}/stage",
                         json={"stage": "shortlisted", "remarks": "Strong CV",
                               "rowVersion": moved.json()["data"]["rowVersion"]}, headers=h).json()["data"]
    assert [(x["fromStage"], x["toStage"]) for x in short["history"]] == \
        [(None, "applied"), ("applied", "screening"), ("screening", "shortlisted")]
    assert short["history"][-1]["remarks"] == "Strong CV" and short["history"][-1]["changedByName"]

    reason = client.post(f"{API}/settings/rejection-reasons", json={"name": f"Not qualified {factories.tag()}"},
                         headers=h).json()["data"]
    rejected = client.post(f"{API}/applications/{app['id']}/reject",
                           json={"rejectionReasonId": reason["id"], "rowVersion": short["rowVersion"]}, headers=h)
    assert rejected.status_code == 200
    rej = rejected.json()["data"]
    assert (rej["stage"], rej["rejectedStage"], rej["rejectionReasonName"]) == ("rejected", "shortlisted", reason["name"])
    twice = client.post(f"{API}/applications/{app['id']}/reject", json={"rowVersion": rej["rowVersion"]}, headers=h)
    assert twice.status_code == 409 and twice.json()["code"] == "APPLICATION_CLOSED"
    # Brought back into the pipeline.
    back = client.patch(f"{API}/applications/{app['id']}/stage",
                        json={"stage": "screening", "rowVersion": rej["rowVersion"]}, headers=h).json()["data"]
    assert back["stage"] == "screening" and back["rejectionReasonId"] is None
    assert _events(db, "recruitment.stage_changed", "rec.application", app["id"]) == 4

    in_use = client.get(f"{API}/settings/rejection-reasons", headers=h).json()["data"]
    assert next(x for x in in_use if x["id"] == reason["id"])["usageCount"] == 0
    listed = client.get(f"{API}/applications", params={"jobOpeningId": opening["id"], "stage": "screening"},
                        headers=h).json()
    assert listed["meta"]["total"] == 1 and listed["data"][0]["cv"]["id"] == cv["id"]


def test_interview_panel_and_evaluations(client, db, company, admin):
    h = admin["headers"]
    opening = rf.opening(client, h)
    app = rf.apply(client, h, opening["id"])
    first = factories.employee(db, company, first_name="Bilal")
    second = factories.employee(db, company, first_name="Sana")
    outsider = factories.employee(db, company)
    first_login = factories.login_as(db, client, company, role_codes="employee", employee_id=first)
    second_user, _ = factories.user(db, company, employee_id=second, role_codes="employee")
    for code in ("recruitment.interviews.view", "recruitment.interviews.evaluate"):
        rf.grant(db, company, first_login["user_id"], code, "own")

    body = {"applicationId": app["id"], "title": "Technical", "mode": "video", "scheduledAt": "2031-03-10T10:30:00",
            "durationMinutes": 45, "venue": "https://meet.example/abc", "interviewerIds": [first, second]}
    r = client.post(f"{API}/interviews", json=body, headers=h)
    assert r.status_code == 201, r.text
    iv = r.json()["data"]
    assert iv["roundNo"] == 1 and iv["status"] == "scheduled" and iv["interviewerCount"] == 2
    assert {p["employeeId"] for p in iv["interviewers"]} == {str(first), str(second)}
    assert iv["applicationStage"] == "interview"  # scheduling moved the application on
    assert _events(db, "recruitment.interview_scheduled", "rec.interview", iv["id"]) == 1
    assert _notifications(db, first_login["user_id"], "rec.interview", iv["id"]) == 1
    assert _notifications(db, second_user, "rec.interview", iv["id"]) == 1

    busy = client.post(f"{API}/interviews", json={**body, "scheduledAt": "2031-03-10T11:00:00"}, headers=h)
    assert busy.status_code == 409 and busy.json()["code"] == "INTERVIEWER_BUSY"
    empty = client.post(f"{API}/interviews", json={**body, "interviewerIds": []}, headers=h)
    assert empty.status_code == 422

    # The interviewer sees and evaluates their own interview, but not on behalf of a colleague.
    fh = first_login["headers"]
    mine = client.get(f"{API}/interviews", params={"mine": "true"}, headers=fh).json()
    assert [x["id"] for x in mine["data"]] == [iv["id"]]
    own = client.post(f"{API}/interviews/{iv['id']}/evaluations",
                      json={"rating": 4, "recommendation": "hire", "strengths": "Clear thinker"}, headers=fh)
    assert own.status_code == 200, own.text
    for_other = client.post(f"{API}/interviews/{iv['id']}/evaluations",
                            json={"employeeId": second, "rating": 5, "recommendation": "hire"}, headers=fh)
    assert for_other.status_code == 403
    assert client.get(f"{API}/applications/{app['id']}", headers=fh).status_code == 403
    not_panel = client.post(f"{API}/interviews/{iv['id']}/evaluations",
                            json={"employeeId": outsider, "rating": 3, "recommendation": "hire"}, headers=h)
    assert not_panel.status_code == 422 and not_panel.json()["code"] == "NOT_ON_PANEL"
    bad = client.post(f"{API}/interviews/{iv['id']}/evaluations",
                      json={"employeeId": second, "rating": 6, "recommendation": "hire"}, headers=h)
    assert bad.status_code == 422
    # HR records the second interviewer's feedback; saving again replaces the first one's.
    hr = client.post(f"{API}/interviews/{iv['id']}/evaluations",
                     json={"employeeId": second, "rating": 3, "recommendation": "no_hire", "concerns": "Thin on SQL"},
                     headers=h)
    assert hr.status_code == 200
    redo = client.post(f"{API}/interviews/{iv['id']}/evaluations",
                       json={"rating": 5, "recommendation": "strong_hire"}, headers=fh).json()["data"]
    assert redo["evaluationCount"] == 2 and redo["averageRating"] == 4.0
    assert all(p["hasEvaluated"] for p in redo["interviewers"])
    assert {e["recommendation"] for e in redo["evaluations"]} == {"strong_hire", "no_hire"}
    assert _events(db, "recruitment.interview_evaluated", "rec.interview", iv["id"]) == 3

    # An interviewer who has evaluated stays on the panel; rescheduling tells the panel again.
    off = client.put(f"{API}/interviews/{iv['id']}", json={**body, "interviewerIds": [first],
                                                         "rowVersion": redo["rowVersion"]}, headers=h)
    assert off.status_code == 409 and off.json()["code"] == "INTERVIEWER_EVALUATED"
    moved = client.put(f"{API}/interviews/{iv['id']}", json={**body, "scheduledAt": "2031-03-11T15:00:00",
                                                           "rowVersion": redo["rowVersion"]}, headers=h)
    assert moved.status_code == 200 and moved.json()["data"]["scheduledAt"].startswith("2031-03-11T15:00")
    stale = client.put(f"{API}/interviews/{iv['id']}", json={**body, "rowVersion": redo["rowVersion"]}, headers=h)
    assert stale.status_code == 409
    assert _events(db, "recruitment.interview_rescheduled", "rec.interview", iv["id"]) == 1
    assert _notifications(db, first_login["user_id"], "rec.interview", iv["id"]) == 2

    done = client.post(f"{API}/interviews/{iv['id']}/complete",
                       json={"result": "passed", "rowVersion": moved.json()["data"]["rowVersion"]}, headers=h)
    assert done.status_code == 200 and (done.json()["data"]["status"], done.json()["data"]["result"]) == ("completed", "passed")
    cancel = client.post(f"{API}/interviews/{iv['id']}/cancel", json={"rowVersion": done.json()["data"]["rowVersion"]},
                         headers=h)
    assert cancel.status_code == 409 and cancel.json()["code"] == "INTERVIEW_CLOSED"

    # A second round, then cancelled: the panel is told.
    second_round = client.post(f"{API}/interviews", json={**body, "title": None, "scheduledAt": "2031-03-20T09:00:00",
                                                        "interviewerIds": [second]}, headers=h).json()["data"]
    assert second_round["roundNo"] == 2 and second_round["title"] == "Interview round 2"
    cancelled = client.post(f"{API}/interviews/{second_round['id']}/cancel",
                            json={"remarks": "Candidate asked to move", "rowVersion": second_round["rowVersion"]},
                            headers=h)
    assert cancelled.json()["data"]["status"] == "cancelled"
    assert _events(db, "recruitment.interview_cancelled", "rec.interview", second_round["id"]) == 1
    assert _notifications(db, second_user, "rec.interview", second_round["id"]) == 2

    listed = client.get(f"{API}/interviews", params={"applicationId": app["id"]}, headers=h).json()
    assert listed["meta"]["total"] == 2


def test_offer_and_hire_creates_the_employee(client, db, company, admin):
    h = admin["headers"]
    jt = rf.job_title(db, company)
    desig = rf.designation(db, company)
    etype = rf.employment_type(db, company)
    dept = factories.department(db, company)
    branch = factories.branch(db, company)
    manager = factories.employee(db, company, branch_id=branch, department_id=dept, first_name="Hiring")
    manager_user, _ = factories.user(db, company, employee_id=manager, role_codes="employee")
    op = rf.open_position(db, company, 1, job_title_id=jt, department_id=dept, branch_id=branch)
    opening = rf.opening(client, h, title=None, openPositionId=op, designationId=desig, employmentTypeId=etype,
                         hiringManagerId=manager, vacancies=None)
    assert opening["vacancies"] == 1 and opening["hiringManagerName"].startswith("Hiring")
    cv = rf.upload_cv(client, h)
    app = rf.apply(client, h, opening["id"], cvFileId=cv["id"], firstName="Hamza", gender="male")

    early = client.post(f"{API}/applications/{app['id']}/hire", json={"rowVersion": app["rowVersion"]}, headers=h)
    assert early.status_code == 409 and early.json()["code"] == "OFFER_NOT_ACCEPTED"

    letter = factories.upload(client, h, name="Offer letter.pdf", module="recruitment")
    r = client.post(f"{API}/offers", json={"applicationId": app["id"], "offeredSalary": 175000, "joiningDate": "2031-02-01",
                                          "probationMonths": 3, "expiresOn": "2031-01-15",
                                          "offerLetterFileId": letter["id"]}, headers=h)
    assert r.status_code == 201, r.text
    offer = r.json()["data"]
    assert offer["status"] == "draft" and offer["jobTitleId"] == str(jt) and offer["branchId"] == str(branch)
    assert offer["offerLetter"]["url"].startswith(f"/api/files/{letter['id']}/download")
    second = client.post(f"{API}/offers", json={"applicationId": app["id"], "offeredSalary": 1, "joiningDate": "2031-02-01"},
                         headers=h)
    assert second.status_code == 409 and second.json()["code"] == "OFFER_EXISTS"
    edited = client.put(f"{API}/offers/{offer['id']}", json={"offeredSalary": 180000, "joiningDate": "2031-02-01",
                                                            "probationMonths": 3, "offerLetterFileId": letter["id"],
                                                            "rowVersion": offer["rowVersion"]}, headers=h)
    assert edited.status_code == 200 and edited.json()["data"]["offeredSalary"] == 180000
    stale = client.put(f"{API}/offers/{offer['id']}", json={"offeredSalary": 1, "joiningDate": "2031-02-01",
                                                           "rowVersion": offer["rowVersion"]}, headers=h)
    assert stale.status_code == 409
    offer = edited.json()["data"]

    early_answer = client.post(f"{API}/offers/{offer['id']}/respond",
                               json={"decision": "accepted", "rowVersion": offer["rowVersion"]}, headers=h)
    assert early_answer.status_code == 409 and early_answer.json()["code"] == "OFFER_STATUS"
    sent = client.post(f"{API}/offers/{offer['id']}/send", json={"rowVersion": offer["rowVersion"]}, headers=h).json()["data"]
    assert sent["status"] == "sent" and sent["sentAt"] and sent["applicationStage"] == "offer"
    assert _events(db, "recruitment.offer_made", "rec.offer", offer["id"]) == 1
    accepted = client.post(f"{API}/offers/{offer['id']}/respond",
                           json={"decision": "accepted", "remarks": "Happy to join", "rowVersion": sent["rowVersion"]},
                           headers=h)
    assert accepted.status_code == 200 and accepted.json()["data"]["status"] == "accepted"
    assert _events(db, "recruitment.offer_accepted", "rec.offer", offer["id"]) == 1
    assert _notifications(db, manager_user, "rec.offer", offer["id"]) == 1

    app = client.get(f"{API}/applications/{app['id']}", headers=h).json()["data"]
    hired = client.post(f"{API}/applications/{app['id']}/hire", json={"rowVersion": app["rowVersion"]}, headers=h)
    assert hired.status_code == 200, hired.text
    done = hired.json()["data"]
    assert done["stage"] == "hired" and done["employeeId"] and done["employeeCode"].startswith("TST-")
    assert done["history"][-1]["toStage"] == "hired"

    emp = int(done["employeeId"])
    cur = db.conn.cursor()
    row = cur.execute("SELECT first_name, branch_id, department_id, job_title_id, designation_id, employment_type_id, "
                      "line_manager_id, status, email FROM hr.employee WHERE id = ?", emp).fetchone()
    assert (row.first_name, row.branch_id, row.department_id, row.job_title_id, row.designation_id,
            row.employment_type_id, row.line_manager_id, row.status) == \
        ("Hamza", branch, dept, jt, desig, etype, manager, "probation")
    period = cur.execute("SELECT joining_date, probation_end_date FROM hr.employment_period WHERE employee_id = ?",
                         emp).fetchall()
    assert [(str(p.joining_date), str(p.probation_end_date)) for p in period] == [("2031-02-01", "2031-04-30")]
    salary = cur.execute("SELECT amount, source FROM hr.employee_salary WHERE employee_id = ?", emp).fetchall()
    assert [(float(s.amount), s.source) for s in salary] == [(180000.0, "joining")]
    docs = cur.execute("SELECT document_type FROM hr.employee_document WHERE employee_id = ? ORDER BY document_type",
                       emp).fetchall()
    assert [d.document_type for d in docs] == ["cv", "offer_letter"]
    seat = cur.execute("SELECT total_positions, status FROM mp.open_position WHERE id = ?", op).fetchone()
    assert (seat.total_positions, seat.status) == (0, "closed")
    cur.close()

    filled = client.get(f"{API}/openings/{opening['id']}", headers=h).json()["data"]
    assert (filled["status"], filled["hiredCount"], filled["remainingVacancies"]) == ("closed", 1, 0)
    assert _events(db, "recruitment.candidate_hired", "rec.application", app["id"]) == 1
    assert _events(db, "recruitment.opening_closed", "rec.job_opening", opening["id"]) == 1
    assert _notifications(db, manager_user, "rec.application", app["id"]) == 1
    payload = rf.scalar(db, "SELECT payload FROM core.outbox_event WHERE event_type = N'recruitment.candidate_hired' "
                            "AND entity_id = ?", int(app["id"]))
    assert f'"employeeId":"{emp}"' in payload

    again = client.post(f"{API}/applications/{app['id']}/hire", json={"rowVersion": done["rowVersion"]}, headers=h)
    assert again.status_code == 409 and again.json()["code"] == "APPLICATION_HIRED"
    withdraw = client.post(f"{API}/offers/{offer['id']}/withdraw",
                           json={"rowVersion": accepted.json()["data"]["rowVersion"]}, headers=h)
    assert withdraw.status_code == 409


def test_hire_is_undone_when_the_employee_is_refused(client, db, company, admin):
    """The employee save is part of the hire's transaction: a refusal there leaves nothing behind."""
    h = admin["headers"]
    opening = rf.opening(client, h)  # no station on the opening or the offer
    app = rf.apply(client, h, opening["id"])
    offer = client.post(f"{API}/offers", json={"applicationId": app["id"], "offeredSalary": 90000,
                                              "joiningDate": "2031-05-01"}, headers=h).json()["data"]
    sent = client.post(f"{API}/offers/{offer['id']}/send", json={"rowVersion": offer["rowVersion"]}, headers=h).json()["data"]
    client.post(f"{API}/offers/{offer['id']}/respond", json={"decision": "accepted", "rowVersion": sent["rowVersion"]},
                headers=h)
    app = client.get(f"{API}/applications/{app['id']}", headers=h).json()["data"]
    no_branch = client.post(f"{API}/applications/{app['id']}/hire", json={"rowVersion": app["rowVersion"]}, headers=h)
    assert no_branch.status_code == 422 and "branchId" in no_branch.json()["fieldErrors"]

    lm = factories.employee(db, company)
    taken = client.post(f"{API}/applications/{app['id']}/hire",
                        json={"rowVersion": app["rowVersion"], "branchId": factories.branch(db, company),
                              "code": rf.scalar(db, "SELECT code FROM hr.employee WHERE id = ?", lm)}, headers=h)
    assert taken.status_code == 409 and taken.json()["code"] == "EMPLOYEE_CODE_DUPLICATE"
    after = client.get(f"{API}/applications/{app['id']}", headers=h).json()["data"]
    assert after["stage"] == "offer" and after["employeeId"] is None and after["rowVersion"] == app["rowVersion"]
    ok = client.post(f"{API}/applications/{app['id']}/hire",
                     json={"rowVersion": app["rowVersion"], "branchId": factories.branch(db, company),
                           "status": "active", "salary": 95000}, headers=h)
    assert ok.status_code == 200, ok.text
    emp = int(ok.json()["data"]["employeeId"])
    assert rf.scalar(db, "SELECT status FROM hr.employee WHERE id = ?", emp) == "active"
    assert float(rf.scalar(db, "SELECT amount FROM hr.employee_salary WHERE employee_id = ?", emp)) == 95000.0


def test_withdraw_cancels_interviews_and_offers(client, db, company, admin):
    h = admin["headers"]
    opening = rf.opening(client, h)
    app = rf.apply(client, h, opening["id"])
    person = factories.employee(db, company)
    iv = client.post(f"{API}/interviews", json={"applicationId": app["id"], "scheduledAt": "2032-01-05T10:00:00",
                                               "interviewerIds": [person]}, headers=h).json()["data"]
    offer = client.post(f"{API}/offers", json={"applicationId": app["id"], "offeredSalary": 50000,
                                              "joiningDate": "2032-02-01"}, headers=h).json()["data"]
    app = client.get(f"{API}/applications/{app['id']}", headers=h).json()["data"]
    out = client.post(f"{API}/applications/{app['id']}/withdraw",
                      json={"remarks": "Took another job", "rowVersion": app["rowVersion"]}, headers=h).json()["data"]
    assert (out["stage"], out["rejectedStage"]) == ("withdrawn", "interview")
    assert client.get(f"{API}/interviews/{iv['id']}", headers=h).json()["data"]["status"] == "cancelled"
    assert client.get(f"{API}/offers/{offer['id']}", headers=h).json()["data"]["status"] == "withdrawn"
    closed = client.post(f"{API}/interviews", json={"applicationId": app["id"], "scheduledAt": "2032-01-06T10:00:00",
                                                   "interviewerIds": [person]}, headers=h)
    assert closed.status_code == 409 and closed.json()["code"] == "APPLICATION_CLOSED"
    in_use = client.delete(f"{API}/applications/{app['id']}", params={"rowVersion": out["rowVersion"]}, headers=h)
    assert in_use.status_code == 409

    fresh = rf.apply(client, h, opening["id"])
    assert client.delete(f"{API}/applications/{fresh['id']}", params={"rowVersion": fresh["rowVersion"]},
                         headers=h).status_code == 204
    applicant = client.get(f"{API}/applicants/{fresh['applicantId']}", headers=h).json()["data"]
    assert client.delete(f"{API}/applicants/{applicant['id']}", params={"rowVersion": "00" * 8},
                         headers=h).status_code == 409
    assert client.delete(f"{API}/applicants/{applicant['id']}", params={"rowVersion": applicant["rowVersion"]},
                         headers=h).status_code == 204


def test_permissions_and_scope(client, db, company, admin):
    staff = factories.login_as(db, client, company, role_codes="employee", employee_id=factories.employee(db, company))
    sh = staff["headers"]
    for url in ("/openings", "/applicants", "/applications", "/interviews", "/offers", "/dashboard"):
        assert client.get(f"{API}{url}", headers=sh).status_code == 403, url
    assert client.post(f"{API}/openings", json={"title": "x", "vacancies": 1}, headers=sh).status_code == 403
    assert client.post(f"{API}/settings/rejection-reasons", json={"name": "x"}, headers=sh).status_code == 403

    # A department-scoped recruiter reaches only their department's openings and cannot place one elsewhere.
    h = admin["headers"]
    mine_dept = factories.department(db, company)
    sub = factories.department(db, company, parent_id=mine_dept)
    other_dept = factories.department(db, company)
    mine = rf.opening(client, h, departmentId=sub)
    theirs = rf.opening(client, h, departmentId=other_dept)
    recruiter = factories.login_as(db, client, company, role_codes="employee",
                                   employee_id=factories.employee(db, company, department_id=mine_dept))
    for code in ("recruitment.openings.view", "recruitment.openings.create", "recruitment.applications.view"):
        rf.grant(db, company, recruiter["user_id"], code, "department")
    rh = recruiter["headers"]
    seen = {o["id"] for o in client.get(f"{API}/openings", params={"pageSize": 100}, headers=rh).json()["data"]}
    assert mine["id"] in seen and theirs["id"] not in seen
    assert client.get(f"{API}/openings/{theirs['id']}", headers=rh).status_code == 404
    elsewhere = client.post(f"{API}/openings", json={"title": "x", "vacancies": 1, "departmentId": other_dept}, headers=rh)
    assert elsewhere.status_code == 403
    assert client.post(f"{API}/openings", json={"title": "Mine", "vacancies": 1, "departmentId": sub},
                       headers=rh).status_code == 201
    app_theirs = rf.apply(client, h, theirs["id"])
    assert client.get(f"{API}/applications/{app_theirs['id']}", headers=rh).status_code == 404


def test_dashboard_and_rejection_reasons(client, db, company, admin):
    h = admin["headers"]
    opening = rf.opening(client, h)
    app = rf.apply(client, h, opening["id"])
    person = factories.employee(db, company, first_name="Zara")
    client.post(f"{API}/interviews", json={"applicationId": app["id"], "scheduledAt": "2099-06-01T09:00:00",
                                          "interviewerIds": [person]}, headers=h)
    r = client.get(f"{API}/dashboard", headers=h)
    assert r.status_code == 200, r.text
    d = r.json()["data"]
    assert d["tiles"]["openOpenings"] >= 1 and d["tiles"]["applications"] >= 1 and d["tiles"]["upcomingInterviews"] >= 1
    assert len(d["jobStatistics"]) == 12 and sum(m["applications"] for m in d["jobStatistics"]) >= 1
    assert any(i["applicationId"] == app["id"] and i["firstInterviewerName"].startswith("Zara")
               for i in d["upcomingInterviews"])
    assert d["recentActivity"] and d["recentActivity"][0]["toStage"]
    assert client.get(f"{API}/dashboard", params={"year": 2031, "month": 13}, headers=h).status_code == 422

    name = f"Salary too high {factories.tag()}"
    made = client.post(f"{API}/settings/rejection-reasons", json={"name": name, "sortOrder": 2}, headers=h)
    assert made.status_code == 201
    reason = made.json()["data"]
    dup = client.post(f"{API}/settings/rejection-reasons", json={"name": name}, headers=h)
    assert dup.status_code == 409 and dup.json()["code"] == "REJECTION_REASON_DUPLICATE"
    off = client.put(f"{API}/settings/rejection-reasons/{reason['id']}",
                     json={"name": name, "isActive": False, "rowVersion": reason["rowVersion"]}, headers=h)
    assert off.status_code == 200 and off.json()["data"]["isActive"] is False
    active = client.get(f"{API}/settings/rejection-reasons", params={"activeOnly": "true"}, headers=h).json()["data"]
    assert reason["id"] not in {x["id"] for x in active}
    inactive_use = client.post(f"{API}/applications/{app['id']}/reject",
                               json={"rejectionReasonId": reason["id"],
                                     "rowVersion": client.get(f"{API}/applications/{app['id']}", headers=h).json()["data"]["rowVersion"]},
                               headers=h)
    assert inactive_use.status_code == 422
    stale = client.delete(f"{API}/settings/rejection-reasons/{reason['id']}", params={"rowVersion": reason["rowVersion"]},
                          headers=h)
    assert stale.status_code == 409
    assert client.delete(f"{API}/settings/rejection-reasons/{reason['id']}",
                         params={"rowVersion": off.json()["data"]["rowVersion"]}, headers=h).status_code == 204
