-- One-time links sent by e-mail (roadmap 1.5): password reset (valid 1 hour) and invitations to set a first
-- password (valid 7 days). Only the SHA-256 of the token is stored, so a copy of the database cannot be
-- used to take over accounts. A new link of the same kind replaces the older one. Checks first, like 0002,
-- so it also runs on a baseline rebuilt from the ERD.

IF OBJECT_ID(N'auth.user_token', N'U') IS NULL
    CREATE TABLE [auth].[user_token] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [user_account_id] BIGINT NOT NULL,
        [purpose] NVARCHAR(30) NOT NULL,
        [token_hash] CHAR(64) NOT NULL,
        [expires_at] DATETIME2(0) NOT NULL,
        [used_at] DATETIME2(0) NULL,
        [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_user_token_created_at] DEFAULT SYSUTCDATETIME(),
        [created_by] BIGINT NULL,
        [updated_at] DATETIME2(0) NULL,
        [updated_by] BIGINT NULL,
        [row_version] ROWVERSION,
        CONSTRAINT [PK_user_token] PRIMARY KEY CLUSTERED ([id]),
        CONSTRAINT [UQ_user_token_token_hash] UNIQUE ([token_hash]),
        CONSTRAINT [FK_user_token_user_account_id] FOREIGN KEY ([user_account_id]) REFERENCES [auth].[user_account] ([id])
    );
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'auth.user_token') AND name = N'IX_user_token_user_account_id')
    CREATE NONCLUSTERED INDEX [IX_user_token_user_account_id] ON [auth].[user_token] ([user_account_id]);
GO
