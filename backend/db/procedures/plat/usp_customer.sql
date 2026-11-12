-- Organisations that use hRango (plat.customer) and the companies they own. Holds no HR data: head counts only.

CREATE OR ALTER PROCEDURE [plat].[usp_customer_get]
    @id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.id, c.name, c.contact_name, c.contact_email, c.contact_phone, c.country, c.status, c.notes,
           c.created_at, c.updated_at, c.row_version,
           (SELECT COUNT(*) FROM [plat].[customer_company] cc WHERE cc.customer_id = c.id) AS company_count,
           (SELECT COUNT(*) FROM [plat].[customer_company] cc
            JOIN [hr].[employee] e ON e.company_id = cc.company_id AND e.status <> N'left'
            WHERE cc.customer_id = c.id) AS employee_count,
           s.plan_name, s.status AS subscription_status, s.renews_on
    FROM [plat].[customer] c
    OUTER APPLY (SELECT TOP 1 p.name AS plan_name, x.status, x.renews_on
                 FROM [plat].[subscription] x JOIN [plat].[plan] p ON p.id = x.plan_id
                 WHERE x.customer_id = c.id AND x.status <> N'cancelled' ORDER BY x.id DESC) s
    WHERE c.id = @id;
    IF @@ROWCOUNT = 0
        THROW 50404, N'Organisation not found', 1;
END
GO

-- Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [plat].[usp_customer_list]
    @search    NVARCHAR(200) = NULL,
    @status    NVARCHAR(20) = NULL,
    @page      INT = 1,
    @page_size INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [plat].[customer] c
    WHERE (@status IS NULL OR c.status = @status)
      AND (@pattern IS NULL OR c.name LIKE @pattern OR c.contact_email LIKE @pattern);

    SELECT c.id, c.name, c.contact_name, c.contact_email, c.contact_phone, c.country, c.status, c.notes,
           c.created_at, c.updated_at, c.row_version,
           (SELECT COUNT(*) FROM [plat].[customer_company] cc WHERE cc.customer_id = c.id) AS company_count,
           (SELECT COUNT(*) FROM [plat].[customer_company] cc
            JOIN [hr].[employee] e ON e.company_id = cc.company_id AND e.status <> N'left'
            WHERE cc.customer_id = c.id) AS employee_count,
           s.plan_name, s.status AS subscription_status, s.renews_on
    FROM [plat].[customer] c
    OUTER APPLY (SELECT TOP 1 p.name AS plan_name, x.status, x.renews_on
                 FROM [plat].[subscription] x JOIN [plat].[plan] p ON p.id = x.plan_id
                 WHERE x.customer_id = c.id AND x.status <> N'cancelled' ORDER BY x.id DESC) s
    WHERE (@status IS NULL OR c.status = @status)
      AND (@pattern IS NULL OR c.name LIKE @pattern OR c.contact_email LIKE @pattern)
    ORDER BY c.created_at DESC, c.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_customer_companies]
    @id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT co.id, co.name, co.is_active,
           (SELECT COUNT(*) FROM [hr].[employee] e WHERE e.company_id = co.id AND e.status <> N'left') AS employee_count
    FROM [plat].[customer_company] cc
    JOIN [org].[company] co ON co.id = cc.company_id
    WHERE cc.customer_id = @id
    ORDER BY co.name;
END
GO

-- Run first when registering: both of these would otherwise take over what is already there, because
-- org.usp_company_provision returns a company of that name and auth.usp_user_provision resets a known email.
CREATE OR ALTER PROCEDURE [plat].[usp_customer_register_check]
    @name        NVARCHAR(200),
    @owner_email NVARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name = N''
        THROW 50400, N'name|Enter the organisation name.', 1;
    IF EXISTS (SELECT 1 FROM [plat].[customer] WHERE name = @name) OR EXISTS (SELECT 1 FROM [org].[company] WHERE name = @name)
        THROW 50409, N'name|CUSTOMER_DUPLICATE|An organisation with this name is already registered.', 1;
    IF EXISTS (SELECT 1 FROM [auth].[user_account] WHERE email = LOWER(LTRIM(RTRIM(@owner_email))))
        THROW 50409, N'ownerEmail|OWNER_EMAIL_TAKEN|This email already signs in to hRango.', 1;
