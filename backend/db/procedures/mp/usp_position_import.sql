-- Upload Excel on Employee Position: rows already read from the sheet, given by names as JSON
--   [{"code", "positionTitle", "station", "employeeGroup", "division", "department", "subDepartment",
--     "costCenter", "grade", "reportsTo", "minSalary", "maxSalary"}]
-- Names are matched to the company's records (cost center by name or code, reports-to by position code,
-- in the database or earlier in the file). Valid rows are added; the others are reported, by row number
-- (1 = the first data row). Result set 1: {created}. Result set 2: errors {row_no, field, message}.
CREATE OR ALTER PROCEDURE [mp].[usp_position_import]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @rows          NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @rows IS NULL OR ISJSON(@rows) = 0 OR LEFT(LTRIM(@rows), 1) <> N'['
        THROW 50400, N'rows|Rows must be a JSON list.', 1;

    CREATE TABLE #r (
        row_no INT PRIMARY KEY, code NVARCHAR(30), position_title NVARCHAR(200), station NVARCHAR(200),
        employee_group NVARCHAR(200), division NVARCHAR(200), department NVARCHAR(200), sub_department NVARCHAR(200),
        cost_center NVARCHAR(200), grade NVARCHAR(200), reports_to NVARCHAR(30), min_text NVARCHAR(50), max_text NVARCHAR(50),
        job_title_id BIGINT, branch_id BIGINT, employee_group_id BIGINT, division_id BIGINT, department_id BIGINT,
        sub_department_id BIGINT, cost_center_id BIGINT, grade_id BIGINT, min_salary DECIMAL(18,2), max_salary DECIMAL(18,2),
        new_id BIGINT, err_field NVARCHAR(50), err NVARCHAR(400));

    INSERT #r (row_no, code, position_title, station, employee_group, division, department, sub_department, cost_center,
               grade, reports_to, min_text, max_text)
    SELECT CAST(j.[key] AS INT) + 1,
           NULLIF(LTRIM(RTRIM(JSON_VALUE(j.value, '$.code'))), N''),
           NULLIF(LTRIM(RTRIM(JSON_VALUE(j.value, '$.positionTitle'))), N''),
           NULLIF(LTRIM(RTRIM(JSON_VALUE(j.value, '$.station'))), N''),
           NULLIF(LTRIM(RTRIM(JSON_VALUE(j.value, '$.employeeGroup'))), N''),
           NULLIF(LTRIM(RTRIM(JSON_VALUE(j.value, '$.division'))), N''),
           NULLIF(LTRIM(RTRIM(JSON_VALUE(j.value, '$.department'))), N''),
           NULLIF(LTRIM(RTRIM(JSON_VALUE(j.value, '$.subDepartment'))), N''),
           NULLIF(LTRIM(RTRIM(JSON_VALUE(j.value, '$.costCenter'))), N''),
           NULLIF(LTRIM(RTRIM(JSON_VALUE(j.value, '$.grade'))), N''),
           NULLIF(LTRIM(RTRIM(JSON_VALUE(j.value, '$.reportsTo'))), N''),
           JSON_VALUE(j.value, '$.minSalary'), JSON_VALUE(j.value, '$.maxSalary')
    FROM OPENJSON(@rows) j;

    IF NOT EXISTS (SELECT 1 FROM #r)
        THROW 50400, N'rows|The file has no rows.', 1;
    IF (SELECT COUNT(*) FROM #r) > 2000
        THROW 50400, N'rows|Import at most 2000 rows at a time.', 1;

    UPDATE r SET
        job_title_id = (SELECT TOP (1) id FROM [org].[job_title] x WHERE x.company_id = @company_id AND x.name = r.position_title),
        branch_id = (SELECT TOP (1) id FROM [org].[branch] x WHERE x.company_id = @company_id AND x.name = r.station),
        employee_group_id = (SELECT TOP (1) id FROM [org].[employee_group] x WHERE x.company_id = @company_id AND x.name = r.employee_group),
        division_id = (SELECT TOP (1) id FROM [org].[division] x WHERE x.company_id = @company_id AND x.name = r.division),
        department_id = (SELECT TOP (1) id FROM [org].[department] x WHERE x.company_id = @company_id AND x.name = r.department),
        cost_center_id = (SELECT TOP (1) id FROM [org].[cost_center] x WHERE x.company_id = @company_id AND (x.name = r.cost_center OR x.code = r.cost_center)),
        grade_id = (SELECT TOP (1) id FROM [org].[grade] x WHERE x.company_id = @company_id AND x.name = r.grade),
        min_salary = TRY_CAST(REPLACE(r.min_text, N',', N'') AS DECIMAL(18,2)),
        max_salary = TRY_CAST(REPLACE(r.max_text, N',', N'') AS DECIMAL(18,2))
    FROM #r r;

    UPDATE r SET sub_department_id = (SELECT TOP (1) id FROM [org].[department] x WHERE x.company_id = @company_id
                                      AND x.name = r.sub_department AND (r.department_id IS NULL OR x.parent_id = r.department_id))
    FROM #r r WHERE r.sub_department IS NOT NULL;

    -- First problem per row wins.
    UPDATE #r SET err_field = N'positionTitle', err = CASE WHEN position_title IS NULL THEN N'Position title is required.'
                  ELSE CONCAT(N'Position title "', position_title, N'" not found.') END
    WHERE err IS NULL AND job_title_id IS NULL;
    UPDATE #r SET err_field = N'station', err = CASE WHEN station IS NULL THEN N'Station is required.'
                  ELSE CONCAT(N'Station "', station, N'" not found.') END
    WHERE err IS NULL AND branch_id IS NULL;
    UPDATE #r SET err_field = N'employeeGroup', err = CASE WHEN employee_group IS NULL THEN N'Employee group is required.'
                  ELSE CONCAT(N'Employee group "', employee_group, N'" not found.') END
    WHERE err IS NULL AND employee_group_id IS NULL;
    UPDATE #r SET err_field = N'division', err = CONCAT(N'Division "', division, N'" not found.')
    WHERE err IS NULL AND division IS NOT NULL AND division_id IS NULL;
    UPDATE #r SET err_field = N'department', err = CONCAT(N'Department "', department, N'" not found.')
    WHERE err IS NULL AND department IS NOT NULL AND department_id IS NULL;
    UPDATE #r SET err_field = N'subDepartment', err = CONCAT(N'Sub department "', sub_department, N'" not found under the department.')
    WHERE err IS NULL AND sub_department IS NOT NULL AND sub_department_id IS NULL;
    UPDATE #r SET err_field = N'costCenter', err = CONCAT(N'Cost center "', cost_center, N'" not found.')
    WHERE err IS NULL AND cost_center IS NOT NULL AND cost_center_id IS NULL;
    UPDATE #r SET err_field = N'grade', err = CONCAT(N'Grade "', grade, N'" not found.')
    WHERE err IS NULL AND grade IS NOT NULL AND grade_id IS NULL;
    UPDATE #r SET err_field = N'minSalary', err = N'Min salary must be a number of 0 or more.'
    WHERE err IS NULL AND (min_salary IS NULL OR min_salary < 0);
    UPDATE #r SET err_field = N'maxSalary', err = N'Max salary must be a number above 0, not below the min salary.'
    WHERE err IS NULL AND (max_salary IS NULL OR max_salary <= 0 OR max_salary < min_salary);
    UPDATE r SET err_field = N'code', err = CONCAT(N'Code "', r.code, N'" already exists.')
    FROM #r r
    WHERE r.err IS NULL AND r.code IS NOT NULL
      AND (EXISTS (SELECT 1 FROM [mp].[position] p WHERE p.company_id = @company_id AND p.code = r.code)
           OR EXISTS (SELECT 1 FROM #r o WHERE o.code = r.code AND o.row_no < r.row_no));
    UPDATE r SET err_field = N'reportsTo', err = CONCAT(N'Reports-to position "', r.reports_to, N'" not found.')
    FROM #r r
    WHERE r.err IS NULL AND r.reports_to IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM [mp].[position] p WHERE p.company_id = @company_id AND p.code = r.reports_to)
      AND NOT EXISTS (SELECT 1 FROM #r o WHERE o.code = r.reports_to AND o.row_no < r.row_no AND o.err IS NULL);

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @map TABLE (row_no INT PRIMARY KEY, id BIGINT);

    BEGIN TRAN;
        DECLARE @next INT = 1 + ISNULL((SELECT MAX(TRY_CAST(SUBSTRING(code, 5, 26) AS INT))
                                       FROM [mp].[position] WITH (UPDLOCK, HOLDLOCK)
                                       WHERE company_id = @company_id AND code LIKE N'POS-%'), 0);
        -- Numbers above any POS- code in the file too.
        SET @next = (SELECT MAX(v) FROM (VALUES (@next),
                     (1 + ISNULL((SELECT MAX(TRY_CAST(SUBSTRING(code, 5, 26) AS INT)) FROM #r WHERE code LIKE N'POS-%'), 0))) n (v));
        WITH blank AS (SELECT row_no, ROW_NUMBER() OVER (ORDER BY row_no) - 1 AS k FROM #r WHERE err IS NULL AND code IS NULL)
        UPDATE r SET code = N'POS-' + RIGHT(N'0000' + CAST(@next + b.k AS NVARCHAR(10)), CASE WHEN @next + b.k > 9999 THEN 10 ELSE 4 END)
        FROM #r r JOIN blank b ON b.row_no = r.row_no;

        MERGE [mp].[position] AS t
        USING (SELECT * FROM #r WHERE err IS NULL) AS s ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (company_id, code, branch_id, job_title_id, employee_group_id, division_id, department_id,
                    sub_department_id, cost_center_id, grade_id, status, created_by)
            VALUES (@company_id, s.code, s.branch_id, s.job_title_id, s.employee_group_id, s.division_id, s.department_id,
                    s.sub_department_id, s.cost_center_id, s.grade_id, N'active', @actor_user_id)
        OUTPUT s.row_no, INSERTED.id INTO @map (row_no, id);

        INSERT [mp].[position_salary_range] (position_id, effective_date, min_salary, max_salary, created_by)
        SELECT m.id, @today, r.min_salary, r.max_salary, @actor_user_id
        FROM @map m JOIN #r r ON r.row_no = m.row_no;

        UPDATE p SET reports_to_id = boss.id
        FROM @map m
        JOIN #r r ON r.row_no = m.row_no
        JOIN [mp].[position] p ON p.id = m.id
        JOIN [mp].[position] boss ON boss.company_id = @company_id AND boss.code = r.reports_to
        WHERE r.reports_to IS NOT NULL;

        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        SELECT N'mp.position', m.id, N'import', @actor_user_id, @now FROM @map m;
    COMMIT;

    SELECT COUNT(*) AS created FROM @map;
    SELECT row_no, err_field AS field, err AS message FROM #r WHERE err IS NOT NULL ORDER BY row_no;
END
