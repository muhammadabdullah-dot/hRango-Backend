-- The sales pipeline, support cases, the staff lookup and the platform dashboard.

CREATE OR ALTER PROCEDURE [plat].[usp_staff_lookup]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id, display_name, role FROM [plat].[staff_account] WHERE is_active = 1 ORDER BY display_name, id;
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_lead_get]
    @id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.id, l.company_name, l.contact_name, l.contact_email, l.contact_phone, l.source, l.stage, l.employee_count,
           l.expected_monthly, l.next_follow_up, l.notes, l.owner_staff_id, a.display_name AS owner_name, l.customer_id,
           l.created_at, l.updated_at, l.row_version
    FROM [plat].[lead] l LEFT JOIN [plat].[staff_account] a ON a.id = l.owner_staff_id
    WHERE l.id = @id;
    IF @@ROWCOUNT = 0
        THROW 50404, N'Lead not found', 1;
END
GO

-- Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [plat].[usp_lead_list]
    @search    NVARCHAR(200) = NULL,
    @stage     NVARCHAR(20) = NULL,
    @page      INT = 1,
    @page_size INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [plat].[lead] l
    WHERE (@stage IS NULL OR l.stage = @stage)
      AND (@pattern IS NULL OR l.company_name LIKE @pattern OR l.contact_name LIKE @pattern OR l.contact_email LIKE @pattern);

    SELECT l.id, l.company_name, l.contact_name, l.contact_email, l.contact_phone, l.source, l.stage, l.employee_count,
           l.expected_monthly, l.next_follow_up, l.notes, l.owner_staff_id, a.display_name AS owner_name, l.customer_id,
           l.created_at, l.updated_at, l.row_version
    FROM [plat].[lead] l LEFT JOIN [plat].[staff_account] a ON a.id = l.owner_staff_id
    WHERE (@stage IS NULL OR l.stage = @stage)
      AND (@pattern IS NULL OR l.company_name LIKE @pattern OR l.contact_name LIKE @pattern OR l.contact_email LIKE @pattern)
    ORDER BY CASE WHEN l.stage IN (N'won', N'lost') THEN 1 ELSE 0 END, l.next_follow_up, l.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_lead_save]
    @actor_id         BIGINT = NULL,
    @id               BIGINT = NULL,
    @company_name     NVARCHAR(200),
    @contact_name     NVARCHAR(200) = NULL,
    @contact_email    NVARCHAR(254) = NULL,
    @contact_phone    NVARCHAR(50) = NULL,
    @source           NVARCHAR(50) = NULL,
    @stage            NVARCHAR(20),
    @employee_count   INT = NULL,
    @expected_monthly DECIMAL(18,2) = NULL,
    @next_follow_up   DATE = NULL,
    @notes            NVARCHAR(1000) = NULL,
    @owner_staff_id   BIGINT = NULL,
    @row_version      BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @company_name = LTRIM(RTRIM(@company_name));
    IF @company_name = N''
        THROW 50400, N'companyName|Enter the company name.', 1;
    IF @stage NOT IN (N'new', N'contacted', N'demo', N'proposal', N'won', N'lost')
        THROW 50400, N'stage|Choose a stage.', 1;
    IF @owner_staff_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [plat].[staff_account] WHERE id = @owner_staff_id)
        THROW 50400, N'ownerStaffId|Choose a staff member.', 1;

    DECLARE @action NVARCHAR(50) = CASE WHEN @id IS NULL THEN N'lead_added' ELSE N'lead_changed' END, @ref NVARCHAR(100);
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [plat].[lead] (company_name, contact_name, contact_email, contact_phone, source, stage, employee_count,
                                  expected_monthly, next_follow_up, notes, owner_staff_id, created_by)
            VALUES (@company_name, @contact_name, @contact_email, @contact_phone, @source, @stage, @employee_count,
                    @expected_monthly, @next_follow_up, @notes, @owner_staff_id, @actor_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE [plat].[lead]
            SET company_name = @company_name, contact_name = @contact_name, contact_email = @contact_email,
                contact_phone = @contact_phone, source = @source, stage = @stage, employee_count = @employee_count,
                expected_monthly = @expected_monthly, next_follow_up = @next_follow_up, notes = @notes,
                owner_staff_id = @owner_staff_id, updated_at = SYSUTCDATETIME(), updated_by = @actor_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this lead. Reload and try again', 1;
        END
        SET @ref = CONVERT(NVARCHAR(30), @id);
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = @action,
             @entity_type = N'lead', @entity_ref = @ref, @detail = @stage;
    COMMIT;
    EXEC [plat].[usp_lead_get] @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_ticket_get]
    @id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.id, t.customer_id, c.name AS customer_name, t.subject, t.detail, t.priority, t.status, t.assignee_staff_id,
           a.display_name AS assignee_name, t.resolved_at, t.created_at, t.updated_at, t.row_version
    FROM [plat].[ticket] t
    JOIN [plat].[customer] c ON c.id = t.customer_id
    LEFT JOIN [plat].[staff_account] a ON a.id = t.assignee_staff_id
    WHERE t.id = @id;
    IF @@ROWCOUNT = 0
        THROW 50404, N'Ticket not found', 1;
