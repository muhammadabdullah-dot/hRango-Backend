-- Performance -> Reviews and Appraisals: one employee's appraisal in a cycle.
-- Stages: self_review (the employee rates themselves, "submit") -> manager_review (a manager rates,
-- "evaluate") -> reviewed -> finalised (HR sets the final score, rating and outcome, "approve").
-- Scores are weighted (perf.usp_appraisal_rescore). An increment outcome writes perf.increment_proposal for
-- payroll. Everything is filtered on auth.fn_visible_employees with the code the endpoint required.

CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_list]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @tab                NVARCHAR(20) = N'all',
    @appraisal_cycle_id BIGINT = NULL,
    @status             NVARCHAR(30) = NULL,
    @employee_id        BIGINT = NULL,
    @search             NVARCHAR(200) = NULL,
    @page               INT = 1,
    @page_size          INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT a.id INTO #ids
    FROM [perf].[fn_appraisal_rows](@company_id) a
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = a.employee_id
    WHERE (@tab = N'all' OR a.employee_id IN (SELECT employee_id FROM [perf].[fn_tab_employees](@actor_user_id, @tab)))
      AND (@appraisal_cycle_id IS NULL OR a.appraisal_cycle_id = @appraisal_cycle_id)
      AND (@status IS NULL OR a.status = @status)
      AND (@employee_id IS NULL OR a.employee_id = @employee_id)
      AND (@pattern IS NULL OR a.employee_name LIKE @pattern OR a.employee_code LIKE @pattern OR a.appraisal_cycle_name LIKE @pattern)
    OPTION (RECOMPILE, MAXRECURSION 100);

    SELECT COUNT(*) AS total FROM #ids;

    SELECT a.*
    FROM #ids i
    JOIN [perf].[fn_appraisal_rows](@company_id) a ON a.id = i.id
    ORDER BY a.period_end DESC, a.employee_name, a.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Result sets: 1 the appraisal; 2 the criteria with both ratings; 3 the goals that count; 4 the scale's
-- levels; 5 the increment proposed (no salary figures: those are on the sensitive Increments screen).
CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @emp BIGINT, @cycle BIGINT, @form BIGINT, @scale BIGINT, @s DATE, @e DATE;
    SELECT @emp = a.employee_id, @cycle = a.appraisal_cycle_id, @form = c.appraisal_form_id, @scale = f.rating_scale_id,
           @s = c.start_date, @e = c.end_date
    FROM [perf].[appraisal] a
    JOIN [perf].[appraisal_cycle] c ON c.id = a.appraisal_cycle_id
    JOIN [perf].[appraisal_form] f ON f.id = c.appraisal_form_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = a.employee_id
    WHERE a.id = @id AND a.company_id = @company_id;
    IF @emp IS NULL
        THROW 50404, N'Appraisal not found', 1;

    SELECT a.* FROM [perf].[fn_appraisal_rows](@company_id) a WHERE a.id = @id;

    SELECT c.id AS criterion_id, c.kpi_id, k.name AS kpi_name, c.name, c.description, c.weight, c.sort_order,
           r.self_rating, r.self_comment, r.manager_rating, r.manager_comment
    FROM [perf].[appraisal_criterion] c
    LEFT JOIN [perf].[kpi] k ON k.id = c.kpi_id
    LEFT JOIN [perf].[appraisal_rating] r ON r.appraisal_criterion_id = c.id AND r.appraisal_id = @id
    WHERE c.appraisal_form_id = @form
    ORDER BY c.sort_order, c.id;

    SELECT g.id, g.title, g.due_date, g.weight, g.progress, g.status
    FROM [perf].[goal] g
    WHERE g.employee_id = @emp AND g.company_id = @company_id AND g.status <> N'cancelled'
      AND (g.appraisal_cycle_id = @cycle OR (g.appraisal_cycle_id IS NULL AND g.due_date BETWEEN @s AND @e))
    ORDER BY g.due_date, g.id;

    SELECT l.score, l.label, l.description FROM [perf].[rating_scale_level] l WHERE l.rating_scale_id = @scale ORDER BY l.score;

    SELECT p.id, p.change_type, p.change_value, p.effective_date, p.status
    FROM [perf].[increment_proposal] p WHERE p.appraisal_id = @id;
END
GO

