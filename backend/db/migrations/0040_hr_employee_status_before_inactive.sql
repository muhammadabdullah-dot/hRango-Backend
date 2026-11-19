-- Reactivate always set the status to active, so someone switched off while on probation (or serving notice)
-- came back active and lost the probation (Test Run 18-19 Nov 2026, row 3.22). status_before_inactive keeps the
-- status a person had when HR switched them off; hr.usp_employee_active_set restores it on Reactivate and clears
-- it. Checks first, like 0002, so it also runs on a baseline rebuilt from the ERD.

IF COL_LENGTH(N'hr.employee', N'status_before_inactive') IS NULL
    ALTER TABLE [hr].[employee] ADD [status_before_inactive] NVARCHAR(30) NULL;
GO

-- People switched off before this change: the status their switch-off recorded in the audit log; failing that,
-- probation while their probation has not ended and they are not confirmed; otherwise active.
UPDATE e
SET status_before_inactive = COALESCE(a.old_value,
        CASE WHEN p.probation_end_date >= CAST(SYSUTCDATETIME() AS DATE) AND p.confirmation_date IS NULL
             THEN N'probation' ELSE N'active' END)
FROM [hr].[employee] e
OUTER APPLY (SELECT TOP 1 l.old_value
             FROM [core].[audit_log] l
             WHERE l.entity_type = N'hr.employee' AND l.entity_id = e.id AND l.field_name = N'status'
               AND l.action_name = N'deactivate' AND l.old_value IN (N'active', N'probation', N'notice')
             ORDER BY l.performed_at DESC, l.id DESC) a
OUTER APPLY (SELECT TOP 1 x.probation_end_date, x.confirmation_date
             FROM [hr].[employment_period] x
             WHERE x.employee_id = e.id
             ORDER BY x.joining_date DESC, x.id DESC) p
WHERE e.status = N'inactive' AND e.status_before_inactive IS NULL;
