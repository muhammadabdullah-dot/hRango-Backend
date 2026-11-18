-- Slowing down password guessing (BE-07), for customer sign-in (@realm 'customer') and platform staff
-- ('staff'). Failed attempts in the last 15 minutes count against three limits:
--   one email from one address        5   (cleared by a successful sign-in from that address)
--   one email from any address       20   (a guess spread over many machines)
--   one address against any email    50   (one machine trying many accounts; an office behind one
--                                          address stays well under this)
-- Past a limit, sign-in from there waits until 15 minutes after the last failure. Attempts refused
-- by the limit are not recorded, so they do not extend the wait.

-- @retry_after_seconds: 0 = go ahead, otherwise how long to wait.
CREATE OR ALTER PROCEDURE [auth].[usp_login_throttle_check]
    @realm      NVARCHAR(20),
    @email      NVARCHAR(254),
    @ip_address NVARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @since DATETIME2(0) = DATEADD(MINUTE, -15, @now);
    DECLARE @pair_since DATETIME2(0) = (
        SELECT MAX(attempted_at) FROM [auth].[login_attempt]
        WHERE realm = @realm AND email = @email AND ISNULL(ip_address, N'') = ISNULL(@ip_address, N'')
          AND succeeded = 1 AND attempted_at >= @since);
    SET @pair_since = ISNULL(@pair_since, @since);

    DECLARE @pair INT, @pair_last DATETIME2(0), @account INT, @account_last DATETIME2(0), @address INT, @address_last DATETIME2(0);

    SELECT @pair = COUNT(*), @pair_last = MAX(attempted_at)
    FROM [auth].[login_attempt]
    WHERE realm = @realm AND email = @email AND ISNULL(ip_address, N'') = ISNULL(@ip_address, N'')
      AND succeeded = 0 AND attempted_at > @pair_since;

    SELECT @account = COUNT(*), @account_last = MAX(attempted_at)
    FROM [auth].[login_attempt]
    WHERE realm = @realm AND email = @email AND succeeded = 0 AND attempted_at >= @since;

    SELECT @address = COUNT(*), @address_last = MAX(attempted_at)
    FROM [auth].[login_attempt]
    WHERE @ip_address IS NOT NULL AND realm = @realm AND ip_address = @ip_address AND succeeded = 0 AND attempted_at >= @since;

    DECLARE @until DATETIME2(0) = (
        SELECT MAX(u) FROM (VALUES
            (CASE WHEN @pair >= 5 THEN DATEADD(MINUTE, 15, @pair_last) END),
            (CASE WHEN @account >= 20 THEN DATEADD(MINUTE, 15, @account_last) END),
            (CASE WHEN @address >= 50 THEN DATEADD(MINUTE, 15, @address_last) END)) v (u));

    SELECT CASE WHEN @until > @now THEN DATEDIFF(SECOND, @now, @until) ELSE 0 END AS retry_after_seconds;
END
GO

-- Records one checked password, and clears out attempts older than a day as it goes.
CREATE OR ALTER PROCEDURE [auth].[usp_login_attempt_add]
    @realm      NVARCHAR(20),
    @email      NVARCHAR(254),
    @ip_address NVARCHAR(45) = NULL,
    @succeeded  BIT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT [auth].[login_attempt] (realm, email, ip_address, succeeded)
    VALUES (@realm, LEFT(@email, 254), @ip_address, @succeeded);
    DELETE TOP (200) FROM [auth].[login_attempt] WHERE attempted_at < DATEADD(DAY, -1, SYSUTCDATETIME());
END
GO