-- Saves ratings and comments of one stage (@stage 'self' or 'manager'); @submit = 1 hands the appraisal on.
-- @ratings: [{"criterionId", "rating", "comment"}]; criteria left out keep what they had.
CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_review_save]
    @company_id        BIGINT,
    @actor_user_id     BIGINT,
    @permission_code   NVARCHAR(150),
    @id                BIGINT,
    @stage             NVARCHAR(20),
    @ratings           NVARCHAR(MAX),
    @comments          NVARCHAR(MAX) = NULL,
    @development_needs NVARCHAR(MAX) = NULL,
    @submit            BIT = 0,
    @row_version       BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @stage NOT IN (N'self', N'manager')
        THROW 50400, N'stage|Unknown review stage.', 1;
    IF ISJSON(@ratings) = 0
        THROW 50400, N'ratings|Ratings are not valid.', 1;

    DECLARE @rv BINARY(8), @emp BIGINT, @reviewer BIGINT, @status NVARCHAR(30), @cycle_status NVARCHAR(30), @form BIGINT,
            @scale BIGINT, @cycle_name NVARCHAR(200), @cycle BIGINT, @emp_name NVARCHAR(400);
    SELECT @rv = a.row_version, @emp = a.employee_id, @reviewer = a.reviewer_employee_id, @status = a.status,
           @cycle_status = a.cycle_status, @form = a.appraisal_form_id, @scale = a.rating_scale_id,
           @cycle_name = a.appraisal_cycle_name, @cycle = a.appraisal_cycle_id, @emp_name = a.employee_name
    FROM [perf].[fn_appraisal_rows](@company_id) a
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = a.employee_id
    WHERE a.id = @id;
    IF @rv IS NULL
        THROW 50404, N'Appraisal not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this appraisal. Reload it and try again', 1;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    IF @stage = N'self' AND (@me IS NULL OR @me <> @emp)
        THROW 50403, N'Only the employee writes their self review.', 1;
    IF @stage = N'manager' AND @me = @emp
        THROW 50403, N'You cannot review your own appraisal.', 1;
    IF @cycle_status <> N'active'
        THROW 50409, N'status|CYCLE_NOT_ACTIVE|This appraisal cycle is not open for reviews.', 1;
    IF (@stage = N'self' AND @status <> N'self_review') OR (@stage = N'manager' AND @status <> N'manager_review')
        THROW 50409, N'status|REVIEW_STAGE|This appraisal is not at that review stage.', 1;

    DECLARE @in TABLE (criterion_id BIGINT PRIMARY KEY, rating DECIMAL(5,2), comment NVARCHAR(MAX));
    INSERT @in
    SELECT x.criterion_id, x.rating, x.comment
    FROM OPENJSON(@ratings) WITH (criterion_id BIGINT '$.criterionId', rating DECIMAL(5,2) '$.rating',
                                  comment NVARCHAR(MAX) '$.comment') x;
    IF EXISTS (SELECT 1 FROM @in i WHERE NOT EXISTS (SELECT 1 FROM [perf].[appraisal_criterion] c
                                                    WHERE c.id = i.criterion_id AND c.appraisal_form_id = @form))
        THROW 50400, N'ratings|A rating names a criterion that is not on this appraisal''s form.', 1;
    DECLARE @min DECIMAL(5,2), @max DECIMAL(5,2);
    SELECT @min = MIN(score), @max = MAX(score) FROM [perf].[rating_scale_level] WHERE rating_scale_id = @scale;
    IF EXISTS (SELECT 1 FROM @in WHERE rating IS NOT NULL AND (rating < @min OR rating > @max))
        THROW 50400, N'ratings|A rating is outside the rating scale.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE r SET self_rating = CASE WHEN @stage = N'self' THEN i.rating ELSE r.self_rating END,
                     self_comment = CASE WHEN @stage = N'self' THEN i.comment ELSE r.self_comment END,
                     manager_rating = CASE WHEN @stage = N'manager' THEN i.rating ELSE r.manager_rating END,
                     manager_comment = CASE WHEN @stage = N'manager' THEN i.comment ELSE r.manager_comment END,
                     updated_at = @now, updated_by = @actor_user_id
        FROM [perf].[appraisal_rating] r JOIN @in i ON i.criterion_id = r.appraisal_criterion_id
        WHERE r.appraisal_id = @id;
        INSERT [perf].[appraisal_rating] (appraisal_id, appraisal_criterion_id, self_rating, self_comment, manager_rating, manager_comment, created_by)
        SELECT @id, i.criterion_id, CASE WHEN @stage = N'self' THEN i.rating END, CASE WHEN @stage = N'self' THEN i.comment END,
               CASE WHEN @stage = N'manager' THEN i.rating END, CASE WHEN @stage = N'manager' THEN i.comment END, @actor_user_id
        FROM @in i
        WHERE NOT EXISTS (SELECT 1 FROM [perf].[appraisal_rating] r WHERE r.appraisal_id = @id AND r.appraisal_criterion_id = i.criterion_id);

        IF @submit = 1 AND EXISTS (
            SELECT 1 FROM [perf].[appraisal_criterion] c
            LEFT JOIN [perf].[appraisal_rating] r ON r.appraisal_criterion_id = c.id AND r.appraisal_id = @id
            WHERE c.appraisal_form_id = @form
              AND ((@stage = N'self' AND r.self_rating IS NULL) OR (@stage = N'manager' AND r.manager_rating IS NULL)))
            THROW 50400, N'ratings|Rate every criterion before you submit.', 1;

        UPDATE [perf].[appraisal]
        SET self_comments = CASE WHEN @stage = N'self' THEN @comments ELSE self_comments END,
            manager_comments = CASE WHEN @stage = N'manager' THEN @comments ELSE manager_comments END,
            development_needs = CASE WHEN @stage = N'manager' THEN @development_needs ELSE development_needs END,
            status = CASE WHEN @submit = 0 THEN status WHEN @stage = N'self' THEN N'manager_review' ELSE N'reviewed' END,
            self_submitted_at = CASE WHEN @submit = 1 AND @stage = N'self' THEN @now ELSE self_submitted_at END,
            manager_submitted_at = CASE WHEN @submit = 1 AND @stage = N'manager' THEN @now ELSE manager_submitted_at END,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this appraisal. Reload it and try again', 1;

        EXEC [perf].[usp_appraisal_rescore] @id = @id;

        IF @submit = 1
        BEGIN
            DECLARE @payload NVARCHAR(MAX) = (SELECT CONVERT(NVARCHAR(20), @id) AS appraisalId, CONVERT(NVARCHAR(20), @cycle) AS cycleId,
                                                     CONVERT(NVARCHAR(20), @emp) AS employeeId, @stage AS stage
                                              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'performance.review_submitted',
                 @entity_type = N'perf.appraisal', @entity_id = @id, @payload = @payload;
            IF @stage = N'self'
            BEGIN
                DECLARE @title NVARCHAR(200) = LEFT(N'Self review submitted: ' + @emp_name, 200),
                        @body NVARCHAR(MAX) = @emp_name + N' submitted the self review for ' + @cycle_name + N'. It is ready for your review.',
                        @link NVARCHAR(500) = N'/performance/reviews/' + CONVERT(NVARCHAR(20), @id);
                EXEC [perf].[usp_notify_employee] @company_id = @company_id, @employee_id = @reviewer, @title = @title,
                     @body = @body, @link = @link, @entity_type = N'perf.appraisal', @entity_id = @id;
            END
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'perf.appraisal', @id, N'status', @status,
                    CASE WHEN @stage = N'self' THEN N'manager_review' ELSE N'reviewed' END, N'submit', @actor_user_id, @now);
        END
    COMMIT;

    EXEC [perf].[usp_appraisal_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Finalises a reviewed appraisal: final score (the manager's unless given), the nearest rating label, outcome,
-- the appraisal letter, and for an increment the proposal payroll applies. Tells the employee.
CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_finalise]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @final_score     DECIMAL(5,2) = NULL,
    @final_comments  NVARCHAR(MAX) = NULL,
    @outcome         NVARCHAR(30),
    @change_type     NVARCHAR(30) = NULL,
    @change_value    DECIMAL(18,2) = NULL,
    @effective_date  DATE = NULL,
    @letter_file_id  BIGINT = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @emp BIGINT, @status NVARCHAR(30), @scale BIGINT, @cycle BIGINT, @cycle_name NVARCHAR(200);
    SELECT @rv = a.row_version, @emp = a.employee_id, @status = a.status, @scale = a.rating_scale_id,
           @cycle = a.appraisal_cycle_id, @cycle_name = a.appraisal_cycle_name
    FROM [perf].[fn_appraisal_rows](@company_id) a
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = a.employee_id
    WHERE a.id = @id;
    IF @rv IS NULL
        THROW 50404, N'Appraisal not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this appraisal. Reload it and try again', 1;
    IF @emp = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id)
        THROW 50403, N'You cannot finalise your own appraisal.', 1;
    IF @status <> N'reviewed'
        THROW 50409, N'status|REVIEW_STAGE|The manager review must be submitted before the appraisal is finalised.', 1;
    IF @letter_file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @letter_file_id))
        THROW 50400, N'letterFileId|The file was not found. Upload it again.', 1;

    DECLARE @min DECIMAL(5,2), @max DECIMAL(5,2);
    SELECT @min = MIN(score), @max = MAX(score) FROM [perf].[rating_scale_level] WHERE rating_scale_id = @scale;
    IF @final_score IS NOT NULL AND (@final_score < @min OR @final_score > @max)
        THROW 50400, N'finalScore|The final score is outside the rating scale.', 1;

    DECLARE @current DECIMAL(18,2), @proposed DECIMAL(18,2);
    IF @outcome = N'increment'
    BEGIN
        SELECT TOP 1 @current = amount FROM [hr].[employee_salary]
        WHERE employee_id = @emp AND effective_date <= @effective_date ORDER BY effective_date DESC, id DESC;
        IF @change_type = N'percent' AND @current IS NULL
            THROW 50400, N'changeType|The employee has no salary to raise by a percentage.', 1;
        SET @proposed = CASE WHEN @change_type = N'percent' THEN ROUND(@current * (1 + @change_value / 100.0), 2)
                             ELSE ISNULL(@current, 0) + @change_value END;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @final DECIMAL(5,2), @label NVARCHAR(100), @pid BIGINT;
    BEGIN TRAN;
        EXEC [perf].[usp_appraisal_rescore] @id = @id;
        SET @final = ISNULL(@final_score, (SELECT manager_score FROM [perf].[appraisal] WHERE id = @id));
        SET @label = [perf].[fn_scale_label](@scale, @final);
        UPDATE [perf].[appraisal]
        SET final_score = @final, final_rating_label = @label, final_comments = @final_comments, outcome = @outcome,
            letter_file_id = @letter_file_id, status = N'finalised', finalised_at = @now, finalised_by_user_id = @actor_user_id,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id;

        DECLARE @payload NVARCHAR(MAX) = (SELECT CONVERT(NVARCHAR(20), @id) AS appraisalId, CONVERT(NVARCHAR(20), @cycle) AS cycleId,
                                                 CONVERT(NVARCHAR(20), @emp) AS employeeId, @final AS finalScore,
                                                 @label AS finalRating, @outcome AS outcome
                                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'performance.appraisal_finalised',
             @entity_type = N'perf.appraisal', @entity_id = @id, @payload = @payload;

        IF @outcome = N'increment'
        BEGIN
            INSERT [perf].[increment_proposal] (company_id, appraisal_id, employee_id, change_type, change_value, effective_date,
                                                current_salary, proposed_salary, status, created_by)
            VALUES (@company_id, @id, @emp, @change_type, @change_value, @effective_date, @current, @proposed, N'proposed', @actor_user_id);
            SET @pid = SCOPE_IDENTITY();
            SET @payload = (SELECT CONVERT(NVARCHAR(20), @pid) AS proposalId, CONVERT(NVARCHAR(20), @id) AS appraisalId,
                                   CONVERT(NVARCHAR(20), @emp) AS employeeId, @change_type AS changeType,
                                   @change_value AS changeValue, @effective_date AS effectiveDate
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'performance.increment_proposed',
                 @entity_type = N'perf.increment_proposal', @entity_id = @pid, @payload = @payload;
        END

        DECLARE @title NVARCHAR(200) = LEFT(N'Your appraisal is final: ' + @cycle_name, 200),
                @body NVARCHAR(MAX) = N'Final rating: ' + ISNULL(@label, N'-') + N' (' + ISNULL(CONVERT(NVARCHAR(20), @final), N'-') + N').',
                @link NVARCHAR(500) = N'/performance/reviews/' + CONVERT(NVARCHAR(20), @id);
        EXEC [perf].[usp_notify_employee] @company_id = @company_id, @employee_id = @emp, @title = @title, @body = @body,
             @link = @link, @entity_type = N'perf.appraisal', @entity_id = @id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'perf.appraisal', @id, N'status', @status, N'finalised', N'finalise', @actor_user_id, @now);
    COMMIT;

    EXEC [perf].[usp_appraisal_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Removes someone from a cycle before anyone has submitted a review for them.
CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @cycle_status NVARCHAR(30), @started BIT, @emp BIGINT;
    SELECT @rv = a.row_version, @cycle_status = a.cycle_status, @emp = a.employee_id,
           @started = CASE WHEN a.self_submitted_at IS NOT NULL OR a.manager_submitted_at IS NOT NULL OR a.status = N'finalised' THEN 1 ELSE 0 END
    FROM [perf].[fn_appraisal_rows](@company_id) a
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = a.employee_id
    WHERE a.id = @id;
    IF @rv IS NULL
        THROW 50404, N'Appraisal not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this appraisal. Reload it and try again', 1;
    IF @cycle_status = N'closed'
        THROW 50409, N'status|CYCLE_CLOSED|This appraisal cycle is closed.', 1;
    IF @started = 1
        THROW 50409, N'status|APPRAISAL_STARTED|A review has been submitted on this appraisal. It cannot be removed.', 1;
    BEGIN TRAN;
        DELETE [perf].[appraisal_rating] WHERE appraisal_id = @id;
        DELETE [perf].[appraisal] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'perf.appraisal', @id, N'employee_id', CONVERT(NVARCHAR(20), @emp), N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
