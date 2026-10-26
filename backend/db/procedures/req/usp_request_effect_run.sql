-- Runs the owning module's hook for a request, when that module has written it:
--   @verb = apply     <schema>.usp_request_apply_<kind>     on final approval
--   @verb = revert    <schema>.usp_request_revert_<kind>    when an approved request is cancelled
--   @verb = validate  <schema>.usp_request_validate_<kind>  on submit and edit, after the engine's checks
-- Always called inside the caller's transaction. A THROW 504xx in the hook stops the whole action
-- and its message reaches the user. The schema comes from this fixed map, never from data.
CREATE OR ALTER PROCEDURE [req].[usp_request_effect_run]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT,
    @verb          NVARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @verb NOT IN (N'apply', N'revert', N'validate')
        THROW 50400, N'Unknown request hook.', 1;

    DECLARE @kind NVARCHAR(30) = (
        SELECT t.kind FROM [req].[request] r JOIN [req].[request_type] t ON t.id = r.request_type_id
        WHERE r.id = @request_id AND r.company_id = @company_id);

    DECLARE @schema SYSNAME = CASE @kind
        WHEN N'leave' THEN N'lv'
        WHEN N'punch' THEN N'att'
        WHEN N'time_window' THEN N'att'
        WHEN N'overtime' THEN N'att'
        WHEN N'work_from_home' THEN N'att'
        WHEN N'rest_day' THEN N'sch'
        WHEN N'shift_swap' THEN N'sch'
        WHEN N'promotion' THEN N'hr'
        WHEN N'transfer' THEN N'hr'
        WHEN N'resignation' THEN N'sep'
        WHEN N'loan' THEN N'loan'
        WHEN N'task_extension' THEN N'pm'
        WHEN N'expense' THEN N'pay'
        WHEN N'air_ticket' THEN N'pay'
        WHEN N'requisition' THEN N'req'
    END;
    IF @schema IS NULL
        RETURN;

    DECLARE @proc NVARCHAR(400) = QUOTENAME(@schema) + N'.' + QUOTENAME(N'usp_request_' + @verb + N'_' + @kind);
    IF OBJECT_ID(@proc, N'P') IS NULL
        RETURN;

    DECLARE @sql NVARCHAR(600) = N'EXEC ' + @proc + N' @company_id = @c, @actor_user_id = @a, @request_id = @r;';
    EXEC sys.sp_executesql @sql, N'@c BIGINT, @a BIGINT, @r BIGINT', @c = @company_id, @a = @actor_user_id, @r = @request_id;
END
