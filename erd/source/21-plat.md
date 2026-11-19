## 21. Platform staff [plat]

The people who run hRango itself, not the people of a customer. Added 2026-11-02. They sign in through their own
address and tokens, are never in a customer's role list, and hold no customer data by default: entering a customer
will be logged support access (comparison/17-platform.md).

```
staff_account                         hRango's own people: Super Admin, Admin, Support, Billing, Sales
  id                PK
  email             {NN}
  display_name      {NN}
  password_hash     {NN}
  role              {NVARCHAR(30)} {NN}    super_admin, admin, support, billing, sales
  is_active         {NN}
  last_login_at     {NULL}
  UNIQUE (email)

staff_session                         one sign-in; revoked_at ends it at once
  id                PK
  staff_account_id  FK staff_account
  device            {NULL}
  ip_address        {NVARCHAR(45)} {NULL}
  expires_at        {NULL}
  revoked_at        {NULL}
  last_seen_at      {NULL}

staff_audit                           everything platform staff do; kept when the account goes
  id                PK
  staff_account_id  FK staff_account {NULL}
  action_name       {NVARCHAR(50)} {NN}
  entity_type       {NVARCHAR(50)} {NULL}
  entity_ref        {NVARCHAR(100)} {NULL}
  detail            {NVARCHAR(1000)} {NULL}
  ip_address        {NVARCHAR(45)} {NULL}
  INDEX (staff_account_id, created_at)

customer                              an organisation that uses hRango (shown as Organisations); owns one or more companies
  id                PK
  name              {NN}
  contact_name      {NVARCHAR(200)} {NULL}
  contact_email     {NVARCHAR(254)} {NN}
  contact_phone     {NVARCHAR(50)} {NULL}
  country           {NVARCHAR(100)} {NULL}
  status            {NVARCHAR(20)} {NN}    active, suspended, cancelled; anything but active stops its people signing in
  notes             {NVARCHAR(1000)} {NULL}
  billing_name      {NVARCHAR(200)} {NULL}   legal name on invoices (default: name)
  billing_email     {NVARCHAR(254)} {NULL}   invoices and reminders go here (default: contact_email)
  billing_address   {NVARCHAR(500)} {NULL}
  tax_number        {NVARCHAR(50)} {NULL}    NTN / STRN for tax invoices
  UNIQUE (name)

customer_company                      which customer owns which company
  id                PK
  customer_id       FK customer
  company_id        FK company
  UNIQUE (company_id)

plan                                  what a customer can buy (documents: Basic, Advanced, Premium; open question B6)
  id                PK
  name              {NN}
  description       {NVARCHAR(500)} {NULL}
  price_monthly     {DECIMAL(18,2)} {NN}
  price_annual      {DECIMAL(18,2)} {NN}
  employee_limit    {INT} {NULL}           NULL: no limit
  is_active         {NN}
  UNIQUE (name)

subscription                          a customer on a plan; at most one that is not cancelled. Amounts in PKR
  id                PK
  customer_id       FK customer
  plan_id           FK plan
  billing_cycle     {NVARCHAR(10)} {NN}    monthly, annual
  status            {NVARCHAR(20)} {NN}    trial, active, past_due, expired (trial ended unpaid), cancelled
  amount            {DECIMAL(18,2)} {NN}   per billing cycle
  start_date        {NN}
  renews_on         {DATE} {NULL}          next renewal; the end of a trial
  cancelled_on      {DATE} {NULL}
  access            {NVARCHAR(20)} {NN}    full, read_only, locked: what the customer's people may do (plat.usp_billing_run)
  access_since      {DATE} {NULL}
  INDEX (status)

invoice                               what a customer is billed; overdue is worked out from due_date
  id                PK
  number            {NVARCHAR(30)} {NN}
  customer_id       FK customer
  subscription_id   FK subscription {NULL}
  issue_date        {NN}
  due_date          {NN}
  amount            {DECIMAL(18,2)} {NN}
  status            {NVARCHAR(20)} {NN}    issued, paid, void
  paid_on           {DATE} {NULL}
  payment_reference {NVARCHAR(100)} {NULL}
  source            {NVARCHAR(20)} {NN}    manual (staff), renewal (issued by plat.usp_billing_run)
  period_start      {DATE} {NULL}          the subscription period it pays for
  period_end        {DATE} {NULL}
  UNIQUE (number)
  INDEX (status, due_date)

payment_submission                    a customer's "I paid by bank transfer" with its proof, for staff to confirm
  id                PK
  invoice_id        FK invoice
  customer_id       FK customer
  company_id        FK company               the company it was sent from (the proof file is that company's)
  submitted_by      FK user_account
  method            {NVARCHAR(30)} {NN}    bank_transfer
  reference         {NVARCHAR(100)} {NN}
  paid_on           {DATE} {NN}
  amount            {DECIMAL(18,2)} {NN}
  file_id           FK stored_file {NULL}
  note              {NVARCHAR(500)} {NULL}
  status            {NVARCHAR(20)} {NN}    pending, accepted, rejected
  review_note       {NVARCHAR(500)} {NULL}
  reviewed_by       FK staff_account {NULL}
  reviewed_at       {DATETIME2(0)} {NULL}
  INDEX (status)

billing_notice                        a billing e-mail sent once (trial ending, invoice due, overdue, read-only, locked)
  id                PK
  subscription_id   FK subscription
  invoice_id        FK invoice {NULL}
  kind              {NVARCHAR(40)} {NN}
  ref_date          {DATE} {NN}
  mailed_at         {DATETIME2(0)} {NULL}  when the e-mail was queued
  UNIQUE (subscription_id, kind, ref_date)

lead                                  a prospect in the sales pipeline
  id                PK
  company_name      {NVARCHAR(200)} {NN}
  contact_name      {NVARCHAR(200)} {NULL}
  contact_email     {NVARCHAR(254)} {NULL}
  contact_phone     {NVARCHAR(50)} {NULL}
  source            {NVARCHAR(50)} {NULL}  website, referral, event, outbound, other
  stage             {NVARCHAR(20)} {NN}    new, contacted, demo, proposal, won, lost
  employee_count    {INT} {NULL}
  expected_monthly  {DECIMAL(18,2)} {NULL}
  next_follow_up    {DATE} {NULL}
  notes             {NVARCHAR(1000)} {NULL}
  owner_staff_id    FK staff_account {NULL}
  customer_id       FK customer {NULL}     set when the lead becomes an organisation
  INDEX (stage)

ticket                                a support case from a customer; holds no HR data
  id                PK
  customer_id       FK customer
  subject           {NVARCHAR(200)} {NN}
  detail            {NVARCHAR(2000)} {NULL}
  priority          {NVARCHAR(10)} {NN}    low, normal, high, urgent
  status            {NVARCHAR(20)} {NN}    open, in_progress, resolved, closed
  assignee_staff_id FK staff_account {NULL}
  resolved_at       {NULL}
  INDEX (status)
```
