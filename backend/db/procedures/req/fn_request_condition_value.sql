-- The value a flow condition tests (approval_node.condition_field), for one request.
--   days        the request's Count (leave, WFH, rest days; 1 for single-day kinds)
--   amount      loan amount asked, travel advances in total, the new salary of a promotion, the
--               expense or air ticket amount claimed (approved once set), a requisition's estimate
--   minutes     overtime minutes applied for, or the length of a relaxation / official visit
--   department_id, branch_id, location_id, grade_id, designation_id, employment_type_id
--               the employee's current placement
CREATE OR ALTER FUNCTION [req].[fn_request_condition_value] (@request_id BIGINT, @field NVARCHAR(200))
RETURNS DECIMAL(18,4)
AS
BEGIN
    DECLARE @v DECIMAL(18,4);

    IF @field = N'days'
        SELECT @v = days FROM [req].[request] WHERE id = @request_id;
    ELSE IF @field = N'amount'
        SELECT @v = COALESCE(
            (SELECT amount_requested FROM [req].[req_loan] WHERE request_id = @request_id),
            (SELECT SUM(amount) FROM [req].[travel_advance] WHERE request_id = @request_id),
            (SELECT new_salary FROM [req].[req_promotion] WHERE request_id = @request_id),
            (SELECT ISNULL(approved_amount, total_amount) FROM [req].[req_expense] WHERE request_id = @request_id),
            (SELECT ISNULL(approved_amount, amount) FROM [req].[req_air_ticket] WHERE request_id = @request_id),
            (SELECT estimated_amount FROM [req].[req_requisition] WHERE request_id = @request_id));
    ELSE IF @field = N'minutes'
        SELECT @v = COALESCE(
            (SELECT applied_minutes FROM [req].[req_overtime] WHERE request_id = @request_id),
            (SELECT duration_minutes FROM [req].[req_time_window] WHERE request_id = @request_id));
    ELSE
        SELECT @v = CASE @field
                        WHEN N'department_id' THEN e.department_id
                        WHEN N'branch_id' THEN e.branch_id
                        WHEN N'location_id' THEN e.location_id
                        WHEN N'grade_id' THEN e.grade_id
                        WHEN N'designation_id' THEN e.designation_id
                        WHEN N'employment_type_id' THEN e.employment_type_id
                    END
        FROM [req].[request] r JOIN [hr].[employee] e ON e.id = r.employee_id
        WHERE r.id = @request_id;

    RETURN @v;
END
