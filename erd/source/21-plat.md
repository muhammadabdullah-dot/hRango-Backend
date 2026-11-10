## 21. Platform staff [plat]

The people who run hRango itself, not the people of a customer. Added 2026-11-02. They sign in through their own
address and tokens, are never in a customer's role list, and hold no customer data by default: entering a customer
will be logged support access (comparison/17-platform.md).

```
staff_account                         hRango's own people: Super Admin, Admin, Support, Billing
  id                PK
  email             {NN}
  display_name      {NN}
  password_hash     {NN}
  role              {NVARCHAR(30)} {NN}    super_admin, admin, support, billing
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
```
