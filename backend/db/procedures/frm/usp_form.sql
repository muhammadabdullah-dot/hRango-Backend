-- Custom Form (HR side, CF1): the Forms list, the builder (sections, fields, options, audience in one
-- save), publishing, closing, duplicating, deleting.
-- A form can be edited in any status. Once a field has answers it keeps its type and its options and
-- cannot be left out, and once the form has responses its anonymity is fixed.

-- Result set 1: total. Result set 2: the page, newest change first. @status filters the effective
-- status; @search matches title, category and description.
CREATE OR ALTER PROCEDURE [frm].[usp_form_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @status     NVARCHAR(30) = NULL,
    @page       INT = 1,
    @page_size  INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [frm].[fn_form_rows](@company_id, @today) r
    WHERE (@status IS NULL OR r.status = @status)
      AND (@pattern IS NULL OR r.title LIKE @pattern OR r.category LIKE @pattern OR r.description LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT r.*, [frm].[fn_form_audience_json](r.id) AS audience_json
    FROM [frm].[fn_form_rows](@company_id, @today) r
    WHERE (@status IS NULL OR r.status = @status)
      AND (@pattern IS NULL OR r.title LIKE @pattern OR r.category LIKE @pattern OR r.description LIKE @pattern)
    ORDER BY r.updated_at DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- One form with its sections, fields (with options) and audience targets, as JSON columns.
CREATE OR ALTER PROCEDURE [frm].[usp_form_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [frm].[form] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Form not found', 1;
    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);

    SELECT r.*, [frm].[fn_form_audience_json](r.id) AS audience_json,
           [frm].[fn_form_sections_json](r.id) AS sections_json, [frm].[fn_form_fields_json](r.id) AS fields_json,
           (SELECT COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))), N''), u.display_name, u.email)
            FROM [auth].[user_account] u LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
            WHERE u.id = r.created_by) AS created_by_name
    FROM [frm].[fn_form_rows](@company_id, @today) r
    WHERE r.id = @id;
END
GO

