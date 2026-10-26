-- What still keeps a pending end of employment from completing, one row per item:
--   final_settlement   Final Settlement ticked and the settlement is not closed (payroll closes it)
--   asset_clearance    Asset Clearance ticked and no approved clearance form for this record
--   assets             Asset Clearance ticked and the employee still holds assets
--   checklist          a required field of an active off-boarding checklist has no answer
--   last_working_date  the last working date has not been reached
-- Empty for a completed record.
CREATE OR ALTER FUNCTION [sep].[fn_end_of_employment_waiting] (@id BIGINT)
RETURNS TABLE
AS RETURN
SELECT w.item, w.label, w.sort_order
FROM [sep].[end_of_employment] x
CROSS APPLY (
    SELECT N'final_settlement' AS item, N'Final settlement to be closed' AS label, 1 AS sort_order
    WHERE x.needs_final_settlement = 1
      AND NOT EXISTS (SELECT 1 FROM [sep].[final_settlement] fs WHERE fs.end_of_employment_id = x.id AND fs.status = N'closed')
    UNION ALL
    SELECT N'asset_clearance', N'Asset clearance to be approved', 2
    WHERE x.needs_asset_clearance = 1
      AND NOT EXISTS (SELECT 1 FROM [sep].[asset_clearance] c WHERE c.end_of_employment_id = x.id AND c.status = N'approved')
    UNION ALL
    SELECT N'assets', N'Assets still allocated to the employee', 3
    WHERE x.needs_asset_clearance = 1
      AND EXISTS (SELECT 1 FROM [sep].[asset_allocation] al WHERE al.employee_id = x.employee_id AND al.deallocated_on IS NULL)
    UNION ALL
    SELECT N'checklist', N'Required checklist answers', 4
    WHERE EXISTS (
        SELECT 1
        FROM [sep].[checklist_field] f
        JOIN [sep].[offboarding_checklist] k ON k.id = f.offboarding_checklist_id
        WHERE k.company_id = x.company_id AND k.is_active = 1 AND f.is_required = 1
          AND NOT EXISTS (SELECT 1 FROM [sep].[checklist_answer] a
                          WHERE a.end_of_employment_id = x.id AND a.checklist_field_id = f.id
                            AND NULLIF(LTRIM(RTRIM(a.answer)), N'') IS NOT NULL))
    UNION ALL
    SELECT N'last_working_date', N'Last working date not reached', 5
    WHERE x.last_working_date > CAST(SYSDATETIME() AS DATE)
) w
WHERE x.id = @id AND x.status = N'pending';