END
GO

-- Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [plat].[usp_ticket_list]
    @search      NVARCHAR(200) = NULL,
    @status      NVARCHAR(20) = NULL,
    @customer_id BIGINT = NULL,
    @page        INT = 1,
    @page_size   INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [plat].[ticket] t JOIN [plat].[customer] c ON c.id = t.customer_id
    WHERE (@status IS NULL OR t.status = @status) AND (@customer_id IS NULL OR t.customer_id = @customer_id)
      AND (@pattern IS NULL OR t.subject LIKE @pattern OR c.name LIKE @pattern);

    SELECT t.id, t.customer_id, c.name AS customer_name, t.subject, t.detail, t.priority, t.status, t.assignee_staff_id,
           a.display_name AS assignee_name, t.resolved_at, t.created_at, t.updated_at, t.row_version
    FROM [plat].[ticket] t
    JOIN [plat].[customer] c ON c.id = t.customer_id
    LEFT JOIN [plat].[staff_account] a ON a.id = t.assignee_staff_id
    WHERE (@status IS NULL OR t.status = @status) AND (@customer_id IS NULL OR t.customer_id = @customer_id)
      AND (@pattern IS NULL OR t.subject LIKE @pattern OR c.name LIKE @pattern)
    ORDER BY CASE WHEN t.status IN (N'resolved', N'closed') THEN 1 ELSE 0 END,
             CASE t.priority WHEN N'urgent' THEN 0 WHEN N'high' THEN 1 WHEN N'normal' THEN 2 ELSE 3 END, t.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_ticket_save]
    @actor_id          BIGINT = NULL,
    @id                BIGINT = NULL,
    @customer_id       BIGINT,
    @subject           NVARCHAR(200),
    @detail            NVARCHAR(2000) = NULL,
    @priority          NVARCHAR(10),
    @status            NVARCHAR(20),
    @assignee_staff_id BIGINT = NULL,
    @row_version       BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @subject = LTRIM(RTRIM(@subject));
    IF @subject = N''
        THROW 50400, N'subject|Enter the subject.', 1;
    IF @priority NOT IN (N'low', N'normal', N'high', N'urgent')
        THROW 50400, N'priority|Choose a priority.', 1;
    IF @status NOT IN (N'open', N'in_progress', N'resolved', N'closed')
        THROW 50400, N'status|Choose a status.', 1;
    IF NOT EXISTS (SELECT 1 FROM [plat].[customer] WHERE id = @customer_id)
        THROW 50400, N'customerId|Choose an organisation.', 1;
    IF @assignee_staff_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [plat].[staff_account] WHERE id = @assignee_staff_id)
        THROW 50400, N'assigneeStaffId|Choose a staff member.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @ref NVARCHAR(100),
            @action NVARCHAR(50) = CASE WHEN @id IS NULL THEN N'ticket_added' ELSE N'ticket_changed' END,
            @done BIT = CASE WHEN @status IN (N'resolved', N'closed') THEN 1 ELSE 0 END;
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [plat].[ticket] (customer_id, subject, detail, priority, status, assignee_staff_id, resolved_at, created_by)
            VALUES (@customer_id, @subject, @detail, @priority, @status, @assignee_staff_id,
                    CASE WHEN @done = 1 THEN @now END, @actor_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE [plat].[ticket]
            SET customer_id = @customer_id, subject = @subject, detail = @detail, priority = @priority, status = @status,
                assignee_staff_id = @assignee_staff_id,
                resolved_at = CASE WHEN @done = 1 THEN COALESCE(resolved_at, @now) END,
                updated_at = @now, updated_by = @actor_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this ticket. Reload and try again', 1;
        END
        SET @ref = CONVERT(NVARCHAR(30), @id);
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = @action,
             @entity_type = N'ticket', @entity_ref = @ref, @detail = @status;
    COMMIT;
    EXEC [plat].[usp_ticket_get] @id = @id;
END
GO

-- Sets: figures; organisations by sign-up month (12 months); subscriptions per plan; leads per stage; renewals due.
-- Monthly recurring revenue counts active and past-due subscriptions, an annual amount as a twelfth a month.
CREATE OR ALTER PROCEDURE [plat].[usp_dashboard]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today DATE = CONVERT(DATE, SYSUTCDATETIME());
    DECLARE @month DATE = DATEFROMPARTS(YEAR(@today), MONTH(@today), 1);

    SELECT
        (SELECT COUNT(*) FROM [plat].[customer]) AS organisations,
        (SELECT COUNT(*) FROM [plat].[customer] WHERE status = N'active') AS active_organisations,
        (SELECT COUNT(*) FROM [plat].[customer] WHERE status = N'suspended') AS suspended_organisations,
        (SELECT COUNT(*) FROM [plat].[customer] WHERE status = N'cancelled') AS cancelled_organisations,
        (SELECT COUNT(*) FROM [plat].[customer] WHERE created_at >= @month) AS new_this_month,
        (SELECT COUNT(*) FROM [plat].[customer_company] cc JOIN [hr].[employee] e ON e.company_id = cc.company_id
         WHERE e.status <> N'left') AS employees,
        (SELECT COUNT(*) FROM [plat].[subscription] WHERE status = N'trial') AS trials,
        (SELECT COUNT(*) FROM [plat].[subscription] WHERE status = N'active') AS paying_subscriptions,
        (SELECT COUNT(*) FROM [plat].[subscription] WHERE status = N'past_due') AS past_due_subscriptions,
        (SELECT ISNULL(SUM(CASE WHEN billing_cycle = N'annual' THEN amount / 12 ELSE amount END), 0)
         FROM [plat].[subscription] WHERE status IN (N'active', N'past_due')) AS monthly_revenue,
        (SELECT COUNT(*) FROM [plat].[invoice] WHERE status = N'issued' AND due_date < @today) AS overdue_invoices,
        (SELECT ISNULL(SUM(amount), 0) FROM [plat].[invoice] WHERE status = N'issued' AND due_date < @today) AS overdue_amount,
        (SELECT ISNULL(SUM(amount), 0) FROM [plat].[invoice] WHERE status = N'paid' AND paid_on >= @month) AS paid_this_month,
        (SELECT COUNT(*) FROM [plat].[lead] WHERE stage NOT IN (N'won', N'lost')) AS open_leads,
        (SELECT ISNULL(SUM(expected_monthly), 0) FROM [plat].[lead] WHERE stage NOT IN (N'won', N'lost')) AS pipeline_monthly,
        (SELECT COUNT(*) FROM [plat].[ticket] WHERE status IN (N'open', N'in_progress')) AS open_tickets,
        (SELECT COUNT(*) FROM [plat].[ticket] WHERE status IN (N'open', N'in_progress') AND priority = N'urgent') AS urgent_tickets;

    ;WITH months AS (
        SELECT DATEADD(MONTH, -11, @month) AS m
        UNION ALL SELECT DATEADD(MONTH, 1, m) FROM months WHERE m < @month
    )
    SELECT CONVERT(CHAR(7), m.m, 120) AS month,
           (SELECT COUNT(*) FROM [plat].[customer] c
            WHERE c.created_at >= m.m AND c.created_at < DATEADD(MONTH, 1, m.m)) AS organisations
    FROM months m ORDER BY m.m;

    SELECT p.name AS [plan], COUNT(s.id) AS subscriptions
    FROM [plat].[plan] p
    LEFT JOIN [plat].[subscription] s ON s.plan_id = p.id AND s.status <> N'cancelled'
    GROUP BY p.name, p.price_monthly
    ORDER BY p.price_monthly, p.name;

    SELECT s.stage, COUNT(l.id) AS leads, ISNULL(SUM(l.expected_monthly), 0) AS monthly
    FROM (VALUES (N'new', 1), (N'contacted', 2), (N'demo', 3), (N'proposal', 4), (N'won', 5), (N'lost', 6)) s(stage, position)
    LEFT JOIN [plat].[lead] l ON l.stage = s.stage
    GROUP BY s.stage, s.position
    ORDER BY s.position;

    SELECT TOP 6 s.id, c.id AS customer_id, c.name AS customer_name, p.name AS plan_name, s.status, s.renews_on, s.amount
    FROM [plat].[subscription] s
    JOIN [plat].[customer] c ON c.id = s.customer_id
    JOIN [plat].[plan] p ON p.id = s.plan_id
    WHERE s.status <> N'cancelled' AND s.renews_on IS NOT NULL AND s.renews_on <= DATEADD(DAY, 30, @today)
    ORDER BY s.renews_on, s.id;
END
GO
