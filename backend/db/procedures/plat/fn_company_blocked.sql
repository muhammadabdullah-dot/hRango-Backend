-- 1 when the company belongs to an organisation that platform staff suspended or cancelled
-- (plat.usp_customer_status_set). Such a company gets no service: no sign-in or company switch, no
-- webhooks, no nightly jobs or reminders, and its public share links answer "not found" (roadmap 0.3).
-- Set-based queries inline the same NOT EXISTS instead of calling this per row.
CREATE OR ALTER FUNCTION [plat].[fn_company_blocked] (@company_id BIGINT)
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN EXISTS (SELECT 1 FROM [plat].[customer_company] cc
                             JOIN [plat].[customer] c ON c.id = cc.customer_id AND c.status <> N'active'
                             WHERE cc.company_id = @company_id) THEN 1 ELSE 0 END;
END
GO
