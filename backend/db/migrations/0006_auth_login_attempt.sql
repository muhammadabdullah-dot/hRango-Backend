-- Sign-in attempts, for slowing down password guessing (BE-07). One row per checked password, customer
-- or platform staff (realm). auth.usp_login_throttle_check reads the last 15 minutes; rows older than a
-- day are removed as new ones arrive (auth.usp_login_attempt_add). Checks first, like 0002, so it also
-- runs on a baseline rebuilt from the ERD.

IF OBJECT_ID(N'auth.login_attempt', N'U') IS NULL
    CREATE TABLE [auth].[login_attempt] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [realm] NVARCHAR(20) NOT NULL,
        [email] NVARCHAR(254) NOT NULL,
        [ip_address] NVARCHAR(45) NULL,
        [succeeded] BIT NOT NULL,
        [attempted_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_login_attempt_attempted_at] DEFAULT SYSUTCDATETIME(),
        [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_login_attempt_created_at] DEFAULT SYSUTCDATETIME(),
        [created_by] BIGINT NULL,
        [updated_at] DATETIME2(0) NULL,
        [updated_by] BIGINT NULL,
        [row_version] ROWVERSION,
        CONSTRAINT [PK_login_attempt] PRIMARY KEY CLUSTERED ([id])
    );
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'auth.login_attempt') AND name = N'IX_login_attempt_realm_email_attempted_at')
    CREATE NONCLUSTERED INDEX [IX_login_attempt_realm_email_attempted_at]
        ON [auth].[login_attempt] ([realm], [email], [attempted_at]) INCLUDE ([ip_address], [succeeded]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'auth.login_attempt') AND name = N'IX_login_attempt_realm_ip_address_attempted_at')
    CREATE NONCLUSTERED INDEX [IX_login_attempt_realm_ip_address_attempted_at]
        ON [auth].[login_attempt] ([realm], [ip_address], [attempted_at]) INCLUDE ([succeeded]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'auth.login_attempt') AND name = N'IX_login_attempt_attempted_at')
    CREATE NONCLUSTERED INDEX [IX_login_attempt_attempted_at] ON [auth].[login_attempt] ([attempted_at]);
GO
