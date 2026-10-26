## 13. Shared [core]

```
stored_file                           an uploaded file: the bytes on the server's disk, this row in the database
  id                PK
  company_id        FK company
  module            {NVARCHAR(30) NN}   the uploading module; also the folder it is stored in
  name              {NVARCHAR(255) NN}  the original file name, used for downloads only
  extension         {NVARCHAR(20) NN}
  mime_type         {NN}
  size_bytes        {NN}
  sha256            {CHAR(64) NN}
  storage_path      {NVARCHAR(500) NN}  relative to the upload root: <company>/<module>/<yyyy>/<mm>/<uuid>.<ext>
  uploaded_by_user_id FK user_account
  UNIQUE (storage_path)

attachment                            any file on any record
  id PK, company_id FK company, entity_type {NN}, entity_id {NN}, file_id FK stored_file, label
  UNIQUE (entity_type, entity_id, file_id)

audit_log                             every "History" popup reads this; also the access change history (ACC-15)
  id PK, company_id {NULL} FK company, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id FK user_account, performed_at

company_setting                       switches and values: attendance basic, the 22 payroll options, leave general, overtime
  id PK, company_id FK company, module, setting_key, setting_value

number_sequence                       codes like RQ-, PR-, AST-, TS-
  id PK, company_id FK company, prefix, next_number

filter_preset                         "Save Preset" on every list
  id PK, user_account_id FK user_account, screen, name, filters

notification                          the inbox; any module adds rows through core.usp_notification_add
  id PK, company_id FK company, user_account_id FK user_account, notification_type, title {NN}, body, link, entity_type, entity_id, read_at, cleared_at

webhook                               an outside system told about events (Settings → Integrations); signed with its secret
  id                PK
  company_id        FK company
  name
  url               {NVARCHAR(1000) NN}
  secret            {NVARCHAR(100) NN}  HMAC-SHA256 key; shown once when the webhook is created
  events            {NVARCHAR(MAX) NN}  JSON list of event types, "module.*" or "*"
  is_active
  failure_count     {INT NN}           consecutive failed deliveries
  last_delivery_at
  last_status_code  {INT}

outbox_event                          every event a module publishes, written in the same transaction as the change
  id                PK
  company_id        FK company
  event_type        {NVARCHAR(100) NN}  notification.created, request.approved ...
  entity_type
  entity_id
  payload           {NVARCHAR(MAX) NN}  JSON
  occurred_at       {NN}

webhook_delivery                      one event to one webhook, retried with back-off
  id                PK
  webhook_id        FK webhook
  outbox_event_id   FK outbox_event
  status                              pending, delivered, failed
  attempts          {INT NN}
  next_attempt_at
  last_attempt_at
  response_code     {INT}
  response_body     {NVARCHAR(2000)}
  error             {NVARCHAR(1000)}
  UNIQUE (webhook_id, outbox_event_id)
```

```
stored_file 1──* attachment
webhook 1──* webhook_delivery *──1 outbox_event
```
