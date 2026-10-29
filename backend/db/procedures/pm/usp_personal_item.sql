-- Personal List (Backend Dependencies T11): the Home dashboard's private to-dos of the signed-in person,
-- not tied to a workspace. Open items first, then by due date (none last), newest first.

CREATE OR ALTER PROCEDURE [pm].[usp_personal_item_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pm].[personal_item] WHERE id = @id AND company_id = @company_id
                                       AND user_account_id = @actor_user_id)
        THROW 50404, N'Item not found', 1;

    SELECT i.id, i.title, i.is_done AS done, i.due_date, i.done_at, i.created_at, i.row_version
    FROM [pm].[personal_item] i
    WHERE i.company_id = @company_id AND i.user_account_id = @actor_user_id AND (@id IS NULL OR i.id = @id)
    ORDER BY i.is_done, CASE WHEN i.due_date IS NULL THEN 1 ELSE 0 END, i.due_date, i.created_at DESC, i.id DESC;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_personal_item_add]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @title         NVARCHAR(400),
    @due_date      DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @title = LTRIM(RTRIM(@title));
    IF @title IS NULL OR LEN(@title) NOT BETWEEN 1 AND 120
        THROW 50400, N'title|Write what you need to do (up to 120 characters).', 1;
    IF (SELECT COUNT(*) FROM [pm].[personal_item] WHERE company_id = @company_id AND user_account_id = @actor_user_id) >= 500
        THROW 50409, N'title|PERSONAL_LIST_FULL|Your list is full. Delete done items first.', 1;

    DECLARE @id BIGINT;
    INSERT [pm].[personal_item] (company_id, user_account_id, title, is_done, due_date, created_by)
    VALUES (@company_id, @actor_user_id, @title, 0, @due_date, @actor_user_id);
    SET @id = SCOPE_IDENTITY();

    EXEC [pm].[usp_personal_item_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_personal_item_set_done]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @is_done       BIT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [pm].[personal_item] WHERE id = @id AND company_id = @company_id AND user_account_id = @actor_user_id)
        THROW 50404, N'Item not found', 1;
    UPDATE [pm].[personal_item]
    SET is_done = @is_done, done_at = CASE WHEN @is_done = 1 THEN ISNULL(done_at, SYSUTCDATETIME()) END,
        updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
    WHERE id = @id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 50409, N'Someone changed this item. Reload and try again.', 1;

    EXEC [pm].[usp_personal_item_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_personal_item_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [pm].[personal_item] WHERE id = @id AND company_id = @company_id
                             AND user_account_id = @actor_user_id);
    IF @rv IS NULL
        THROW 50404, N'Item not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone changed this item. Reload and try again.', 1;
    DELETE [pm].[personal_item] WHERE id = @id;
END
