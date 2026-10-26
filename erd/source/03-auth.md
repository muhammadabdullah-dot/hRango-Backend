## 3. Users and access [auth]

```
user_account
  id                PK
  employee_id       FK employee       optional: blank for system users
  company_id        FK company        home company: the one active after sign-in
  display_name                        used when there is no employee
  email, password_hash
  is_active, is_system_admin

permission                            the catalogue: one row per view or button (module.screen.action)
  id                PK
  code                                leave.requests.approve
  module                              leave
  screen                              leave.requests
  action_code                         view, create, edit, delete, approve, reject, export, import ...
  label
  hint
  is_sensitive                        salary, bank, CNIC, loan and payslip figures
  sort_order

role                                  per company; default roles are copied in when a company is created
  id PK, company_id FK company, code, name, description, is_system, is_active

role_permission                       one tick on the role screen
  role_id FK role, permission_id FK permission, scope              own, team, department, branch, selected_units, company

role_permission_unit                  when scope = selected_units
  id PK, role_id FK role, permission_id FK permission, unit_type, unit_id       unit_type: branch, department, location

role_default_offer                    codes a default role has already been offered; one the customer removed is not offered again
  role_id FK role, permission_id FK permission

user_role
  user_account_id FK user_account, role_id FK role                  *──*

user_permission_override              a grant or a denial for one person in one company; a denial wins
  id                PK
  company_id        FK company
  user_account_id   FK user_account
  permission_id     FK permission
  effect                              grant, deny
  scope                               for grants
  reason

user_company                          which companies a user may see
  user_account_id FK user_account, company_id FK company

user_session                          one sign-in; the token names it, so ending it signs that device out
  id PK, user_account_id FK user_account, company_id FK company, refresh_token_hash, device, ip_address, last_seen_at, expires_at, revoked_at
```

```
user_account *──* role   (user_role)
permission 1──* role_permission *──1 role
role_permission 1──* role_permission_unit
user_account 1──* user_permission_override *──1 permission
user_account 1──* user_session
```