-- Creates a draft (@id NULL) or edits a form, replacing its sections, fields, options and audience.
-- @audience_ids: [id, ...] (departments, branches or employees by @audience_kind; none for everyone).
-- @sections: [{key, id, title, description}] in order; key is unique in the request.
-- @fields: [{id, section_key, type, label, help_text, required, options: [{id, label}], min, max}] in order.
-- A section or field or option with an id is kept (and keeps its answers); one without is new; one left
-- out is removed.
CREATE OR ALTER PROCEDURE [frm].[usp_form_save]
    @company_id        BIGINT,
    @actor_user_id     BIGINT,
    @id                BIGINT = NULL,
    @title             NVARCHAR(400),
    @description       NVARCHAR(MAX) = NULL,
    @category          NVARCHAR(200) = NULL,
    @closes_on         DATE = NULL,
    @audience_kind     NVARCHAR(30) = N'everyone',
    @audience_ids      NVARCHAR(MAX) = NULL,
    @is_one_per_person BIT = 0,
    @is_anonymous      BIT = 0,
    @sections          NVARCHAR(MAX) = NULL,
    @fields            NVARCHAR(MAX) = NULL,
    @row_version       BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE), @msg NVARCHAR(400), @bad INT;
    SET @title = LTRIM(RTRIM(@title));
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    SET @category = NULLIF(LTRIM(RTRIM(@category)), N'');
    SET @is_one_per_person = ISNULL(@is_one_per_person, 0);
    SET @is_anonymous = ISNULL(@is_anonymous, 0);

    IF @title IS NULL OR @title = N'' OR LEN(@title) > 200
        THROW 50400, N'title|Give the form a title (up to 200 characters).', 1;
    IF LEN(@category) > 100
        THROW 50400, N'category|The category is up to 100 characters.', 1;
    IF @audience_kind IS NULL OR @audience_kind NOT IN (N'everyone', N'departments', N'branches', N'people')
        THROW 50400, N'audience.kind|Choose who the form is for.', 1;
    IF ISJSON(ISNULL(@audience_ids, N'[]')) = 0
        THROW 50400, N'audience.ids|The audience is not valid.', 1;
    IF ISJSON(ISNULL(@sections, N'[]')) = 0
        THROW 50400, N'sections|The sections are not valid.', 1;
    IF ISJSON(ISNULL(@fields, N'[]')) = 0
        THROW 50400, N'fields|The questions are not valid.', 1;

    DECLARE @rv BINARY(8), @old_anon BIT, @old_closes DATE, @has_responses BIT = 0;
    IF @id IS NOT NULL
    BEGIN
        SELECT @rv = row_version, @old_anon = is_anonymous, @old_closes = closes_on
        FROM [frm].[form] WHERE id = @id AND company_id = @company_id;
        IF @rv IS NULL
            THROW 50404, N'Form not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a form.', 1;
        IF @rv <> @row_version
            THROW 50409, N'rowVersion|STALE_ROW_VERSION|Someone else changed this form. Reload it and try again.', 1;
        IF EXISTS (SELECT 1 FROM [frm].[form_response] WHERE form_id = @id)
            SET @has_responses = 1;
    END

    -- A closing date in the past is refused when it is set or moved (not when an old form is reworded).
    IF @closes_on < @today AND (@id IS NULL OR @old_closes IS NULL OR @closes_on <> @old_closes)
        THROW 50400, N'closesOn|The closing date has passed.', 1;
    IF @has_responses = 1 AND @is_anonymous <> @old_anon
        THROW 50400, N'anonymous|People have answered this form, so whether it is anonymous cannot change.', 1;

    -- Audience
    DECLARE @unit_type NVARCHAR(30) = CASE @audience_kind WHEN N'departments' THEN N'department'
        WHEN N'branches' THEN N'branch' WHEN N'people' THEN N'employee' END;
    DECLARE @aud TABLE (unit_id BIGINT PRIMARY KEY);
    IF @unit_type IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM OPENJSON(ISNULL(@audience_ids, N'[]')) j WHERE TRY_CAST(j.[value] AS BIGINT) IS NULL)
            THROW 50400, N'audience.ids|The audience is not valid.', 1;
        INSERT @aud SELECT DISTINCT CAST(j.[value] AS BIGINT) FROM OPENJSON(ISNULL(@audience_ids, N'[]')) j;
        IF NOT EXISTS (SELECT 1 FROM @aud)
            THROW 50400, N'audience.ids|Choose at least one.', 1;
        IF EXISTS (SELECT 1 FROM @aud a WHERE NOT (
                      (@unit_type = N'department' AND EXISTS (SELECT 1 FROM [org].[department] d WHERE d.id = a.unit_id AND d.company_id = @company_id))
                   OR (@unit_type = N'branch' AND EXISTS (SELECT 1 FROM [org].[branch] b WHERE b.id = a.unit_id AND b.company_id = @company_id))
                   OR (@unit_type = N'employee' AND EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = a.unit_id AND e.company_id = @company_id))))
            THROW 50400, N'audience.ids|A department, branch or person in the audience was not found.', 1;
    END

    -- Sections
    DECLARE @sec TABLE (pos INT PRIMARY KEY, skey NVARCHAR(100), id BIGINT, title NVARCHAR(400), description NVARCHAR(MAX),
                        new_id BIGINT);
    INSERT @sec (pos, skey, id, title, description)
    SELECT CAST(j.[key] AS INT), x.skey, x.id, LTRIM(RTRIM(x.title)), NULLIF(LTRIM(RTRIM(x.description)), N'')
    FROM OPENJSON(ISNULL(@sections, N'[]')) j
    CROSS APPLY OPENJSON(j.[value]) WITH (skey NVARCHAR(100) '$.key', id BIGINT '$.id', title NVARCHAR(400) '$.title',
                                          description NVARCHAR(MAX) '$.description') x;
    IF (SELECT COUNT(*) FROM @sec) > 50
        THROW 50400, N'sections|A form can have at most 50 sections.', 1;

    SET @bad = (SELECT MIN(pos) FROM @sec WHERE title IS NULL OR title = N'' OR LEN(title) > 200);
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'sections.', @bad, N'.title|Give the section a title (up to 200 characters).');
        THROW 50400, @msg, 1;
    END
    SET @bad = (SELECT MIN(s.pos) FROM @sec s
                WHERE s.skey IS NULL OR EXISTS (SELECT 1 FROM @sec o WHERE o.skey = s.skey AND o.pos < s.pos));
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'sections.', @bad, N'.key|Each section needs its own key.');
        THROW 50400, @msg, 1;
    END
    SET @bad = (SELECT MIN(s.pos) FROM @sec s
                WHERE s.id IS NOT NULL
                  AND (NOT EXISTS (SELECT 1 FROM [frm].[form_section] x WHERE x.id = s.id AND x.form_id = @id)
                       OR EXISTS (SELECT 1 FROM @sec o WHERE o.id = s.id AND o.pos < s.pos)));
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'sections.', @bad, N'.id|This section is not on the form.');
        THROW 50400, @msg, 1;
    END

    -- Fields
    DECLARE @fld TABLE (pos INT PRIMARY KEY, id BIGINT, skey NVARCHAR(100), field_type NVARCHAR(30), label NVARCHAR(600),
                        help_text NVARCHAR(1100), is_required BIT, min_value DECIMAL(18,4), max_value DECIMAL(18,4),
                        options NVARCHAR(MAX), old_type NVARCHAR(30), has_answers BIT NOT NULL DEFAULT 0, new_id BIGINT);
    INSERT @fld (pos, id, skey, field_type, label, help_text, is_required, min_value, max_value, options)
    SELECT CAST(j.[key] AS INT), x.id, x.skey, x.field_type, LTRIM(RTRIM(x.label)), NULLIF(LTRIM(RTRIM(x.help_text)), N''),
           ISNULL(x.is_required, 0), x.min_value, x.max_value, x.options
    FROM OPENJSON(ISNULL(@fields, N'[]')) j
    CROSS APPLY OPENJSON(j.[value]) WITH (id BIGINT '$.id', skey NVARCHAR(100) '$.section_key', field_type NVARCHAR(30) '$.type',
        label NVARCHAR(600) '$.label', help_text NVARCHAR(1100) '$.help_text', is_required BIT '$.required',
        min_value DECIMAL(18,4) '$.min', max_value DECIMAL(18,4) '$.max', options NVARCHAR(MAX) '$.options' AS JSON) x;
    IF (SELECT COUNT(*) FROM @fld) > 200
        THROW 50400, N'fields|A form can have at most 200 questions.', 1;

    UPDATE x SET old_type = f.field_type,
                 has_answers = CASE WHEN EXISTS (SELECT 1 FROM [frm].[form_answer] a WHERE a.form_field_id = f.id) THEN 1 ELSE 0 END
    FROM @fld x JOIN [frm].[form_field] f ON f.id = x.id AND f.form_id = @id;
    -- A rating's scale defaults to 5.
    UPDATE @fld SET min_value = NULL, max_value = ISNULL(max_value, 5) WHERE field_type = N'rating';

    IF @has_responses = 1 AND EXISTS (
        SELECT 1 FROM [frm].[form_field] f
        WHERE f.form_id = @id AND NOT EXISTS (SELECT 1 FROM @fld x WHERE x.id = f.id)
          AND EXISTS (SELECT 1 FROM [frm].[form_answer] a WHERE a.form_field_id = f.id))
        THROW 50409, N'fields|FORM_HAS_RESPONSES|A question that people have answered cannot be removed.', 1;

    SET @bad = (SELECT MIN(pos) FROM @fld WHERE field_type IS NULL OR field_type NOT IN (N'short_text', N'long_text', N'number',
                N'date', N'single_choice', N'multiple_choice', N'dropdown', N'checkbox', N'file', N'rating'));
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.type|Choose the question type.');
        THROW 50400, @msg, 1;
    END
    SET @bad = (SELECT MIN(pos) FROM @fld WHERE label IS NULL OR label = N'' OR LEN(label) > 500);
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.label|Write the question (up to 500 characters).');
        THROW 50400, @msg, 1;
    END
    SET @bad = (SELECT MIN(pos) FROM @fld WHERE LEN(help_text) > 1000);
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.helpText|The help text is up to 1000 characters.');
        THROW 50400, @msg, 1;
    END
    SET @bad = (SELECT MIN(x.pos) FROM @fld x
                WHERE x.id IS NOT NULL AND (x.old_type IS NULL OR EXISTS (SELECT 1 FROM @fld o WHERE o.id = x.id AND o.pos < x.pos)));
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.id|This question is not on the form.');
        THROW 50400, @msg, 1;
    END
    SET @bad = (SELECT MIN(x.pos) FROM @fld x WHERE x.skey IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @sec s WHERE s.skey = x.skey));
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.sectionKey|This section is not on the form.');
        THROW 50400, @msg, 1;
    END
    SET @bad = (SELECT MIN(pos) FROM @fld WHERE has_answers = 1 AND field_type <> old_type);
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.type|People have answered this question, so its type cannot change.');
        THROW 50400, @msg, 1;
    END
    SET @bad = (SELECT MIN(pos) FROM @fld WHERE field_type <> N'number' AND (min_value < 0 OR max_value < 0));
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.min|The limits cannot be negative.');
        THROW 50400, @msg, 1;
    END
    SET @bad = (SELECT MIN(pos) FROM @fld WHERE min_value > max_value);
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.max|The maximum is below the minimum.');
        THROW 50400, @msg, 1;
    END
    SET @bad = (SELECT MIN(pos) FROM @fld WHERE field_type = N'rating' AND (max_value NOT BETWEEN 3 AND 10 OR max_value <> FLOOR(max_value)));
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.max|A rating scale runs from 3 to 10.');
        THROW 50400, @msg, 1;
    END

    -- Options (choice types only; others drop theirs)
    DECLARE @opt TABLE (field_pos INT, pos INT, id BIGINT, label NVARCHAR(600), PRIMARY KEY (field_pos, pos));
    INSERT @opt
    SELECT f.pos, CAST(o.[key] AS INT), x.id, LTRIM(RTRIM(x.label))
    FROM @fld f
    CROSS APPLY OPENJSON(ISNULL(f.options, N'[]')) o
    CROSS APPLY OPENJSON(CASE WHEN o.[type] = 5 THEN o.[value] ELSE N'{}' END) WITH (id BIGINT '$.id', label NVARCHAR(600) '$.label') x
    WHERE f.field_type IN (N'single_choice', N'multiple_choice', N'dropdown');

    SET @bad = (SELECT MIN(f.pos) FROM @fld f
                WHERE f.field_type IN (N'single_choice', N'multiple_choice', N'dropdown')
                  AND (NOT EXISTS (SELECT 1 FROM @opt o WHERE o.field_pos = f.pos)
                       OR (SELECT COUNT(*) FROM @opt o WHERE o.field_pos = f.pos) > 100
                       OR EXISTS (SELECT 1 FROM @opt o WHERE o.field_pos = f.pos AND (o.label IS NULL OR o.label = N'' OR LEN(o.label) > 500))
                       OR EXISTS (SELECT o.label FROM @opt o WHERE o.field_pos = f.pos GROUP BY o.label HAVING COUNT(*) > 1)));
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.options|Give the question its options: up to 100, each different and up to 500 characters.');
        THROW 50400, @msg, 1;
    END
    SET @bad = (SELECT MIN(o.field_pos) FROM @opt o JOIN @fld f ON f.pos = o.field_pos
                WHERE o.id IS NOT NULL
                  AND (NOT EXISTS (SELECT 1 FROM [frm].[form_field_option] x WHERE x.id = o.id AND x.form_field_id = f.id)
                       OR EXISTS (SELECT 1 FROM @opt d WHERE d.id = o.id AND (d.field_pos < o.field_pos OR (d.field_pos = o.field_pos AND d.pos < o.pos)))));
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.options|An option is not on this question.');
        THROW 50400, @msg, 1;
    END
    SET @bad = (SELECT MIN(f.pos) FROM @fld f JOIN [frm].[form_field_option] x ON x.form_field_id = f.id
                WHERE f.has_answers = 1 AND NOT EXISTS (SELECT 1 FROM @opt o WHERE o.field_pos = f.pos AND o.id = x.id));
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.options|People have answered this question, so its options cannot be removed.');
        THROW 50400, @msg, 1;
    END
    -- TODO(business): multiple_choice min / max picks against the number of options; min / max for dates.

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @map TABLE (pos INT PRIMARY KEY, id BIGINT);
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [frm].[form] (company_id, title, description, category, status, closes_on, audience_kind, is_one_per_person,
                                 is_anonymous, created_by)
            VALUES (@company_id, @title, @description, @category, N'draft', @closes_on, @audience_kind, @is_one_per_person,
                    @is_anonymous, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'frm.form', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [frm].[form]
            SET title = @title, description = @description, category = @category, closes_on = @closes_on,
                audience_kind = @audience_kind, is_one_per_person = @is_one_per_person, is_anonymous = @is_anonymous,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'rowVersion|STALE_ROW_VERSION|Someone else changed this form. Reload it and try again.', 1;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'frm.form', @id, N'update', @actor_user_id, @now);
        END

        DELETE [frm].[form_audience] WHERE form_id = @id;
        INSERT [frm].[form_audience] (form_id, unit_type, unit_id, created_by)
        SELECT @id, @unit_type, unit_id, @actor_user_id FROM @aud;

        -- Sections: keep and reorder, add new ones (removed ones go after the fields have moved).
        UPDATE s SET sort_order = x.pos, title = x.title, description = x.description, updated_at = @now, updated_by = @actor_user_id
        FROM [frm].[form_section] s JOIN @sec x ON x.id = s.id
        WHERE s.form_id = @id;
        UPDATE @sec SET new_id = id WHERE id IS NOT NULL;
        MERGE [frm].[form_section] AS t
        USING (SELECT pos, title, description FROM @sec WHERE id IS NULL) AS src ON 1 = 0
        WHEN NOT MATCHED THEN INSERT (form_id, sort_order, title, description, created_by)
             VALUES (@id, src.pos, src.title, src.description, @actor_user_id)
        OUTPUT src.pos, inserted.id INTO @map (pos, id);
        UPDATE x SET new_id = m.id FROM @sec x JOIN @map m ON m.pos = x.pos;
        DELETE @map;

        -- Fields left out (none of them has answers: checked above), with their options.
        DELETE o FROM [frm].[form_field_option] o JOIN [frm].[form_field] f ON f.id = o.form_field_id
        WHERE f.form_id = @id AND NOT EXISTS (SELECT 1 FROM @fld x WHERE x.id = f.id);
        DELETE f FROM [frm].[form_field] f
        WHERE f.form_id = @id AND NOT EXISTS (SELECT 1 FROM @fld x WHERE x.id = f.id);

        UPDATE f SET form_section_id = s.new_id, sort_order = x.pos, field_type = x.field_type, label = x.label,
                     help_text = x.help_text, is_required = x.is_required, min_value = x.min_value, max_value = x.max_value,
                     updated_at = @now, updated_by = @actor_user_id
        FROM [frm].[form_field] f JOIN @fld x ON x.id = f.id LEFT JOIN @sec s ON s.skey = x.skey
        WHERE f.form_id = @id;
        UPDATE @fld SET new_id = id WHERE id IS NOT NULL;
        MERGE [frm].[form_field] AS t
        USING (SELECT x.pos, s.new_id AS section_id, x.field_type, x.label, x.help_text, x.is_required, x.min_value, x.max_value
               FROM @fld x LEFT JOIN @sec s ON s.skey = x.skey WHERE x.id IS NULL) AS src ON 1 = 0
        WHEN NOT MATCHED THEN INSERT (form_id, form_section_id, sort_order, field_type, label, help_text, is_required, min_value,
                                      max_value, created_by)
             VALUES (@id, src.section_id, src.pos, src.field_type, src.label, src.help_text, src.is_required, src.min_value,
                     src.max_value, @actor_user_id)
        OUTPUT src.pos, inserted.id INTO @map (pos, id);
        UPDATE x SET new_id = m.id FROM @fld x JOIN @map m ON m.pos = x.pos;

        DELETE s FROM [frm].[form_section] s
        WHERE s.form_id = @id AND NOT EXISTS (SELECT 1 FROM @sec x WHERE x.new_id = s.id);

        -- Options: remove the ones left out, keep and reorder the rest, add new ones.
        DELETE o FROM [frm].[form_field_option] o JOIN @fld f ON f.new_id = o.form_field_id
        WHERE NOT EXISTS (SELECT 1 FROM @opt x WHERE x.field_pos = f.pos AND x.id = o.id);
        UPDATE o SET sort_order = x.pos, label = x.label, updated_at = @now, updated_by = @actor_user_id
        FROM [frm].[form_field_option] o JOIN @opt x ON x.id = o.id;
        INSERT [frm].[form_field_option] (form_field_id, sort_order, label, created_by)
        SELECT f.new_id, x.pos, x.label, @actor_user_id FROM @opt x JOIN @fld f ON f.pos = x.field_pos WHERE x.id IS NULL;
    COMMIT;

    EXEC [frm].[usp_form_get] @company_id = @company_id, @id = @id;
