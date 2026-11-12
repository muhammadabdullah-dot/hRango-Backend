-- The daily "due tomorrow" and "now overdue" notices, run by scripts/nightly.py for each company. The
-- assignees of open tasks are told (notification and event types projects.task_due_tomorrow and
-- projects.task_overdue, linking to the task panel). pm.task_due_notice keeps what was sent, one row per
-- task, person, kind and due date, so a second run the same day (or one that overlaps) sends nothing
-- more, and a task whose due date moves is announced again for the new date.
-- Overdue covers tasks that fell due in the last 7 days: a missed night is caught up, but the first run
-- does not announce every old task. @today: the company's own date (att.fn_company_now) unless given
-- (tests, catch-up runs). Returns one row: notified (notices sent).
CREATE OR ALTER PROCEDURE [pm].[usp_task_due_notify]
    @company_id BIGINT,
    @today      DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @today = ISNULL(@today, CAST([att].[fn_company_now](@company_id) AS DATE));
    DECLARE @tomorrow DATE = DATEADD(DAY, 1, @today), @since DATE = DATEADD(DAY, -7, @today);

    DECLARE @claimed TABLE (task_id BIGINT, employee_id BIGINT, notice_kind NVARCHAR(30), due_date DATE,
                            PRIMARY KEY (task_id, notice_kind, employee_id));
    DECLARE @tasks TABLE (rn INT IDENTITY(1, 1) PRIMARY KEY, task_id BIGINT, notice_kind NVARCHAR(30));
    DECLARE @i INT = 1, @last INT, @task_id BIGINT, @kind NVARCHAR(30), @ws BIGINT, @code NVARCHAR(30),
            @name NVARCHAR(200), @due DATE, @event NVARCHAR(100), @title NVARCHAR(200), @body NVARCHAR(MAX),
            @link NVARCHAR(500), @payload NVARCHAR(MAX), @emp BIGINT;

    BEGIN TRAN;
        -- Claimed first; the range locks make an overlapping run wait and then find them taken.
        INSERT [pm].[task_due_notice] (task_id, employee_id, notice_kind, due_date)
        OUTPUT inserted.task_id, inserted.employee_id, inserted.notice_kind, inserted.due_date INTO @claimed
        SELECT t.id, a.employee_id, k.notice_kind, t.due_date
        FROM [pm].[task] t
        JOIN [pm].[workspace_status] s ON s.id = t.status_id
        JOIN [pm].[task_assignee] a ON a.task_id = t.id
        CROSS APPLY (SELECT CASE WHEN t.due_date = @tomorrow THEN N'due_tomorrow' ELSE N'overdue' END AS notice_kind) k
        WHERE t.company_id = @company_id
          AND s.status_group NOT IN (N'done', N'closed')
          AND (t.due_date = @tomorrow OR (t.due_date < @today AND t.due_date >= @since))
          AND NOT EXISTS (SELECT 1 FROM [pm].[task_due_notice] n WITH (UPDLOCK, HOLDLOCK)
                          WHERE n.task_id = t.id AND n.employee_id = a.employee_id AND n.notice_kind = k.notice_kind
                            AND n.due_date = t.due_date);

        -- One event per task and kind, and a notification to each assignee claimed for it.
        INSERT @tasks (task_id, notice_kind)
        SELECT DISTINCT task_id, notice_kind FROM @claimed ORDER BY task_id, notice_kind;
        SET @last = (SELECT COUNT(*) FROM @tasks);
        WHILE @i <= @last
        BEGIN
            SELECT @task_id = x.task_id, @kind = x.notice_kind, @ws = t.workspace_id, @code = t.code, @name = t.name,
                   @due = t.due_date
            FROM @tasks x JOIN [pm].[task] t ON t.id = x.task_id
            WHERE x.rn = @i;
            SET @event = CASE @kind WHEN N'due_tomorrow' THEN N'projects.task_due_tomorrow' ELSE N'projects.task_overdue' END;
            SET @title = LEFT(CONCAT(CASE @kind WHEN N'due_tomorrow' THEN N'Due tomorrow: ' ELSE N'Overdue: ' END,
                                     @code, N' ', @name), 200);
            SET @body = CASE @kind WHEN N'due_tomorrow' THEN CONCAT(N'This task is due on ', CONVERT(NVARCHAR(10), @due, 23), N'.')
                        ELSE CONCAT(N'This task was due on ', CONVERT(NVARCHAR(10), @due, 23), N' and is not done yet.') END;
            SET @link = CONCAT(N'/project-management/workspaces/', @ws, N'?task=', @task_id);
            SET @payload = (SELECT CONVERT(NVARCHAR(30), @task_id) AS taskId, @code AS code, @name AS name,
                                   CONVERT(NVARCHAR(30), @ws) AS workspaceId, CONVERT(NVARCHAR(10), @due, 23) AS dueDate,
                                   (SELECT CONVERT(NVARCHAR(30), c.employee_id) AS employeeId FROM @claimed c
                                    WHERE c.task_id = @task_id AND c.notice_kind = @kind FOR JSON PATH) AS assignees
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @event,
                 @entity_type = N'pm.task', @entity_id = @task_id, @payload = @payload;

            SET @emp = (SELECT MIN(employee_id) FROM @claimed WHERE task_id = @task_id AND notice_kind = @kind);
            WHILE @emp IS NOT NULL
            BEGIN
                EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @emp,
                     @title = @title, @body = @body, @notification_type = @event, @link = @link,
                     @entity_type = N'pm.task', @entity_id = @task_id;
                SET @emp = (SELECT MIN(employee_id) FROM @claimed WHERE task_id = @task_id AND notice_kind = @kind AND employee_id > @emp);
            END
            SET @i += 1;
        END
    COMMIT;

    SELECT COUNT(*) AS notified FROM @claimed;
END
