-- Fixed allowances and deductions per person (employees.salary, sensitive). Each payroll run takes the latest row per
-- pay item whose effective date has come (pay.usp_payroll_run). Plus the photo list every list of people reads.

CREATE OR ALTER PROCEDURE [hr].[usp_employee_pay_item_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.salary.view') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;

    SELECT epi.id, epi.employee_id, epi.pay_item_id, i.name AS pay_item_name, epi.amount, epi.effective_date,
           epi.created_at, epi.updated_at, epi.row_version
    FROM [hr].[employee_pay_item] epi
    JOIN [pay].[pay_item] i ON i.id = epi.pay_item_id
    WHERE epi.employee_id = @employee_id
    ORDER BY i.name, epi.effective_date DESC, epi.id DESC;
END
GO

-- Adds a row (@id NULL) or corrects one.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_pay_item_save]
    @company_id     BIGINT,
    @actor_user_id  BIGINT,
    @employee_id    BIGINT,
    @id             BIGINT = NULL,
    @pay_item_id    BIGINT,
    @amount         DECIMAL(18,2),
    @effective_date DATE = NULL,
    @row_version    BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.salary.edit') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;
    IF NOT EXISTS (SELECT 1 FROM [pay].[pay_item] WHERE id = @pay_item_id AND company_id = @company_id)
        THROW 50400, N'payItemId|Pay item not found.', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee_pay_item]
               WHERE employee_id = @employee_id AND pay_item_id = @pay_item_id
                 AND ((effective_date IS NULL AND @effective_date IS NULL) OR effective_date = @effective_date)
                 AND (@id IS NULL OR id <> @id))
        THROW 50409, N'effectiveDate|EMPLOYEE_PAY_ITEM_DUPLICATE|This pay item already has an amount from that date.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NULL
    BEGIN
        INSERT [hr].[employee_pay_item] (employee_id, pay_item_id, amount, effective_date, created_by)
        VALUES (@employee_id, @pay_item_id, @amount, @effective_date, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit this.', 1;
        UPDATE [hr].[employee_pay_item]
        SET pay_item_id = @pay_item_id, amount = @amount, effective_date = @effective_date,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND employee_id = @employee_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this. Reload it and try again', 1;
    END

    SELECT epi.id, epi.employee_id, epi.pay_item_id, i.name AS pay_item_name, epi.amount, epi.effective_date,
           epi.created_at, epi.updated_at, epi.row_version
    FROM [hr].[employee_pay_item] epi
    JOIN [pay].[pay_item] i ON i.id = epi.pay_item_id
    WHERE epi.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_pay_item_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.salary.edit') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;
    DELETE [hr].[employee_pay_item] WHERE id = @id AND employee_id = @employee_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 50409, N'Someone else changed this. Reload it and try again', 1;
END
GO

-- Everyone in the company with a photo: lists of people show them, and a colleague's face is not private.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_photos]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id AS employee_id, LTRIM(RTRIM(CONCAT(first_name, N' ', last_name))) AS name, photo_file_id
    FROM [hr].[employee]
    WHERE company_id = @company_id AND photo_file_id IS NOT NULL;
END
GO
