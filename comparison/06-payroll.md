# 06 Payroll: frontend vs documents vs ERD

Sources: FRD = "Functional Requirements for HRango.pdf" (page numbers below), digest
`requirements/HRango - Functional Requirements Document/02-Payroll/README.md`; Design =
`requirements/HRango - UI design/Design/02-Payroll/README.md`; Dash = `All Dashboards/05-Payroll`; SRS =
"HRango - Mini SRS.pdf" (M8 PAY-1..13, WF3, WF4, ACC-9); OQ = "HRango - Open Questions.pdf" (C9, C12, E1-E12).
Frontend = `frontend/src/routes/_app/payroll/**`. Backend: `/api/payroll/...`, schema `pay`.

## Screens

| Screen / feature | Frontend route | Documents | ERD tables | Decision |
|---|---|---|---|---|
| Settings: General (22 options) | `settings/general` | FRD p.98-100, 166-176; Design "Payroll Settings / General"; SRS PAY-1 | core.company_setting (module `payroll`) | Build. `GET/PUT /settings/general`, one row version over all keys. Applied in the engine: tax rounding, "How to prorate", Use shift hours, Exclude FS from payroll, Disable tax distribution on FS, Do not display payslip after run, salary-report rounding, show on-hold amounts, print signature, payslip display options. Stored only (no data or no mail service): revision on fixed / shift days, cut-off proration, the two e-mails |
| Settings: Leave configuration | `settings/general` | FRD p.101; Design | core.company_setting | Build as stored settings (CPL leave type, max earned CPL, deduction order, calendar/fiscal year). The leave module reads them |
| Tax structure + slabs | `settings/tax` | FRD p.102-103; Design (TS-0004); SRS PAY-2 | tax_structure, tax_slab | Build. Code `TXS-0004` (TXS, not TS: time slots use TS-). Slabs checked for order and overlap |
| Tax rebate | `settings/tax` | FRD p.101-102; SRS PAY-2 | tax_rebate | Build. Lowers the tax year's tax |
| Rewards: Benefits | `settings/rewards` | FRD p.103-104; Design "Benefit Create" | reward_benefit, reward_benefit_member, reward_benefit_field | Build. Type list decided (allowance, bonus, reward, other). Group benefit = only its members get the pay item; formula adds an amount |
| Rewards: Sales incentive | `settings/rewards` | FRD p.104-105; Design (Amount = target, Value = reward) | sales_incentive | Build CRUD; **no payroll effect**: HRango has no sales figures to compare with the target |
| Pay items | `settings/pay-components` | FRD p.106-110; Design; SRS PAY-3 | pay_item | Build. Types: union of FRD and Design (earning, deduction, reimbursement, employee_data, other; OQ E11). Calculation fixed / manual / formula. Nine system items added per company |
| Formulas | `settings/pay-components` | FRD p.110-111; Design (+Is Custom); SRS PAY-4 | formula | Build. Expression builder endpoint `/settings/variables`, `/settings/expressions/check` |
| Rules | `settings/pay-components` | FRD p.111-112 | pay_rule | Build: evaluated on every run, the amount is posted to the rule's employee account |
| Account types | `settings/account-type` | FRD p.112-114 | account_type | Build. Category benefit / leave_quota / custom_pay_item with the referenced record; code `ACT-0001` |
| Disbursement banks | `settings/disbursement-banks` | FRD p.114-116 | disbursement_bank | Build. Employee bank details stay in hr (EMP-2) |
| Payrolls: Monthly (create, employees, run, stop, history, errors, close) | `payrolls/monthly` | FRD p.116-122, 125-127, 177-179; Design; SRS PAY-6, PAY-12, WF3 | payroll, payroll_pay_item, payroll_employee, payroll_run_log, payroll_run_error, payslip, payslip_line | Build. Run/recalculate, close (irreversible, logged), hold/unhold the whole run. **Stop** = hold (runs are synchronous, there is nothing to stop) |
| Payrolls: Daily wages | `payrolls/daily-wages` | FRD p.122-124, 179-180; Design (batch per time slot); SRS PAY-7 | payroll (kind daily_wage), payslip, voucher | Build as the Design: one run per day and time slot, wages from the day's time sheet; edit totals by hand; vouchers after close |
| Salary sheet | `salary-sheet` | FRD p.124-125; Design; SRS PAY-8 | payslip, payslip_line | Build (JSON; print/Excel are the frontend's) |
| Pay slips My / All, view, edit, hold, recalculate, pay, history, Employee Accounts panel | `pay-slips/my`, `pay-slips/all` | FRD p.127-131; Design; SRS PAY-9 | payslip, payslip_line, core.audit_log, employee_account_entry, loan tables | Build. PDF is rendered by the frontend from `GET /payslips/{id}` (lines + display settings) |
| Vouchers + Employee voucher (approval, finance verification) | `vouchers`, `vouchers/employee` | FRD p.131-136; Design; SRS PAY-10 | voucher | Build: pending -> approved/rejected (`approve`/`reject`) -> processed (`verify`, Finance) |
| Final settlement | `final-settlement` | FRD p.139-140, 166-167; SRS SEP-5, WF4 | sep.end_of_employment (read), sep.final_settlement, payslip | Build: list of leavers needing FS, recalculate, view payslip, close |
| Balances: Opening balance (+import, adjust) | `balances/opening-balance` | FRD p.136-138; Design; SRS PAY-11 | opening_balance | Build; added to the pay item in that month's run |
| Balances: Employee accounts (+import), statement | `balances/employee-accounts`, `balances/account-statement` | FRD p.138-139; Design | employee_account_entry | Build. Statement with running balance per account |
| Salary revision (+import) | `salary-revision` | FRD p.140-143; Design; SRS PAY-11 | hr.employee_salary (rows written through pay procedures) | Build. Flat = amount added, percent = raise on previous salary (FRD p.141 "Type of Revision") |
| Leave encashment | `leave-encashment` | FRD p.155-157; Design; SRS PAY-11 | lv.leave_encashment, lv.leave_encashment_employee, lv.leave_ledger | Build: days = balance within the type's min/max; mode payroll (next run) or manual |
| Reports | `reports/employee-accounts` | Design (only Employee Account Report); FRD p.179-180 (Payroll Summary, Employee-wise, Daily Wages Summary, Voucher report); OQ E12 | payslip, employee_account_entry, tax_rebate, voucher | Build the four named reports; the voucher report is the voucher list with filters |
| Dashboard | `dashboard` | Dash "Payroll Dashboard" (tiles, Salary Statistics, Salary Breakup) | payslip, payslip_line, payroll | Build those three blocks. The frontend's extra charts (yearly comparison, loan month-wise, per-person earning) are not in the documents; the employee-wise report covers the per-person one |
| Assets, end of employment, off-boarding checklist, rehire | under Payroll in the Design menu | FRD p.143-162 | sep.* | Not here: owned by the assets/off-boarding module |

## Gaps

Frontend has, documents do not: `/lookups` aggregate (not built; each list endpoint serves its dropdown);
dashboard charts above; payslip status "Released With FS" (here: `isFinalSettlement` + `released`); manual
leave encashment adding voucher lines (not built: FRD says manual means handled outside payroll); hourly /
fortnightly / weekly pay frequency (Dash "Payroll Settings", OQ E9: not built, monthly and daily wages only).

Documents have, frontend lacks: payroll Error Logs per run (built), run history (built), employee-wise and daily
wages summary reports (built), voucher Rejected status (built), tax rebates feeding tax (built).

Not in the first build (documents silent or open questions): arrears (`arrearApplicable` stored, no
calculation: a back-dated revision is refused once that month is closed), reopening a closed payroll (FRD:
irreversible; OQ E2), approval before close (OQ E3), bank-specific transfer layouts (E4; the generic CSV / TXT
file is built, below), posting to finance ledgers (E5), multi-currency conversion (E7; currency stored per run),
statutory returns (E1), actually sending e-mail (no mail service yet; the e-mails are recorded, below),
scheduled processing by Processing Date (stored; runs are on demand), sales incentive calculation (no sales
data), cut-off proration and revision by fixed / shift days (stored).

## Frontend dependencies P1-P4 (frontend/docs/backend-dependencies.md), built as a gray structure

| Item | Endpoints (permission) | How | Left as TODO |
|---|---|---|---|
| P1 Close e-mail | `GET /payrolls/{id}/close-email/preview` (`payroll.payrolls.view`) -> `{enabled, subject, bodyHtml, recipientCount}`; `POST /payrolls/{id}/close` (`close`) now answers `email: {status, sentCount, failedCount}` (null for daily wages); `GET /payrolls/{id}/close-email` (`view`) -> `{status, queuedAt, sentAt, recipientCount, sentCount, failedCount, failures[]}` | `pay.usp_payroll_close` records `pay.payroll_close_email` in the close's transaction (`disabled` while `app.core.mail.enabled()` is false, else `queued`) and one `pay.mail_outbox` row per person with a released payslip and an e-mail address (`pay.fn_employee_email`: employee e-mail, else their account's). Status is `none` before the close. Subject/body: built-in plain template (`app/services/payroll_mail_service.py`) | the mail sender (deliver queued rows, mark sent / failed, set the run's status and `sent_at`); company-editable templates and the two e-mail options of Settings -> General |
| P2 Salary revision letter | `GET /salary-revisions/{id}/email/preview` (`payroll.salary_revision.view`) -> `{subject, bodyHtml, to}`; `POST /salary-revisions/{id}/email {rowVersion}` (new action `payroll.salary_revision.send`) -> `{status, sentAt}`; `SalaryRevisionOut.emailStatus` (`none, queued, sent, failed, disabled`) and `emailedAt` | rowVersion is the revision's (409 when stale). Each request adds a `pay.mail_outbox` row (entity `hr.employee_salary`; no FK, hr owns and may delete the row); status `disabled` while mail is off, else `queued` (422 `to` when the person has no address; 409 `EMAIL_QUEUED` when one is already waiting). The latest row gives `emailStatus`; `emailedAt` is its `sent_at`. Deleting a revision here withdraws its unsent rows | sending; an attachment (PDF letter) |
| P3 Bank transfer file | `GET /bank-file-formats` (`payroll.payrolls.export` or `payroll.daily_wages.export`) -> `csv` Generic CSV, `txt` Generic fixed width; `GET /payrolls/{id}/bank-file?disbursementBankId&format` (`payroll.payrolls.export`) and `GET /daily-wages/{id}/bank-file` (`payroll.daily_wages.export`): attachment, `text/csv` / `text/plain` declared in OpenAPI | `pay.usp_payroll_bank_file`: 409 `PAYROLL_NOT_CLOSED` until closed; the bank defaults to the run's and must be the run's (any company bank for daily wages, which name none; 422 `disbursementBankId`); rows = bank-paid payslips not on hold with net pay > 0, the person's primary bank account, net pay. Unknown format: 422 `format` | bank-specific layouts; xlsx (no spreadsheet library installed, not listed); a per-person disbursement bank (a run is paid through one bank) |
| P4 Leave encashment preview | `POST /leave-encashments/preview {leaveTypeId, fiscalYear, allEmployees, employeeIds, basis, amountPerLeave, id?}` (`payroll.leave_encashment.create` or `edit`) -> `[{employeeId, employeeName, availableDays, encashableDays, cappedBy, amount}]` | `pay.usp_leave_encashment_preview`, same rules as saving without writing; `id` (edit) gives the encashment's own days back. Save already applied the spec's limits (type off -> 422 `leaveTypeId`; under `encashmentMin` left out; above `encashmentMax` paid for the max; nobody left -> 422 `employeeIds`); only change: the "nobody left" message now says why (below the minimum / no salary) | share the balance rule between preview and save (now duplicated); `/api/leaves/encashments` (leaves module, `lv.usp_leave_encashment_save`) is not changed |

## ERD changes (erd/source/09-pay.md)

- tax_structure: `code` TXS-, required dates, UNIQUE (company_id, name); slab formula documented.
- tax_rebate: `description`. formula: UNIQUE name; `is_custom` (0 = system formula).
- pay_item: `is_taxable` (default for a run), `system_code` (+ filtered UNIQUE), `description`; `reimbursement`
  added to item types; both formula FKs nullable; required type / calculation / distribution.
- pay_rule: `description`, UNIQUE name. account_type: `code` ACT-, required category, `ref_id`, UNIQUE name.
- reward_benefit: `description`, UNIQUE name, formula optional; new **reward_benefit_field** (Additional
  Information); members may be employees or employee groups (both FKs nullable).
- sales_incentive: `description`, required fields. disbursement_bank: `description`, UNIQUE account number.
- payroll: `description`, statuses `open, running, on_hold, closed`; time slot / tax structure / bank optional
  (daily-wage runs have none).
- payroll_pay_item: UNIQUE (payroll_id, pay_item_id). payroll_run_log: `kind` (run, recalculate, close),
  `processed_count`, `error_count`.
- payslip: `company_id`, `payroll_id` optional (final settlement slips), `applicable_days`, `taxable_income`,
  `tax_amount` (year-to-date tax), `released_at`, `is_manually_updated` (daily wages); statuses `ready, on_hold,
  released` (+ `paid_at`).
- payslip_line: `is_taxable` (snapshot), UNIQUE (payslip_id, pay_item_id).
- employee_account_entry: `pay_rule_id` (postings a rule made), `description`.
- voucher: UNIQUE (company_id, voucher_no) and (payroll_id, employee_id) (one daily-wage voucher per person),
  `file_id`, `remarks`, type `daily_wage`; `decided_by_user_id` (who approved or rejected) and
  `verified_by_user_id` (who verified), FK user_account, so the decider is kept when the account has no
  employee record.
- New **payroll_close_email** (one per closed monthly run: status, recipient_count, queued_at, sent_at) and
  **mail_outbox** (one row per person and e-mail: entity_type / entity_id, employee, address, subject, status
  disabled / queued / sent / failed, queued_at, sent_at, error) for P1 and P2.

## Decisions on unclear points

- **Where expressions run:** in Python, `app/services/payroll_expression.py`, a whitelisted AST evaluator in
  Decimal (numbers, + - * / % **, comparisons, and/or/not, `if(c,a,b)`, min, max, round, floor, ceil, abs;
  references only in braces). Gathering inputs and writing payslips stay set-based in procedures
  (`pay.usp_payroll_run_inputs` -> `payroll_engine.compute` -> `pay.usp_payroll_run_save`). Expressions are
  checked on save: syntax, unknown references, loops through formulas and pay items.
- **References:** `{name}` with the name lower-cased and non-alphanumerics as `_`; system variables (32, listed
  by `/settings/variables`) are reserved names.
- **System pay items** (added per company on first use, editable formulas, not deletable): Salary (`{gross_salary}
  * {employed_days} / {month_days}`), Overtime, Absent / Leave / Short / Penalty deductions (per-day and per-minute
  rates on the payroll's applicable days and the 480-minute or shift day), Loan Deduction, Leave Encashment, Tax.
- **Tax:** slab = highest slab whose minimum the annual income reaches; tax = fixed + % of the part above the
  minimum (the Pakistani "Rs X + Y% of the amount exceeding Z" form); surcharge % of tax or flat. Monthly tax
  projects the year: taxable already paid this tax year + this month's recurring taxable x months left + one-offs;
  rebates come off the year's tax; tax caused by one-off items with "Current Month" distribution is taken now, the
  rest is spread over the months left. Taxable deductions (absence etc.) reduce taxable income. FS settles the
  year's remaining tax at once unless "Disable Tax Distribution on Final Settlement".
- **Exclude Final Settlement from Payroll:** followed by its name (FRD p.166 says the opposite once): when on,
  leavers whose last working day falls in the month are skipped by the run (error log says why) and paid by FS.
- **Attendance:** days without a time sheet row are paid; absent = `absent`, half day = 0.5, short minutes =
  late + early-left; overtime = approved overtime minutes when the time sheet has them.
- **Close** releases ready slips, freezes the time sheet days (OQ C9), marks loan installments paid, links
  penalties and payroll leave encashments to the payslip, marks rule postings processed. Hold/unhold and Pay
  still work on a closed run (status only). Recalculate keeps hand-edited lines (FRD silent).
- **Nobody changes their own pay:** any payroll write whose target is the caller's own employee record is refused
  (403 `OWN_PAY_RECORD`), so own-scope grants of the Employee role cannot be used on pay screens.
- Daily wage rate = hr.employee_salary read with hr.employee.salary_frequency (hourly x hours worked, daily x
  day (half day 0.5), monthly / days in month x day).
- Leave encashment amount per day: given, or for basis "earned salary" a day's salary (monthly / 30); other bases
  need the amount (their sums are not defined).
- **Who did it:** `POST /payrolls/{id}/run` and `/daily-wages/{id}/process` return `runByUserId` / `runByName`
  like the history. Vouchers return `approvedByUserId` (approve or reject) and `verifiedByUserId` beside the
  employee ids; `approvedByName` / `verifiedByName` are the employee's name, else the account's display name
  (else its email). Names are built with `NULLIF(CONCAT_WS(...), '')`, so a missing name is null, never `" "`
  (e.g. a benefit member that is an employee group).
- **Daily Wages Summary report:** `employeeCount` is the people in the run the caller may see (same as the run's
  own count, before or after processing); worked minutes and net payable add up their payslips (0 until processed).
- **Salary revision list** carries `departmentName`, `locationName`, `branchName`, `jobTitleName`, `joiningDate`
  like the single record.
- **Voucher `voucherCode` filter** is a contains search (escaped `[`, `%`, `_`), like `q`.
- Final settlement: month of the last working day up to that day, every pay item, all unpaid installments,
  encashable leave balance (types with allow_encashment, within max) x monthly salary / days in month; the
  month's salary is left out when a monthly run already has a payslip for that month.

## Cross-module needs

- **Leave (lv):** `availed` ledger rows dated on the leave day (payroll counts them by month); `is_deductible`
  = unpaid leave; `lv.fn_leave_balance(employee_id, leave_type_id, fiscal_year)` scalar if provided (used
  through sp_executesql, ledger sum otherwise); leave configuration lives in core.company_setting module `payroll`.
- **Attendance (att):** day_status codes used above; `approved_overtime_minutes`, `expected_minutes`; do not
  change `is_frozen` days; `warning.deduction` (payroll/both) and `penalty_percentage` (100 = one day).
- **Loans:** installment `status` `pending`/`paid` (payroll writes paid, paid_amount, paid_at, payslip_id) and sets
  `loan.status = settled` when every installment is paid; `loan_type.deduction_pay_item_id` may be the system
  `loan_deduction` item.
- **Separation (sep):** payroll writes `sep.final_settlement` (status `open`/`closed`); off-boarding may mark the
  end of employment completed when FS is closed.
- **Employees (hr):** payroll writes `hr.employee_salary` rows (source `revision`/`import`, change_type `flat`/`percent`);
  reads `employee_pay_item`, `employment_period`, `employee_bank_account`, `salary_frequency`.
- **Default roles (core):** line managers / department heads exclude `payroll.*`, so manager approval of vouchers
  needs `payroll.vouchers.approve` (team scope) granted by a customer or added to those roles; recommend the
  Employee role exclude `payroll.*` except `payroll.payslips.view/download`, `payroll.employee_accounts.view`,
  `payroll.final_settlement.view` (its `*.create` own grants reach payroll screens; the backend refuses them on
  one's own record, but they should not be offered).
- number_sequence prefixes used: `PR-`, `TXS-`, `ACT-`, `VCH-`.
