-- Self-service sign-up (roadmap 1.1), called by app/services/signup_service.py inside one transaction after
-- org.usp_company_provision and the default roles. The owner gets no password: the e-mail link
-- (auth.user_token, purpose invite) both proves the address and lets them choose one.

-- A free customer name: the company name, or "Name (2)", "Name (3)" ... when another organisation has it.
-- Customer names are only seen by platform staff; the company keeps the name the person typed.
CREATE OR ALTER PROCEDURE [plat].[usp_customer_name_free]
    @name NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET @name = LTRIM(RTRIM(@name));
    DECLARE @try NVARCHAR(200) = @name, @n INT = 2;
    WHILE EXISTS (SELECT 1 FROM [plat].[customer] WHERE name = @try)
    BEGIN
        SET @try = CONCAT(LEFT(@name, 190), N' (', @n, N')');
        SET @n += 1;
    END
    SELECT @try AS name;
END
GO

-- The Account Owner of a new organisation. Unlike auth.usp_user_provision (the installer's, which resets a
-- known email), this never touches an existing account: an email that already signs in is refused.
CREATE OR ALTER PROCEDURE [plat].[usp_signup_owner_add]
    @company_id    BIGINT,
    @email         NVARCHAR(254),
    @display_name  NVARCHAR(200),
    @password_hash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @email = LOWER(LTRIM(RTRIM(@email)));
    DECLARE @id BIGINT;
    BEGIN TRAN;
        IF EXISTS (SELECT 1 FROM [auth].[user_account] WITH (UPDLOCK, HOLDLOCK) WHERE email = @email)
            THROW 50409, N'ownerEmail|OWNER_EMAIL_TAKEN|This email already signs in to hRango.', 1;
        INSERT [auth].[user_account] (employee_id, company_id, display_name, email, password_hash, is_active, is_account_owner)
        VALUES (NULL, @company_id, LTRIM(RTRIM(@display_name)), @email, @password_hash, 1, 1);
        SET @id = SCOPE_IDENTITY();
        INSERT [auth].[user_company] (user_account_id, company_id) VALUES (@id, @company_id);
        INSERT [auth].[user_role] (user_account_id, role_id)
        SELECT @id, r.id FROM [auth].[role] r WHERE r.company_id = @company_id AND r.code = N'company_admin';
        IF @@ROWCOUNT = 0
            THROW 50500, N'The company has no Company Administrator role yet.', 1;
    COMMIT;
    SELECT @id AS user_id;
END
GO

-- The plans a visitor may choose from on the sign-up page: active ones only, without internal figures.
CREATE OR ALTER PROCEDURE [plat].[usp_plan_public_list]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.id, p.name, p.description, p.price_monthly, p.price_annual, p.employee_limit
    FROM [plat].[plan] p
    WHERE p.is_active = 1
    ORDER BY p.price_monthly, p.name;
END
GO
