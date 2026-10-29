-- A bulk filing (Create Bulk Overtime Request): the header row the requests filed together point at
-- (req_overtime.bulk_id). Called by the API inside the transaction that files every person's request,
-- so a refusal of anyone rolls the bulk row back with the rest. Result set: the new id.
CREATE OR ALTER PROCEDURE [req].[usp_request_bulk_add]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @type_code     NVARCHAR(30),
    @request_count INT,
    @reason        NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @type_id BIGINT = (SELECT id FROM [req].[request_type] WHERE code = @type_code AND is_active = 1);
    IF @type_id IS NULL
        THROW 50404, N'Request type not found', 1;
    IF @request_count IS NULL OR @request_count < 1
        THROW 50400, N'employeeIds|Choose at least one employee.', 1;

    INSERT [req].[request_bulk] (company_id, request_type_id, request_count, reason, created_by)
    VALUES (@company_id, @type_id, @request_count, NULLIF(LTRIM(RTRIM(@reason)), N''), @actor_user_id);

    SELECT CAST(SCOPE_IDENTITY() AS BIGINT) AS id;
END
