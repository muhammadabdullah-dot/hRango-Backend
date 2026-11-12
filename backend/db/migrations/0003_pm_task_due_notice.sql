-- What the daily due job (pm.usp_task_due_notify) has told: one row per task, person, kind (due_tomorrow,
-- overdue) and due date, so nobody hears about the same thing twice. Checks first, like 0002, so it also
-- runs on a baseline rebuilt from the ERD.

IF OBJECT_ID(N'pm.task_due_notice', N'U') IS NULL
    CREATE TABLE [pm].[task_due_notice] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [task_id] BIGINT NOT NULL,
        [employee_id] BIGINT NOT NULL,
        [notice_kind] NVARCHAR(30) NOT NULL,
        [due_date] DATE NOT NULL,
        [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_task_due_notice_created_at] DEFAULT SYSUTCDATETIME(),
        [created_by] BIGINT NULL,
        [updated_at] DATETIME2(0) NULL,
        [updated_by] BIGINT NULL,
        [row_version] ROWVERSION,
        CONSTRAINT [PK_task_due_notice] PRIMARY KEY CLUSTERED ([id]),
        CONSTRAINT [UQ_task_due_notice_task_id_employee_id_notice_kind_due_date]
            UNIQUE ([task_id], [employee_id], [notice_kind], [due_date]),
        CONSTRAINT [FK_task_due_notice_task_id] FOREIGN KEY ([task_id]) REFERENCES [pm].[task] ([id]),
        CONSTRAINT [FK_task_due_notice_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id])
    );
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'pm.task_due_notice') AND name = N'IX_task_due_notice_employee_id')
    CREATE NONCLUSTERED INDEX [IX_task_due_notice_employee_id] ON [pm].[task_due_notice] ([employee_id]);
GO
