# 04 Requests and approvals, Loans: frontend vs documents vs ERD

Sources: "Functional Requirements for HRango.pdf" pp. 1-97 (FRD), its digest
`requirements/HRango - Functional Requirements Document/01-Requests/README.md`, the Figma digests
`requirements/HRango - UI design/Design/01-Requests` and `07-Request-Settings-and-Flow`, the Figma file
"HRango Dashboard App Version" (Work Expense / Claim Expense, Air Tickets; read by the lead), "HRango -
Mini SRS.pdf" (WF2, APR-1..10, REQ-1..12, ACC-13), "HRango - Open Questions.pdf" (D1..D9, C10, C11,
E8), the frontend (`frontend/src/features/requests`, routes `frontend/src/routes/_app/requests/*`,
frontend README "Requests", "Request Settings and Transfer", "The newer request types") and the ERD
(`erd/source/07-req.md`, `08-loan.md`). The documents are the authority; the frontend's mock data and
payload shapes are not a specification.

## Final list of request kinds (read this first)

A **kind** is the detail table suffix (`req.req_<kind>`) and the name of the hooks the owning module
writes, all with the parameters `@company_id, @actor_user_id, @request_id`:

- `<schema>.usp_request_apply_<kind>`: on FINAL approval, in the approval's transaction.
- `<schema>.usp_request_revert_<kind>`: when an APPROVED request's cancellation is finally approved, in that transaction.
- `<schema>.usp_request_validate_<kind>` (optional): on submit and edit, after the engine's own checks.

The engine calls a hook only when it exists (`req.usp_request_effect_run`, fixed kind -> schema map,
QUOTENAME, sp_executesql). A THROW 504xx in a hook stops the action and its message reaches the user.
A withdrawn (pending) request never ran its effect, so nothing is reverted.

| Kind code | Request types (code = URL segment with hyphens; flows and permissions are per type) | Detail table | Effect owner |
|---|---|---|---|
| leave | leave | req_leave (+ request_day) | lv.usp_request_apply_leave / _revert_leave |
| punch | punch | req_punch | att.usp_request_apply_punch / _revert_punch |
| time_window | relaxation, official_visit | req_time_window (kind = the type code) | att.usp_request_apply_time_window / _revert |
| work_from_home | work_from_home | none: request.from_date/to_date + request_day | att.usp_request_apply_work_from_home / _revert |
| overtime | overtime | req_overtime | att.usp_request_apply_overtime / _revert |
| rest_day | rest_day | req_rest_day (+ request_day) | sch.usp_request_apply_rest_day / _revert |
| shift_swap | shift_swap | req_shift_swap | sch.usp_request_apply_shift_swap / _revert |
| promotion | promotion | req_promotion (+ req_promotion_benefit) | hr.usp_request_apply_promotion / _revert |
| transfer | transfer | req_transfer | hr.usp_request_apply_transfer / _revert |
| resignation | resignation | req_resignation | sep.usp_request_apply_resignation / _revert |
| loan | loan | req_loan (+ req.loan_guarantor) | loan.usp_request_apply_loan / _revert (this module) |
| travel | travel | req_travel (+ travel_advance, travel_leg, travel_stay, travel_ticket) | none: no module owns travel; approval only |
| expense | expense | req_expense (+ expense_line) | pay.usp_request_validate_expense / _apply_expense / _revert_expense (written by this module) |
| air_ticket | air_ticket | req_air_ticket | pay.usp_request_validate_air_ticket / _apply_air_ticket / _revert_air_ticket (written by this module) |
| requisition | requisition | req_requisition (+ requisition_line) | req.usp_request_apply_requisition (notifies who fulfils it; no revert) |
| task_extension | task_extension (no screen here) | none (pm.task_extension points at the request) | pm.usp_request_apply_task_extension |

`req.request_type` is reference data (`db/seeds/0400_req_request_type.sql`): `code, name, kind,
prefix, is_admin_only, is_active, sort_order`. Columns added beyond `(code, name, kind)` are nullable
or default, so other modules' test factories that insert `(code, name, kind)` still work; codes are
seeded anyway. Request codes are `RQ-<prefix>-0001` from `core.number_sequence` (prefix `RQ-LV`,
`RQ-PCH`, `RQ-RLX`, `RQ-OV`, `RQ-WFH`, `RQ-OT`, `RQ-RD`, `RQ-SFT`, `RQ-PRM`, `RQ-TRF`, `RQ-RSG`,
`RQ-LA`, `RQ-TRV`, `RQ-EXP`, `RQ-AIR`, `RQ-RQN`, `RQ-TEX`).