END
GO

-- Deletes a form with its responses. Refused while it is open (published, not past its closing date)
-- and has responses: close it first.
CREATE OR ALTER PROCEDURE [frm].[usp_form_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @closes DATE;
    SELECT @rv = row_version, @status = status, @closes = closes_on FROM [frm].[form] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Form not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'rowVersion|STALE_ROW_VERSION|Someone else changed this form. Reload it and try again.', 1;
    IF @status = N'published' AND (@closes IS NULL OR @closes >= @today)
       AND EXISTS (SELECT 1 FROM [frm].[form_response] WHERE form_id = @id)
        THROW 50409, N'id|FORM_HAS_RESPONSES|People have answered this form. Close it before deleting it.', 1;

    BEGIN TRAN;
        DELETE ao FROM [frm].[form_answer_option] ao
        JOIN [frm].[form_answer] a ON a.id = ao.form_answer_id
        JOIN [frm].[form_response] r ON r.id = a.form_response_id
        WHERE r.form_id = @id;
        DELETE a FROM [frm].[form_answer] a JOIN [frm].[form_response] r ON r.id = a.form_response_id WHERE r.form_id = @id;
        DELETE [frm].[form_response] WHERE form_id = @id;
        DELETE o FROM [frm].[form_field_option] o JOIN [frm].[form_field] f ON f.id = o.form_field_id WHERE f.form_id = @id;
        DELETE [frm].[form_field] WHERE form_id = @id;
        DELETE [frm].[form_section] WHERE form_id = @id;
        DELETE [frm].[form_audience] WHERE form_id = @id;
        DELETE [frm].[form] WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'rowVersion|STALE_ROW_VERSION|Someone else changed this form. Reload it and try again.', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'frm.form', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Publishes a draft, or reopens a closed form. It needs at least one question and a closing date that
-- has not passed.
CREATE OR ALTER PROCEDURE [frm].[usp_form_publish]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @closes DATE;
    SELECT @rv = row_version, @status = status, @closes = closes_on FROM [frm].[form] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Form not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'rowVersion|STALE_ROW_VERSION|Someone else changed this form. Reload it and try again.', 1;
    IF @status = N'published' AND (@closes IS NULL OR @closes >= @today)
        THROW 50409, N'status|FORM_PUBLISHED|This form is already published.', 1;
    IF NOT EXISTS (SELECT 1 FROM [frm].[form_field] WHERE form_id = @id)
        THROW 50400, N'fields|Add at least one question before publishing.', 1;
    IF @closes < @today
        THROW 50400, N'closesOn|The closing date has passed. Move it before publishing.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [frm].[form]
        SET status = N'published', published_at = @now, published_by_user_id = @actor_user_id, closed_at = NULL,
            closed_by_user_id = NULL, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'rowVersion|STALE_ROW_VERSION|Someone else changed this form. Reload it and try again.', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'frm.form', @id, N'publish', @actor_user_id, @now);

        -- TODO(business): tell the audience in the inbox (core.usp_notification_add_employee, @quiet = 1).
        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), f.id) AS formId, f.title, f.category, f.is_anonymous AS anonymous,
                   f.closes_on AS closesOn, f.audience_kind AS audienceKind,
                   (SELECT COUNT(*) FROM [frm].[fn_form_audience](@company_id, @id)) AS audienceCount,
                   f.published_at AS publishedAt
            FROM [frm].[form] f WHERE f.id = @id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'forms.form_published',
             @entity_type = N'frm.form', @entity_id = @id, @payload = @payload;
    COMMIT;

    EXEC [frm].[usp_form_get] @company_id = @company_id, @id = @id;
