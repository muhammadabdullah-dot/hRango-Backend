-- Training: tells an employee's accounts in the inbox. core.usp_notification_add_employee is called
-- with @quiet = 1, so the calling procedure's own result set stays the first one.
CREATE OR ALTER PROCEDURE [trn].[usp_notify_employee]
    @company_id  BIGINT,
    @employee_id BIGINT,
    @title       NVARCHAR(200),
    @body        NVARCHAR(MAX) = NULL,
    @link        NVARCHAR(500) = NULL,
    @entity_type NVARCHAR(50) = NULL,
    @entity_id   BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @employee_id IS NULL
        RETURN;
    EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @employee_id, @title = @title,
         @body = @body, @notification_type = N'training', @link = @link, @entity_type = @entity_type,
         @entity_id = @entity_id;
END
GO

-- Tells everyone holding (or waiting for) a seat on a session, e.g. when it moves or is cancelled.
-- @statuses: comma-separated enrolment statuses.
CREATE OR ALTER PROCEDURE [trn].[usp_notify_session]
    @company_id BIGINT,
    @session_id BIGINT,
    @statuses   NVARCHAR(200),
    @title      NVARCHAR(200),
    @body       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @link NVARCHAR(500) = N'/training/sessions/' + CONVERT(NVARCHAR(20), @session_id), @emp BIGINT;
    DECLARE @people TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @people SELECT DISTINCT e.employee_id FROM [trn].[training_enrolment] e
    WHERE e.training_session_id = @session_id AND e.status IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@statuses, N','));
    SET @emp = (SELECT MIN(employee_id) FROM @people);
    WHILE @emp IS NOT NULL
    BEGIN
        EXEC [trn].[usp_notify_employee] @company_id = @company_id, @employee_id = @emp, @title = @title, @body = @body,
             @link = @link, @entity_type = N'trn.training_session', @entity_id = @session_id;
        SET @emp = (SELECT MIN(employee_id) FROM @people WHERE employee_id > @emp);
    END
END