END
GO

-- The customer record for a company that has just been provisioned. @lead_id closes the lead it came from.
CREATE OR ALTER PROCEDURE [plat].[usp_customer_add]
    @actor_id      BIGINT = NULL,
    @company_id    BIGINT,
    @name          NVARCHAR(200),
    @contact_name  NVARCHAR(200) = NULL,
    @contact_email NVARCHAR(254),
    @contact_phone NVARCHAR(50) = NULL,
    @country       NVARCHAR(100) = NULL,
    @notes         NVARCHAR(1000) = NULL,
    @lead_id       BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @id BIGINT, @ref NVARCHAR(100), @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [plat].[customer] (name, contact_name, contact_email, contact_phone, country, status, notes, created_by)
        VALUES (LTRIM(RTRIM(@name)), @contact_name, LOWER(LTRIM(RTRIM(@contact_email))), @contact_phone, @country,
                N'active', @notes, @actor_id);
        SET @id = SCOPE_IDENTITY();
        INSERT [plat].[customer_company] (customer_id, company_id, created_by) VALUES (@id, @company_id, @actor_id);
        IF @lead_id IS NOT NULL
            UPDATE [plat].[lead] SET stage = N'won', customer_id = @id, updated_at = @now, updated_by = @actor_id
            WHERE id = @lead_id;
        SET @ref = CONVERT(NVARCHAR(30), @id);
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = N'organisation_registered',
             @entity_type = N'customer', @entity_ref = @ref, @detail = @name;
    COMMIT;
    EXEC [plat].[usp_customer_get] @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_customer_save]
    @actor_id      BIGINT,
    @id            BIGINT,
    @name          NVARCHAR(200),
    @contact_name  NVARCHAR(200) = NULL,
    @contact_email NVARCHAR(254),
    @contact_phone NVARCHAR(50) = NULL,
    @country       NVARCHAR(100) = NULL,
    @notes         NVARCHAR(1000) = NULL,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [plat].[customer] WHERE id = @id)
        THROW 50404, N'Organisation not found', 1;
    IF EXISTS (SELECT 1 FROM [plat].[customer] WHERE name = LTRIM(RTRIM(@name)) AND id <> @id)
        THROW 50409, N'name|CUSTOMER_DUPLICATE|An organisation with this name is already registered.', 1;

    DECLARE @ref NVARCHAR(100) = CONVERT(NVARCHAR(30), @id);
    BEGIN TRAN;
        UPDATE [plat].[customer]
        SET name = LTRIM(RTRIM(@name)), contact_name = @contact_name, contact_email = LOWER(LTRIM(RTRIM(@contact_email))),
            contact_phone = @contact_phone, country = @country, notes = @notes,
            updated_at = SYSUTCDATETIME(), updated_by = @actor_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this organisation. Reload and try again', 1;
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = N'organisation_changed',
             @entity_type = N'customer', @entity_ref = @ref, @detail = @name;
    COMMIT;
    EXEC [plat].[usp_customer_get] @id = @id;
END
GO

-- Suspended or cancelled: its people cannot sign in, and open sessions stop at once (auth.usp_session_context).
CREATE OR ALTER PROCEDURE [plat].[usp_customer_status_set]
    @actor_id    BIGINT,
    @id          BIGINT,
    @status      NVARCHAR(20),
    @row_version BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @status NOT IN (N'active', N'suspended', N'cancelled')
        THROW 50400, N'status|Choose active, suspended or cancelled.', 1;
    IF NOT EXISTS (SELECT 1 FROM [plat].[customer] WHERE id = @id)
        THROW 50404, N'Organisation not found', 1;

    DECLARE @ref NVARCHAR(100) = CONVERT(NVARCHAR(30), @id), @action NVARCHAR(50) = N'organisation_' + @status;
    BEGIN TRAN;
        UPDATE [plat].[customer]
        SET status = @status, updated_at = SYSUTCDATETIME(), updated_by = @actor_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this organisation. Reload and try again', 1;
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = @action,
             @entity_type = N'customer', @entity_ref = @ref;
    COMMIT;
    EXEC [plat].[usp_customer_get] @id = @id;
END
GO
