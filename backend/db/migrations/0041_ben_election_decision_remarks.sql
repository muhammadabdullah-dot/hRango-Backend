-- A benefit election kept one remarks column for both the employee's note to HR and HR's remarks on the
-- decision: a rejection without remarks left the employee's note there, and My Benefits showed it under "HR's
-- reason" (Test Run 18-19 Nov 2026, row 12.21). decision_remarks now holds what HR says when approving or
-- rejecting (required to reject); remarks stays the employee's note. Checks first, like 0002, so it also runs
-- on a baseline rebuilt from the ERD.

IF COL_LENGTH(N'ben.election', N'decision_remarks') IS NULL
    ALTER TABLE [ben].[election] ADD [decision_remarks] NVARCHAR(MAX) NULL;
GO

-- Elections decided before this: HR's remarks went to the employee as the body of the decision's notification
-- (none when HR gave none) and replaced the note in remarks. Take them from there, and clear remarks where it
-- holds HR's words rather than the employee's (the note they replaced is gone). The decision's notification is
-- the first one written with it (a few seconds' slack for rounding to whole seconds).
UPDATE e
SET decision_remarks = n.body,
    remarks = CASE WHEN e.remarks = n.body THEN NULL ELSE e.remarks END
FROM [ben].[election] e
CROSS APPLY (SELECT TOP 1 x.body
             FROM [core].[notification] x
             WHERE x.entity_type = N'ben.election' AND x.entity_id = e.id AND x.notification_type = N'benefits'
               AND x.created_at >= DATEADD(SECOND, -5, e.decided_at)
             ORDER BY x.created_at, x.id) n
WHERE e.status IN (N'approved', N'rejected') AND e.decision_remarks IS NULL
  AND NULLIF(LTRIM(RTRIM(n.body)), N'') IS NOT NULL;