END
GO

-- Closes a published form now: no more answers; the responses stay.
CREATE OR ALTER PROCEDURE [frm].[usp_form_close]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @status NVARCHAR(30);
    SELECT @rv = row_version, @status = status FROM [frm].[form] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Form not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'rowVersion|STALE_ROW_VERSION|Someone else changed this form. Reload it and try again.', 1;
    IF @status <> N'published'
        THROW 50409, N'status|FORM_NOT_PUBLISHED|Only a published form can be closed.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [frm].[form]
        SET status = N'closed', closed_at = @now, closed_by_user_id = @actor_user_id, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'rowVersion|STALE_ROW_VERSION|Someone else changed this form. Reload it and try again.', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'frm.form', @id, N'close', @actor_user_id, @now);

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), f.id) AS formId, f.title,
                   (SELECT COUNT(*) FROM [frm].[form_response] r WHERE r.form_id = f.id) AS responseCount, f.closed_at AS closedAt
            FROM [frm].[form] f WHERE f.id = @id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'forms.form_closed',
             @entity_type = N'frm.form', @entity_id = @id, @payload = @payload;
    COMMIT;

    EXEC [frm].[usp_form_get] @company_id = @company_id, @id = @id;
END
GO

-- A draft copy ("Copy of ...") with the same sections, questions, options, audience and settings, new
-- ids and no responses. A closing date that has passed is not copied.
CREATE OR ALTER PROCEDURE [frm].[usp_form_duplicate]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [frm].[form] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Form not found', 1;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE), @now DATETIME2(0) = SYSUTCDATETIME(), @new BIGINT;
    DECLARE @smap TABLE (old_id BIGINT PRIMARY KEY, new_id BIGINT);
    DECLARE @fmap TABLE (old_id BIGINT PRIMARY KEY, new_id BIGINT);

    BEGIN TRAN;
        INSERT [frm].[form] (company_id, title, description, category, status, closes_on, audience_kind, is_one_per_person,
                             is_anonymous, created_by)
        SELECT company_id, LEFT(CONCAT(N'Copy of ', title), 200), description, category, N'draft',
               CASE WHEN closes_on >= @today THEN closes_on END, audience_kind, is_one_per_person, is_anonymous, @actor_user_id
        FROM [frm].[form] WHERE id = @id;
        SET @new = SCOPE_IDENTITY();

        INSERT [frm].[form_audience] (form_id, unit_type, unit_id, created_by)
        SELECT @new, unit_type, unit_id, @actor_user_id FROM [frm].[form_audience] WHERE form_id = @id;

        MERGE [frm].[form_section] AS t
        USING (SELECT id, sort_order, title, description FROM [frm].[form_section] WHERE form_id = @id) AS src ON 1 = 0
        WHEN NOT MATCHED THEN INSERT (form_id, sort_order, title, description, created_by)
             VALUES (@new, src.sort_order, src.title, src.description, @actor_user_id)
        OUTPUT src.id, inserted.id INTO @smap (old_id, new_id);

        MERGE [frm].[form_field] AS t
        USING (SELECT f.id, m.new_id AS section_id, f.sort_order, f.field_type, f.label, f.help_text, f.is_required,
                      f.min_value, f.max_value
               FROM [frm].[form_field] f LEFT JOIN @smap m ON m.old_id = f.form_section_id
               WHERE f.form_id = @id) AS src ON 1 = 0
        WHEN NOT MATCHED THEN INSERT (form_id, form_section_id, sort_order, field_type, label, help_text, is_required, min_value,
                                      max_value, created_by)
             VALUES (@new, src.section_id, src.sort_order, src.field_type, src.label, src.help_text, src.is_required,
                     src.min_value, src.max_value, @actor_user_id)
        OUTPUT src.id, inserted.id INTO @fmap (old_id, new_id);

        INSERT [frm].[form_field_option] (form_field_id, sort_order, label, created_by)
        SELECT m.new_id, o.sort_order, o.label, @actor_user_id
        FROM [frm].[form_field_option] o JOIN @fmap m ON m.old_id = o.form_field_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, new_value, performed_by_user_id, performed_at)
        VALUES (@company_id, N'frm.form', @new, N'create', CONCAT(N'copy of ', @id), @actor_user_id, @now);
    COMMIT;

    EXEC [frm].[usp_form_get] @company_id = @company_id, @id = @new;
END
