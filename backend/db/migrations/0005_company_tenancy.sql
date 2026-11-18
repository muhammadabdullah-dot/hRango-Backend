-- Tenancy fixes (roadmap 0.4 and BE-06 b, d).
--
-- 1. Company names are unique within one organisation, not across the whole platform: the global
--    UQ_company_name told any customer, through a 409, which names other customers use. The rule now
--    lives in org.usp_company_save.
-- 2. The default HR Manager role no longer creates companies (its creator becomes that company's
--    administrator, with users, roles and webhooks). Removed only from the built-in HR Manager roles;
--    the default offer stays recorded, so the next seed run does not grant it again.
-- 3. Companies a customer created before this fix were not linked to the customer, so its plan,
--    billing and suspension did not reach them. Each is linked to the organisation of its creator.
-- Checks first, like 0002, so it also runs on a baseline rebuilt from the ERD.

IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = N'UQ_company_name' AND parent_object_id = OBJECT_ID(N'org.company'))
    ALTER TABLE [org].[company] DROP CONSTRAINT [UQ_company_name];
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'org.company') AND name = N'IX_company_name')
    CREATE NONCLUSTERED INDEX [IX_company_name] ON [org].[company] ([name]);
GO

DELETE rp
FROM [auth].[role_permission] rp
JOIN [auth].[role] r ON r.id = rp.role_id AND r.code = N'hr_manager' AND r.is_system = 1
JOIN [auth].[permission] p ON p.id = rp.permission_id AND p.code = N'organisation.companies.create';
GO

INSERT [plat].[customer_company] (customer_id, company_id, created_by)
SELECT cc.customer_id, c.id, c.created_by
FROM [org].[company] c
JOIN [auth].[user_account] u ON u.id = c.created_by
JOIN [plat].[customer_company] cc ON cc.company_id = u.company_id
WHERE NOT EXISTS (SELECT 1 FROM [plat].[customer_company] x WHERE x.company_id = c.id);
GO
