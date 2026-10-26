-- Sessions (ACC-14): an administrator lists the sign-ins of the company's users and ends them;
-- the user is signed out on their next request, on web and mobile. Also the access change
-- history (ACC-15).

-- Result set 1: total. Result set 2: the page. @active_only: not ended and not expired.
CREATE OR ALTER PROCEDURE [auth].[usp_access_session_list]
    @company_id  BIGINT,
    @user_id     BIGINT = NULL,
    @active_only BIT = 1,
    @page        INT = 1,
    @page_size   INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    SELECT COUNT(*) AS total
    FROM [auth].[user_session] s
    JOIN [auth].[fn_access_company_users](@company_id) cu ON cu.id = s.user_account_id
    WHERE (@user_id IS NULL OR s.user_account_id = @user_id)
      AND (@active_only = 0 OR (s.revoked_at IS NULL AND (s.expires_at IS NULL OR s.expires_at > @now)));

    SELECT s.id, s.user_account_id, u.email,
           COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))), N''), u.display_name, u.email) AS user_name,
           s.device, s.ip_address, s.created_at AS signed_in_at, s.last_seen_at, s.expires_at, s.revoked_at,
           CAST(CASE WHEN s.revoked_at IS NULL AND (s.expires_at IS NULL OR s.expires_at > @now) THEN 1 ELSE 0 END AS BIT) AS is_active
    FROM [auth].[user_session] s
    JOIN [auth].[fn_access_company_users](@company_id) cu ON cu.id = s.user_account_id
    JOIN [auth].[user_account] u ON u.id = s.user_account_id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE (@user_id IS NULL OR s.user_account_id = @user_id)
      AND (@active_only = 0 OR (s.revoked_at IS NULL AND (s.expires_at IS NULL OR s.expires_at > @now)))
    ORDER BY s.last_seen_at DESC, s.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Ends one session (@id) or every open session of a user (@user_id). Returns how many ended.
CREATE OR ALTER PROCEDURE [auth].[usp_access_session_end]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @user_id       BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @id IS NOT NULL
        SET @user_id = (SELECT s.user_account_id FROM [auth].[user_session] s
                        JOIN [auth].[fn_access_company_users](@company_id) cu ON cu.id = s.user_account_id
                        WHERE s.id = @id);
    ELSE IF NOT EXISTS (SELECT 1 FROM [auth].[fn_access_company_users](@company_id) WHERE id = @user_id)
        SET @user_id = NULL;
    IF @user_id IS NULL
    BEGIN
        DECLARE @missing NVARCHAR(100) = CASE WHEN @id IS NULL THEN N'User not found' ELSE N'Session not found' END;
        THROW 50404, @missing, 1;
    END
    IF EXISTS (SELECT 1 FROM [auth].[user_account] WHERE id = @user_id AND is_system_admin = 1)
       AND ISNULL((SELECT is_system_admin FROM [auth].[user_account] WHERE id = @actor_user_id), 0) = 0
        THROW 50403, N'Only a system administrator can sign out a system administrator.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @ended INT;
    BEGIN TRAN;
        UPDATE [auth].[user_session] SET revoked_at = @now, updated_at = @now, updated_by = @actor_user_id
        WHERE user_account_id = @user_id AND revoked_at IS NULL AND (@id IS NULL OR id = @id);
        SET @ended = @@ROWCOUNT;
        IF @ended > 0
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'auth.user_account', @user_id, N'session', CONVERT(NVARCHAR(30), @ended), N'session_ended',
                    @actor_user_id, @now);
    COMMIT;

    SELECT @ended AS ended;
END
GO

-- Access change history: roles, users, their roles and grants. Result set 1: total. 2: the page.
CREATE OR ALTER PROCEDURE [auth].[usp_access_audit_list]
    @company_id  BIGINT,
    @entity_type NVARCHAR(50) = NULL,
    @entity_id   BIGINT = NULL,
    @page        INT = 1,
    @page_size   INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS total
    FROM [core].[audit_log] a
    WHERE a.company_id = @company_id AND a.entity_type IN (N'auth.role', N'auth.user_account')
      AND (@entity_type IS NULL OR a.entity_type = @entity_type) AND (@entity_id IS NULL OR a.entity_id = @entity_id);

    SELECT a.id, a.entity_type, a.entity_id,
           CASE a.entity_type WHEN N'auth.role' THEN r.name ELSE tu.email END AS entity_name,
           a.field_name, a.old_value, a.new_value, a.action_name, a.performed_at, a.performed_by_user_id,
           COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(pe.first_name, N' ', pe.last_name))), N''), pu.display_name, pu.email) AS performed_by_name
    FROM [core].[audit_log] a
    LEFT JOIN [auth].[role] r ON a.entity_type = N'auth.role' AND r.id = a.entity_id
    LEFT JOIN [auth].[user_account] tu ON a.entity_type = N'auth.user_account' AND tu.id = a.entity_id
    LEFT JOIN [auth].[user_account] pu ON pu.id = a.performed_by_user_id
    LEFT JOIN [hr].[employee] pe ON pe.id = pu.employee_id
    WHERE a.company_id = @company_id AND a.entity_type IN (N'auth.role', N'auth.user_account')
      AND (@entity_type IS NULL OR a.entity_type = @entity_type) AND (@entity_id IS NULL OR a.entity_id = @entity_id)
    ORDER BY a.performed_at DESC, a.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