Leave: before saving, the engine EXECs `lv.usp_leave_request_check` (when it exists) with the
counted days, `@is_short`, `@has_attachment` and `@request_id` (edits); it keeps its own overlap
check and, only when that procedure is missing, its own copy of the leave-type rules and the
`lv.fn_leave_balance` check (deductible types only). `req_leave.days` holds the counted days.

## Screens and request types

| Screen / kind | In frontend (route) | In documents | ERD tables | Decision |
|---|---|---|---|---|
| Punch | `/requests/punch` (own page) | FRD pp. 17-25 "Punch Requests", "Punch Approvals", "Delegates Screen"; SRS REQ-1 | req_punch | Build. Date <= today, a shift that day is required, time inside the shift when there is one shift (FRD; any time on multi-shift days), one live request per date and punch type (frontend; no conflict) |
| Leave | `/requests/leave` (standard page) | FRD pp. 48-55 "Leave Request/Approvals/Delegates"; SRS REQ-2, LEV-5 | req_leave, request_day | Build. Types, short leave (half / quarter day; frontend's values, the FRD says "e.g. Morning/Afternoon"), shift days counted, overlap refused, lv rules and balance |
| Work From Home | `/requests/work-from-home` | FRD pp. 8-16; SRS REQ-3 | request, request_day | Build. No detail table: only shift days count; optional ticked `dates`; "proceed only if one shift is applied" -> 422 when none |
| Official Visit | `/requests/official-visits` (placeholder) | Figma (Open Questions: answered by the designs); SRS REQ-4; FRD flow list "Official Duty" | req_time_window | Build with changes: shares the kind time_window with Relaxation; no shift needed |
| Relaxation | `/requests/relaxation` | FRD pp. 73-79; SRS REQ-5 | req_time_window | Build. Shift needed, times inside it (frontend; no conflict); reason required (Figma `Reason *`); approval remarks required (Figma "Reason for Approval *") |
| Rest Days | `/requests/rest-days` | FRD pp. 80-85; SRS REQ-6 | req_rest_day, request_day | Build. Payable flag kept (Figma, SRS; D9 open) |
| Overtime | not under Requests (Attendance module screens) | FRD pp. 90-97; SRS ATT-12 | req_overtime | Build. Approver enters approved minutes (defaults to applied minutes); Open Question C11 settled as "uses the standard flow" |
| Shift Request | `/requests/shift` (own page) | Figma single frame; Open Questions D3; SRS REQ-12 "not defined" | req_shift_swap | Build with changes: either a new time slot for the day or a swap with a colleague (frontend); the colleague's consent is a step before the flow |
| Loan & Advances | `/requests/loan-advances` (+ Settings tab) | FRD pp. 36-47; SRS REQ-7; Open Questions D8 | req_loan, req.loan_guarantor, loan.* | Build. Eligibility from the type; approver fields; loan + installments on approval |
| Promotion | `/requests/promotion` | FRD pp. 60-65; SRS REQ-9 | req_promotion, req_promotion_benefit | Build. Admin only; Level optional (Figma `Level *`, not in FRD; D9); promotion cannot lower / demotion cannot raise salary (frontend; no conflict); approval remarks required (FRD) |
| Transfer | `/requests/transfer` (own page) | FRD pp. 86-89; SRS REQ-10 | req_transfer | Build. Admin only; the final authority on the form decides the `final_authority` node |
| Resignation | `/requests/resignation` | FRD pp. 66-72; SRS REQ-11, WF4 | req_resignation | Build. Last working date optional on the form (Figma), required before final approval (FRD); approver may set it and the notice period |
| Travel | `/requests/travel` | FRD pp. 26-35; SRS REQ-8 | req_travel, travel_* | Build. Legs must not overlap each other or another trip (frontend; no conflict); stays inside the trip |
| Expense (Work Expense / Claim Expense) | placeholder | Figma "HRango Dashboard App Version": per claim Expense Claim Title*, Expense Claim Date, Expense Claim Category*, Amount*, Description*, upload; "Generate Claim" prepares several, "Submit All" sends them; manager "Approve & Forward", "Reject & Forward". FRD flow list "Expense Request / Expense Cancel Request"; Control Panel icon "expense" | req_expense, expense_line, expense_category, reimbursement_setting | Build: one request carries the claims sent together (lines, each with its own receipt). Paid through payroll (see "Expense, air tickets and requisitions") |
| Air Tickets | none | Figma (App Version): title, claim date, travel date, description, file | req_air_ticket | Build with an Amount* (a claim needs one; not drawn) and optional From / To. Paid through payroll |
| Requisition | none | Figma Request Flows list names "Requisition"; Control Panel icon "requisition"; no form anywhere | req_requisition, requisition_line | Build, designed here: title, kind, needed-by date, delivery location, items (name, quantity, unit, estimated unit cost), justification (Reason*). Approval only, then the fulfilling authority is told |
| Request Settings: Expense Categories, Reimbursement | none | Figma category values (Travel Fee, Tech & Soft, Venue Rental, Equipment & Supplies, Instructor Fees, Event, Software); Control Panel "expense" | expense_category, reimbursement_setting | Build (`/requests/settings/expense-categories`, `/requests/settings/reimbursement`) |
| Approvals (Requested / Delegates / Consents / Cancellations, status tabs) | Approvals tab on every type | FRD every "... Approvals", "Delegates Screen"; Figma Requested/Cancellations/Delegates/Consents; SRS APR-4..9 | request_step | Build: one screen across types, `type` filter |
| Request Restriction | `/requests/settings/restrictions` | FRD p. 1; Figma Request Settings; SRS APR-8 | request_restriction | Build. Blocks a type for the company over the request's own dates |
| Delegation | `/requests/settings/delegation` | FRD pp. 2-4; Figma; SRS APR-6/7 | delegation | Build. No start/end dates (D6 open) |
| Request Flows (node editor) | `/requests/settings/flows` | Figma "Request Flow Edit"; SRS APR-1..3; FRD pp. 5-7 "Request flow" (authority assignment) | approval_flow, approval_node, approval_authority | Build: node editor + Authorities tab for the FRD's "assign an authority to an employee" |
| Loan Settings: Types, Categories, Repayment | Loan & Advances Settings tab | FRD pp. 46-47; Figma Settings Types/Categories/Repayment | loan_type, loan_type_employment_type, loan_category, loan_installment | Build (`/loans/types`, `/loans/categories`, `/loans/installments`) |
| My / All loans, schedule | not drawn (frontend shows Repayment only) | SRS MOB-3 "loan summary", PAY-9 employee accounts; Figma approve popup totals | loan, loan_installment | Build (`/loans`, `/loans/{id}`, `/loans/summary`) |

## What the engine does (decisions)

- **Flows** (APR-1..3): a flow per request type and purpose (`request`, `cancellation`), scoped to the
  company, a branch, a department or one employee (the frontend's "assignment"); the most specific
  active one wins. A cancellation without its own flow walks the request flow. Nodes: an approver
  (`employee`, `line_manager`, `hod`, `branch_manager`, `final_authority`, `role`, or an authority
  code), or a condition (`<field> <op> <number>`; fields days, amount, minutes, department_id,
  branch_id, location_id, grade_id, designation_id, employment_type_id; Open Question D2). Empty Next /
  If True / If False means the next node by number. Saving checks numbers, links and loops and stores a
  **new version**; requests already on the way keep theirs.
- **General Flow**: when a company has never had a request flow for a type, the first request saves
  "General Flow" (Line Manager, then Final Authority) for it, editable afterwards. A flow that was
  deleted or switched off is a choice: requests are refused (NO_FLOW) until one applies.
- **Walking**: a node nobody holds, a node that would make the employee decide their own request, and
  a node held by the person who decided the step before are recorded as `skipped`; observer ("On
  Looker") nodes are recorded as `informed`. A request no one can decide is refused at submit
  (NO_APPROVER).
- **Who decides** (ACC-13): the step's approver, a holder of the step's role, or an active delegatee
  of the approver for that type. `requests.approvals.approve/reject` only open the buttons; consent
  answers need only `requests.approvals.view`.
- **Can Disagree** (D1, inferred from Figma): a consent step; agree or disagree, both recorded and the
  flow goes on (the final authority sees the disagreement). **Can Edit**: that step's approver may edit
  the request. **Forward** (MOB-2): passes the current step to another employee.
- **Statuses**: pending, approved, rejected, cancelling, cancelled. "Approved by HOD" style labels are
  the step history (`approverKind` + `actionTaken`); "Extended" and "Evaluating" (D4) are not built.
- **Edit / delete** (D5): only while pending and nobody has acted (requester side) or by a Can Edit
  approver; delete keeps the row marked deleted (NFR-4). Withdrawing a pending request cancels it at
  once; cancelling an approved one walks the cancellation flow (WF2 steps 6-7). Reasons are required
  for reject, disagree and cancel.
- **Actions** (`actions` on a request's detail): the request type's own screen
  (`GET /requests/<type>/{id}`) is the requester side: edit / delete / cancel as above, plus the
  decision of a step the caller holds. The Approvals detail (`GET /requests/approvals/{id}` and the
  answers of approve / reject / consent / forward / cancel there) is the approver side: only the
  decision the caller's pending step allows (`approve`, `reject`, `forward`, or `consent`, `disagree`),
  and `edit` only when that flow node has Can Edit. An approver never gets the requester's edit, delete
  or cancel there (decision of the frontend-integration fixes).
- **Restrictions**: start date in the future, end on or after start, no overlap per type; a request
  whose dates touch the period is refused (REQUEST_RESTRICTED). Edit with `PUT
  /requests/settings/restrictions/{id}` and the rowVersion (`requests.settings.restrictions.edit`): same
  rules, except that an edit may keep a start date that has already passed and may not move the end
  date into the past.
- **Delegation**: delegator and delegatee differ; one active delegation per delegator and type;
  disable / enable through PATCH; `DELETE /requests/settings/delegations/{id}?rowVersion=`
  (`requests.settings.delegations.delete`) removes it (steps a delegatee already decided keep their
  history). Delegated actions show `isDelegate` and the delegator on the Delegates tab.
- **Bulk approve / reject** (APR-9): each request is decided on its own; the answer lists each result.
  Bulk approve has no approval form, so `usp_request_decide @prefill = 1` fills what the form would
  prefill and nobody entered: a loan's approved amount (the amount asked, or what an earlier approver
  set), payment method (`bank` when the employee has a bank account, else `cash`) and repayment date
  (the first of the month after the required date, or after today when that is later). A single
  approve still needs them from the approver at the final step.
- **Details JSON**: every list inside `details` (WFH / rest days, promotion benefits, loan guarantors,
  travel advances / legs / stays / tickets, expense and requisition lines) carries its empty fields as
  `null` (`FOR JSON ... INCLUDE_NULL_VALUES`), so the shapes are stable.
- **Self-service options** (`/api/requests/options/...`): the request forms' dropdowns for people who
  hold the request kind's create permission but not the settings permissions of the full lists. No new
  permission codes; ids, names and what the form needs only (`db/procedures/req/usp_request_options.sql`).
  - `GET /options/leave-types?employeeId=&asOf=` (`requests.leave.create`; employee default the caller,
    the permission must reach them, else 404): the active types the employee's leave policy gives them
    (`lv.fn_leave_coverage`) as `{id, name, code, isDeductible, isShortLeave, allowHalfDay,
    allowShortLeave, attachmentRequired, attachmentRule, allowBackDate, backDateLimitDays,
    futureLimitDays, entitled, used, pending, available}`; balance from `lv.fn_leave_balance` on `asOf`
    (today by default); `allowHalfDay` / `allowShortLeave` combine the type's short leave flag with the
    employee's Half leave & Short leave policy (`lv.fn_leave_half_short`).
  - `GET /options/loan-types?employeeId=` (`requests.loan.create`): active types `{id, name,
    guarantorRequired, nonPayable, minExperienceMonths, gapBetweenRequestsMonths, installments,
    gapBetweenInstallmentsMonths, description, eligible}`; `eligible` = the employee's contract type may
    apply (null without an employee).
  - `GET /options/loan-categories` (`requests.loan.create`): active `{id, name, description}`.
  - `GET /options/colleagues?q=&employeeId=&page=&pageSize=` (`requests.shift_swap.create`): paged
    `{id, code, name, departmentId, departmentName, branchId, branchName}` of the company's employees
    who have not left, without the requester (`employeeId`, default the caller); search on code and name.
  - Already reachable without settings codes: time slots and roster groups
    (`/scheduling/options/*`, `scheduling.schedules.view`), organisation look-ups, expense categories
    (`/requests/expense/categories`). Left settings-only: pay items (reimbursement settings, promotion
    benefits: HR forms), roles for flow nodes.
- **Who files for whom**: the create permission's scope (own = My, wider = All). Promotion and
  Transfer are `is_admin_only`: never for oneself.
- **AI-generated application** (D7): not built; `application` stores the text the client sends.
- **Events and notifications** (APR-10, README "Events, notifications and webhooks"): every action publishes
  an event in its own transaction (`req.usp_request_publish`; list below) and tells people in the inbox:
  whoever must act on a step that just became pending (the named approver and their active delegatees for
  the type, or every active holder of the step's role; type `request_approval`, link
  `/requests/approvals/<id>`), and the employee the request is for when it is approved, rejected,
  cancelled or its cancellation rejected (type `request_update`, link `/requests/<type-with-hyphens>/<id>`),
  unless they did it themselves. Escalation (reminders when nobody acts) is not built: no rule in the
  documents.
- **Attachments** are uploaded files (`POST /api/files`, then the id): `attachments: [fileId]` on create,
  `POST .../attachments {fileId, label}` later; `core.attachment` with `company_id`, entity `req.request`,
  checked with `core.fn_file_usable` (another company's file is "not found", 422). Responses give id, name,
  type, size and a signed `url`; never a path. File ids inside the details (expense receipts, the air
  ticket, travel tickets, loan guarantors) get `fileName` and a signed `fileUrl` next to them. Removing an
  attachment keeps the file (its uploader may delete it once nothing uses it).

### Events (app/catalogue/requests.py EVENTS)

`requests.submitted`, `requests.step_decided` (approved / consented / disagreed at a step, the flow goes on),
`requests.forwarded`, `requests.approved` (effect applied), `requests.rejected`,
`requests.cancellation_requested`, `requests.cancellation_rejected`, `requests.cancelled` (action `withdrawn`,
`deleted` or `cancellation_approved`). Payload (camelCase, ids as strings): requestId, code, type, typeName,
kind, action, status, employeeId, employeeCode, employeeName, departmentId, branchId, fromDate, toDate, days,
amount (the flow condition's amount), submittedAt, decidedAt, actorUserId, actorEmployeeId, remarks and
currentStep {stepId, purpose, stepNo, approverKind, approverId, approverName, approverRoleId, isConsent}.
Entity `req.request`. Every notification is also published as `notification.created` by core.

## Work from home and shift change (decisions)

- **Work from home** (FRD pp. 8-16; frontend "WFH day ticks"): the request keeps the From / To the
  employee entered; its days (`request_day`, `details.days`, the Count) are the shift days inside it,
  only the ticked ones when `details.dates` is sent. A ticked date outside From..To is refused (422
  `dates`); ticked days without a shift are left out; no shift at all is NO_SHIFT. On final approval
  `att.usp_request_apply_work_from_home` sets `sch.schedule.is_wfh = 1` on the employee's shifts of those
  days and re-processes attendance; when the cancellation is approved `_revert_` sets them back to 0
  (unless another approved WFH request covers the day). Attendance reads WFH days from `request_day`, not
  the From..To range. A shift the planner had already marked WFH is cleared by a cancellation too (no
  record of who set it).
- **Shift change**: a change to the slot the shift already has, or to another slot with the same hours,
  is refused (422 `timeSlotId`, SHIFT_UNCHANGED); a swap with a colleague who works the same slot and
  hours that day is refused (422 `withEmployeeId`, SHIFT_UNCHANGED).
- **Leave rules on submit**: the engine calls `lv.usp_leave_request_check` directly (it was called only
  when found, through dynamic SQL, with a copy of the rules as fallback; the copy is gone, lv owns the
  rules). Half-day leave needs the type's short leave flag and, when the employee has a Half leave &
  Short leave policy, its `allowHalfDay` (422 `shortLeaveType`, HALF_DAY_NOT_ALLOWED); a quarter day
  (short leave) needs `allowShortLeave` (SHORT_LEAVE_NOT_ALLOWED).

## Loans (decisions)

- Type: Formula* is stored but optional until payroll formulas exist and is not evaluated (no rule
  says what it limits). Deduction pay item is required unless Non-Payable. Employment contract types:
  at least one.
- Request eligibility: active type, contract type, months of service, one waiting request per type,
  Gap Between Requests (months since the last submitted request of the type), guarantor when required.
- Approval: approved amount (no more than asked), payment method (bank, cash, pay_order, cheque),
  repayment date and currency (company currency by default); required before the final approval.
- On approval `loan.usp_request_apply_loan` makes the loan and `installments` rows of
  approved / n (the last takes the rounding), every Gap Between Installments months (1 when empty)
  from the repayment date's month (D8: repayment is by installments through payroll). Non-Payable:
  a loan with status `non_payable` and no schedule. Cancelling the approved request removes the loan
  unless payroll has recovered an installment (409).

## Expense, air tickets and requisitions (decisions)

- **Expense, one request with lines.** The Figma "Generate Claim" / "Submit All" pair becomes one request
  whose `details.lines` are the claims (1 to 50): title*, claim date (today when empty, never in the future),
  category* (active, this company's), amount* (> 0), description*, `fileId` (the receipt). The header's
  dates are the first and last claim dates; the flow condition `amount` is the total (approved once set).
  Category rules: `maxAmount` per claim (`EXPENSE_OVER_LIMIT`), `receiptRequired` (`EXPENSE_RECEIPT_REQUIRED`).
  The same category, date and amount in another live expense request is refused (`EXPENSE_DUPLICATE`, 409).
- **"Approve & Forward" / "Reject & Forward"** are the engine's approve and reject: approve passes the
  request to the next step (the flow forwards it); reject ends it. Any approver may lower a claim
  (`details.lines: [{id, approvedAmount}]`, 0 = not reimbursed, never above the claim); claims nobody lowered
  are approved as claimed at the final approval.
- **Air tickets**: title*, claim date, travel date*, from / to, amount* (not drawn, needed to pay it),
  description, `fileId` (the ticket). One live claim per travel date (`AIR_TICKET_DUPLICATE`). The approver
  may lower it (`details.approvedAmount`).
- **How a claim is paid: through payroll, as an opening balance.** Of what payroll already pays, only
  `pay.opening_balance` fits: the run adds a person's opening balances of a month to that pay item
  (`pay.usp_payroll_run_inputs`, one-off). Employee account entries are a ledger payroll does not pay, and
  vouchers are a separate payment with their own approval and finance verification (they would ask for a
  second approval of an approved claim). On final approval `pay.usp_request_apply_expense` adds one opening
  balance per claim with an approved amount (kind `reimbursement`, not taxable, description "RQ-EXP-0001
  expense claim: <title>") under the category's reimbursement pay item, else the default of Request Settings
  -> Reimbursement, in the first month payroll has not closed for the employee (`pay.fn_month_locked`); the
  claim keeps the id (`expense_line.opening_balance_id`, shown as `paidInMonth`). Air tickets: one opening
  balance under the air ticket pay item. Cancelling an approved claim removes the opening balances, refused
  (409) once a closed payroll has paid that month. Pay items must be of type `reimbursement`; the pay item
  must also be on the payroll (Payroll -> pay items) for the run to pay it.
- **No pay item, no claim**: `pay.usp_request_validate_expense` / `_air_ticket` refuse a submit whose claims
  cannot be paid (`EXPENSE_NOT_PAYABLE`, `AIR_TICKET_NOT_PAYABLE`), so the configuration gap shows before
  anyone approves; apply checks again.
- **Requisition** (designed here; no form in any document): title*, kind* (stationery, it_equipment,
  furniture, asset, consumable, service, other), needed-by date* (not before the request date), delivery
  location, items* (name*, quantity* > 0, unit, estimated unit cost >= 0, description), justification =
  Reason*. Estimated amount = sum of quantity x cost (the flow condition `amount`). Approval only: nothing in
  HRango stocks or buys items. On approval `req.usp_request_apply_requisition` tells who fulfils it: holders
  of the IT Administrator authority for IT equipment, of the Admin Manager authority otherwise (Request
  Settings -> Authorities, matched on type, branch and department; type `request_fulfil`); the
  `requests.approved` event carries it for a purchasing system. No fulfilment tracking (no design).
- **Settings**: Expense Categories (name*, reimbursement pay item, max amount per claim, receipt required,
  active, description; a category with claims cannot be deleted, switch it off) and Reimbursement (default
  expense pay item, air ticket pay item). The claim form reads active categories from
  `GET /requests/expense/categories` (needs `requests.expense.create`).

## Gaps both ways

- In documents, not in frontend: Overtime under Requests (frontend keeps it in Attendance), the
  Request Flow "authority -> employee" screen (built as Authorities), bulk approve on every type, the
  Cancelling / Cancelled tabs on every type, the loan approve popup's totals (`/loans/summary`).
- In frontend, not in documents: Consents behaviour, shift change by time slot, the per-person flow
  assignment, the WFH day ticks, "Completed" for WFH (not built: status stays `approved`), the
  Subordinates tab (built as `view=subordinates`).
- In neither: escalation, delegation dates, edit after approval, requisition fulfilment tracking, multi-currency
  claims (claims are in the company currency).

## Frontend dependencies R1-R4 and the overtime gaps (gray structure, Oct 2026)

From `frontend/docs/backend-dependencies.md` (Requests) and `backend-mapping/attendance-overtime.md` (Gaps both ways).
Tests: `backend/tests/test_requests_extras.py`.

Built:
- **R1** `POST /api/requests/{type}/application/generate` (`GenerateApplicationIn` -> `{data: {text, generatedAt}}`),
  guarded by the type's `.create` code. Calls `app.core.ai.ensure_available()` first, so it answers **503
  AI_UNAVAILABLE** while no model is connected; 422 when the form is empty.
- **R2** `CancelIn` + optional `dates[]`, `startTime`, `endTime` on `POST /requests/{type}/{id}/cancel` and
  `POST /requests/approvals/{id}/cancel`. Work from home only (422 `dates` for other types: in Python on the type
  route, in `req.usp_request_cancel` on the Approvals route); dates must lie within the request, end after start.
  Stored on `req.request` (`cancel_dates` JSON, `cancel_start_time`, `cancel_end_time`) and returned as
  `cancelDates`, `cancelStartTime`, `cancelEndTime` on every request.
- **R3** `?flowStep=<approver kind or authority>` on every `/requests/{type}` list (and its export) and on
  `/requests/approvals`: requests with a pending step of that `approver_kind`. Unknown values 422.
- **R4** every `/requests/{type}/export` declares `200 text/csv` (no JSON) and sends
  `Content-Disposition: attachment; filename="<type>-<yyyy-MM-dd>.csv"`, UTF-8, header line then one row per
  request (every page). Overtime adds Overtime date, Start / End time, Applied / Approved minutes, Type, Bulk,
  Location, Branch. `requests.overtime.view|create|cancel|export` are in the catalogue.
- **Bulk overtime** `POST /api/requests/overtime/bulk` (`requests.overtime.create`)
  `{employeeIds[], overtimeType: mandatory|voluntary, fromDate, toDate?, reason, description?, attachments[], details}`
  -> 201 `{data: {bulkId, overtimeType, count, requests[]}}`. One request per person on their behalf, all or
  nothing: each person is tried first (filed and rolled back) so every refusal is reported at once
  (422 `BULK_REFUSED`, `fieldErrors["employeeIds.<id>"]`), then all are filed in one transaction with a
  `req.request_bulk` row. One day only (`toDate` must equal `fromDate`). `?bulk=true|false` filters the lists.
- **Overtime output typed**: `OvertimeDetailsOut` on the overtime routes (list, get, create, edit, cancel):
  department / location / branch ids and names, date, times, applied / approved minutes, `overtimeType`,
  `isBulk`, `bulkId`, and the policy an approval fell under (`overtimePolicyId`, `overtimePolicyName`,
  `slabMinMinutes`, `slabMaxMinutes`, `encashmentType`, `encashmentLeaveTypeId`, `encashmentLeaveTypeName`).
- **Bulk approve with details**: `BulkItemIn.details` (the single approve's `ApprovalDetailsIn`, e.g.
  `approvedMinutes`) is passed to `req.usp_request_decide` per item; what is left out is prefilled as before.
- **Policy usage**: see 03-attendance.md (`usageCount`, 409 `IN_USE`).

TODO (left on purpose):
- R1: no model call; prompt, employee scope check and HTML clean-up are marked `TODO(R1)` in
  `requests_service.generate_application`.
- R2: what cancelling a WFH day "from-to a time" means is an open product question; the values change nothing
  (the whole request is cancelled as before). `TODO(R2)` in `usp_request_cancel` and `requests_service.cancel`.
- Bulk overtime: attachments are linked to every request; no bulk edit / bulk cancel; the trial pass costs two
  submits per person (fine up to the 100-person limit).
- Overtime policy: the policy is the company's first active **daily** policy whose slab holds the minutes;
  policies are not assigned to people, monthly policies, capping by the top slab and encashment are not done
  (`TODO(overtime policy)` in `att.usp_request_apply_overtime`).

## ERD changes (07-req.md, 08-loan.md)

- `request_type`: added `kind`, `prefix`, `is_admin_only`, `sort_order`; `UNIQUE (code)`; codes as above
  (`wfh` -> `work_from_home`; `manpower_budget` dropped: manpower approves inside its module).
- `request`: added `days` (Count), `description`, `application`, `approval_flow_id` (the flow version
  walked), `cancel_requested_at`.
- `request_day`: `UNIQUE (request_id, request_date)`.
- Detail tables: required columns marked `{NN}`, optional foreign keys `{NULL}` (detail tables have no
  id, so build.py would make every FK NOT NULL); `req_time_window` + `time_slot_id`, `duration_minutes`;
  `req_overtime` + `branch_id`, - `reason_kind` (the reason is the header's); `req_shift_swap` +
  `shift_date`, `time_slot_id`, all four references nullable (change or swap); `req_loan.currency` CHAR(3).
- `loan_guarantor`, `travel_*`: required columns `{NN}`; `travel_ticket.description`. Their `file_id` is now
  saved from the form (uploaded file ids).
- New `req_expense` (currency, total, approved total) + `expense_line` (line_no, title, claim_date, category,
  amount, approved_amount, description, file_id, opening_balance_id; `UNIQUE (request_id, line_no)`).
- New `req_air_ticket` (title, claim/travel dates, from/to, amount, approved_amount, currency, description,
  file_id, opening_balance_id).
- New `req_requisition` (title, requisition_type, needed_by_date, delivery_location, estimated_amount, currency)
  + `requisition_line` (line_no, item_name, quantity, unit, estimated_unit_cost, description; unique line_no).
- New settings `expense_category` (`UNIQUE (company_id, name)`, pay_item_id, max_amount, receipt_required) and
  `reimbursement_setting` (one row per company: expense and air ticket pay items).
- `request_type` codes + `expense`, `air_ticket`, `requisition`.
- `approval_flow`: + `description`, `is_current` (versioning); scope_type adds `employee`.
- `approval_node`: + `role_id`, `condition_field`, `condition_operator`, `condition_value` (parsed from
  `expression`), `step_no {NN}`, `UNIQUE (approval_flow_id, step_no)`.
- New `approval_authority` (who holds HR Manager, Finance Manager ... per type / branch / department).
- `request_step`: + `approver_role_id`, `is_consent`; `action_taken {NN}` with the event values.
- `request`: + `cancel_dates {NVARCHAR(MAX)}`, `cancel_start_time`, `cancel_end_time` (WFH cancellation, R2).
- `req_overtime` (now one column per line): + `overtime_type`, `bulk_id FK request_bulk`, `overtime_policy_id FK
  overtime_policy`, `slab_min_minutes`, `slab_max_minutes`, `encashment_type`, `encashment_leave_type_id FK leave_type`
  (the slab is copied: policy edits replace slabs).
- New `request_bulk` (company_id, request_type_id, request_count, reason): requests filed together.
- 08-loan: `loan_type.description`, `UNIQUE (company_id, name)`; `loan_category.description`, unique
  name; `loan` + `company_id`, `loan_category_id`, `gap_between_installments_months`, `currency`,
  `payment_method`, `settled_at`, `UNIQUE (request_id)`, status `non_payable`; `loan_installment` +
  `installment_no`, `paid_at`, `UNIQUE (loan_id, installment_no)`.

## Permissions (app/catalogue/requests.py, loans.py)

- `requests.<type>.view/create/cancel/export` for the 16 types with screens, including `expense`,
  `air_ticket`, `requisition` (loan and promotion are sensitive). `requests.approvals.view/approve/reject/cancel`.
  `requests.settings.restrictions` (view, create, edit, delete), `.delegations` (view, create, edit, delete),
  `.flows` (view, create, edit, delete), `.authorities` (view, create, edit, delete),
  `.expense_categories` (view, create, edit, delete), `.reimbursement` (view, edit).
- `loans.loans.view/export` (sensitive), `loans.settings.types` and `loans.settings.categories` (CRUD).

## Cross-module needs

- lv, att, sch, hr, sep, pm: write `usp_request_apply_<kind>` / `usp_request_revert_<kind>` with the
  parameters above (most exist). Payroll: mark `loan.loan_installment` rows paid (`paid_amount`,
  `payslip_id`, `paid_at`, `status = 'paid'`) and deduct through `loan_type.deduction_pay_item_id`.
- Payroll: `pay.usp_request_{validate,apply,revert}_{expense,air_ticket}` were written by this module (files
  `db/procedures/pay/usp_request_apply_expense.sql`, `usp_request_apply_air_ticket.sql`); please keep them when
  changing `opening_balance`. They add opening balances of kind `reimbursement` (the payroll schema's `kind`
  input is `opening | adjustment`; its list shows the new value as it is). `req.expense_line` /
  `req.req_air_ticket` point at them, so deleting such an opening balance on the payroll screen is refused
  (409 IN_USE): cancel the request instead.
- Core (default roles): add `expense`, `air_ticket`, `requisition` to SELF_SERVICE's request kinds (view, create,
  cancel, own); managers already get them through `requests.*.view/export`; Payroll Manager could read
  `requests.expense.view` and `requests.air_ticket.view` (company). Until then the tests grant staff these codes.
- The frontend: endpoints are `/api/requests/<type-with-hyphens>` (list `?view=my|subordinates|all`,
  create, edit, delete, `/cancel`, `/attachments`, `/export`), `/api/requests/approvals` (`?box=`,
  `/approve`, `/reject`, `/consent`, `/forward`, `/cancel`, `/bulk-approve`, `/bulk-reject`),
  `/api/requests/settings/{restrictions,delegations,flows,authorities,expense-categories,reimbursement}`,
  `/api/requests/expense/categories` (the claim form's dropdown), `/api/requests/types`,
  `/api/loans/...`. Each request carries `details` (camelCase) and `actions`. Attachments: upload with
  `POST /api/files` (module `requests`) and send the ids.
