-- HRango baseline schema. Generated from erd/source/*.md by erd/build.py. Do not edit by hand:
-- change erd/source/*.md and rebuild. Once a database outside development has this applied,
-- freeze this file and put further changes in new numbered migrations.
SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
GO

IF SCHEMA_ID(N'org') IS NULL EXEC(N'CREATE SCHEMA [org]');
GO
IF SCHEMA_ID(N'hr') IS NULL EXEC(N'CREATE SCHEMA [hr]');
GO
IF SCHEMA_ID(N'auth') IS NULL EXEC(N'CREATE SCHEMA [auth]');
GO
IF SCHEMA_ID(N'sch') IS NULL EXEC(N'CREATE SCHEMA [sch]');
GO
IF SCHEMA_ID(N'att') IS NULL EXEC(N'CREATE SCHEMA [att]');
GO
IF SCHEMA_ID(N'lv') IS NULL EXEC(N'CREATE SCHEMA [lv]');
GO
IF SCHEMA_ID(N'req') IS NULL EXEC(N'CREATE SCHEMA [req]');
GO
IF SCHEMA_ID(N'loan') IS NULL EXEC(N'CREATE SCHEMA [loan]');
GO
IF SCHEMA_ID(N'pay') IS NULL EXEC(N'CREATE SCHEMA [pay]');
GO
IF SCHEMA_ID(N'sep') IS NULL EXEC(N'CREATE SCHEMA [sep]');
GO
IF SCHEMA_ID(N'rec') IS NULL EXEC(N'CREATE SCHEMA [rec]');
GO
IF SCHEMA_ID(N'mp') IS NULL EXEC(N'CREATE SCHEMA [mp]');
GO
IF SCHEMA_ID(N'core') IS NULL EXEC(N'CREATE SCHEMA [core]');
GO
IF SCHEMA_ID(N'eng') IS NULL EXEC(N'CREATE SCHEMA [eng]');
GO
IF SCHEMA_ID(N'pm') IS NULL EXEC(N'CREATE SCHEMA [pm]');
GO
IF SCHEMA_ID(N'ben') IS NULL EXEC(N'CREATE SCHEMA [ben]');
GO
IF SCHEMA_ID(N'perf') IS NULL EXEC(N'CREATE SCHEMA [perf]');
GO
IF SCHEMA_ID(N'trn') IS NULL EXEC(N'CREATE SCHEMA [trn]');
GO
IF SCHEMA_ID(N'frm') IS NULL EXEC(N'CREATE SCHEMA [frm]');
GO

CREATE TABLE [org].[company] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [legal_name] NVARCHAR(200) NULL,
    [logo_file_id] BIGINT NULL,
    [email] NVARCHAR(254) NULL,
    [phone] NVARCHAR(30) NULL,
    [website] NVARCHAR(200) NULL,
    [address] NVARCHAR(500) NULL,
    [country_id] BIGINT NULL,
    [currency] CHAR(3) NULL,
    [timezone] NVARCHAR(64) NULL,
    [date_format] NVARCHAR(200) NULL,
    [week_start_day] NVARCHAR(30) NULL,
    [fiscal_year_start_month] INT NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_company_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_company_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_company] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_company_name] UNIQUE ([name])
);
GO
CREATE TABLE [org].[country] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [iso_code] CHAR(2) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_country_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_country] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_country_iso_code] UNIQUE ([iso_code])
);
GO
CREATE TABLE [org].[state] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [country_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_state_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_state] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_state_code] UNIQUE ([code])
);
GO
CREATE TABLE [org].[city] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [state_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_city_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_city] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_city_state_id_name] UNIQUE ([state_id], [name])
);
GO
CREATE TABLE [org].[location] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [employee_prefix] NVARCHAR(10) NULL,
    [description] NVARCHAR(MAX) NULL,
    [latitude] DECIMAL(9,6) NULL,
    [longitude] DECIMAL(9,6) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_location_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_location] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_location_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [org].[area] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [location_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_area_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_area] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_area_location_id_name] UNIQUE ([location_id], [name])
);
GO
CREATE TABLE [org].[branch] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [location_id] BIGINT NOT NULL,
    [area_id] BIGINT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [employee_prefix] NVARCHAR(10) NULL,
    [description] NVARCHAR(MAX) NULL,
    [manager_id] BIGINT NULL,
    [country_id] BIGINT NULL,
    [state_id] BIGINT NULL,
    [city_id] BIGINT NULL,
    [latitude] DECIMAL(9,6) NULL,
    [longitude] DECIMAL(9,6) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_branch_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_branch] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_branch_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [org].[department] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [parent_id] BIGINT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [head_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_department_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_department] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_department_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [org].[division] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_division_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_division] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_division_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [org].[cost_center] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_cost_center_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_cost_center] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_cost_center_company_id_code] UNIQUE ([company_id], [code]),
    CONSTRAINT [UQ_cost_center_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [org].[designation] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_designation_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_designation] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_designation_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [org].[job_title] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [limit_head_count] BIT NOT NULL CONSTRAINT [DF_job_title_limit_head_count] DEFAULT 0,
    [max_head_count] INT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_job_title_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_job_title] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_job_title_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [org].[grade] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_grade_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_grade] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_grade_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [org].[job_level] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_job_level_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_job_level] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_job_level_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [org].[employee_group] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_group_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_group] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_employee_group_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [org].[employment_type] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employment_type_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employment_type] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_employment_type_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [hr].[employee] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [first_name] NVARCHAR(200) NOT NULL,
    [last_name] NVARCHAR(200) NOT NULL,
    [parent_name] NVARCHAR(200) NULL,
    [gender] NVARCHAR(30) NULL,
    [marital_status] NVARCHAR(30) NULL,
    [religion] NVARCHAR(50) NULL,
    [nationality] NVARCHAR(50) NULL,
    [date_of_birth] DATE NULL,
    [cnic] NVARCHAR(15) NULL,
    [email] NVARCHAR(254) NULL,
    [phone_1] NVARCHAR(30) NULL,
    [phone_2] NVARCHAR(30) NULL,
    [home_address] NVARCHAR(500) NULL,
    [home_city_id] BIGINT NULL,
    [photo_file_id] BIGINT NULL,
    [branch_id] BIGINT NOT NULL,
    [location_id] BIGINT NULL,
    [area_id] BIGINT NULL,
    [department_id] BIGINT NULL,
    [division_id] BIGINT NULL,
    [cost_center_id] BIGINT NULL,
    [designation_id] BIGINT NULL,
    [job_title_id] BIGINT NULL,
    [grade_id] BIGINT NULL,
    [job_level_id] BIGINT NULL,
    [employee_group_id] BIGINT NULL,
    [employment_type_id] BIGINT NULL,
    [line_manager_id] BIGINT NULL,
    [final_authority_id] BIGINT NULL,
    [default_time_slot_id] BIGINT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [salary_frequency] NVARCHAR(30) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_employee_company_id_code] UNIQUE ([company_id], [code])
);
GO
CREATE TABLE [hr].[employment_period] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [joining_date] DATE NOT NULL,
    [confirmation_date] DATE NULL,
    [probation_end_date] DATE NULL,
    [end_date] DATE NULL,
    [end_of_employment_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employment_period_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employment_period] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [hr].[employee_history] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [change_type] NVARCHAR(30) NOT NULL,
    [effective_date] DATE NOT NULL,
    [location_id] BIGINT NULL,
    [branch_id] BIGINT NULL,
    [department_id] BIGINT NULL,
    [designation_id] BIGINT NULL,
    [job_title_id] BIGINT NULL,
    [grade_id] BIGINT NULL,
    [job_level_id] BIGINT NULL,
    [line_manager_id] BIGINT NULL,
    [final_authority_id] BIGINT NULL,
    [source_request_id] BIGINT NULL,
    [previous_values] NVARCHAR(MAX) NULL,
    [is_reverted] BIT NOT NULL CONSTRAINT [DF_employee_history_is_reverted] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_history_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_history] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [hr].[employee_salary] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [effective_date] DATE NOT NULL,
    [amount] DECIMAL(18,2) NOT NULL,
    [previous_amount] DECIMAL(18,2) NULL,
    [change_type] NVARCHAR(30) NULL,
    [change_value] DECIMAL(18,2) NULL,
    [source] NVARCHAR(30) NULL,
    [source_request_id] BIGINT NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_salary_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_salary] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [hr].[employee_pay_item] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [pay_item_id] BIGINT NULL,
    [amount] DECIMAL(18,2) NULL,
    [effective_date] DATE NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_pay_item_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_pay_item] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [hr].[employee_bank_account] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [account_holder] NVARCHAR(200) NULL,
    [account_number] NVARCHAR(50) NOT NULL,
    [bank_name] NVARCHAR(200) NOT NULL,
    [branch_name] NVARCHAR(200) NULL,
    [branch_code] NVARCHAR(30) NULL,
    [tax_payer_id] NVARCHAR(30) NULL,
    [is_primary] BIT NOT NULL CONSTRAINT [DF_employee_bank_account_is_primary] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_bank_account_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_bank_account] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_employee_bank_account_employee_id_account_number] UNIQUE ([employee_id], [account_number])
);
GO
CREATE TABLE [hr].[employee_document] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [document_type] NVARCHAR(30) NOT NULL,
    [title] NVARCHAR(200) NULL,
    [document_number] NVARCHAR(100) NULL,
    [issue_date] DATE NULL,
    [expiry_date] DATE NULL,
    [file_id] BIGINT NOT NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [expiry_notified_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_document_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_document] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [hr].[employee_experience] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [company_name] NVARCHAR(200) NOT NULL,
    [role_title] NVARCHAR(100) NOT NULL,
    [from_date] DATE NOT NULL,
    [to_date] DATE NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_experience_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_experience] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [hr].[employee_agreement] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [file_id] BIGINT NULL,
    [accepted_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_agreement_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_agreement] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [hr].[employee_emergency_contact] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [relation] NVARCHAR(30) NOT NULL,
    [phone] NVARCHAR(30) NOT NULL,
    [alt_phone] NVARCHAR(30) NULL,
    [address] NVARCHAR(500) NULL,
    [is_primary] BIT NOT NULL CONSTRAINT [DF_employee_emergency_contact_is_primary] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_emergency_contact_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_emergency_contact] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [hr].[employee_dependent] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [first_name] NVARCHAR(200) NOT NULL,
    [last_name] NVARCHAR(200) NULL,
    [relation] NVARCHAR(30) NOT NULL,
    [occupation] NVARCHAR(200) NULL,
    [date_of_birth] DATE NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_dependent_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_dependent] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [hr].[employee_skill] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [skill_title] NVARCHAR(200) NOT NULL,
    [skill_level] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_skill_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_skill] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_employee_skill_employee_id_skill_title] UNIQUE ([employee_id], [skill_title])
);
GO
CREATE TABLE [hr].[employee_education] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [institute] NVARCHAR(200) NOT NULL,
    [from_date] DATE NULL,
    [to_date] DATE NULL,
    [is_in_process] BIT NOT NULL CONSTRAINT [DF_employee_education_is_in_process] DEFAULT 0,
    [file_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_education_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_education] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [hr].[employee_contract] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [contract_type] NVARCHAR(30) NOT NULL,
    [duration_months] INT NULL,
    [from_date] DATE NOT NULL,
    [to_date] DATE NULL,
    [file_id] BIGINT NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_contract_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_contract] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [hr].[employee_change_request] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [changes] NVARCHAR(MAX) NOT NULL,
    [previous_values] NVARCHAR(MAX) NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [decided_by_user_id] BIGINT NULL,
    [decided_at] DATETIME2(0) NULL,
    [decision_remarks] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_change_request_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_change_request] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [auth].[user_account] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NULL,
    [company_id] BIGINT NOT NULL,
    [display_name] NVARCHAR(200) NULL,
    [email] NVARCHAR(254) NOT NULL,
    [password_hash] NVARCHAR(255) NOT NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_user_account_is_active] DEFAULT 0,
    [is_system_admin] BIT NOT NULL CONSTRAINT [DF_user_account_is_system_admin] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_user_account_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_user_account] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_user_account_email] UNIQUE ([email])
);
GO
CREATE TABLE [auth].[permission] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [code] NVARCHAR(150) NOT NULL,
    [module] NVARCHAR(30) NOT NULL,
    [screen] NVARCHAR(100) NOT NULL,
    [action_code] NVARCHAR(50) NOT NULL,
    [label] NVARCHAR(200) NOT NULL,
    [hint] NVARCHAR(500) NULL,
    [is_sensitive] BIT NOT NULL CONSTRAINT [DF_permission_is_sensitive] DEFAULT 0,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_permission_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_permission] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_permission_code] UNIQUE ([code])
);
GO
CREATE TABLE [auth].[role] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [is_system] BIT NOT NULL CONSTRAINT [DF_role_is_system] DEFAULT 0,
    [is_active] BIT NOT NULL CONSTRAINT [DF_role_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_role_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_role] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_role_company_id_code] UNIQUE ([company_id], [code])
);
GO
CREATE TABLE [auth].[role_permission] (
    [role_id] BIGINT NOT NULL,
    [permission_id] BIGINT NOT NULL,
    [scope] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_role_permission_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_role_permission] PRIMARY KEY CLUSTERED ([role_id], [permission_id])
);
GO
CREATE TABLE [auth].[role_permission_unit] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [role_id] BIGINT NOT NULL,
    [permission_id] BIGINT NOT NULL,
    [unit_type] NVARCHAR(30) NOT NULL,
    [unit_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_role_permission_unit_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_role_permission_unit] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_role_permission_unit_role_id_permission_id_unit_type_unit_id] UNIQUE ([role_id], [permission_id], [unit_type], [unit_id])
);
GO
CREATE TABLE [auth].[role_default_offer] (
    [role_id] BIGINT NOT NULL,
    [permission_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_role_default_offer_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_role_default_offer] PRIMARY KEY CLUSTERED ([role_id], [permission_id])
);
GO
CREATE TABLE [auth].[user_role] (
    [user_account_id] BIGINT NOT NULL,
    [role_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_user_role_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_user_role] PRIMARY KEY CLUSTERED ([user_account_id], [role_id])
);
GO
CREATE TABLE [auth].[user_permission_override] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [user_account_id] BIGINT NOT NULL,
    [permission_id] BIGINT NOT NULL,
    [effect] NVARCHAR(30) NOT NULL,
    [scope] NVARCHAR(30) NULL,
    [reason] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_user_permission_override_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_user_permission_override] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_user_permission_override_company_id_user_account_id_permission_id] UNIQUE ([company_id], [user_account_id], [permission_id])
);
GO
CREATE TABLE [auth].[user_company] (
    [user_account_id] BIGINT NOT NULL,
    [company_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_user_company_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_user_company] PRIMARY KEY CLUSTERED ([user_account_id], [company_id])
);
GO
CREATE TABLE [auth].[user_session] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [user_account_id] BIGINT NOT NULL,
    [company_id] BIGINT NOT NULL,
    [refresh_token_hash] NVARCHAR(255) NULL,
    [device] NVARCHAR(200) NULL,
    [ip_address] NVARCHAR(45) NULL,
    [last_seen_at] DATETIME2(0) NULL,
    [expires_at] DATETIME2(0) NULL,
    [revoked_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_user_session_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_user_session] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [sch].[time_slot] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [color] NVARCHAR(20) NULL,
    [start_time] TIME(0) NOT NULL,
    [end_time] TIME(0) NOT NULL,
    [duration_minutes] INT NOT NULL,
    [workable_minutes] INT NOT NULL,
    [is_flexible] BIT NOT NULL CONSTRAINT [DF_time_slot_is_flexible] DEFAULT 0,
    [is_overnight] BIT NOT NULL CONSTRAINT [DF_time_slot_is_overnight] DEFAULT 0,
    [full_overtime] BIT NOT NULL CONSTRAINT [DF_time_slot_full_overtime] DEFAULT 0,
    [short_overtime] BIT NOT NULL CONSTRAINT [DF_time_slot_short_overtime] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_time_slot_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_time_slot] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_time_slot_company_id_code] UNIQUE ([company_id], [code]),
    CONSTRAINT [UQ_time_slot_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [sch].[break_type] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [start_identifier] NVARCHAR(50) NOT NULL,
    [end_identifier] NVARCHAR(50) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_break_type_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_break_type] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_break_type_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [sch].[time_slot_break] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [time_slot_id] BIGINT NOT NULL,
    [break_type_id] BIGINT NOT NULL,
    [start_time] TIME(0) NOT NULL,
    [end_time] TIME(0) NOT NULL,
    [is_inclusive] BIT NOT NULL CONSTRAINT [DF_time_slot_break_is_inclusive] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_time_slot_break_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_time_slot_break] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [sch].[roster_group] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [from_date] DATE NOT NULL,
    [to_date] DATE NULL,
    [description] NVARCHAR(MAX) NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_roster_group_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_roster_group_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_roster_group] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_roster_group_company_id_title] UNIQUE ([company_id], [title])
);
GO
CREATE TABLE [sch].[roster_group_day] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [roster_group_id] BIGINT NOT NULL,
    [weekday] TINYINT NOT NULL,
    [is_day_off] BIT NOT NULL CONSTRAINT [DF_roster_group_day_is_day_off] DEFAULT 0,
    [time_slot_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_roster_group_day_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_roster_group_day] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_roster_group_day_roster_group_id_weekday] UNIQUE ([roster_group_id], [weekday])
);
GO
CREATE TABLE [sch].[roster_group_member] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [roster_group_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [start_date] DATE NOT NULL,
    [end_date] DATE NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_roster_group_member_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_roster_group_member] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [sch].[schedule_batch] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [batch_kind] NVARCHAR(30) NOT NULL,
    [start_date] DATE NOT NULL,
    [end_date] DATE NOT NULL,
    [time_slot_id] BIGINT NULL,
    [roster_group_id] BIGINT NULL,
    [weekdays] NVARCHAR(30) NULL,
    [repeat_every_weeks] INT NOT NULL,
    [step] INT NOT NULL,
    [geo_fence_id] BIGINT NULL,
    [is_wfh] BIT NOT NULL CONSTRAINT [DF_schedule_batch_is_wfh] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_schedule_batch_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_schedule_batch] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [sch].[schedule] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [work_date] DATE NOT NULL,
    [start_at] DATETIME2(0) NOT NULL,
    [end_at] DATETIME2(0) NOT NULL,
    [time_slot_id] BIGINT NOT NULL,
    [schedule_batch_id] BIGINT NULL,
    [geo_fence_id] BIGINT NULL,
    [is_wfh] BIT NOT NULL CONSTRAINT [DF_schedule_is_wfh] DEFAULT 0,
    [planned_minutes] INT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_schedule_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_schedule] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_schedule_employee_id_start_at] UNIQUE ([employee_id], [start_at])
);
GO
CREATE TABLE [sch].[schedule_break] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [schedule_id] BIGINT NOT NULL,
    [break_type_id] BIGINT NOT NULL,
    [start_at] DATETIME2(0) NOT NULL,
    [end_at] DATETIME2(0) NOT NULL,
    [is_inclusive] BIT NOT NULL CONSTRAINT [DF_schedule_break_is_inclusive] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_schedule_break_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_schedule_break] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [sch].[rest_day_rule] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [from_date] DATE NOT NULL,
    [to_date] DATE NOT NULL,
    [weekdays] NVARCHAR(30) NOT NULL,
    [repeat_every_weeks] INT NOT NULL,
    [step] INT NOT NULL,
    [is_payable] BIT NOT NULL CONSTRAINT [DF_rest_day_rule_is_payable] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_rest_day_rule_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_rest_day_rule] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [sch].[rest_day_rule_employee] (
    [rest_day_rule_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_rest_day_rule_employee_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_rest_day_rule_employee] PRIMARY KEY CLUSTERED ([rest_day_rule_id], [employee_id])
);
GO
CREATE TABLE [sch].[rest_day] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [rest_date] DATE NOT NULL,
    [is_payable] BIT NOT NULL CONSTRAINT [DF_rest_day_is_payable] DEFAULT 0,
    [rest_day_rule_id] BIGINT NULL,
    [request_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_rest_day_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_rest_day] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_rest_day_employee_id_rest_date] UNIQUE ([employee_id], [rest_date])
);
GO
CREATE TABLE [sch].[holiday] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [holiday_type] NVARCHAR(30) NOT NULL,
    [start_date] DATE NOT NULL,
    [end_date] DATE NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [attendance_exempt] BIT NOT NULL CONSTRAINT [DF_holiday_attendance_exempt] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_holiday_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_holiday] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_holiday_company_id_name_start_date] UNIQUE ([company_id], [name], [start_date])
);
GO
CREATE TABLE [sch].[holiday_rule] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [holiday_id] BIGINT NOT NULL,
    [rule_type] NVARCHAR(30) NOT NULL,
    [employee_id] BIGINT NULL,
    [location_id] BIGINT NULL,
    [branch_id] BIGINT NULL,
    [country_id] BIGINT NULL,
    [state_id] BIGINT NULL,
    [city_id] BIGINT NULL,
    [religion] NVARCHAR(50) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_holiday_rule_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_holiday_rule] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [att].[device] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [model] NVARCHAR(100) NULL,
    [serial_no] NVARCHAR(50) NULL,
    [ip_address] NVARCHAR(45) NULL,
    [port] INT NULL,
    [branch_id] BIGINT NULL,
    [address] NVARCHAR(500) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [last_synced_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_device_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_device] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_device_company_id_code] UNIQUE ([company_id], [code]),
    CONSTRAINT [UQ_device_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [att].[device_enrolment] (
    [device_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [device_user_no] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_device_enrolment_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_device_enrolment] PRIMARY KEY CLUSTERED ([device_id], [employee_id]),
    CONSTRAINT [UQ_device_enrolment_device_id_device_user_no] UNIQUE ([device_id], [device_user_no])
);
GO
CREATE TABLE [att].[geo_fence] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [shape] NVARCHAR(30) NOT NULL,
    [center_lat] DECIMAL(9,6) NULL,
    [center_lng] DECIMAL(9,6) NULL,
    [radius_m] INT NULL,
    [polygon_points] NVARCHAR(MAX) NULL,
    [applies_to_all] BIT NOT NULL CONSTRAINT [DF_geo_fence_applies_to_all] DEFAULT 0,
    [joining_from_date] DATE NULL,
    [joining_to_date] DATE NULL,
    [is_for_shift] BIT NOT NULL CONSTRAINT [DF_geo_fence_is_for_shift] DEFAULT 0,
    [is_active] BIT NOT NULL CONSTRAINT [DF_geo_fence_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_geo_fence_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_geo_fence] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_geo_fence_company_id_code] UNIQUE ([company_id], [code]),
    CONSTRAINT [UQ_geo_fence_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [att].[geo_fence_target] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [geo_fence_id] BIGINT NOT NULL,
    [target_type] NVARCHAR(30) NOT NULL,
    [target_id] BIGINT NULL,
    [target_value] NVARCHAR(200) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_geo_fence_target_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_geo_fence_target] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [att].[ip_restriction] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [ipv4] NVARCHAR(45) NULL,
    [ipv6] NVARCHAR(45) NULL,
    [netmask] NVARCHAR(45) NULL,
    [range_start] NVARCHAR(45) NULL,
    [range_end] NVARCHAR(45) NULL,
    [applies_to_all] BIT NOT NULL CONSTRAINT [DF_ip_restriction_applies_to_all] DEFAULT 0,
    [is_active] BIT NOT NULL CONSTRAINT [DF_ip_restriction_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_ip_restriction_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_ip_restriction] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_ip_restriction_company_id_code] UNIQUE ([company_id], [code])
);
GO
CREATE TABLE [att].[ip_restriction_target] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [ip_restriction_id] BIGINT NOT NULL,
    [target_type] NVARCHAR(30) NOT NULL,
    [target_id] BIGINT NULL,
    [target_value] NVARCHAR(200) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_ip_restriction_target_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_ip_restriction_target] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [att].[punch] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [punched_at] DATETIME2(0) NOT NULL,
    [punch_type] NVARCHAR(30) NOT NULL,
    [break_type_id] BIGINT NULL,
    [source] NVARCHAR(30) NOT NULL,
    [device_id] BIGINT NULL,
    [latitude] DECIMAL(9,6) NULL,
    [longitude] DECIMAL(9,6) NULL,
    [ip_address] NVARCHAR(45) NULL,
    [photo_file_id] BIGINT NULL,
    [request_id] BIGINT NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [is_manually_updated] BIT NOT NULL CONSTRAINT [DF_punch_is_manually_updated] DEFAULT 0,
    [is_ignored] BIT NOT NULL CONSTRAINT [DF_punch_is_ignored] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_punch_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_punch] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_punch_employee_id_punched_at_punch_type] UNIQUE ([employee_id], [punched_at], [punch_type])
);
GO
CREATE TABLE [att].[timesheet_day] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [work_date] DATE NOT NULL,
    [schedule_id] BIGINT NULL,
    [expected_in] DATETIME2(0) NULL,
    [expected_out] DATETIME2(0) NULL,
    [expected_minutes] INT NULL,
    [first_in] DATETIME2(0) NULL,
    [last_out] DATETIME2(0) NULL,
    [worked_minutes] INT NULL,
    [break_minutes] INT NULL,
    [shift_worked_minutes] INT NULL,
    [late_minutes] INT NULL,
    [early_left_minutes] INT NULL,
    [overtime_before_minutes] INT NULL,
    [overtime_after_minutes] INT NULL,
    [approved_overtime_minutes] INT NULL,
    [grace_consumed_minutes] INT NULL,
    [day_status] NVARCHAR(30) NOT NULL,
    [marked_status] NVARCHAR(30) NULL,
    [leave_request_id] BIGINT NULL,
    [is_manually_updated] BIT NOT NULL CONSTRAINT [DF_timesheet_day_is_manually_updated] DEFAULT 0,
    [comments] NVARCHAR(MAX) NULL,
    [processed_at] DATETIME2(0) NULL,
    [is_frozen] BIT NOT NULL CONSTRAINT [DF_timesheet_day_is_frozen] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_timesheet_day_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_timesheet_day] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_timesheet_day_employee_id_work_date] UNIQUE ([employee_id], [work_date])
);
GO
CREATE TABLE [att].[timesheet_flag] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [timesheet_day_id] BIGINT NOT NULL,
    [flag] NVARCHAR(30) NOT NULL,
    [minutes] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_timesheet_flag_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_timesheet_flag] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [att].[timesheet_break] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [timesheet_day_id] BIGINT NOT NULL,
    [break_type_id] BIGINT NULL,
    [out_at] DATETIME2(0) NOT NULL,
    [in_at] DATETIME2(0) NULL,
    [minutes] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_timesheet_break_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_timesheet_break] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [att].[overtime_policy] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [period] NVARCHAR(30) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_overtime_policy_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_overtime_policy_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_overtime_policy] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_overtime_policy_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [att].[overtime_policy_slab] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [overtime_policy_id] BIGINT NOT NULL,
    [min_minutes] INT NOT NULL,
    [max_minutes] INT NOT NULL,
    [encashment_type] NVARCHAR(30) NOT NULL,
    [leave_type_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_overtime_policy_slab_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_overtime_policy_slab] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [lv].[leave_type] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [short_code] NVARCHAR(10) NULL,
    [allowance] DECIMAL(6,2) NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_leave_type_is_active] DEFAULT 0,
    [is_probation_type] BIT NOT NULL CONSTRAINT [DF_leave_type_is_probation_type] DEFAULT 0,
    [auto_allotment] BIT NOT NULL CONSTRAINT [DF_leave_type_auto_allotment] DEFAULT 0,
    [auto_balance_on_joining] BIT NOT NULL CONSTRAINT [DF_leave_type_auto_balance_on_joining] DEFAULT 0,
    [is_composite] BIT NOT NULL CONSTRAINT [DF_leave_type_is_composite] DEFAULT 0,
    [is_short_leave] BIT NOT NULL CONSTRAINT [DF_leave_type_is_short_leave] DEFAULT 0,
    [show_in_payslip] BIT NOT NULL CONSTRAINT [DF_leave_type_show_in_payslip] DEFAULT 0,
    [is_deductible] BIT NOT NULL CONSTRAINT [DF_leave_type_is_deductible] DEFAULT 0,
    [is_sandwich] BIT NOT NULL CONSTRAINT [DF_leave_type_is_sandwich] DEFAULT 0,
    [sandwich_across_types] BIT NOT NULL CONSTRAINT [DF_leave_type_sandwich_across_types] DEFAULT 0,
    [is_earned] BIT NOT NULL CONSTRAINT [DF_leave_type_is_earned] DEFAULT 0,
    [allow_back_date] BIT NOT NULL CONSTRAINT [DF_leave_type_allow_back_date] DEFAULT 0,
    [back_date_limit_days] INT NULL,
    [has_future_limit] BIT NOT NULL CONSTRAINT [DF_leave_type_has_future_limit] DEFAULT 0,
    [future_limit_days] INT NULL,
    [attachment_required] BIT NOT NULL CONSTRAINT [DF_leave_type_attachment_required] DEFAULT 0,
    [attachment_rule] NVARCHAR(30) NULL,
    [allow_encashment] BIT NOT NULL CONSTRAINT [DF_leave_type_allow_encashment] DEFAULT 0,
    [encashment_min] DECIMAL(6,2) NULL,
    [encashment_max] DECIMAL(6,2) NULL,
    [carry_forward] BIT NOT NULL CONSTRAINT [DF_leave_type_carry_forward] DEFAULT 0,
    [pro_rated] BIT NOT NULL CONSTRAINT [DF_leave_type_pro_rated] DEFAULT 0,
    [gender] NVARCHAR(30) NOT NULL,
    [marital_status] NVARCHAR(30) NOT NULL,
    [allowed_in_probation] BIT NOT NULL CONSTRAINT [DF_leave_type_allowed_in_probation] DEFAULT 0,
    [min_experience_months] INT NULL,
    [max_applications] INT NULL,
    [gap_between_applications_months] INT NULL,
    [tenure] NVARCHAR(30) NOT NULL,
    [balance_basis] NVARCHAR(30) NOT NULL,
    [accumulative_count] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_leave_type_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_leave_type] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_leave_type_company_id_title] UNIQUE ([company_id], [title])
);
GO
CREATE TABLE [lv].[leave_type_experience_slab] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [leave_type_id] BIGINT NOT NULL,
    [min_months] INT NOT NULL,
    [max_months] INT NULL,
    [balance] DECIMAL(6,2) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_leave_type_experience_slab_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_leave_type_experience_slab] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [lv].[leave_type_short_slab] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [leave_type_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [balance] DECIMAL(6,2) NULL,
    [value_type] NVARCHAR(30) NOT NULL,
    [slab_value] DECIMAL(9,2) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_leave_type_short_slab_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_leave_type_short_slab] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [lv].[leave_policy] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [policy_kind] NVARCHAR(30) NOT NULL,
    [policy_level] NVARCHAR(30) NOT NULL,
    [allow_half_day] BIT NOT NULL CONSTRAINT [DF_leave_policy_allow_half_day] DEFAULT 0,
    [allow_short_leave] BIT NOT NULL CONSTRAINT [DF_leave_policy_allow_short_leave] DEFAULT 0,
    [is_active] BIT NOT NULL CONSTRAINT [DF_leave_policy_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_leave_policy_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_leave_policy] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_leave_policy_company_id_title] UNIQUE ([company_id], [title])
);
GO
CREATE TABLE [lv].[leave_policy_type] (
    [leave_policy_id] BIGINT NOT NULL,
    [leave_type_id] BIGINT NOT NULL,
    [allowance] DECIMAL(6,2) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_leave_policy_type_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_leave_policy_type] PRIMARY KEY CLUSTERED ([leave_policy_id], [leave_type_id])
);
GO
CREATE TABLE [lv].[leave_policy_employee] (
    [leave_policy_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_leave_policy_employee_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_leave_policy_employee] PRIMARY KEY CLUSTERED ([leave_policy_id], [employee_id])
);
GO
CREATE TABLE [lv].[leave_ledger] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [leave_type_id] BIGINT NOT NULL,
    [fiscal_year] SMALLINT NOT NULL,
    [entry_date] DATE NOT NULL,
    [days] DECIMAL(6,2) NOT NULL,
    [reason] NVARCHAR(30) NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [request_id] BIGINT NULL,
    [leave_encashment_id] BIGINT NULL,
    [warning_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_leave_ledger_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_leave_ledger] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [lv].[leave_encashment] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [leave_type_id] BIGINT NOT NULL,
    [fiscal_year] SMALLINT NOT NULL,
    [encashment_date] DATE NOT NULL,
    [applies_to_all] BIT NOT NULL CONSTRAINT [DF_leave_encashment_applies_to_all] DEFAULT 0,
    [basis] NVARCHAR(30) NOT NULL,
    [amount_per_leave] DECIMAL(18,2) NOT NULL,
    [mode] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_leave_encashment_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_leave_encashment] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [lv].[leave_encashment_employee] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [leave_encashment_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [days] DECIMAL(6,2) NOT NULL,
    [amount] DECIMAL(18,2) NOT NULL,
    [payslip_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_leave_encashment_employee_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_leave_encashment_employee] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_leave_encashment_employee_leave_encashment_id_employee_id] UNIQUE ([leave_encashment_id], [employee_id])
);
GO
CREATE TABLE [req].[request_type] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [kind] NVARCHAR(30) NOT NULL,
    [prefix] NVARCHAR(10) NULL,
    [is_admin_only] BIT NOT NULL CONSTRAINT [DF_request_type_is_admin_only] DEFAULT 0,
    [is_active] BIT NOT NULL CONSTRAINT [DF_request_type_is_active] DEFAULT 0,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_request_type_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_request_type] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_request_type_code] UNIQUE ([code])
);
GO
CREATE TABLE [req].[request] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [request_type_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [created_by_user_id] BIGINT NULL,
    [from_date] DATE NULL,
    [to_date] DATE NULL,
    [days] DECIMAL(6,2) NULL,
    [reason] NVARCHAR(MAX) NULL,
    [description] NVARCHAR(MAX) NULL,
    [application] NVARCHAR(MAX) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [approval_flow_id] BIGINT NULL,
    [current_node_id] BIGINT NULL,
    [submitted_at] DATETIME2(0) NULL,
    [decided_at] DATETIME2(0) NULL,
    [cancel_reason] NVARCHAR(MAX) NULL,
    [cancel_requested_at] DATETIME2(0) NULL,
    [cancel_dates] NVARCHAR(MAX) NULL,
    [cancel_start_time] TIME(0) NULL,
    [cancel_end_time] TIME(0) NULL,
    [is_deleted] BIT NOT NULL CONSTRAINT [DF_request_is_deleted] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_request_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_request] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_request_company_id_code] UNIQUE ([company_id], [code])
);
GO
CREATE TABLE [req].[request_day] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [request_id] BIGINT NOT NULL,
    [request_date] DATE NOT NULL,
    [schedule_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_request_day_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_request_day] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_request_day_request_id_request_date] UNIQUE ([request_id], [request_date])
);
GO
CREATE TABLE [req].[req_leave] (
    [request_id] BIGINT NOT NULL,
    [leave_type_id] BIGINT NOT NULL,
    [is_short] BIT NOT NULL CONSTRAINT [DF_req_leave_is_short] DEFAULT 0,
    [short_leave_type] NVARCHAR(30) NULL,
    [start_time] TIME(0) NULL,
    [end_time] TIME(0) NULL,
    [days] DECIMAL(6,2) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_leave_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_leave] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[req_punch] (
    [request_id] BIGINT NOT NULL,
    [punch_date] DATE NOT NULL,
    [punch_type] NVARCHAR(30) NOT NULL,
    [punch_time] TIME(0) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_punch_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_punch] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[req_time_window] (
    [request_id] BIGINT NOT NULL,
    [kind] NVARCHAR(30) NOT NULL,
    [window_date] DATE NOT NULL,
    [start_time] TIME(0) NOT NULL,
    [end_time] TIME(0) NOT NULL,
    [time_slot_id] BIGINT NULL,
    [duration_minutes] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_time_window_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_time_window] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[req_rest_day] (
    [request_id] BIGINT NOT NULL,
    [department_id] BIGINT NOT NULL,
    [roster_group_id] BIGINT NOT NULL,
    [is_payable] BIT NOT NULL CONSTRAINT [DF_req_rest_day_is_payable] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_rest_day_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_rest_day] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[req_overtime] (
    [request_id] BIGINT NOT NULL,
    [department_id] BIGINT NOT NULL,
    [location_id] BIGINT NULL,
    [branch_id] BIGINT NULL,
    [overtime_date] DATE NOT NULL,
    [start_time] TIME(0) NOT NULL,
    [end_time] TIME(0) NOT NULL,
    [applied_minutes] INT NOT NULL,
    [approved_minutes] INT NULL,
    [overtime_type] NVARCHAR(30) NULL,
    [bulk_id] BIGINT NULL,
    [overtime_policy_id] BIGINT NULL,
    [slab_min_minutes] INT NULL,
    [slab_max_minutes] INT NULL,
    [encashment_type] NVARCHAR(30) NULL,
    [encashment_leave_type_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_overtime_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_overtime] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[request_bulk] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [request_type_id] BIGINT NOT NULL,
    [request_count] INT NOT NULL,
    [reason] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_request_bulk_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_request_bulk] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [req].[req_loan] (
    [request_id] BIGINT NOT NULL,
    [loan_type_id] BIGINT NOT NULL,
    [loan_category_id] BIGINT NULL,
    [amount_requested] DECIMAL(18,2) NOT NULL,
    [required_date] DATE NOT NULL,
    [extension_no] NVARCHAR(20) NULL,
    [approved_amount] DECIMAL(18,2) NULL,
    [currency] CHAR(3) NULL,
    [payment_method] NVARCHAR(30) NULL,
    [repayment_date] DATE NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_loan_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_loan] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[req_travel] (
    [request_id] BIGINT NOT NULL,
    [purpose] NVARCHAR(500) NOT NULL,
    [extension_no] NVARCHAR(20) NULL,
    [alt_phone] NVARCHAR(30) NULL,
    [advance_required] BIT NOT NULL CONSTRAINT [DF_req_travel_advance_required] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_travel_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_travel] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[req_promotion] (
    [request_id] BIGINT NOT NULL,
    [is_demotion] BIT NOT NULL CONSTRAINT [DF_req_promotion_is_demotion] DEFAULT 0,
    [grade_id] BIGINT NOT NULL,
    [job_level_id] BIGINT NULL,
    [designation_id] BIGINT NOT NULL,
    [job_title_id] BIGINT NOT NULL,
    [previous_salary] DECIMAL(18,2) NULL,
    [new_salary] DECIMAL(18,2) NOT NULL,
    [effective_date] DATE NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_promotion_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_promotion] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[req_transfer] (
    [request_id] BIGINT NOT NULL,
    [location_id] BIGINT NOT NULL,
    [branch_id] BIGINT NOT NULL,
    [department_id] BIGINT NOT NULL,
    [line_manager_id] BIGINT NOT NULL,
    [final_authority_id] BIGINT NOT NULL,
    [effective_date] DATE NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_transfer_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_transfer] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[req_resignation] (
    [request_id] BIGINT NOT NULL,
    [resignation_type] NVARCHAR(30) NOT NULL,
    [resignation_date] DATE NOT NULL,
    [last_working_date] DATE NULL,
    [notice_period_days] INT NULL,
    [serve_notice] BIT NOT NULL CONSTRAINT [DF_req_resignation_serve_notice] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_resignation_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_resignation] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[req_shift_swap] (
    [request_id] BIGINT NOT NULL,
    [shift_date] DATE NOT NULL,
    [from_schedule_id] BIGINT NULL,
    [time_slot_id] BIGINT NULL,
    [with_employee_id] BIGINT NULL,
    [to_schedule_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_shift_swap_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_shift_swap] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[loan_guarantor] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [request_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [cnic] NVARCHAR(15) NOT NULL,
    [known_since] DATE NOT NULL,
    [relationship] NVARCHAR(200) NOT NULL,
    [extension_no] NVARCHAR(20) NULL,
    [description] NVARCHAR(MAX) NULL,
    [file_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_loan_guarantor_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_loan_guarantor] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [req].[travel_advance] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [request_id] BIGINT NOT NULL,
    [amount] DECIMAL(18,2) NOT NULL,
    [currency] CHAR(3) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_travel_advance_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_travel_advance] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [req].[travel_leg] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [request_id] BIGINT NOT NULL,
    [travel_type] NVARCHAR(30) NOT NULL,
    [from_place] NVARCHAR(200) NOT NULL,
    [to_place] NVARCHAR(200) NOT NULL,
    [travel_mode] NVARCHAR(30) NOT NULL,
    [distance_km] DECIMAL(9,2) NULL,
    [depart_at] DATETIME2(0) NOT NULL,
    [arrive_at] DATETIME2(0) NOT NULL,
    [stay_required] BIT NOT NULL CONSTRAINT [DF_travel_leg_stay_required] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_travel_leg_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_travel_leg] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [req].[travel_stay] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [request_id] BIGINT NOT NULL,
    [stay_type] NVARCHAR(30) NOT NULL,
    [address] NVARCHAR(500) NOT NULL,
    [city] NVARCHAR(200) NOT NULL,
    [from_date] DATE NOT NULL,
    [to_date] DATE NOT NULL,
    [nights] INT NOT NULL,
    [phone] NVARCHAR(30) NOT NULL,
    [email] NVARCHAR(254) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_travel_stay_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_travel_stay] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [req].[travel_ticket] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [request_id] BIGINT NOT NULL,
    [ticket_no] NVARCHAR(50) NOT NULL,
    [travel_class] NVARCHAR(30) NULL,
    [from_place] NVARCHAR(200) NULL,
    [to_place] NVARCHAR(200) NULL,
    [travel_at] DATETIME2(0) NOT NULL,
    [file_id] BIGINT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_travel_ticket_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_travel_ticket] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [req].[req_promotion_benefit] (
    [request_id] BIGINT NOT NULL,
    [pay_item_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_promotion_benefit_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_promotion_benefit] PRIMARY KEY CLUSTERED ([request_id], [pay_item_id])
);
GO
CREATE TABLE [req].[req_expense] (
    [request_id] BIGINT NOT NULL,
    [currency] CHAR(3) NULL,
    [total_amount] DECIMAL(18,2) NOT NULL,
    [approved_amount] DECIMAL(18,2) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_expense_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_expense] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[expense_line] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [request_id] BIGINT NOT NULL,
    [line_no] INT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [claim_date] DATE NOT NULL,
    [expense_category_id] BIGINT NOT NULL,
    [amount] DECIMAL(18,2) NOT NULL,
    [approved_amount] DECIMAL(18,2) NULL,
    [description] NVARCHAR(MAX) NOT NULL,
    [file_id] BIGINT NULL,
    [opening_balance_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_expense_line_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_expense_line] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_expense_line_request_id_line_no] UNIQUE ([request_id], [line_no])
);
GO
CREATE TABLE [req].[req_air_ticket] (
    [request_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [claim_date] DATE NOT NULL,
    [travel_date] DATE NOT NULL,
    [from_place] NVARCHAR(200) NULL,
    [to_place] NVARCHAR(200) NULL,
    [amount] DECIMAL(18,2) NOT NULL,
    [approved_amount] DECIMAL(18,2) NULL,
    [currency] CHAR(3) NULL,
    [description] NVARCHAR(MAX) NULL,
    [file_id] BIGINT NULL,
    [opening_balance_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_air_ticket_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_air_ticket] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[req_requisition] (
    [request_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [requisition_type] NVARCHAR(30) NOT NULL,
    [needed_by_date] DATE NOT NULL,
    [delivery_location] NVARCHAR(200) NULL,
    [estimated_amount] DECIMAL(18,2) NULL,
    [currency] CHAR(3) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_req_requisition_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_req_requisition] PRIMARY KEY CLUSTERED ([request_id])
);
GO
CREATE TABLE [req].[requisition_line] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [request_id] BIGINT NOT NULL,
    [line_no] INT NOT NULL,
    [item_name] NVARCHAR(200) NOT NULL,
    [quantity] DECIMAL(18,2) NOT NULL,
    [unit] NVARCHAR(200) NULL,
    [estimated_unit_cost] DECIMAL(18,2) NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_requisition_line_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_requisition_line] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_requisition_line_request_id_line_no] UNIQUE ([request_id], [line_no])
);
GO
CREATE TABLE [req].[expense_category] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [pay_item_id] BIGINT NULL,
    [max_amount] DECIMAL(18,2) NULL,
    [receipt_required] BIT NOT NULL CONSTRAINT [DF_expense_category_receipt_required] DEFAULT 0,
    [is_active] BIT NOT NULL CONSTRAINT [DF_expense_category_is_active] DEFAULT 0,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_expense_category_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_expense_category] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_expense_category_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [req].[reimbursement_setting] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [expense_pay_item_id] BIGINT NULL,
    [air_ticket_pay_item_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_reimbursement_setting_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_reimbursement_setting] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_reimbursement_setting_company_id] UNIQUE ([company_id])
);
GO
CREATE TABLE [req].[approval_flow] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [request_type_id] BIGINT NOT NULL,
    [purpose] NVARCHAR(30) NULL,
    [name] NVARCHAR(200) NOT NULL,
    [scope_type] NVARCHAR(30) NULL,
    [scope_id] BIGINT NULL,
    [description] NVARCHAR(MAX) NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_approval_flow_is_active] DEFAULT 0,
    [is_current] BIT NOT NULL CONSTRAINT [DF_approval_flow_is_current] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_approval_flow_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_approval_flow] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [req].[approval_node] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [approval_flow_id] BIGINT NOT NULL,
    [step_no] INT NOT NULL,
    [approver_kind] NVARCHAR(30) NULL,
    [approver_employee_id] BIGINT NULL,
    [role_id] BIGINT NULL,
    [is_condition] BIT NOT NULL CONSTRAINT [DF_approval_node_is_condition] DEFAULT 0,
    [expression] NVARCHAR(MAX) NULL,
    [condition_field] NVARCHAR(200) NULL,
    [condition_operator] NVARCHAR(2) NULL,
    [condition_value] DECIMAL(18,4) NULL,
    [next_node_id] BIGINT NULL,
    [true_node_id] BIGINT NULL,
    [false_node_id] BIGINT NULL,
    [can_edit] BIT NOT NULL CONSTRAINT [DF_approval_node_can_edit] DEFAULT 0,
    [can_disagree] BIT NOT NULL CONSTRAINT [DF_approval_node_can_disagree] DEFAULT 0,
    [is_observer] BIT NOT NULL CONSTRAINT [DF_approval_node_is_observer] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_approval_node_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_approval_node] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_approval_node_approval_flow_id_step_no] UNIQUE ([approval_flow_id], [step_no])
);
GO
CREATE TABLE [req].[approval_authority] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [authority] NVARCHAR(30) NULL,
    [employee_id] BIGINT NOT NULL,
    [request_type_id] BIGINT NULL,
    [branch_id] BIGINT NULL,
    [department_id] BIGINT NULL,
    [description] NVARCHAR(MAX) NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_approval_authority_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_approval_authority_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_approval_authority] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [req].[delegation] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [delegator_id] BIGINT NOT NULL,
    [delegatee_id] BIGINT NOT NULL,
    [request_type_id] BIGINT NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_delegation_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_delegation_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_delegation] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [req].[request_restriction] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [request_type_id] BIGINT NOT NULL,
    [start_date] DATE NOT NULL,
    [end_date] DATE NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_request_restriction_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_request_restriction] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [req].[request_step] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [request_id] BIGINT NOT NULL,
    [approval_node_id] BIGINT NULL,
    [purpose] NVARCHAR(30) NULL,
    [approver_kind] NVARCHAR(30) NULL,
    [approver_id] BIGINT NULL,
    [approver_role_id] BIGINT NULL,
    [acted_by_id] BIGINT NULL,
    [is_delegate] BIT NOT NULL CONSTRAINT [DF_request_step_is_delegate] DEFAULT 0,
    [is_consent] BIT NOT NULL CONSTRAINT [DF_request_step_is_consent] DEFAULT 0,
    [action_taken] NVARCHAR(30) NOT NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [acted_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_request_step_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_request_step] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [loan].[loan_type] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_loan_type_is_active] DEFAULT 0,
    [guarantor_required] BIT NOT NULL CONSTRAINT [DF_loan_type_guarantor_required] DEFAULT 0,
    [non_payable] BIT NOT NULL CONSTRAINT [DF_loan_type_non_payable] DEFAULT 0,
    [min_experience_months] INT NOT NULL,
    [gap_between_requests_months] INT NULL,
    [installments] INT NOT NULL,
    [gap_between_installments_months] INT NULL,
    [formula_id] BIGINT NULL,
    [deduction_pay_item_id] BIGINT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_loan_type_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_loan_type] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_loan_type_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [loan].[loan_type_employment_type] (
    [loan_type_id] BIGINT NOT NULL,
    [employment_type_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_loan_type_employment_type_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_loan_type_employment_type] PRIMARY KEY CLUSTERED ([loan_type_id], [employment_type_id])
);
GO
CREATE TABLE [loan].[loan_category] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_loan_category_is_active] DEFAULT 0,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_loan_category_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_loan_category] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_loan_category_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [loan].[loan] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [request_id] BIGINT NULL,
    [loan_type_id] BIGINT NOT NULL,
    [loan_category_id] BIGINT NULL,
    [principal] DECIMAL(18,2) NOT NULL,
    [installment_amount] DECIMAL(18,2) NULL,
    [installments] INT NULL,
    [gap_between_installments_months] INT NULL,
    [currency] CHAR(3) NULL,
    [payment_method] NVARCHAR(30) NULL,
    [start_month] DATE NULL,
    [status] NVARCHAR(30) NOT NULL,
    [settled_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_loan_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_loan] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [loan].[loan_installment] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [loan_id] BIGINT NOT NULL,
    [installment_no] INT NOT NULL,
    [due_month] DATE NOT NULL,
    [amount] DECIMAL(18,2) NOT NULL,
    [paid_amount] DECIMAL(18,2) NULL,
    [payslip_id] BIGINT NULL,
    [paid_at] DATETIME2(0) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_loan_installment_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_loan_installment] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_loan_installment_loan_id_installment_no] UNIQUE ([loan_id], [installment_no])
);
GO
CREATE TABLE [pay].[tax_structure] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [start_date] DATE NOT NULL,
    [end_date] DATE NOT NULL,
    [surcharge_type] NVARCHAR(30) NULL,
    [surcharge_value] DECIMAL(18,2) NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_tax_structure_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_tax_structure] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_tax_structure_company_id_code] UNIQUE ([company_id], [code]),
    CONSTRAINT [UQ_tax_structure_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [pay].[tax_slab] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [tax_structure_id] BIGINT NOT NULL,
    [min_amount] DECIMAL(18,2) NOT NULL,
    [max_amount] DECIMAL(18,2) NULL,
    [fixed_amount] DECIMAL(18,2) NOT NULL,
    [percentage] DECIMAL(5,2) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_tax_slab_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_tax_slab] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pay].[tax_rebate] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [rebate_date] DATE NOT NULL,
    [amount] DECIMAL(18,2) NOT NULL,
    [file_id] BIGINT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_tax_rebate_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_tax_rebate] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pay].[formula] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [expression] NVARCHAR(MAX) NOT NULL,
    [is_salary_division] BIT NOT NULL CONSTRAINT [DF_formula_is_salary_division] DEFAULT 0,
    [for_integration] BIT NOT NULL CONSTRAINT [DF_formula_for_integration] DEFAULT 0,
    [is_custom] BIT NOT NULL CONSTRAINT [DF_formula_is_custom] DEFAULT 0,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_formula_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_formula] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_formula_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [pay].[pay_item] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [label] NVARCHAR(200) NULL,
    [item_type] NVARCHAR(30) NOT NULL,
    [calculation_type] NVARCHAR(30) NOT NULL,
    [tax_distribution] NVARCHAR(30) NOT NULL,
    [employee_formula_id] BIGINT NULL,
    [employer_formula_id] BIGINT NULL,
    [is_taxable] BIT NOT NULL CONSTRAINT [DF_pay_item_is_taxable] DEFAULT 0,
    [is_display_only] BIT NOT NULL CONSTRAINT [DF_pay_item_is_display_only] DEFAULT 0,
    [is_benefit] BIT NOT NULL CONSTRAINT [DF_pay_item_is_benefit] DEFAULT 0,
    [is_advance_payment] BIT NOT NULL CONSTRAINT [DF_pay_item_is_advance_payment] DEFAULT 0,
    [eligibility_expression] NVARCHAR(MAX) NULL,
    [system_code] NVARCHAR(30) NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_pay_item_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_pay_item] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_pay_item_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [pay].[pay_rule] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [expression] NVARCHAR(MAX) NOT NULL,
    [account_type_id] BIGINT NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_pay_rule_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_pay_rule] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_pay_rule_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [pay].[account_type] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [category] NVARCHAR(30) NOT NULL,
    [ref_id] BIGINT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_account_type_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_account_type] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_account_type_company_id_code] UNIQUE ([company_id], [code]),
    CONSTRAINT [UQ_account_type_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [pay].[reward_benefit] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [benefit_type] NVARCHAR(30) NOT NULL,
    [pay_item_id] BIGINT NOT NULL,
    [formula_id] BIGINT NULL,
    [is_group] BIT NOT NULL CONSTRAINT [DF_reward_benefit_is_group] DEFAULT 0,
    [is_accumulative] BIT NOT NULL CONSTRAINT [DF_reward_benefit_is_accumulative] DEFAULT 0,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_reward_benefit_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_reward_benefit] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_reward_benefit_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [pay].[reward_benefit_member] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [reward_benefit_id] BIGINT NOT NULL,
    [employee_id] BIGINT NULL,
    [employee_group_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_reward_benefit_member_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_reward_benefit_member] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pay].[reward_benefit_field] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [reward_benefit_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [field_type] NVARCHAR(30) NOT NULL,
    [is_required] BIT NOT NULL CONSTRAINT [DF_reward_benefit_field_is_required] DEFAULT 0,
    [min_value] DECIMAL(18,4) NULL,
    [max_value] DECIMAL(18,4) NULL,
    [min_length] INT NULL,
    [max_length] INT NULL,
    [field_value] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_reward_benefit_field_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_reward_benefit_field] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pay].[sales_incentive] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [branch_id] BIGINT NOT NULL,
    [applicable_month] DATE NOT NULL,
    [incentive_type] NVARCHAR(30) NOT NULL,
    [target_amount] DECIMAL(18,2) NOT NULL,
    [value_type] NVARCHAR(30) NOT NULL,
    [reward_value] DECIMAL(18,2) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_sales_incentive_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_sales_incentive] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pay].[disbursement_bank] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [account_holder] NVARCHAR(200) NOT NULL,
    [account_number] NVARCHAR(50) NOT NULL,
    [bank_name] NVARCHAR(200) NOT NULL,
    [branch_name] NVARCHAR(200) NULL,
    [branch_code] NVARCHAR(30) NOT NULL,
    [branch_location] NVARCHAR(200) NOT NULL,
    [tax_payer_id] NVARCHAR(30) NOT NULL,
    [effective_date] DATE NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_disbursement_bank_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_disbursement_bank] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_disbursement_bank_company_id_account_number] UNIQUE ([company_id], [account_number])
);
GO
CREATE TABLE [pay].[payroll] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [kind] NVARCHAR(30) NOT NULL,
    [payroll_month] DATE NULL,
    [work_date] DATE NULL,
    [time_slot_id] BIGINT NULL,
    [currency] CHAR(3) NULL,
    [tax_structure_id] BIGINT NULL,
    [tax_applicable] BIT NOT NULL CONSTRAINT [DF_payroll_tax_applicable] DEFAULT 0,
    [processing_mode] NVARCHAR(30) NULL,
    [processing_date] DATE NULL,
    [applicable_days] NVARCHAR(30) NULL,
    [fixed_days] INT NULL,
    [disbursement_bank_id] BIGINT NULL,
    [description] NVARCHAR(MAX) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [last_run_at] DATETIME2(0) NULL,
    [closed_at] DATETIME2(0) NULL,
    [closed_by_user_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_payroll_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_payroll] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_payroll_company_id_code] UNIQUE ([company_id], [code])
);
GO
CREATE TABLE [pay].[payroll_pay_item] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [payroll_id] BIGINT NOT NULL,
    [pay_item_id] BIGINT NOT NULL,
    [is_taxable] BIT NOT NULL CONSTRAINT [DF_payroll_pay_item_is_taxable] DEFAULT 0,
    [arrear_applicable] BIT NOT NULL CONSTRAINT [DF_payroll_pay_item_arrear_applicable] DEFAULT 0,
    [final_settlement] BIT NOT NULL CONSTRAINT [DF_payroll_pay_item_final_settlement] DEFAULT 0,
    [calculate_only] BIT NOT NULL CONSTRAINT [DF_payroll_pay_item_calculate_only] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_payroll_pay_item_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_payroll_pay_item] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_payroll_pay_item_payroll_id_pay_item_id] UNIQUE ([payroll_id], [pay_item_id])
);
GO
CREATE TABLE [pay].[payroll_employee] (
    [payroll_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_payroll_employee_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_payroll_employee] PRIMARY KEY CLUSTERED ([payroll_id], [employee_id])
);
GO
CREATE TABLE [pay].[payroll_run_log] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [payroll_id] BIGINT NOT NULL,
    [kind] NVARCHAR(30) NOT NULL,
    [started_at] DATETIME2(0) NULL,
    [finished_at] DATETIME2(0) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [run_by_user_id] BIGINT NULL,
    [processed_count] INT NULL,
    [error_count] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_payroll_run_log_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_payroll_run_log] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pay].[payroll_run_error] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [payroll_run_log_id] BIGINT NOT NULL,
    [employee_id] BIGINT NULL,
    [message] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_payroll_run_error_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_payroll_run_error] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pay].[payslip] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [payroll_id] BIGINT NULL,
    [employee_id] BIGINT NOT NULL,
    [payslip_month] DATE NOT NULL,
    [applicable_days] DECIMAL(6,2) NULL,
    [worked_days] DECIMAL(6,2) NULL,
    [worked_minutes] INT NULL,
    [expected_minutes] INT NULL,
    [leave_days] DECIMAL(6,2) NULL,
    [absent_days] DECIMAL(6,2) NULL,
    [overtime_minutes] INT NULL,
    [gross] DECIMAL(18,2) NULL,
    [total_earnings] DECIMAL(18,2) NULL,
    [total_deductions] DECIMAL(18,2) NULL,
    [total_reimbursements] DECIMAL(18,2) NULL,
    [net_payable] DECIMAL(18,2) NULL,
    [taxable_income] DECIMAL(18,2) NULL,
    [tax_amount] DECIMAL(18,2) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [payment_method] NVARCHAR(30) NULL,
    [released_at] DATETIME2(0) NULL,
    [paid_at] DATETIME2(0) NULL,
    [is_final_settlement] BIT NOT NULL CONSTRAINT [DF_payslip_is_final_settlement] DEFAULT 0,
    [is_manually_updated] BIT NOT NULL CONSTRAINT [DF_payslip_is_manually_updated] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_payslip_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_payslip] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pay].[payslip_line] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [payslip_id] BIGINT NOT NULL,
    [pay_item_id] BIGINT NOT NULL,
    [amount] DECIMAL(18,2) NOT NULL,
    [employer_contribution] DECIMAL(18,2) NULL,
    [is_taxable] BIT NOT NULL CONSTRAINT [DF_payslip_line_is_taxable] DEFAULT 0,
    [is_manually_updated] BIT NOT NULL CONSTRAINT [DF_payslip_line_is_manually_updated] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_payslip_line_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_payslip_line] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_payslip_line_payslip_id_pay_item_id] UNIQUE ([payslip_id], [pay_item_id])
);
GO
CREATE TABLE [pay].[opening_balance] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [balance_month] DATE NOT NULL,
    [pay_item_id] BIGINT NOT NULL,
    [amount] DECIMAL(18,2) NOT NULL,
    [is_taxable] BIT NOT NULL CONSTRAINT [DF_opening_balance_is_taxable] DEFAULT 0,
    [kind] NVARCHAR(30) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_opening_balance_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_opening_balance] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pay].[employee_account_entry] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [account_type_id] BIGINT NOT NULL,
    [entry_month] DATE NOT NULL,
    [credit] DECIMAL(18,2) NULL,
    [debit] DECIMAL(18,2) NULL,
    [is_processed] BIT NOT NULL CONSTRAINT [DF_employee_account_entry_is_processed] DEFAULT 0,
    [payslip_id] BIGINT NULL,
    [pay_rule_id] BIGINT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_employee_account_entry_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_employee_account_entry] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pay].[voucher] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [voucher_no] NVARCHAR(30) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [voucher_type] NVARCHAR(30) NOT NULL,
    [voucher_date] DATE NOT NULL,
    [currency] CHAR(3) NULL,
    [amount] DECIMAL(18,2) NOT NULL,
    [payment_method] NVARCHAR(30) NULL,
    [purpose] NVARCHAR(500) NULL,
    [notes] NVARCHAR(MAX) NULL,
    [file_id] BIGINT NULL,
    [payroll_id] BIGINT NULL,
    [requested_by_id] BIGINT NULL,
    [approved_by_id] BIGINT NULL,
    [decided_by_user_id] BIGINT NULL,
    [approved_at] DATETIME2(0) NULL,
    [verified_by_id] BIGINT NULL,
    [verified_by_user_id] BIGINT NULL,
    [verified_at] DATETIME2(0) NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_voucher_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_voucher] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_voucher_company_id_voucher_no] UNIQUE ([company_id], [voucher_no])
);
GO
CREATE TABLE [pay].[payroll_close_email] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [payroll_id] BIGINT NOT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [recipient_count] INT NULL,
    [queued_at] DATETIME2(0) NULL,
    [sent_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_payroll_close_email_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_payroll_close_email] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_payroll_close_email_payroll_id] UNIQUE ([payroll_id])
);
GO
CREATE TABLE [pay].[mail_outbox] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [entity_type] NVARCHAR(50) NOT NULL,
    [entity_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [to_address] NVARCHAR(254) NULL,
    [subject] NVARCHAR(300) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [queued_at] DATETIME2(0) NULL,
    [sent_at] DATETIME2(0) NULL,
    [error] NVARCHAR(1000) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_mail_outbox_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_mail_outbox] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [sep].[asset_type] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_asset_type_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_asset_type_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_asset_type] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_asset_type_company_id_code] UNIQUE ([company_id], [code]),
    CONSTRAINT [UQ_asset_type_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [sep].[asset] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [asset_type_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [identification_no] NVARCHAR(100) NULL,
    [is_taxable] BIT NOT NULL CONSTRAINT [DF_asset_is_taxable] DEFAULT 0,
    [asset_condition] NVARCHAR(30) NULL,
    [manufacturer] NVARCHAR(100) NULL,
    [model] NVARCHAR(100) NULL,
    [current_value] DECIMAL(18,2) NULL,
    [acquired_date] DATE NULL,
    [description] NVARCHAR(MAX) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [file_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_asset_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_asset] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_asset_company_id_code] UNIQUE ([company_id], [code])
);
GO
CREATE TABLE [sep].[asset_allocation] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [asset_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [allocated_on] DATE NOT NULL,
    [deallocated_on] DATE NULL,
    [status] NVARCHAR(30) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [return_condition] NVARCHAR(30) NULL,
    [deallocation_remarks] NVARCHAR(500) NULL,
    [file_id] BIGINT NULL,
    [asset_clearance_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_asset_allocation_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_asset_allocation] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [sep].[end_of_employment] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [reason] NVARCHAR(30) NOT NULL,
    [resignation_request_id] BIGINT NULL,
    [serve_notice] BIT NOT NULL CONSTRAINT [DF_end_of_employment_serve_notice] DEFAULT 0,
    [notice_period_days] INT NULL,
    [last_working_date] DATE NOT NULL,
    [needs_final_settlement] BIT NOT NULL CONSTRAINT [DF_end_of_employment_needs_final_settlement] DEFAULT 0,
    [needs_asset_clearance] BIT NOT NULL CONSTRAINT [DF_end_of_employment_needs_asset_clearance] DEFAULT 0,
    [asset_clear_by_date] DATE NULL,
    [replacement_id] BIGINT NULL,
    [delegatee_id] BIGINT NULL,
    [description] NVARCHAR(MAX) NULL,
    [file_id] BIGINT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [completed_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_end_of_employment_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_end_of_employment] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [sep].[asset_clearance] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [end_of_employment_id] BIGINT NULL,
    [clearance_date] DATE NOT NULL,
    [checked_by_id] BIGINT NULL,
    [approved_by_id] BIGINT NULL,
    [approval_date] DATE NULL,
    [file_id] BIGINT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_asset_clearance_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_asset_clearance] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [sep].[asset_clearance_item] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [asset_clearance_id] BIGINT NOT NULL,
    [asset_allocation_id] BIGINT NOT NULL,
    [condition_at_clearance] NVARCHAR(30) NULL,
    [reason] NVARCHAR(MAX) NULL,
    [return_status] NVARCHAR(30) NULL,
    [comments] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_asset_clearance_item_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_asset_clearance_item] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_asset_clearance_item_asset_clearance_id_asset_allocation_id] UNIQUE ([asset_clearance_id], [asset_allocation_id])
);
GO
CREATE TABLE [sep].[final_settlement] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [end_of_employment_id] BIGINT NOT NULL,
    [payslip_id] BIGINT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [closed_at] DATETIME2(0) NULL,
    [file_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_final_settlement_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_final_settlement] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_final_settlement_end_of_employment_id] UNIQUE ([end_of_employment_id])
);
GO
CREATE TABLE [sep].[offboarding_checklist] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_offboarding_checklist_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_offboarding_checklist_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_offboarding_checklist] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_offboarding_checklist_company_id_code] UNIQUE ([company_id], [code]),
    CONSTRAINT [UQ_offboarding_checklist_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [sep].[checklist_field] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [offboarding_checklist_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [field_type] NVARCHAR(30) NULL,
    [is_required] BIT NOT NULL CONSTRAINT [DF_checklist_field_is_required] DEFAULT 0,
    [min_value] DECIMAL(18,4) NULL,
    [max_value] DECIMAL(18,4) NULL,
    [min_length] INT NULL,
    [max_length] INT NULL,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_checklist_field_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_checklist_field] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_checklist_field_offboarding_checklist_id_name] UNIQUE ([offboarding_checklist_id], [name])
);
GO
CREATE TABLE [sep].[checklist_answer] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [end_of_employment_id] BIGINT NOT NULL,
    [checklist_field_id] BIGINT NOT NULL,
    [answer] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_checklist_answer_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_checklist_answer] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_checklist_answer_end_of_employment_id_checklist_field_id] UNIQUE ([end_of_employment_id], [checklist_field_id])
);
GO
CREATE TABLE [rec].[job_opening] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [open_position_id] BIGINT NULL,
    [job_title_id] BIGINT NULL,
    [designation_id] BIGINT NULL,
    [department_id] BIGINT NULL,
    [branch_id] BIGINT NULL,
    [employment_type_id] BIGINT NULL,
    [hiring_manager_id] BIGINT NULL,
    [city_id] BIGINT NULL,
    [work_mode] NVARCHAR(30) NULL,
    [experience_from_years] INT NULL,
    [experience_to_years] INT NULL,
    [vacancies] INT NOT NULL,
    [posted_on] DATE NULL,
    [apply_by] DATE NULL,
    [close_on] DATE NULL,
    [salary_from] DECIMAL(18,2) NULL,
    [salary_to] DECIMAL(18,2) NULL,
    [is_salary_visible] BIT NOT NULL CONSTRAINT [DF_job_opening_is_salary_visible] DEFAULT 0,
    [description] NVARCHAR(MAX) NULL,
    [requirements] NVARCHAR(MAX) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [published_at] DATETIME2(0) NULL,
    [closed_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_job_opening_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_job_opening] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_job_opening_company_id_code] UNIQUE ([company_id], [code])
);
GO
CREATE TABLE [rec].[applicant] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [first_name] NVARCHAR(200) NOT NULL,
    [last_name] NVARCHAR(200) NOT NULL,
    [email] NVARCHAR(254) NOT NULL,
    [phone] NVARCHAR(30) NULL,
    [gender] NVARCHAR(30) NULL,
    [date_of_birth] DATE NULL,
    [city_id] BIGINT NULL,
    [address] NVARCHAR(500) NULL,
    [current_employer] NVARCHAR(200) NULL,
    [current_job_title] NVARCHAR(200) NULL,
    [experience_years] DECIMAL(4,1) NULL,
    [current_salary] DECIMAL(18,2) NULL,
    [expected_salary] DECIMAL(18,2) NULL,
    [notice_period_days] INT NULL,
    [highest_education] NVARCHAR(200) NULL,
    [linkedin_url] NVARCHAR(500) NULL,
    [source] NVARCHAR(30) NULL,
    [referred_by_employee_id] BIGINT NULL,
    [cv_file_id] BIGINT NULL,
    [notes] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_applicant_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_applicant] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_applicant_company_id_email] UNIQUE ([company_id], [email])
);
GO
CREATE TABLE [rec].[application] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [job_opening_id] BIGINT NOT NULL,
    [applicant_id] BIGINT NOT NULL,
    [applied_on] DATE NOT NULL,
    [source] NVARCHAR(30) NULL,
    [cover_letter] NVARCHAR(MAX) NULL,
    [stage] NVARCHAR(30) NOT NULL,
    [stage_changed_at] DATETIME2(0) NULL,
    [rejection_reason_id] BIGINT NULL,
    [rejected_stage] NVARCHAR(30) NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [employee_id] BIGINT NULL,
    [hired_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_application_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_application] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_application_job_opening_id_applicant_id] UNIQUE ([job_opening_id], [applicant_id])
);
GO
CREATE TABLE [rec].[application_stage_history] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [application_id] BIGINT NOT NULL,
    [from_stage] NVARCHAR(30) NULL,
    [to_stage] NVARCHAR(30) NOT NULL,
    [changed_at] DATETIME2(0) NOT NULL,
    [changed_by_user_id] BIGINT NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_application_stage_history_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_application_stage_history] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [rec].[interview] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [application_id] BIGINT NOT NULL,
    [round_no] INT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [mode] NVARCHAR(30) NULL,
    [scheduled_at] DATETIME2(0) NOT NULL,
    [duration_minutes] INT NOT NULL,
    [venue] NVARCHAR(500) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [result] NVARCHAR(30) NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_interview_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_interview] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [rec].[interview_interviewer] (
    [interview_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_interview_interviewer_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_interview_interviewer] PRIMARY KEY CLUSTERED ([interview_id], [employee_id])
);
GO
CREATE TABLE [rec].[interview_evaluation] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [interview_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [rating] INT NOT NULL,
    [recommendation] NVARCHAR(30) NOT NULL,
    [strengths] NVARCHAR(MAX) NULL,
    [concerns] NVARCHAR(MAX) NULL,
    [comments] NVARCHAR(MAX) NULL,
    [evaluated_at] DATETIME2(0) NOT NULL,
    [evaluated_by_user_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_interview_evaluation_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_interview_evaluation] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_interview_evaluation_interview_id_employee_id] UNIQUE ([interview_id], [employee_id])
);
GO
CREATE TABLE [rec].[offer] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [application_id] BIGINT NOT NULL,
    [job_title_id] BIGINT NULL,
    [designation_id] BIGINT NULL,
    [department_id] BIGINT NULL,
    [branch_id] BIGINT NULL,
    [employment_type_id] BIGINT NULL,
    [offered_salary] DECIMAL(18,2) NOT NULL,
    [salary_frequency] NVARCHAR(30) NULL,
    [joining_date] DATE NOT NULL,
    [probation_months] INT NULL,
    [expires_on] DATE NULL,
    [offer_letter_file_id] BIGINT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [sent_at] DATETIME2(0) NULL,
    [responded_at] DATETIME2(0) NULL,
    [response_remarks] NVARCHAR(MAX) NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_offer_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_offer] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [rec].[rejection_reason] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_rejection_reason_is_active] DEFAULT 0,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_rejection_reason_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_rejection_reason] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_rejection_reason_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [mp].[budget_duration] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [start_date] DATE NOT NULL,
    [end_date] DATE NOT NULL,
    [is_current] BIT NOT NULL CONSTRAINT [DF_budget_duration_is_current] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_budget_duration_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_budget_duration] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_budget_duration_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [mp].[position] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [branch_id] BIGINT NOT NULL,
    [job_title_id] BIGINT NOT NULL,
    [employee_group_id] BIGINT NOT NULL,
    [division_id] BIGINT NULL,
    [department_id] BIGINT NULL,
    [sub_department_id] BIGINT NULL,
    [cost_center_id] BIGINT NULL,
    [grade_id] BIGINT NULL,
    [reports_to_id] BIGINT NULL,
    [employee_id] BIGINT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_position_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_position] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_position_company_id_code] UNIQUE ([company_id], [code])
);
GO
CREATE TABLE [mp].[position_salary_range] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [position_id] BIGINT NOT NULL,
    [effective_date] DATE NOT NULL,
    [min_salary] DECIMAL(18,2) NOT NULL,
    [max_salary] DECIMAL(18,2) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_position_salary_range_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_position_salary_range] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_position_salary_range_position_id_effective_date] UNIQUE ([position_id], [effective_date])
);
GO
CREATE TABLE [mp].[manpower_plan] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [budget_duration_id] BIGINT NOT NULL,
    [division_id] BIGINT NULL,
    [branch_id] BIGINT NULL,
    [department_id] BIGINT NULL,
    [sub_department_id] BIGINT NULL,
    [employee_group_id] BIGINT NULL,
    [description] NVARCHAR(MAX) NULL,
    [monthly_amount] DECIMAL(18,2) NOT NULL,
    [annual_amount] DECIMAL(18,2) NOT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [submitted_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_manpower_plan_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_manpower_plan] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [mp].[manpower_plan_line] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [manpower_plan_id] BIGINT NOT NULL,
    [kind] NVARCHAR(30) NOT NULL,
    [sort_order] INT NULL,
    [position_id] BIGINT NULL,
    [employee_id] BIGINT NULL,
    [e_budget_id] BIGINT NULL,
    [headcount] INT NOT NULL,
    [start_date] DATE NOT NULL,
    [end_date] DATE NOT NULL,
    [months] INT NOT NULL,
    [min_salary] DECIMAL(18,2) NULL,
    [max_salary] DECIMAL(18,2) NULL,
    [monthly_salary] DECIMAL(18,2) NULL,
    [total_allowance] DECIMAL(18,2) NOT NULL,
    [total_salary] DECIMAL(18,2) NOT NULL,
    [annual_gross] DECIMAL(18,2) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_manpower_plan_line_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_manpower_plan_line] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [mp].[e_budget] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [budget_duration_id] BIGINT NOT NULL,
    [manpower_plan_id] BIGINT NULL,
    [job_title_id] BIGINT NULL,
    [department_id] BIGINT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [amount] DECIMAL(18,2) NOT NULL,
    [total_positions] INT NOT NULL,
    [start_date] DATE NOT NULL,
    [end_date] DATE NOT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [decided_by_user_id] BIGINT NULL,
    [decided_at] DATETIME2(0) NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_e_budget_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_e_budget] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [mp].[open_position] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [e_budget_id] BIGINT NOT NULL,
    [manpower_plan_line_id] BIGINT NULL,
    [position_id] BIGINT NULL,
    [job_title_id] BIGINT NULL,
    [department_id] BIGINT NULL,
    [branch_id] BIGINT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [approved_positions] INT NOT NULL,
    [total_positions] INT NOT NULL,
    [end_date] DATE NULL,
    [jd_file_id] BIGINT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_open_position_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_open_position] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [core].[stored_file] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [module] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [extension] NVARCHAR(20) NOT NULL,
    [mime_type] NVARCHAR(100) NOT NULL,
    [size_bytes] BIGINT NOT NULL,
    [sha256] CHAR(64) NOT NULL,
    [storage_path] NVARCHAR(500) NOT NULL,
    [uploaded_by_user_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_stored_file_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_stored_file] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_stored_file_storage_path] UNIQUE ([storage_path])
);
GO
CREATE TABLE [core].[attachment] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [entity_type] NVARCHAR(50) NOT NULL,
    [entity_id] BIGINT NOT NULL,
    [file_id] BIGINT NULL,
    [label] NVARCHAR(200) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_attachment_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_attachment] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [core].[audit_log] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NULL,
    [entity_type] NVARCHAR(50) NULL,
    [entity_id] BIGINT NULL,
    [field_name] NVARCHAR(100) NULL,
    [old_value] NVARCHAR(MAX) NULL,
    [new_value] NVARCHAR(MAX) NULL,
    [action_name] NVARCHAR(30) NULL,
    [performed_by_user_id] BIGINT NULL,
    [performed_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_audit_log_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_audit_log] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [core].[company_setting] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [module] NVARCHAR(30) NULL,
    [setting_key] NVARCHAR(100) NULL,
    [setting_value] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_company_setting_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_company_setting] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [core].[number_sequence] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [prefix] NVARCHAR(10) NULL,
    [next_number] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_number_sequence_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_number_sequence] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [core].[filter_preset] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [user_account_id] BIGINT NOT NULL,
    [screen] NVARCHAR(100) NULL,
    [name] NVARCHAR(200) NOT NULL,
    [filters] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_filter_preset_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_filter_preset] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [core].[notification] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [user_account_id] BIGINT NOT NULL,
    [notification_type] NVARCHAR(30) NULL,
    [title] NVARCHAR(200) NOT NULL,
    [body] NVARCHAR(MAX) NULL,
    [link] NVARCHAR(500) NULL,
    [entity_type] NVARCHAR(50) NULL,
    [entity_id] BIGINT NULL,
    [read_at] DATETIME2(0) NULL,
    [cleared_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_notification_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_notification] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [core].[webhook] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [url] NVARCHAR(1000) NOT NULL,
    [secret] NVARCHAR(100) NOT NULL,
    [events] NVARCHAR(MAX) NOT NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_webhook_is_active] DEFAULT 0,
    [failure_count] INT NOT NULL,
    [last_delivery_at] DATETIME2(0) NULL,
    [last_status_code] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_webhook_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_webhook] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [core].[outbox_event] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [event_type] NVARCHAR(100) NOT NULL,
    [entity_type] NVARCHAR(50) NULL,
    [entity_id] BIGINT NULL,
    [payload] NVARCHAR(MAX) NOT NULL,
    [occurred_at] DATETIME2(0) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_outbox_event_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_outbox_event] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [core].[webhook_delivery] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [webhook_id] BIGINT NOT NULL,
    [outbox_event_id] BIGINT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [attempts] INT NOT NULL,
    [next_attempt_at] DATETIME2(0) NULL,
    [last_attempt_at] DATETIME2(0) NULL,
    [response_code] INT NULL,
    [response_body] NVARCHAR(2000) NULL,
    [error] NVARCHAR(1000) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_webhook_delivery_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_webhook_delivery] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [eng].[announcement] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [author_id] BIGINT NULL,
    [kind] NVARCHAR(30) NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [body] NVARCHAR(MAX) NULL,
    [event_date] DATE NULL,
    [publish_from] DATE NULL,
    [publish_to] DATE NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_announcement_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_announcement] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [eng].[announcement_read] (
    [announcement_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [read_at] DATETIME2(0) NULL,
    [cleared_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_announcement_read_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_announcement_read] PRIMARY KEY CLUSTERED ([announcement_id], [employee_id])
);
GO
CREATE TABLE [eng].[post] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [author_id] BIGINT NOT NULL,
    [body] NVARCHAR(MAX) NULL,
    [visibility] NVARCHAR(30) NOT NULL,
    [department_id] BIGINT NULL,
    [branch_id] BIGINT NULL,
    [posted_at] DATETIME2(0) NOT NULL,
    [edited_at] DATETIME2(0) NULL,
    [is_pinned] BIT NOT NULL CONSTRAINT [DF_post_is_pinned] DEFAULT 0,
    [pinned_at] DATETIME2(0) NULL,
    [pinned_by_user_id] BIGINT NULL,
    [is_hidden] BIT NOT NULL CONSTRAINT [DF_post_is_hidden] DEFAULT 0,
    [hidden_at] DATETIME2(0) NULL,
    [hidden_by_user_id] BIGINT NULL,
    [hidden_reason] NVARCHAR(500) NULL,
    [is_deleted] BIT NOT NULL CONSTRAINT [DF_post_is_deleted] DEFAULT 0,
    [deleted_at] DATETIME2(0) NULL,
    [deleted_by_user_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_post_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_post] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [eng].[post_media] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [post_id] BIGINT NOT NULL,
    [file_id] BIGINT NOT NULL,
    [media_type] NVARCHAR(30) NULL,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_post_media_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_post_media] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_post_media_post_id_file_id] UNIQUE ([post_id], [file_id])
);
GO
CREATE TABLE [eng].[post_reaction] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [post_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [kind] NVARCHAR(30) NOT NULL,
    [reacted_at] DATETIME2(0) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_post_reaction_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_post_reaction] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_post_reaction_post_id_employee_id] UNIQUE ([post_id], [employee_id])
);
GO
CREATE TABLE [eng].[post_comment] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [post_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [parent_id] BIGINT NULL,
    [body] NVARCHAR(MAX) NOT NULL,
    [commented_at] DATETIME2(0) NOT NULL,
    [edited_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_post_comment_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_post_comment] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [eng].[post_comment_like] (
    [post_comment_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [liked_at] DATETIME2(0) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_post_comment_like_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_post_comment_like] PRIMARY KEY CLUSTERED ([post_comment_id], [employee_id])
);
GO
CREATE TABLE [eng].[post_view] (
    [post_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [viewed_at] DATETIME2(0) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_post_view_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_post_view] PRIMARY KEY CLUSTERED ([post_id], [employee_id])
);
GO
CREATE TABLE [eng].[post_mention] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [post_id] BIGINT NOT NULL,
    [post_comment_id] BIGINT NULL,
    [employee_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_post_mention_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_post_mention] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [eng].[survey] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [is_anonymous] BIT NOT NULL CONSTRAINT [DF_survey_is_anonymous] DEFAULT 0,
    [status] NVARCHAR(30) NOT NULL,
    [opens_on] DATE NULL,
    [closes_on] DATE NULL,
    [published_at] DATETIME2(0) NULL,
    [published_by_user_id] BIGINT NULL,
    [closed_at] DATETIME2(0) NULL,
    [closed_by_user_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_survey_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_survey] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [eng].[survey_audience] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [survey_id] BIGINT NOT NULL,
    [unit_type] NVARCHAR(30) NOT NULL,
    [unit_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_survey_audience_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_survey_audience] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_survey_audience_survey_id_unit_type_unit_id] UNIQUE ([survey_id], [unit_type], [unit_id])
);
GO
CREATE TABLE [eng].[survey_question] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [survey_id] BIGINT NOT NULL,
    [sort_order] INT NULL,
    [question_type] NVARCHAR(30) NOT NULL,
    [question_text] NVARCHAR(1000) NOT NULL,
    [is_required] BIT NOT NULL CONSTRAINT [DF_survey_question_is_required] DEFAULT 0,
    [scale_min] INT NULL,
    [scale_max] INT NULL,
    [scale_min_label] NVARCHAR(100) NULL,
    [scale_max_label] NVARCHAR(100) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_survey_question_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_survey_question] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [eng].[survey_option] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [survey_question_id] BIGINT NOT NULL,
    [sort_order] INT NULL,
    [option_text] NVARCHAR(500) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_survey_option_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_survey_option] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [eng].[survey_participant] (
    [survey_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [responded_at] DATETIME2(0) NULL,
    [skipped] BIT NOT NULL CONSTRAINT [DF_survey_participant_skipped] DEFAULT 0,
    [skipped_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_survey_participant_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_survey_participant] PRIMARY KEY CLUSTERED ([survey_id], [employee_id])
);
GO
CREATE TABLE [eng].[survey_response] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [survey_id] BIGINT NOT NULL,
    [employee_id] BIGINT NULL,
    [submitted_at] DATETIME2(0) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_survey_response_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_survey_response] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [eng].[survey_answer] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [survey_response_id] BIGINT NOT NULL,
    [survey_question_id] BIGINT NOT NULL,
    [survey_option_id] BIGINT NULL,
    [answer_text] NVARCHAR(MAX) NULL,
    [rating_value] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_survey_answer_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_survey_answer] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[template] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [template_kind] NVARCHAR(30) NOT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_template_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_template] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_template_template_kind_code] UNIQUE ([template_kind], [code])
);
GO
CREATE TABLE [pm].[template_item] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [template_id] BIGINT NOT NULL,
    [item_type] NVARCHAR(30) NOT NULL,
    [item_code] NVARCHAR(50) NULL,
    [name] NVARCHAR(200) NOT NULL,
    [status_group] NVARCHAR(30) NULL,
    [color] NVARCHAR(20) NULL,
    [sort_order] INT NULL,
    [is_default] BIT NOT NULL CONSTRAINT [DF_template_item_is_default] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_template_item_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_template_item] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[workspace] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [privacy] NVARCHAR(30) NOT NULL,
    [department_id] BIGINT NOT NULL,
    [workflow_template_id] BIGINT NOT NULL,
    [status_mode] NVARCHAR(30) NOT NULL,
    [status_template_id] BIGINT NULL,
    [owner_id] BIGINT NOT NULL,
    [cover_file_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_workspace_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_workspace] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_workspace_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [pm].[workspace_member] (
    [workspace_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [member_role] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_workspace_member_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_workspace_member] PRIMARY KEY CLUSTERED ([workspace_id], [employee_id])
);
GO
CREATE TABLE [pm].[workspace_status] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [status_group] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [color] NVARCHAR(20) NULL,
    [sort_order] INT NULL,
    [wip_limit] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_workspace_status_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_workspace_status] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_workspace_status_workspace_id_name] UNIQUE ([workspace_id], [name])
);
GO
CREATE TABLE [pm].[workspace_feature] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [feature_code] NVARCHAR(50) NOT NULL,
    [setting_value] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_workspace_feature_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_workspace_feature] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_workspace_feature_workspace_id_feature_code] UNIQUE ([workspace_id], [feature_code])
);
GO
CREATE TABLE [pm].[folder] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_folder_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_folder] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_folder_workspace_id_name] UNIQUE ([workspace_id], [name])
);
GO
CREATE TABLE [pm].[task_list] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [folder_id] BIGINT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [privacy] NVARCHAR(30) NULL,
    [color] NVARCHAR(20) NULL,
    [description] NVARCHAR(MAX) NULL,
    [start_at] DATETIME2(0) NULL,
    [end_at] DATETIME2(0) NULL,
    [priority] NVARCHAR(30) NULL,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_task_list_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_task_list] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_task_list_workspace_id_name] UNIQUE ([workspace_id], [name])
);
GO
CREATE TABLE [pm].[task_list_member] (
    [task_list_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_task_list_member_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_task_list_member] PRIMARY KEY CLUSTERED ([task_list_id], [employee_id])
);
GO
CREATE TABLE [pm].[sprint] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [start_date] DATE NULL,
    [end_date] DATE NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_sprint_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_sprint] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[task] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [task_list_id] BIGINT NULL,
    [parent_task_id] BIGINT NULL,
    [code] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [task_type] NVARCHAR(30) NOT NULL,
    [status_id] BIGINT NOT NULL,
    [priority] NVARCHAR(30) NULL,
    [start_date] DATE NULL,
    [start_time] TIME(0) NULL,
    [due_date] DATE NULL,
    [due_time] TIME(0) NULL,
    [original_due_date] DATE NULL,
    [time_estimate_minutes] INT NULL,
    [rating] INT NULL,
    [url] NVARCHAR(2000) NULL,
    [recurrence] NVARCHAR(MAX) NULL,
    [sprint_id] BIGINT NULL,
    [cover_file_id] BIGINT NULL,
    [sort_order] INT NULL,
    [closed_at] DATETIME2(0) NULL,
    [is_closed_late] BIT NOT NULL CONSTRAINT [DF_task_is_closed_late] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_task_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_task] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_task_company_id_code] UNIQUE ([company_id], [code])
);
GO
CREATE TABLE [pm].[task_assignee] (
    [task_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [story_points] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_task_assignee_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_task_assignee] PRIMARY KEY CLUSTERED ([task_id], [employee_id])
);
GO
CREATE TABLE [pm].[task_dependency] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [task_id] BIGINT NOT NULL,
    [other_task_id] BIGINT NOT NULL,
    [kind] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_task_dependency_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_task_dependency] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_task_dependency_task_id_other_task_id] UNIQUE ([task_id], [other_task_id])
);
GO
CREATE TABLE [pm].[tag] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [color] NVARCHAR(20) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_tag_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_tag] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_tag_workspace_id_name] UNIQUE ([workspace_id], [name])
);
GO
CREATE TABLE [pm].[task_tag] (
    [task_id] BIGINT NOT NULL,
    [tag_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_task_tag_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_task_tag] PRIMARY KEY CLUSTERED ([task_id], [tag_id])
);
GO
CREATE TABLE [pm].[checklist_item] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [task_id] BIGINT NOT NULL,
    [item_text] NVARCHAR(500) NOT NULL,
    [is_done] BIT NOT NULL CONSTRAINT [DF_checklist_item_is_done] DEFAULT 0,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_checklist_item_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_checklist_item] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[time_entry] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [task_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [start_at] DATETIME2(0) NOT NULL,
    [end_at] DATETIME2(0) NULL,
    [minutes] INT NULL,
    [notes] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_time_entry_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_time_entry] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[task_comment] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [task_id] BIGINT NOT NULL,
    [author_id] BIGINT NOT NULL,
    [body] NVARCHAR(MAX) NOT NULL,
    [parent_id] BIGINT NULL,
    [assigned_to_id] BIGINT NULL,
    [assigned_by_id] BIGINT NULL,
    [resolved_by_id] BIGINT NULL,
    [resolved_at] DATETIME2(0) NULL,
    [edited_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_task_comment_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_task_comment] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[comment_mention] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [comment_id] BIGINT NOT NULL,
    [employee_id] BIGINT NULL,
    [mentioned_task_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_comment_mention_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_comment_mention] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[comment_reaction] (
    [comment_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [reaction] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_comment_reaction_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_comment_reaction] PRIMARY KEY CLUSTERED ([comment_id], [employee_id])
);
GO
CREATE TABLE [pm].[reminder] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [entity_type] NVARCHAR(50) NOT NULL,
    [entity_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [owner_id] BIGINT NOT NULL,
    [assignee_id] BIGINT NULL,
    [remind_at] DATETIME2(0) NOT NULL,
    [notify_before_minutes] INT NULL,
    [reminder_kind] NVARCHAR(30) NULL,
    [notified_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_reminder_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_reminder] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[task_extension] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [task_id] BIGINT NOT NULL,
    [requested_by_id] BIGINT NOT NULL,
    [old_due_date] DATE NULL,
    [new_due_date] DATE NOT NULL,
    [reason] NVARCHAR(MAX) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [decided_by_id] BIGINT NULL,
    [decided_at] DATETIME2(0) NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [request_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_task_extension_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_task_extension] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[custom_field] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [field_type] NVARCHAR(30) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [config] NVARCHAR(MAX) NULL,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_custom_field_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_custom_field] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_custom_field_workspace_id_name] UNIQUE ([workspace_id], [name])
);
GO
CREATE TABLE [pm].[column_permission] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [column_key] NVARCHAR(50) NOT NULL,
    [member_role] NVARCHAR(30) NULL,
    [employee_id] BIGINT NULL,
    [permission_level] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_column_permission_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_column_permission] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[task_field_value] (
    [task_id] BIGINT NOT NULL,
    [custom_field_id] BIGINT NOT NULL,
    [field_value] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_task_field_value_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_task_field_value] PRIMARY KEY CLUSTERED ([task_id], [custom_field_id])
);
GO
CREATE TABLE [pm].[list_view] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [task_list_id] BIGINT NULL,
    [owner_id] BIGINT NULL,
    [view_type] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [config] NVARCHAR(MAX) NULL,
    [is_pinned] BIT NOT NULL CONSTRAINT [DF_list_view_is_pinned] DEFAULT 0,
    [is_private] BIT NOT NULL CONSTRAINT [DF_list_view_is_private] DEFAULT 0,
    [is_protected] BIT NOT NULL CONSTRAINT [DF_list_view_is_protected] DEFAULT 0,
    [is_default] BIT NOT NULL CONSTRAINT [DF_list_view_is_default] DEFAULT 0,
    [is_required] BIT NOT NULL CONSTRAINT [DF_list_view_is_required] DEFAULT 0,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_list_view_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_list_view] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[share_link] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [entity_type] NVARCHAR(50) NOT NULL,
    [entity_id] BIGINT NOT NULL,
    [share_scope] NVARCHAR(30) NULL,
    [token] NVARCHAR(100) NOT NULL,
    [is_public] BIT NOT NULL CONSTRAINT [DF_share_link_is_public] DEFAULT 0,
    [allow_open_tasks] BIT NOT NULL CONSTRAINT [DF_share_link_allow_open_tasks] DEFAULT 0,
    [valid_from] DATETIME2(0) NULL,
    [valid_to] DATETIME2(0) NULL,
    [max_access] INT NULL,
    [access_count] INT NULL,
    [properties] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_share_link_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_share_link] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_share_link_token] UNIQUE ([token]),
    CONSTRAINT [UQ_share_link_entity_type_entity_id] UNIQUE ([entity_type], [entity_id])
);
GO
CREATE TABLE [pm].[share_member] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [share_link_id] BIGINT NOT NULL,
    [employee_id] BIGINT NULL,
    [email] NVARCHAR(254) NULL,
    [access_level] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_share_member_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_share_member] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[share_access] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [share_link_id] BIGINT NOT NULL,
    [accessed_at] DATETIME2(0) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_share_access_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_share_access] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[favorite] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [entity_type] NVARCHAR(50) NOT NULL,
    [entity_id] BIGINT NOT NULL,
    [kind] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_favorite_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_favorite] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_favorite_employee_id_entity_type_entity_id_kind] UNIQUE ([employee_id], [entity_type], [entity_id], [kind])
);
GO
CREATE TABLE [pm].[workspace_overdue_setting] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [penalty_percent] DECIMAL(5,2) NOT NULL,
    [max_extensions] INT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_workspace_overdue_setting_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_workspace_overdue_setting] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_workspace_overdue_setting_workspace_id] UNIQUE ([workspace_id])
);
GO
CREATE TABLE [pm].[task_external_file] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [task_id] BIGINT NOT NULL,
    [provider] NVARCHAR(30) NOT NULL,
    [external_id] NVARCHAR(500) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [web_url] NVARCHAR(2000) NOT NULL,
    [mime_type] NVARCHAR(100) NULL,
    [size_bytes] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_task_external_file_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_task_external_file] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_task_external_file_task_id_provider_external_id] UNIQUE ([task_id], [provider], [external_id])
);
GO
CREATE TABLE [pm].[doc] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [workspace_id] BIGINT NOT NULL,
    [folder_id] BIGINT NULL,
    [task_list_id] BIGINT NULL,
    [title] NVARCHAR(50) NOT NULL,
    [content] NVARCHAR(MAX) NULL,
    [content_html] NVARCHAR(MAX) NULL,
    [visibility] NVARCHAR(30) NOT NULL,
    [owner_id] BIGINT NOT NULL,
    [cover_file_id] BIGINT NULL,
    [settings] NVARCHAR(MAX) NULL,
    [word_count] INT NULL,
    [character_count] INT NULL,
    [archived_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_doc_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_doc] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[doc_contributor] (
    [doc_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_doc_contributor_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_doc_contributor] PRIMARY KEY CLUSTERED ([doc_id], [employee_id])
);
GO
CREATE TABLE [pm].[doc_task] (
    [doc_id] BIGINT NOT NULL,
    [task_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_doc_task_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_doc_task] PRIMARY KEY CLUSTERED ([doc_id], [task_id])
);
GO
CREATE TABLE [pm].[doc_comment] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [doc_id] BIGINT NOT NULL,
    [author_id] BIGINT NOT NULL,
    [body] NVARCHAR(MAX) NOT NULL,
    [parent_id] BIGINT NULL,
    [edited_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_doc_comment_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_doc_comment] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[note] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [user_account_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [content_html] NVARCHAR(MAX) NULL,
    [version_no] INT NULL,
    [archived_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_note_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_note] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[note_version] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [note_id] BIGINT NOT NULL,
    [version_no] INT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [content_html] NVARCHAR(MAX) NULL,
    [edited_by_user_id] BIGINT NULL,
    [edited_at] DATETIME2(0) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_note_version_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_note_version] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_note_version_note_id_version_no] UNIQUE ([note_id], [version_no])
);
GO
CREATE TABLE [pm].[personal_item] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [user_account_id] BIGINT NOT NULL,
    [title] NVARCHAR(120) NOT NULL,
    [is_done] BIT NOT NULL CONSTRAINT [DF_personal_item_is_done] DEFAULT 0,
    [due_date] DATE NULL,
    [done_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_personal_item_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_personal_item] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [pm].[recent_item] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [user_account_id] BIGINT NOT NULL,
    [entity_type] NVARCHAR(50) NOT NULL,
    [entity_id] BIGINT NOT NULL,
    [workspace_id] BIGINT NULL,
    [opened_at] DATETIME2(0) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_recent_item_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_recent_item] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_recent_item_user_account_id_entity_type_entity_id] UNIQUE ([user_account_id], [entity_type], [entity_id])
);
GO
CREATE TABLE [att].[warning_policy] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [applies_to] NVARCHAR(30) NOT NULL,
    [period] NVARCHAR(30) NOT NULL,
    [grace_minutes] INT NULL,
    [week_start_day] NVARCHAR(30) NULL,
    [week_end_day] NVARCHAR(30) NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_warning_policy_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_warning_policy_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_warning_policy] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_warning_policy_company_id_title] UNIQUE ([company_id], [title])
);
GO
CREATE TABLE [att].[warning_policy_rule] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [warning_policy_id] BIGINT NOT NULL,
    [clock_event] NVARCHAR(30) NOT NULL,
    [minutes] INT NOT NULL,
    [occurrence_count] INT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_warning_policy_rule_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_warning_policy_rule] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_warning_policy_rule_warning_policy_id_clock_event] UNIQUE ([warning_policy_id], [clock_event])
);
GO
CREATE TABLE [att].[penalty_rule] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [warning_policy_id] BIGINT NOT NULL,
    [after_count] INT NOT NULL,
    [period] NVARCHAR(30) NOT NULL,
    [penalty_type] NVARCHAR(30) NOT NULL,
    [percentage] DECIMAL(5,2) NOT NULL,
    [deduction] NVARCHAR(30) NOT NULL,
    [leave_type_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_penalty_rule_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_penalty_rule] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_penalty_rule_warning_policy_id_period_after_count] UNIQUE ([warning_policy_id], [period], [after_count])
);
GO
CREATE TABLE [att].[warning] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [warning_policy_id] BIGINT NOT NULL,
    [warning_policy_rule_id] BIGINT NOT NULL,
    [timesheet_day_id] BIGINT NOT NULL,
    [work_date] DATE NOT NULL,
    [minutes] INT NULL,
    [occurrence_no] INT NULL,
    [penalty_rule_id] BIGINT NULL,
    [penalty_type] NVARCHAR(30) NULL,
    [penalty_percentage] DECIMAL(5,2) NULL,
    [deduction] NVARCHAR(30) NULL,
    [payslip_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_warning_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_warning] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_warning_warning_policy_rule_id_timesheet_day_id] UNIQUE ([warning_policy_rule_id], [timesheet_day_id])
);
GO
CREATE TABLE [ben].[plan_year] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [start_date] DATE NOT NULL,
    [end_date] DATE NOT NULL,
    [new_hire_start] NVARCHAR(30) NOT NULL,
    [waiting_period_days] INT NULL,
    [election_period] INT NOT NULL,
    [election_unit] NVARCHAR(10) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_plan_year_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_plan_year] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_plan_year_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [ben].[benefit_plan] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [category] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [plan_type] NVARCHAR(100) NULL,
    [plan_type_ref] NVARCHAR(50) NULL,
    [carrier] NVARCHAR(200) NULL,
    [start_date] DATE NOT NULL,
    [end_date] DATE NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_benefit_plan_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_benefit_plan] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_benefit_plan_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [ben].[plan_year_plan] (
    [plan_year_id] BIGINT NOT NULL,
    [benefit_plan_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_plan_year_plan_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_plan_year_plan] PRIMARY KEY CLUSTERED ([plan_year_id], [benefit_plan_id])
);
GO
CREATE TABLE [ben].[enrollment_window] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [plan_year_id] BIGINT NOT NULL,
    [kind] NVARCHAR(30) NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [effective_date] DATE NOT NULL,
    [closes_on] DATE NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_enrollment_window_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_enrollment_window] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [ben].[enrollment_window_plan] (
    [enrollment_window_id] BIGINT NOT NULL,
    [benefit_plan_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_enrollment_window_plan_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_enrollment_window_plan] PRIMARY KEY CLUSTERED ([enrollment_window_id], [benefit_plan_id])
);
GO
CREATE TABLE [ben].[enrollment_window_employee] (
    [enrollment_window_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_enrollment_window_employee_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_enrollment_window_employee] PRIMARY KEY CLUSTERED ([enrollment_window_id], [employee_id])
);
GO
CREATE TABLE [ben].[election] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [plan_year_id] BIGINT NOT NULL,
    [enrollment_window_id] BIGINT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [submitted_at] DATETIME2(0) NULL,
    [decided_by_user_id] BIGINT NULL,
    [decided_at] DATETIME2(0) NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_election_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_election] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_election_employee_id_plan_year_id] UNIQUE ([employee_id], [plan_year_id])
);
GO
CREATE TABLE [ben].[election_plan] (
    [election_id] BIGINT NOT NULL,
    [benefit_plan_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_election_plan_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_election_plan] PRIMARY KEY CLUSTERED ([election_id], [benefit_plan_id])
);
GO
CREATE TABLE [ben].[health_benefit] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [insurer] NVARCHAR(200) NULL,
    [policy_no] NVARCHAR(50) NULL,
    [coverage_amount] DECIMAL(18,2) NULL,
    [life_cover_amount] DECIMAL(18,2) NULL,
    [annual_payment] DECIMAL(18,2) NULL,
    [start_date] DATE NULL,
    [end_date] DATE NULL,
    [status] NVARCHAR(30) NOT NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [document_file_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_health_benefit_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_health_benefit] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [ben].[perk] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [occasion] NVARCHAR(30) NOT NULL,
    [perk_date] DATE NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [amount] DECIMAL(18,2) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_perk_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_perk] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_perk_employee_id_occasion_perk_date] UNIQUE ([employee_id], [occasion], [perk_date])
);
GO
CREATE TABLE [perf].[rating_scale] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [is_default] BIT NOT NULL CONSTRAINT [DF_rating_scale_is_default] DEFAULT 0,
    [is_active] BIT NOT NULL CONSTRAINT [DF_rating_scale_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_rating_scale_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_rating_scale] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_rating_scale_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [perf].[rating_scale_level] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [rating_scale_id] BIGINT NOT NULL,
    [score] DECIMAL(5,2) NOT NULL,
    [label] NVARCHAR(100) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_rating_scale_level_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_rating_scale_level] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_rating_scale_level_rating_scale_id_score] UNIQUE ([rating_scale_id], [score])
);
GO
CREATE TABLE [perf].[kpi] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [key_result_area] NVARCHAR(200) NULL,
    [description] NVARCHAR(MAX) NULL,
    [measure_type] NVARCHAR(30) NULL,
    [target_value] DECIMAL(18,2) NULL,
    [unit] NVARCHAR(30) NULL,
    [default_weight] DECIMAL(5,2) NULL,
    [department_id] BIGINT NULL,
    [job_title_id] BIGINT NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_kpi_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_kpi_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_kpi] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_kpi_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [perf].[appraisal_form] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [rating_scale_id] BIGINT NOT NULL,
    [goals_weight] DECIMAL(5,2) NOT NULL,
    [has_self_review] BIT NOT NULL CONSTRAINT [DF_appraisal_form_has_self_review] DEFAULT 0,
    [is_active] BIT NOT NULL CONSTRAINT [DF_appraisal_form_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_appraisal_form_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_appraisal_form] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_appraisal_form_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [perf].[appraisal_criterion] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [appraisal_form_id] BIGINT NOT NULL,
    [kpi_id] BIGINT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [weight] DECIMAL(5,2) NOT NULL,
    [sort_order] INT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_appraisal_criterion_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_appraisal_criterion] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [perf].[appraisal_cycle] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [appraisal_form_id] BIGINT NOT NULL,
    [start_date] DATE NOT NULL,
    [end_date] DATE NOT NULL,
    [self_review_due_date] DATE NULL,
    [manager_review_due_date] DATE NULL,
    [status] NVARCHAR(30) NOT NULL,
    [launched_at] DATETIME2(0) NULL,
    [closed_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_appraisal_cycle_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_appraisal_cycle] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_appraisal_cycle_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [perf].[appraisal] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [appraisal_cycle_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [reviewer_employee_id] BIGINT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [goals_score] DECIMAL(5,2) NULL,
    [self_score] DECIMAL(5,2) NULL,
    [manager_score] DECIMAL(5,2) NULL,
    [final_score] DECIMAL(5,2) NULL,
    [final_rating_label] NVARCHAR(100) NULL,
    [self_comments] NVARCHAR(MAX) NULL,
    [manager_comments] NVARCHAR(MAX) NULL,
    [final_comments] NVARCHAR(MAX) NULL,
    [development_needs] NVARCHAR(MAX) NULL,
    [outcome] NVARCHAR(30) NULL,
    [self_submitted_at] DATETIME2(0) NULL,
    [manager_submitted_at] DATETIME2(0) NULL,
    [finalised_at] DATETIME2(0) NULL,
    [finalised_by_user_id] BIGINT NULL,
    [letter_file_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_appraisal_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_appraisal] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_appraisal_appraisal_cycle_id_employee_id] UNIQUE ([appraisal_cycle_id], [employee_id])
);
GO
CREATE TABLE [perf].[appraisal_rating] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [appraisal_id] BIGINT NOT NULL,
    [appraisal_criterion_id] BIGINT NOT NULL,
    [self_rating] DECIMAL(5,2) NULL,
    [manager_rating] DECIMAL(5,2) NULL,
    [self_comment] NVARCHAR(MAX) NULL,
    [manager_comment] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_appraisal_rating_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_appraisal_rating] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_appraisal_rating_appraisal_id_appraisal_criterion_id] UNIQUE ([appraisal_id], [appraisal_criterion_id])
);
GO
CREATE TABLE [perf].[goal] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [appraisal_cycle_id] BIGINT NULL,
    [kpi_id] BIGINT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [start_date] DATE NULL,
    [due_date] DATE NOT NULL,
    [weight] DECIMAL(5,2) NOT NULL,
    [target_value] DECIMAL(18,2) NULL,
    [actual_value] DECIMAL(18,2) NULL,
    [progress] DECIMAL(5,2) NOT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [completed_at] DATETIME2(0) NULL,
    [set_by_user_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_goal_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_goal] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [perf].[goal_check_in] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [goal_id] BIGINT NOT NULL,
    [progress] DECIMAL(5,2) NOT NULL,
    [actual_value] DECIMAL(18,2) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [comments] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_goal_check_in_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_goal_check_in] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [perf].[increment_proposal] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [appraisal_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [change_type] NVARCHAR(30) NOT NULL,
    [change_value] DECIMAL(18,2) NOT NULL,
    [effective_date] DATE NOT NULL,
    [current_salary] DECIMAL(18,2) NULL,
    [proposed_salary] DECIMAL(18,2) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [employee_salary_id] BIGINT NULL,
    [decided_at] DATETIME2(0) NULL,
    [decided_by_user_id] BIGINT NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_increment_proposal_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_increment_proposal] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_increment_proposal_appraisal_id] UNIQUE ([appraisal_id])
);
GO
CREATE TABLE [trn].[training_category] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [name] NVARCHAR(200) NOT NULL,
    [is_active] BIT NOT NULL CONSTRAINT [DF_training_category_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_training_category_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_training_category] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_training_category_company_id_name] UNIQUE ([company_id], [name])
);
GO
CREATE TABLE [trn].[training_program] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [training_category_id] BIGINT NULL,
    [description] NVARCHAR(MAX) NULL,
    [delivery_mode] NVARCHAR(30) NULL,
    [provider_type] NVARCHAR(30) NULL,
    [provider_name] NVARCHAR(200) NULL,
    [duration_hours] DECIMAL(6,2) NULL,
    [cost_per_head] DECIMAL(18,2) NULL,
    [issues_certificate] BIT NOT NULL CONSTRAINT [DF_training_program_issues_certificate] DEFAULT 0,
    [certificate_validity_months] INT NULL,
    [is_mandatory] BIT NOT NULL CONSTRAINT [DF_training_program_is_mandatory] DEFAULT 0,
    [is_active] BIT NOT NULL CONSTRAINT [DF_training_program_is_active] DEFAULT 0,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_training_program_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_training_program] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_training_program_company_id_title] UNIQUE ([company_id], [title])
);
GO
CREATE TABLE [trn].[training_session] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [training_program_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [start_date] DATE NOT NULL,
    [end_date] DATE NOT NULL,
    [start_time] TIME(0) NULL,
    [end_time] TIME(0) NULL,
    [delivery_mode] NVARCHAR(30) NULL,
    [venue] NVARCHAR(300) NULL,
    [online_link] NVARCHAR(500) NULL,
    [trainer_type] NVARCHAR(30) NULL,
    [trainer_employee_id] BIGINT NULL,
    [trainer_name] NVARCHAR(200) NULL,
    [capacity] INT NULL,
    [nomination_deadline] DATE NULL,
    [status] NVARCHAR(30) NOT NULL,
    [cost] DECIMAL(18,2) NULL,
    [cancel_reason] NVARCHAR(MAX) NULL,
    [completed_at] DATETIME2(0) NULL,
    [cancelled_at] DATETIME2(0) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_training_session_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_training_session] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [trn].[training_enrolment] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [training_session_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [nomination_source] NVARCHAR(30) NULL,
    [nominated_by_user_id] BIGINT NULL,
    [decided_by_user_id] BIGINT NULL,
    [decided_at] DATETIME2(0) NULL,
    [decision_remarks] NVARCHAR(MAX) NULL,
    [attendance_percent] DECIMAL(5,2) NULL,
    [score] DECIMAL(5,2) NULL,
    [result_remarks] NVARCHAR(MAX) NULL,
    [completed_at] DATETIME2(0) NULL,
    [certificate_file_id] BIGINT NULL,
    [certificate_no] NVARCHAR(100) NULL,
    [certificate_issued_date] DATE NULL,
    [certificate_expiry_date] DATE NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_training_enrolment_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_training_enrolment] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_training_enrolment_training_session_id_employee_id] UNIQUE ([training_session_id], [employee_id])
);
GO
CREATE TABLE [trn].[training_attendance] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [training_enrolment_id] BIGINT NOT NULL,
    [attendance_date] DATE NOT NULL,
    [status] NVARCHAR(30) NOT NULL,
    [remarks] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_training_attendance_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_training_attendance] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_training_attendance_training_enrolment_id_attendance_date] UNIQUE ([training_enrolment_id], [attendance_date])
);
GO
CREATE TABLE [trn].[training_feedback] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [training_enrolment_id] BIGINT NOT NULL,
    [overall_rating] INT NOT NULL,
    [trainer_rating] INT NULL,
    [content_rating] INT NULL,
    [comments] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_training_feedback_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_training_feedback] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_training_feedback_training_enrolment_id] UNIQUE ([training_enrolment_id])
);
GO
CREATE TABLE [frm].[form] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [category] NVARCHAR(100) NULL,
    [status] NVARCHAR(30) NOT NULL,
    [closes_on] DATE NULL,
    [audience_kind] NVARCHAR(30) NOT NULL,
    [is_one_per_person] BIT NOT NULL CONSTRAINT [DF_form_is_one_per_person] DEFAULT 0,
    [is_anonymous] BIT NOT NULL CONSTRAINT [DF_form_is_anonymous] DEFAULT 0,
    [published_at] DATETIME2(0) NULL,
    [published_by_user_id] BIGINT NULL,
    [closed_at] DATETIME2(0) NULL,
    [closed_by_user_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_form_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_form] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [frm].[form_section] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [form_id] BIGINT NOT NULL,
    [sort_order] INT NULL,
    [title] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(MAX) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_form_section_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_form_section] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [frm].[form_field] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [form_id] BIGINT NOT NULL,
    [form_section_id] BIGINT NULL,
    [sort_order] INT NULL,
    [field_type] NVARCHAR(30) NOT NULL,
    [label] NVARCHAR(500) NOT NULL,
    [help_text] NVARCHAR(1000) NULL,
    [is_required] BIT NOT NULL CONSTRAINT [DF_form_field_is_required] DEFAULT 0,
    [min_value] DECIMAL(18,4) NULL,
    [max_value] DECIMAL(18,4) NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_form_field_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_form_field] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [frm].[form_field_option] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [form_field_id] BIGINT NOT NULL,
    [sort_order] INT NULL,
    [label] NVARCHAR(500) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_form_field_option_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_form_field_option] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [frm].[form_audience] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [form_id] BIGINT NOT NULL,
    [unit_type] NVARCHAR(30) NOT NULL,
    [unit_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_form_audience_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_form_audience] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_form_audience_form_id_unit_type_unit_id] UNIQUE ([form_id], [unit_type], [unit_id])
);
GO
CREATE TABLE [frm].[form_response] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [company_id] BIGINT NOT NULL,
    [form_id] BIGINT NOT NULL,
    [employee_id] BIGINT NOT NULL,
    [submitted_at] DATETIME2(0) NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_form_response_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_form_response] PRIMARY KEY CLUSTERED ([id])
);
GO
CREATE TABLE [frm].[form_answer] (
    [id] BIGINT IDENTITY(1,1) NOT NULL,
    [form_response_id] BIGINT NOT NULL,
    [form_field_id] BIGINT NOT NULL,
    [answer_text] NVARCHAR(MAX) NULL,
    [answer_number] DECIMAL(18,4) NULL,
    [answer_date] DATE NULL,
    [answer_bool] BIT NULL CONSTRAINT [DF_form_answer_answer_bool] DEFAULT 0,
    [file_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_form_answer_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_form_answer] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_form_answer_form_response_id_form_field_id] UNIQUE ([form_response_id], [form_field_id])
);
GO
CREATE TABLE [frm].[form_answer_option] (
    [form_answer_id] BIGINT NOT NULL,
    [form_field_option_id] BIGINT NOT NULL,
    [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_form_answer_option_created_at] DEFAULT SYSUTCDATETIME(),
    [created_by] BIGINT NULL,
    [updated_at] DATETIME2(0) NULL,
    [updated_by] BIGINT NULL,
    [row_version] ROWVERSION,
    CONSTRAINT [PK_form_answer_option] PRIMARY KEY CLUSTERED ([form_answer_id], [form_field_option_id])
);
GO

-- Foreign keys (all ON DELETE NO ACTION)
ALTER TABLE [org].[company] ADD CONSTRAINT [FK_company_logo_file_id] FOREIGN KEY ([logo_file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [org].[company] ADD CONSTRAINT [FK_company_country_id] FOREIGN KEY ([country_id]) REFERENCES [org].[country] ([id]);
ALTER TABLE [org].[state] ADD CONSTRAINT [FK_state_country_id] FOREIGN KEY ([country_id]) REFERENCES [org].[country] ([id]);
ALTER TABLE [org].[city] ADD CONSTRAINT [FK_city_state_id] FOREIGN KEY ([state_id]) REFERENCES [org].[state] ([id]);
ALTER TABLE [org].[location] ADD CONSTRAINT [FK_location_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [org].[area] ADD CONSTRAINT [FK_area_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [org].[area] ADD CONSTRAINT [FK_area_location_id] FOREIGN KEY ([location_id]) REFERENCES [org].[location] ([id]);
ALTER TABLE [org].[branch] ADD CONSTRAINT [FK_branch_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [org].[branch] ADD CONSTRAINT [FK_branch_location_id] FOREIGN KEY ([location_id]) REFERENCES [org].[location] ([id]);
ALTER TABLE [org].[branch] ADD CONSTRAINT [FK_branch_area_id] FOREIGN KEY ([area_id]) REFERENCES [org].[area] ([id]);
ALTER TABLE [org].[branch] ADD CONSTRAINT [FK_branch_manager_id] FOREIGN KEY ([manager_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [org].[branch] ADD CONSTRAINT [FK_branch_country_id] FOREIGN KEY ([country_id]) REFERENCES [org].[country] ([id]);
ALTER TABLE [org].[branch] ADD CONSTRAINT [FK_branch_state_id] FOREIGN KEY ([state_id]) REFERENCES [org].[state] ([id]);
ALTER TABLE [org].[branch] ADD CONSTRAINT [FK_branch_city_id] FOREIGN KEY ([city_id]) REFERENCES [org].[city] ([id]);
ALTER TABLE [org].[department] ADD CONSTRAINT [FK_department_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [org].[department] ADD CONSTRAINT [FK_department_parent_id] FOREIGN KEY ([parent_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [org].[department] ADD CONSTRAINT [FK_department_head_id] FOREIGN KEY ([head_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [org].[division] ADD CONSTRAINT [FK_division_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [org].[cost_center] ADD CONSTRAINT [FK_cost_center_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [org].[designation] ADD CONSTRAINT [FK_designation_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [org].[job_title] ADD CONSTRAINT [FK_job_title_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [org].[grade] ADD CONSTRAINT [FK_grade_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [org].[job_level] ADD CONSTRAINT [FK_job_level_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [org].[employee_group] ADD CONSTRAINT [FK_employee_group_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [org].[employment_type] ADD CONSTRAINT [FK_employment_type_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_home_city_id] FOREIGN KEY ([home_city_id]) REFERENCES [org].[city] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_photo_file_id] FOREIGN KEY ([photo_file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_location_id] FOREIGN KEY ([location_id]) REFERENCES [org].[location] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_area_id] FOREIGN KEY ([area_id]) REFERENCES [org].[area] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_division_id] FOREIGN KEY ([division_id]) REFERENCES [org].[division] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_cost_center_id] FOREIGN KEY ([cost_center_id]) REFERENCES [org].[cost_center] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_designation_id] FOREIGN KEY ([designation_id]) REFERENCES [org].[designation] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_job_title_id] FOREIGN KEY ([job_title_id]) REFERENCES [org].[job_title] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_grade_id] FOREIGN KEY ([grade_id]) REFERENCES [org].[grade] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_job_level_id] FOREIGN KEY ([job_level_id]) REFERENCES [org].[job_level] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_employee_group_id] FOREIGN KEY ([employee_group_id]) REFERENCES [org].[employee_group] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_employment_type_id] FOREIGN KEY ([employment_type_id]) REFERENCES [org].[employment_type] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_line_manager_id] FOREIGN KEY ([line_manager_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_final_authority_id] FOREIGN KEY ([final_authority_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee] ADD CONSTRAINT [FK_employee_default_time_slot_id] FOREIGN KEY ([default_time_slot_id]) REFERENCES [sch].[time_slot] ([id]);
ALTER TABLE [hr].[employment_period] ADD CONSTRAINT [FK_employment_period_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employment_period] ADD CONSTRAINT [FK_employment_period_end_of_employment_id] FOREIGN KEY ([end_of_employment_id]) REFERENCES [sep].[end_of_employment] ([id]);
ALTER TABLE [hr].[employee_history] ADD CONSTRAINT [FK_employee_history_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_history] ADD CONSTRAINT [FK_employee_history_location_id] FOREIGN KEY ([location_id]) REFERENCES [org].[location] ([id]);
ALTER TABLE [hr].[employee_history] ADD CONSTRAINT [FK_employee_history_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [hr].[employee_history] ADD CONSTRAINT [FK_employee_history_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [hr].[employee_history] ADD CONSTRAINT [FK_employee_history_designation_id] FOREIGN KEY ([designation_id]) REFERENCES [org].[designation] ([id]);
ALTER TABLE [hr].[employee_history] ADD CONSTRAINT [FK_employee_history_job_title_id] FOREIGN KEY ([job_title_id]) REFERENCES [org].[job_title] ([id]);
ALTER TABLE [hr].[employee_history] ADD CONSTRAINT [FK_employee_history_grade_id] FOREIGN KEY ([grade_id]) REFERENCES [org].[grade] ([id]);
ALTER TABLE [hr].[employee_history] ADD CONSTRAINT [FK_employee_history_job_level_id] FOREIGN KEY ([job_level_id]) REFERENCES [org].[job_level] ([id]);
ALTER TABLE [hr].[employee_history] ADD CONSTRAINT [FK_employee_history_line_manager_id] FOREIGN KEY ([line_manager_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_history] ADD CONSTRAINT [FK_employee_history_final_authority_id] FOREIGN KEY ([final_authority_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_history] ADD CONSTRAINT [FK_employee_history_source_request_id] FOREIGN KEY ([source_request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [hr].[employee_salary] ADD CONSTRAINT [FK_employee_salary_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_salary] ADD CONSTRAINT [FK_employee_salary_source_request_id] FOREIGN KEY ([source_request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [hr].[employee_pay_item] ADD CONSTRAINT [FK_employee_pay_item_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_pay_item] ADD CONSTRAINT [FK_employee_pay_item_pay_item_id] FOREIGN KEY ([pay_item_id]) REFERENCES [pay].[pay_item] ([id]);
ALTER TABLE [hr].[employee_bank_account] ADD CONSTRAINT [FK_employee_bank_account_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_document] ADD CONSTRAINT [FK_employee_document_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_document] ADD CONSTRAINT [FK_employee_document_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [hr].[employee_experience] ADD CONSTRAINT [FK_employee_experience_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_agreement] ADD CONSTRAINT [FK_employee_agreement_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_agreement] ADD CONSTRAINT [FK_employee_agreement_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [hr].[employee_emergency_contact] ADD CONSTRAINT [FK_employee_emergency_contact_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_dependent] ADD CONSTRAINT [FK_employee_dependent_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_skill] ADD CONSTRAINT [FK_employee_skill_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_education] ADD CONSTRAINT [FK_employee_education_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_education] ADD CONSTRAINT [FK_employee_education_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [hr].[employee_contract] ADD CONSTRAINT [FK_employee_contract_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_contract] ADD CONSTRAINT [FK_employee_contract_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [hr].[employee_change_request] ADD CONSTRAINT [FK_employee_change_request_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [hr].[employee_change_request] ADD CONSTRAINT [FK_employee_change_request_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [hr].[employee_change_request] ADD CONSTRAINT [FK_employee_change_request_decided_by_user_id] FOREIGN KEY ([decided_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [auth].[user_account] ADD CONSTRAINT [FK_user_account_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [auth].[user_account] ADD CONSTRAINT [FK_user_account_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [auth].[role] ADD CONSTRAINT [FK_role_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [auth].[role_permission] ADD CONSTRAINT [FK_role_permission_role_id] FOREIGN KEY ([role_id]) REFERENCES [auth].[role] ([id]);
ALTER TABLE [auth].[role_permission] ADD CONSTRAINT [FK_role_permission_permission_id] FOREIGN KEY ([permission_id]) REFERENCES [auth].[permission] ([id]);
ALTER TABLE [auth].[role_permission_unit] ADD CONSTRAINT [FK_role_permission_unit_role_id] FOREIGN KEY ([role_id]) REFERENCES [auth].[role] ([id]);
ALTER TABLE [auth].[role_permission_unit] ADD CONSTRAINT [FK_role_permission_unit_permission_id] FOREIGN KEY ([permission_id]) REFERENCES [auth].[permission] ([id]);
ALTER TABLE [auth].[role_default_offer] ADD CONSTRAINT [FK_role_default_offer_role_id] FOREIGN KEY ([role_id]) REFERENCES [auth].[role] ([id]);
ALTER TABLE [auth].[role_default_offer] ADD CONSTRAINT [FK_role_default_offer_permission_id] FOREIGN KEY ([permission_id]) REFERENCES [auth].[permission] ([id]);
ALTER TABLE [auth].[user_role] ADD CONSTRAINT [FK_user_role_user_account_id] FOREIGN KEY ([user_account_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [auth].[user_role] ADD CONSTRAINT [FK_user_role_role_id] FOREIGN KEY ([role_id]) REFERENCES [auth].[role] ([id]);
ALTER TABLE [auth].[user_permission_override] ADD CONSTRAINT [FK_user_permission_override_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [auth].[user_permission_override] ADD CONSTRAINT [FK_user_permission_override_user_account_id] FOREIGN KEY ([user_account_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [auth].[user_permission_override] ADD CONSTRAINT [FK_user_permission_override_permission_id] FOREIGN KEY ([permission_id]) REFERENCES [auth].[permission] ([id]);
ALTER TABLE [auth].[user_company] ADD CONSTRAINT [FK_user_company_user_account_id] FOREIGN KEY ([user_account_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [auth].[user_company] ADD CONSTRAINT [FK_user_company_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [auth].[user_session] ADD CONSTRAINT [FK_user_session_user_account_id] FOREIGN KEY ([user_account_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [auth].[user_session] ADD CONSTRAINT [FK_user_session_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sch].[time_slot] ADD CONSTRAINT [FK_time_slot_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sch].[break_type] ADD CONSTRAINT [FK_break_type_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sch].[time_slot_break] ADD CONSTRAINT [FK_time_slot_break_time_slot_id] FOREIGN KEY ([time_slot_id]) REFERENCES [sch].[time_slot] ([id]);
ALTER TABLE [sch].[time_slot_break] ADD CONSTRAINT [FK_time_slot_break_break_type_id] FOREIGN KEY ([break_type_id]) REFERENCES [sch].[break_type] ([id]);
ALTER TABLE [sch].[roster_group] ADD CONSTRAINT [FK_roster_group_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sch].[roster_group_day] ADD CONSTRAINT [FK_roster_group_day_roster_group_id] FOREIGN KEY ([roster_group_id]) REFERENCES [sch].[roster_group] ([id]);
ALTER TABLE [sch].[roster_group_day] ADD CONSTRAINT [FK_roster_group_day_time_slot_id] FOREIGN KEY ([time_slot_id]) REFERENCES [sch].[time_slot] ([id]);
ALTER TABLE [sch].[roster_group_member] ADD CONSTRAINT [FK_roster_group_member_roster_group_id] FOREIGN KEY ([roster_group_id]) REFERENCES [sch].[roster_group] ([id]);
ALTER TABLE [sch].[roster_group_member] ADD CONSTRAINT [FK_roster_group_member_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sch].[schedule_batch] ADD CONSTRAINT [FK_schedule_batch_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sch].[schedule_batch] ADD CONSTRAINT [FK_schedule_batch_time_slot_id] FOREIGN KEY ([time_slot_id]) REFERENCES [sch].[time_slot] ([id]);
ALTER TABLE [sch].[schedule_batch] ADD CONSTRAINT [FK_schedule_batch_roster_group_id] FOREIGN KEY ([roster_group_id]) REFERENCES [sch].[roster_group] ([id]);
ALTER TABLE [sch].[schedule_batch] ADD CONSTRAINT [FK_schedule_batch_geo_fence_id] FOREIGN KEY ([geo_fence_id]) REFERENCES [att].[geo_fence] ([id]);
ALTER TABLE [sch].[schedule] ADD CONSTRAINT [FK_schedule_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sch].[schedule] ADD CONSTRAINT [FK_schedule_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sch].[schedule] ADD CONSTRAINT [FK_schedule_time_slot_id] FOREIGN KEY ([time_slot_id]) REFERENCES [sch].[time_slot] ([id]);
ALTER TABLE [sch].[schedule] ADD CONSTRAINT [FK_schedule_schedule_batch_id] FOREIGN KEY ([schedule_batch_id]) REFERENCES [sch].[schedule_batch] ([id]);
ALTER TABLE [sch].[schedule] ADD CONSTRAINT [FK_schedule_geo_fence_id] FOREIGN KEY ([geo_fence_id]) REFERENCES [att].[geo_fence] ([id]);
ALTER TABLE [sch].[schedule_break] ADD CONSTRAINT [FK_schedule_break_schedule_id] FOREIGN KEY ([schedule_id]) REFERENCES [sch].[schedule] ([id]);
ALTER TABLE [sch].[schedule_break] ADD CONSTRAINT [FK_schedule_break_break_type_id] FOREIGN KEY ([break_type_id]) REFERENCES [sch].[break_type] ([id]);
ALTER TABLE [sch].[rest_day_rule] ADD CONSTRAINT [FK_rest_day_rule_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sch].[rest_day_rule_employee] ADD CONSTRAINT [FK_rest_day_rule_employee_rest_day_rule_id] FOREIGN KEY ([rest_day_rule_id]) REFERENCES [sch].[rest_day_rule] ([id]);
ALTER TABLE [sch].[rest_day_rule_employee] ADD CONSTRAINT [FK_rest_day_rule_employee_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sch].[rest_day] ADD CONSTRAINT [FK_rest_day_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sch].[rest_day] ADD CONSTRAINT [FK_rest_day_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sch].[rest_day] ADD CONSTRAINT [FK_rest_day_rest_day_rule_id] FOREIGN KEY ([rest_day_rule_id]) REFERENCES [sch].[rest_day_rule] ([id]);
ALTER TABLE [sch].[rest_day] ADD CONSTRAINT [FK_rest_day_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [sch].[holiday] ADD CONSTRAINT [FK_holiday_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sch].[holiday_rule] ADD CONSTRAINT [FK_holiday_rule_holiday_id] FOREIGN KEY ([holiday_id]) REFERENCES [sch].[holiday] ([id]);
ALTER TABLE [sch].[holiday_rule] ADD CONSTRAINT [FK_holiday_rule_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sch].[holiday_rule] ADD CONSTRAINT [FK_holiday_rule_location_id] FOREIGN KEY ([location_id]) REFERENCES [org].[location] ([id]);
ALTER TABLE [sch].[holiday_rule] ADD CONSTRAINT [FK_holiday_rule_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [sch].[holiday_rule] ADD CONSTRAINT [FK_holiday_rule_country_id] FOREIGN KEY ([country_id]) REFERENCES [org].[country] ([id]);
ALTER TABLE [sch].[holiday_rule] ADD CONSTRAINT [FK_holiday_rule_state_id] FOREIGN KEY ([state_id]) REFERENCES [org].[state] ([id]);
ALTER TABLE [sch].[holiday_rule] ADD CONSTRAINT [FK_holiday_rule_city_id] FOREIGN KEY ([city_id]) REFERENCES [org].[city] ([id]);
ALTER TABLE [att].[device] ADD CONSTRAINT [FK_device_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [att].[device] ADD CONSTRAINT [FK_device_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [att].[device_enrolment] ADD CONSTRAINT [FK_device_enrolment_device_id] FOREIGN KEY ([device_id]) REFERENCES [att].[device] ([id]);
ALTER TABLE [att].[device_enrolment] ADD CONSTRAINT [FK_device_enrolment_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [att].[geo_fence] ADD CONSTRAINT [FK_geo_fence_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [att].[geo_fence_target] ADD CONSTRAINT [FK_geo_fence_target_geo_fence_id] FOREIGN KEY ([geo_fence_id]) REFERENCES [att].[geo_fence] ([id]);
ALTER TABLE [att].[ip_restriction] ADD CONSTRAINT [FK_ip_restriction_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [att].[ip_restriction_target] ADD CONSTRAINT [FK_ip_restriction_target_ip_restriction_id] FOREIGN KEY ([ip_restriction_id]) REFERENCES [att].[ip_restriction] ([id]);
ALTER TABLE [att].[punch] ADD CONSTRAINT [FK_punch_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [att].[punch] ADD CONSTRAINT [FK_punch_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [att].[punch] ADD CONSTRAINT [FK_punch_break_type_id] FOREIGN KEY ([break_type_id]) REFERENCES [sch].[break_type] ([id]);
ALTER TABLE [att].[punch] ADD CONSTRAINT [FK_punch_device_id] FOREIGN KEY ([device_id]) REFERENCES [att].[device] ([id]);
ALTER TABLE [att].[punch] ADD CONSTRAINT [FK_punch_photo_file_id] FOREIGN KEY ([photo_file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [att].[punch] ADD CONSTRAINT [FK_punch_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [att].[timesheet_day] ADD CONSTRAINT [FK_timesheet_day_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [att].[timesheet_day] ADD CONSTRAINT [FK_timesheet_day_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [att].[timesheet_day] ADD CONSTRAINT [FK_timesheet_day_schedule_id] FOREIGN KEY ([schedule_id]) REFERENCES [sch].[schedule] ([id]);
ALTER TABLE [att].[timesheet_day] ADD CONSTRAINT [FK_timesheet_day_leave_request_id] FOREIGN KEY ([leave_request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [att].[timesheet_flag] ADD CONSTRAINT [FK_timesheet_flag_timesheet_day_id] FOREIGN KEY ([timesheet_day_id]) REFERENCES [att].[timesheet_day] ([id]);
ALTER TABLE [att].[timesheet_break] ADD CONSTRAINT [FK_timesheet_break_timesheet_day_id] FOREIGN KEY ([timesheet_day_id]) REFERENCES [att].[timesheet_day] ([id]);
ALTER TABLE [att].[timesheet_break] ADD CONSTRAINT [FK_timesheet_break_break_type_id] FOREIGN KEY ([break_type_id]) REFERENCES [sch].[break_type] ([id]);
ALTER TABLE [att].[overtime_policy] ADD CONSTRAINT [FK_overtime_policy_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [att].[overtime_policy_slab] ADD CONSTRAINT [FK_overtime_policy_slab_overtime_policy_id] FOREIGN KEY ([overtime_policy_id]) REFERENCES [att].[overtime_policy] ([id]);
ALTER TABLE [att].[overtime_policy_slab] ADD CONSTRAINT [FK_overtime_policy_slab_leave_type_id] FOREIGN KEY ([leave_type_id]) REFERENCES [lv].[leave_type] ([id]);
ALTER TABLE [lv].[leave_type] ADD CONSTRAINT [FK_leave_type_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [lv].[leave_type_experience_slab] ADD CONSTRAINT [FK_leave_type_experience_slab_leave_type_id] FOREIGN KEY ([leave_type_id]) REFERENCES [lv].[leave_type] ([id]);
ALTER TABLE [lv].[leave_type_short_slab] ADD CONSTRAINT [FK_leave_type_short_slab_leave_type_id] FOREIGN KEY ([leave_type_id]) REFERENCES [lv].[leave_type] ([id]);
ALTER TABLE [lv].[leave_policy] ADD CONSTRAINT [FK_leave_policy_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [lv].[leave_policy_type] ADD CONSTRAINT [FK_leave_policy_type_leave_policy_id] FOREIGN KEY ([leave_policy_id]) REFERENCES [lv].[leave_policy] ([id]);
ALTER TABLE [lv].[leave_policy_type] ADD CONSTRAINT [FK_leave_policy_type_leave_type_id] FOREIGN KEY ([leave_type_id]) REFERENCES [lv].[leave_type] ([id]);
ALTER TABLE [lv].[leave_policy_employee] ADD CONSTRAINT [FK_leave_policy_employee_leave_policy_id] FOREIGN KEY ([leave_policy_id]) REFERENCES [lv].[leave_policy] ([id]);
ALTER TABLE [lv].[leave_policy_employee] ADD CONSTRAINT [FK_leave_policy_employee_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [lv].[leave_ledger] ADD CONSTRAINT [FK_leave_ledger_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [lv].[leave_ledger] ADD CONSTRAINT [FK_leave_ledger_leave_type_id] FOREIGN KEY ([leave_type_id]) REFERENCES [lv].[leave_type] ([id]);
ALTER TABLE [lv].[leave_ledger] ADD CONSTRAINT [FK_leave_ledger_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [lv].[leave_ledger] ADD CONSTRAINT [FK_leave_ledger_leave_encashment_id] FOREIGN KEY ([leave_encashment_id]) REFERENCES [lv].[leave_encashment] ([id]);
ALTER TABLE [lv].[leave_ledger] ADD CONSTRAINT [FK_leave_ledger_warning_id] FOREIGN KEY ([warning_id]) REFERENCES [att].[warning] ([id]);
ALTER TABLE [lv].[leave_encashment] ADD CONSTRAINT [FK_leave_encashment_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [lv].[leave_encashment] ADD CONSTRAINT [FK_leave_encashment_leave_type_id] FOREIGN KEY ([leave_type_id]) REFERENCES [lv].[leave_type] ([id]);
ALTER TABLE [lv].[leave_encashment_employee] ADD CONSTRAINT [FK_leave_encashment_employee_leave_encashment_id] FOREIGN KEY ([leave_encashment_id]) REFERENCES [lv].[leave_encashment] ([id]);
ALTER TABLE [lv].[leave_encashment_employee] ADD CONSTRAINT [FK_leave_encashment_employee_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [lv].[leave_encashment_employee] ADD CONSTRAINT [FK_leave_encashment_employee_payslip_id] FOREIGN KEY ([payslip_id]) REFERENCES [pay].[payslip] ([id]);
ALTER TABLE [req].[request] ADD CONSTRAINT [FK_request_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [req].[request] ADD CONSTRAINT [FK_request_request_type_id] FOREIGN KEY ([request_type_id]) REFERENCES [req].[request_type] ([id]);
ALTER TABLE [req].[request] ADD CONSTRAINT [FK_request_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [req].[request] ADD CONSTRAINT [FK_request_created_by_user_id] FOREIGN KEY ([created_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [req].[request] ADD CONSTRAINT [FK_request_approval_flow_id] FOREIGN KEY ([approval_flow_id]) REFERENCES [req].[approval_flow] ([id]);
ALTER TABLE [req].[request] ADD CONSTRAINT [FK_request_current_node_id] FOREIGN KEY ([current_node_id]) REFERENCES [req].[approval_node] ([id]);
ALTER TABLE [req].[request_day] ADD CONSTRAINT [FK_request_day_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[request_day] ADD CONSTRAINT [FK_request_day_schedule_id] FOREIGN KEY ([schedule_id]) REFERENCES [sch].[schedule] ([id]);
ALTER TABLE [req].[req_leave] ADD CONSTRAINT [FK_req_leave_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_leave] ADD CONSTRAINT [FK_req_leave_leave_type_id] FOREIGN KEY ([leave_type_id]) REFERENCES [lv].[leave_type] ([id]);
ALTER TABLE [req].[req_punch] ADD CONSTRAINT [FK_req_punch_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_time_window] ADD CONSTRAINT [FK_req_time_window_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_time_window] ADD CONSTRAINT [FK_req_time_window_time_slot_id] FOREIGN KEY ([time_slot_id]) REFERENCES [sch].[time_slot] ([id]);
ALTER TABLE [req].[req_rest_day] ADD CONSTRAINT [FK_req_rest_day_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_rest_day] ADD CONSTRAINT [FK_req_rest_day_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [req].[req_rest_day] ADD CONSTRAINT [FK_req_rest_day_roster_group_id] FOREIGN KEY ([roster_group_id]) REFERENCES [sch].[roster_group] ([id]);
ALTER TABLE [req].[req_overtime] ADD CONSTRAINT [FK_req_overtime_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_overtime] ADD CONSTRAINT [FK_req_overtime_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [req].[req_overtime] ADD CONSTRAINT [FK_req_overtime_location_id] FOREIGN KEY ([location_id]) REFERENCES [org].[location] ([id]);
ALTER TABLE [req].[req_overtime] ADD CONSTRAINT [FK_req_overtime_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [req].[req_overtime] ADD CONSTRAINT [FK_req_overtime_bulk_id] FOREIGN KEY ([bulk_id]) REFERENCES [req].[request_bulk] ([id]);
ALTER TABLE [req].[req_overtime] ADD CONSTRAINT [FK_req_overtime_overtime_policy_id] FOREIGN KEY ([overtime_policy_id]) REFERENCES [att].[overtime_policy] ([id]);
ALTER TABLE [req].[req_overtime] ADD CONSTRAINT [FK_req_overtime_encashment_leave_type_id] FOREIGN KEY ([encashment_leave_type_id]) REFERENCES [lv].[leave_type] ([id]);
ALTER TABLE [req].[request_bulk] ADD CONSTRAINT [FK_request_bulk_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [req].[request_bulk] ADD CONSTRAINT [FK_request_bulk_request_type_id] FOREIGN KEY ([request_type_id]) REFERENCES [req].[request_type] ([id]);
ALTER TABLE [req].[req_loan] ADD CONSTRAINT [FK_req_loan_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_loan] ADD CONSTRAINT [FK_req_loan_loan_type_id] FOREIGN KEY ([loan_type_id]) REFERENCES [loan].[loan_type] ([id]);
ALTER TABLE [req].[req_loan] ADD CONSTRAINT [FK_req_loan_loan_category_id] FOREIGN KEY ([loan_category_id]) REFERENCES [loan].[loan_category] ([id]);
ALTER TABLE [req].[req_travel] ADD CONSTRAINT [FK_req_travel_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_promotion] ADD CONSTRAINT [FK_req_promotion_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_promotion] ADD CONSTRAINT [FK_req_promotion_grade_id] FOREIGN KEY ([grade_id]) REFERENCES [org].[grade] ([id]);
ALTER TABLE [req].[req_promotion] ADD CONSTRAINT [FK_req_promotion_job_level_id] FOREIGN KEY ([job_level_id]) REFERENCES [org].[job_level] ([id]);
ALTER TABLE [req].[req_promotion] ADD CONSTRAINT [FK_req_promotion_designation_id] FOREIGN KEY ([designation_id]) REFERENCES [org].[designation] ([id]);
ALTER TABLE [req].[req_promotion] ADD CONSTRAINT [FK_req_promotion_job_title_id] FOREIGN KEY ([job_title_id]) REFERENCES [org].[job_title] ([id]);
ALTER TABLE [req].[req_transfer] ADD CONSTRAINT [FK_req_transfer_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_transfer] ADD CONSTRAINT [FK_req_transfer_location_id] FOREIGN KEY ([location_id]) REFERENCES [org].[location] ([id]);
ALTER TABLE [req].[req_transfer] ADD CONSTRAINT [FK_req_transfer_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [req].[req_transfer] ADD CONSTRAINT [FK_req_transfer_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [req].[req_transfer] ADD CONSTRAINT [FK_req_transfer_line_manager_id] FOREIGN KEY ([line_manager_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [req].[req_transfer] ADD CONSTRAINT [FK_req_transfer_final_authority_id] FOREIGN KEY ([final_authority_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [req].[req_resignation] ADD CONSTRAINT [FK_req_resignation_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_shift_swap] ADD CONSTRAINT [FK_req_shift_swap_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_shift_swap] ADD CONSTRAINT [FK_req_shift_swap_from_schedule_id] FOREIGN KEY ([from_schedule_id]) REFERENCES [sch].[schedule] ([id]);
ALTER TABLE [req].[req_shift_swap] ADD CONSTRAINT [FK_req_shift_swap_time_slot_id] FOREIGN KEY ([time_slot_id]) REFERENCES [sch].[time_slot] ([id]);
ALTER TABLE [req].[req_shift_swap] ADD CONSTRAINT [FK_req_shift_swap_with_employee_id] FOREIGN KEY ([with_employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [req].[req_shift_swap] ADD CONSTRAINT [FK_req_shift_swap_to_schedule_id] FOREIGN KEY ([to_schedule_id]) REFERENCES [sch].[schedule] ([id]);
ALTER TABLE [req].[loan_guarantor] ADD CONSTRAINT [FK_loan_guarantor_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[loan_guarantor] ADD CONSTRAINT [FK_loan_guarantor_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [req].[travel_advance] ADD CONSTRAINT [FK_travel_advance_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[travel_leg] ADD CONSTRAINT [FK_travel_leg_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[travel_stay] ADD CONSTRAINT [FK_travel_stay_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[travel_ticket] ADD CONSTRAINT [FK_travel_ticket_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[travel_ticket] ADD CONSTRAINT [FK_travel_ticket_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [req].[req_promotion_benefit] ADD CONSTRAINT [FK_req_promotion_benefit_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_promotion_benefit] ADD CONSTRAINT [FK_req_promotion_benefit_pay_item_id] FOREIGN KEY ([pay_item_id]) REFERENCES [pay].[pay_item] ([id]);
ALTER TABLE [req].[req_expense] ADD CONSTRAINT [FK_req_expense_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[expense_line] ADD CONSTRAINT [FK_expense_line_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[expense_line] ADD CONSTRAINT [FK_expense_line_expense_category_id] FOREIGN KEY ([expense_category_id]) REFERENCES [req].[expense_category] ([id]);
ALTER TABLE [req].[expense_line] ADD CONSTRAINT [FK_expense_line_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [req].[expense_line] ADD CONSTRAINT [FK_expense_line_opening_balance_id] FOREIGN KEY ([opening_balance_id]) REFERENCES [pay].[opening_balance] ([id]);
ALTER TABLE [req].[req_air_ticket] ADD CONSTRAINT [FK_req_air_ticket_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[req_air_ticket] ADD CONSTRAINT [FK_req_air_ticket_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [req].[req_air_ticket] ADD CONSTRAINT [FK_req_air_ticket_opening_balance_id] FOREIGN KEY ([opening_balance_id]) REFERENCES [pay].[opening_balance] ([id]);
ALTER TABLE [req].[req_requisition] ADD CONSTRAINT [FK_req_requisition_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[requisition_line] ADD CONSTRAINT [FK_requisition_line_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[expense_category] ADD CONSTRAINT [FK_expense_category_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [req].[expense_category] ADD CONSTRAINT [FK_expense_category_pay_item_id] FOREIGN KEY ([pay_item_id]) REFERENCES [pay].[pay_item] ([id]);
ALTER TABLE [req].[reimbursement_setting] ADD CONSTRAINT [FK_reimbursement_setting_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [req].[reimbursement_setting] ADD CONSTRAINT [FK_reimbursement_setting_expense_pay_item_id] FOREIGN KEY ([expense_pay_item_id]) REFERENCES [pay].[pay_item] ([id]);
ALTER TABLE [req].[reimbursement_setting] ADD CONSTRAINT [FK_reimbursement_setting_air_ticket_pay_item_id] FOREIGN KEY ([air_ticket_pay_item_id]) REFERENCES [pay].[pay_item] ([id]);
ALTER TABLE [req].[approval_flow] ADD CONSTRAINT [FK_approval_flow_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [req].[approval_flow] ADD CONSTRAINT [FK_approval_flow_request_type_id] FOREIGN KEY ([request_type_id]) REFERENCES [req].[request_type] ([id]);
ALTER TABLE [req].[approval_node] ADD CONSTRAINT [FK_approval_node_approval_flow_id] FOREIGN KEY ([approval_flow_id]) REFERENCES [req].[approval_flow] ([id]);
ALTER TABLE [req].[approval_node] ADD CONSTRAINT [FK_approval_node_approver_employee_id] FOREIGN KEY ([approver_employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [req].[approval_node] ADD CONSTRAINT [FK_approval_node_role_id] FOREIGN KEY ([role_id]) REFERENCES [auth].[role] ([id]);
ALTER TABLE [req].[approval_node] ADD CONSTRAINT [FK_approval_node_next_node_id] FOREIGN KEY ([next_node_id]) REFERENCES [req].[approval_node] ([id]);
ALTER TABLE [req].[approval_node] ADD CONSTRAINT [FK_approval_node_true_node_id] FOREIGN KEY ([true_node_id]) REFERENCES [req].[approval_node] ([id]);
ALTER TABLE [req].[approval_node] ADD CONSTRAINT [FK_approval_node_false_node_id] FOREIGN KEY ([false_node_id]) REFERENCES [req].[approval_node] ([id]);
ALTER TABLE [req].[approval_authority] ADD CONSTRAINT [FK_approval_authority_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [req].[approval_authority] ADD CONSTRAINT [FK_approval_authority_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [req].[approval_authority] ADD CONSTRAINT [FK_approval_authority_request_type_id] FOREIGN KEY ([request_type_id]) REFERENCES [req].[request_type] ([id]);
ALTER TABLE [req].[approval_authority] ADD CONSTRAINT [FK_approval_authority_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [req].[approval_authority] ADD CONSTRAINT [FK_approval_authority_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [req].[delegation] ADD CONSTRAINT [FK_delegation_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [req].[delegation] ADD CONSTRAINT [FK_delegation_delegator_id] FOREIGN KEY ([delegator_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [req].[delegation] ADD CONSTRAINT [FK_delegation_delegatee_id] FOREIGN KEY ([delegatee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [req].[delegation] ADD CONSTRAINT [FK_delegation_request_type_id] FOREIGN KEY ([request_type_id]) REFERENCES [req].[request_type] ([id]);
ALTER TABLE [req].[request_restriction] ADD CONSTRAINT [FK_request_restriction_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [req].[request_restriction] ADD CONSTRAINT [FK_request_restriction_request_type_id] FOREIGN KEY ([request_type_id]) REFERENCES [req].[request_type] ([id]);
ALTER TABLE [req].[request_step] ADD CONSTRAINT [FK_request_step_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [req].[request_step] ADD CONSTRAINT [FK_request_step_approval_node_id] FOREIGN KEY ([approval_node_id]) REFERENCES [req].[approval_node] ([id]);
ALTER TABLE [req].[request_step] ADD CONSTRAINT [FK_request_step_approver_id] FOREIGN KEY ([approver_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [req].[request_step] ADD CONSTRAINT [FK_request_step_approver_role_id] FOREIGN KEY ([approver_role_id]) REFERENCES [auth].[role] ([id]);
ALTER TABLE [req].[request_step] ADD CONSTRAINT [FK_request_step_acted_by_id] FOREIGN KEY ([acted_by_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [loan].[loan_type] ADD CONSTRAINT [FK_loan_type_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [loan].[loan_type] ADD CONSTRAINT [FK_loan_type_formula_id] FOREIGN KEY ([formula_id]) REFERENCES [pay].[formula] ([id]);
ALTER TABLE [loan].[loan_type] ADD CONSTRAINT [FK_loan_type_deduction_pay_item_id] FOREIGN KEY ([deduction_pay_item_id]) REFERENCES [pay].[pay_item] ([id]);
ALTER TABLE [loan].[loan_type_employment_type] ADD CONSTRAINT [FK_loan_type_employment_type_loan_type_id] FOREIGN KEY ([loan_type_id]) REFERENCES [loan].[loan_type] ([id]);
ALTER TABLE [loan].[loan_type_employment_type] ADD CONSTRAINT [FK_loan_type_employment_type_employment_type_id] FOREIGN KEY ([employment_type_id]) REFERENCES [org].[employment_type] ([id]);
ALTER TABLE [loan].[loan_category] ADD CONSTRAINT [FK_loan_category_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [loan].[loan] ADD CONSTRAINT [FK_loan_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [loan].[loan] ADD CONSTRAINT [FK_loan_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [loan].[loan] ADD CONSTRAINT [FK_loan_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [loan].[loan] ADD CONSTRAINT [FK_loan_loan_type_id] FOREIGN KEY ([loan_type_id]) REFERENCES [loan].[loan_type] ([id]);
ALTER TABLE [loan].[loan] ADD CONSTRAINT [FK_loan_loan_category_id] FOREIGN KEY ([loan_category_id]) REFERENCES [loan].[loan_category] ([id]);
ALTER TABLE [loan].[loan_installment] ADD CONSTRAINT [FK_loan_installment_loan_id] FOREIGN KEY ([loan_id]) REFERENCES [loan].[loan] ([id]);
ALTER TABLE [loan].[loan_installment] ADD CONSTRAINT [FK_loan_installment_payslip_id] FOREIGN KEY ([payslip_id]) REFERENCES [pay].[payslip] ([id]);
ALTER TABLE [pay].[tax_structure] ADD CONSTRAINT [FK_tax_structure_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pay].[tax_slab] ADD CONSTRAINT [FK_tax_slab_tax_structure_id] FOREIGN KEY ([tax_structure_id]) REFERENCES [pay].[tax_structure] ([id]);
ALTER TABLE [pay].[tax_rebate] ADD CONSTRAINT [FK_tax_rebate_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pay].[tax_rebate] ADD CONSTRAINT [FK_tax_rebate_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [pay].[formula] ADD CONSTRAINT [FK_formula_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pay].[pay_item] ADD CONSTRAINT [FK_pay_item_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pay].[pay_item] ADD CONSTRAINT [FK_pay_item_employee_formula_id] FOREIGN KEY ([employee_formula_id]) REFERENCES [pay].[formula] ([id]);
ALTER TABLE [pay].[pay_item] ADD CONSTRAINT [FK_pay_item_employer_formula_id] FOREIGN KEY ([employer_formula_id]) REFERENCES [pay].[formula] ([id]);
ALTER TABLE [pay].[pay_rule] ADD CONSTRAINT [FK_pay_rule_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pay].[pay_rule] ADD CONSTRAINT [FK_pay_rule_account_type_id] FOREIGN KEY ([account_type_id]) REFERENCES [pay].[account_type] ([id]);
ALTER TABLE [pay].[account_type] ADD CONSTRAINT [FK_account_type_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pay].[reward_benefit] ADD CONSTRAINT [FK_reward_benefit_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pay].[reward_benefit] ADD CONSTRAINT [FK_reward_benefit_pay_item_id] FOREIGN KEY ([pay_item_id]) REFERENCES [pay].[pay_item] ([id]);
ALTER TABLE [pay].[reward_benefit] ADD CONSTRAINT [FK_reward_benefit_formula_id] FOREIGN KEY ([formula_id]) REFERENCES [pay].[formula] ([id]);
ALTER TABLE [pay].[reward_benefit_member] ADD CONSTRAINT [FK_reward_benefit_member_reward_benefit_id] FOREIGN KEY ([reward_benefit_id]) REFERENCES [pay].[reward_benefit] ([id]);
ALTER TABLE [pay].[reward_benefit_member] ADD CONSTRAINT [FK_reward_benefit_member_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pay].[reward_benefit_member] ADD CONSTRAINT [FK_reward_benefit_member_employee_group_id] FOREIGN KEY ([employee_group_id]) REFERENCES [org].[employee_group] ([id]);
ALTER TABLE [pay].[reward_benefit_field] ADD CONSTRAINT [FK_reward_benefit_field_reward_benefit_id] FOREIGN KEY ([reward_benefit_id]) REFERENCES [pay].[reward_benefit] ([id]);
ALTER TABLE [pay].[sales_incentive] ADD CONSTRAINT [FK_sales_incentive_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pay].[sales_incentive] ADD CONSTRAINT [FK_sales_incentive_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [pay].[disbursement_bank] ADD CONSTRAINT [FK_disbursement_bank_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pay].[payroll] ADD CONSTRAINT [FK_payroll_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pay].[payroll] ADD CONSTRAINT [FK_payroll_time_slot_id] FOREIGN KEY ([time_slot_id]) REFERENCES [sch].[time_slot] ([id]);
ALTER TABLE [pay].[payroll] ADD CONSTRAINT [FK_payroll_tax_structure_id] FOREIGN KEY ([tax_structure_id]) REFERENCES [pay].[tax_structure] ([id]);
ALTER TABLE [pay].[payroll] ADD CONSTRAINT [FK_payroll_disbursement_bank_id] FOREIGN KEY ([disbursement_bank_id]) REFERENCES [pay].[disbursement_bank] ([id]);
ALTER TABLE [pay].[payroll] ADD CONSTRAINT [FK_payroll_closed_by_user_id] FOREIGN KEY ([closed_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [pay].[payroll_pay_item] ADD CONSTRAINT [FK_payroll_pay_item_payroll_id] FOREIGN KEY ([payroll_id]) REFERENCES [pay].[payroll] ([id]);
ALTER TABLE [pay].[payroll_pay_item] ADD CONSTRAINT [FK_payroll_pay_item_pay_item_id] FOREIGN KEY ([pay_item_id]) REFERENCES [pay].[pay_item] ([id]);
ALTER TABLE [pay].[payroll_employee] ADD CONSTRAINT [FK_payroll_employee_payroll_id] FOREIGN KEY ([payroll_id]) REFERENCES [pay].[payroll] ([id]);
ALTER TABLE [pay].[payroll_employee] ADD CONSTRAINT [FK_payroll_employee_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pay].[payroll_run_log] ADD CONSTRAINT [FK_payroll_run_log_payroll_id] FOREIGN KEY ([payroll_id]) REFERENCES [pay].[payroll] ([id]);
ALTER TABLE [pay].[payroll_run_log] ADD CONSTRAINT [FK_payroll_run_log_run_by_user_id] FOREIGN KEY ([run_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [pay].[payroll_run_error] ADD CONSTRAINT [FK_payroll_run_error_payroll_run_log_id] FOREIGN KEY ([payroll_run_log_id]) REFERENCES [pay].[payroll_run_log] ([id]);
ALTER TABLE [pay].[payroll_run_error] ADD CONSTRAINT [FK_payroll_run_error_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pay].[payslip] ADD CONSTRAINT [FK_payslip_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pay].[payslip] ADD CONSTRAINT [FK_payslip_payroll_id] FOREIGN KEY ([payroll_id]) REFERENCES [pay].[payroll] ([id]);
ALTER TABLE [pay].[payslip] ADD CONSTRAINT [FK_payslip_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pay].[payslip_line] ADD CONSTRAINT [FK_payslip_line_payslip_id] FOREIGN KEY ([payslip_id]) REFERENCES [pay].[payslip] ([id]);
ALTER TABLE [pay].[payslip_line] ADD CONSTRAINT [FK_payslip_line_pay_item_id] FOREIGN KEY ([pay_item_id]) REFERENCES [pay].[pay_item] ([id]);
ALTER TABLE [pay].[opening_balance] ADD CONSTRAINT [FK_opening_balance_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pay].[opening_balance] ADD CONSTRAINT [FK_opening_balance_pay_item_id] FOREIGN KEY ([pay_item_id]) REFERENCES [pay].[pay_item] ([id]);
ALTER TABLE [pay].[employee_account_entry] ADD CONSTRAINT [FK_employee_account_entry_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pay].[employee_account_entry] ADD CONSTRAINT [FK_employee_account_entry_account_type_id] FOREIGN KEY ([account_type_id]) REFERENCES [pay].[account_type] ([id]);
ALTER TABLE [pay].[employee_account_entry] ADD CONSTRAINT [FK_employee_account_entry_payslip_id] FOREIGN KEY ([payslip_id]) REFERENCES [pay].[payslip] ([id]);
ALTER TABLE [pay].[employee_account_entry] ADD CONSTRAINT [FK_employee_account_entry_pay_rule_id] FOREIGN KEY ([pay_rule_id]) REFERENCES [pay].[pay_rule] ([id]);
ALTER TABLE [pay].[voucher] ADD CONSTRAINT [FK_voucher_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pay].[voucher] ADD CONSTRAINT [FK_voucher_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pay].[voucher] ADD CONSTRAINT [FK_voucher_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [pay].[voucher] ADD CONSTRAINT [FK_voucher_payroll_id] FOREIGN KEY ([payroll_id]) REFERENCES [pay].[payroll] ([id]);
ALTER TABLE [pay].[voucher] ADD CONSTRAINT [FK_voucher_requested_by_id] FOREIGN KEY ([requested_by_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pay].[voucher] ADD CONSTRAINT [FK_voucher_approved_by_id] FOREIGN KEY ([approved_by_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pay].[voucher] ADD CONSTRAINT [FK_voucher_decided_by_user_id] FOREIGN KEY ([decided_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [pay].[voucher] ADD CONSTRAINT [FK_voucher_verified_by_id] FOREIGN KEY ([verified_by_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pay].[voucher] ADD CONSTRAINT [FK_voucher_verified_by_user_id] FOREIGN KEY ([verified_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [pay].[payroll_close_email] ADD CONSTRAINT [FK_payroll_close_email_payroll_id] FOREIGN KEY ([payroll_id]) REFERENCES [pay].[payroll] ([id]);
ALTER TABLE [pay].[mail_outbox] ADD CONSTRAINT [FK_mail_outbox_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pay].[mail_outbox] ADD CONSTRAINT [FK_mail_outbox_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sep].[asset_type] ADD CONSTRAINT [FK_asset_type_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sep].[asset] ADD CONSTRAINT [FK_asset_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sep].[asset] ADD CONSTRAINT [FK_asset_asset_type_id] FOREIGN KEY ([asset_type_id]) REFERENCES [sep].[asset_type] ([id]);
ALTER TABLE [sep].[asset] ADD CONSTRAINT [FK_asset_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [sep].[asset_allocation] ADD CONSTRAINT [FK_asset_allocation_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sep].[asset_allocation] ADD CONSTRAINT [FK_asset_allocation_asset_id] FOREIGN KEY ([asset_id]) REFERENCES [sep].[asset] ([id]);
ALTER TABLE [sep].[asset_allocation] ADD CONSTRAINT [FK_asset_allocation_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sep].[asset_allocation] ADD CONSTRAINT [FK_asset_allocation_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [sep].[asset_allocation] ADD CONSTRAINT [FK_asset_allocation_asset_clearance_id] FOREIGN KEY ([asset_clearance_id]) REFERENCES [sep].[asset_clearance] ([id]);
ALTER TABLE [sep].[end_of_employment] ADD CONSTRAINT [FK_end_of_employment_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sep].[end_of_employment] ADD CONSTRAINT [FK_end_of_employment_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sep].[end_of_employment] ADD CONSTRAINT [FK_end_of_employment_resignation_request_id] FOREIGN KEY ([resignation_request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [sep].[end_of_employment] ADD CONSTRAINT [FK_end_of_employment_replacement_id] FOREIGN KEY ([replacement_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sep].[end_of_employment] ADD CONSTRAINT [FK_end_of_employment_delegatee_id] FOREIGN KEY ([delegatee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sep].[end_of_employment] ADD CONSTRAINT [FK_end_of_employment_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [sep].[asset_clearance] ADD CONSTRAINT [FK_asset_clearance_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sep].[asset_clearance] ADD CONSTRAINT [FK_asset_clearance_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sep].[asset_clearance] ADD CONSTRAINT [FK_asset_clearance_end_of_employment_id] FOREIGN KEY ([end_of_employment_id]) REFERENCES [sep].[end_of_employment] ([id]);
ALTER TABLE [sep].[asset_clearance] ADD CONSTRAINT [FK_asset_clearance_checked_by_id] FOREIGN KEY ([checked_by_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sep].[asset_clearance] ADD CONSTRAINT [FK_asset_clearance_approved_by_id] FOREIGN KEY ([approved_by_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [sep].[asset_clearance] ADD CONSTRAINT [FK_asset_clearance_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [sep].[asset_clearance_item] ADD CONSTRAINT [FK_asset_clearance_item_asset_clearance_id] FOREIGN KEY ([asset_clearance_id]) REFERENCES [sep].[asset_clearance] ([id]);
ALTER TABLE [sep].[asset_clearance_item] ADD CONSTRAINT [FK_asset_clearance_item_asset_allocation_id] FOREIGN KEY ([asset_allocation_id]) REFERENCES [sep].[asset_allocation] ([id]);
ALTER TABLE [sep].[final_settlement] ADD CONSTRAINT [FK_final_settlement_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sep].[final_settlement] ADD CONSTRAINT [FK_final_settlement_end_of_employment_id] FOREIGN KEY ([end_of_employment_id]) REFERENCES [sep].[end_of_employment] ([id]);
ALTER TABLE [sep].[final_settlement] ADD CONSTRAINT [FK_final_settlement_payslip_id] FOREIGN KEY ([payslip_id]) REFERENCES [pay].[payslip] ([id]);
ALTER TABLE [sep].[final_settlement] ADD CONSTRAINT [FK_final_settlement_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [sep].[offboarding_checklist] ADD CONSTRAINT [FK_offboarding_checklist_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [sep].[checklist_field] ADD CONSTRAINT [FK_checklist_field_offboarding_checklist_id] FOREIGN KEY ([offboarding_checklist_id]) REFERENCES [sep].[offboarding_checklist] ([id]);
ALTER TABLE [sep].[checklist_answer] ADD CONSTRAINT [FK_checklist_answer_end_of_employment_id] FOREIGN KEY ([end_of_employment_id]) REFERENCES [sep].[end_of_employment] ([id]);
ALTER TABLE [sep].[checklist_answer] ADD CONSTRAINT [FK_checklist_answer_checklist_field_id] FOREIGN KEY ([checklist_field_id]) REFERENCES [sep].[checklist_field] ([id]);
ALTER TABLE [rec].[job_opening] ADD CONSTRAINT [FK_job_opening_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [rec].[job_opening] ADD CONSTRAINT [FK_job_opening_open_position_id] FOREIGN KEY ([open_position_id]) REFERENCES [mp].[open_position] ([id]);
ALTER TABLE [rec].[job_opening] ADD CONSTRAINT [FK_job_opening_job_title_id] FOREIGN KEY ([job_title_id]) REFERENCES [org].[job_title] ([id]);
ALTER TABLE [rec].[job_opening] ADD CONSTRAINT [FK_job_opening_designation_id] FOREIGN KEY ([designation_id]) REFERENCES [org].[designation] ([id]);
ALTER TABLE [rec].[job_opening] ADD CONSTRAINT [FK_job_opening_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [rec].[job_opening] ADD CONSTRAINT [FK_job_opening_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [rec].[job_opening] ADD CONSTRAINT [FK_job_opening_employment_type_id] FOREIGN KEY ([employment_type_id]) REFERENCES [org].[employment_type] ([id]);
ALTER TABLE [rec].[job_opening] ADD CONSTRAINT [FK_job_opening_hiring_manager_id] FOREIGN KEY ([hiring_manager_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [rec].[job_opening] ADD CONSTRAINT [FK_job_opening_city_id] FOREIGN KEY ([city_id]) REFERENCES [org].[city] ([id]);
ALTER TABLE [rec].[applicant] ADD CONSTRAINT [FK_applicant_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [rec].[applicant] ADD CONSTRAINT [FK_applicant_city_id] FOREIGN KEY ([city_id]) REFERENCES [org].[city] ([id]);
ALTER TABLE [rec].[applicant] ADD CONSTRAINT [FK_applicant_referred_by_employee_id] FOREIGN KEY ([referred_by_employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [rec].[applicant] ADD CONSTRAINT [FK_applicant_cv_file_id] FOREIGN KEY ([cv_file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [rec].[application] ADD CONSTRAINT [FK_application_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [rec].[application] ADD CONSTRAINT [FK_application_job_opening_id] FOREIGN KEY ([job_opening_id]) REFERENCES [rec].[job_opening] ([id]);
ALTER TABLE [rec].[application] ADD CONSTRAINT [FK_application_applicant_id] FOREIGN KEY ([applicant_id]) REFERENCES [rec].[applicant] ([id]);
ALTER TABLE [rec].[application] ADD CONSTRAINT [FK_application_rejection_reason_id] FOREIGN KEY ([rejection_reason_id]) REFERENCES [rec].[rejection_reason] ([id]);
ALTER TABLE [rec].[application] ADD CONSTRAINT [FK_application_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [rec].[application_stage_history] ADD CONSTRAINT [FK_application_stage_history_application_id] FOREIGN KEY ([application_id]) REFERENCES [rec].[application] ([id]);
ALTER TABLE [rec].[application_stage_history] ADD CONSTRAINT [FK_application_stage_history_changed_by_user_id] FOREIGN KEY ([changed_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [rec].[interview] ADD CONSTRAINT [FK_interview_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [rec].[interview] ADD CONSTRAINT [FK_interview_application_id] FOREIGN KEY ([application_id]) REFERENCES [rec].[application] ([id]);
ALTER TABLE [rec].[interview_interviewer] ADD CONSTRAINT [FK_interview_interviewer_interview_id] FOREIGN KEY ([interview_id]) REFERENCES [rec].[interview] ([id]);
ALTER TABLE [rec].[interview_interviewer] ADD CONSTRAINT [FK_interview_interviewer_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [rec].[interview_evaluation] ADD CONSTRAINT [FK_interview_evaluation_interview_id] FOREIGN KEY ([interview_id]) REFERENCES [rec].[interview] ([id]);
ALTER TABLE [rec].[interview_evaluation] ADD CONSTRAINT [FK_interview_evaluation_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [rec].[interview_evaluation] ADD CONSTRAINT [FK_interview_evaluation_evaluated_by_user_id] FOREIGN KEY ([evaluated_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [rec].[offer] ADD CONSTRAINT [FK_offer_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [rec].[offer] ADD CONSTRAINT [FK_offer_application_id] FOREIGN KEY ([application_id]) REFERENCES [rec].[application] ([id]);
ALTER TABLE [rec].[offer] ADD CONSTRAINT [FK_offer_job_title_id] FOREIGN KEY ([job_title_id]) REFERENCES [org].[job_title] ([id]);
ALTER TABLE [rec].[offer] ADD CONSTRAINT [FK_offer_designation_id] FOREIGN KEY ([designation_id]) REFERENCES [org].[designation] ([id]);
ALTER TABLE [rec].[offer] ADD CONSTRAINT [FK_offer_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [rec].[offer] ADD CONSTRAINT [FK_offer_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [rec].[offer] ADD CONSTRAINT [FK_offer_employment_type_id] FOREIGN KEY ([employment_type_id]) REFERENCES [org].[employment_type] ([id]);
ALTER TABLE [rec].[offer] ADD CONSTRAINT [FK_offer_offer_letter_file_id] FOREIGN KEY ([offer_letter_file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [rec].[rejection_reason] ADD CONSTRAINT [FK_rejection_reason_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [mp].[budget_duration] ADD CONSTRAINT [FK_budget_duration_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [mp].[position] ADD CONSTRAINT [FK_position_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [mp].[position] ADD CONSTRAINT [FK_position_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [mp].[position] ADD CONSTRAINT [FK_position_job_title_id] FOREIGN KEY ([job_title_id]) REFERENCES [org].[job_title] ([id]);
ALTER TABLE [mp].[position] ADD CONSTRAINT [FK_position_employee_group_id] FOREIGN KEY ([employee_group_id]) REFERENCES [org].[employee_group] ([id]);
ALTER TABLE [mp].[position] ADD CONSTRAINT [FK_position_division_id] FOREIGN KEY ([division_id]) REFERENCES [org].[division] ([id]);
ALTER TABLE [mp].[position] ADD CONSTRAINT [FK_position_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [mp].[position] ADD CONSTRAINT [FK_position_sub_department_id] FOREIGN KEY ([sub_department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [mp].[position] ADD CONSTRAINT [FK_position_cost_center_id] FOREIGN KEY ([cost_center_id]) REFERENCES [org].[cost_center] ([id]);
ALTER TABLE [mp].[position] ADD CONSTRAINT [FK_position_grade_id] FOREIGN KEY ([grade_id]) REFERENCES [org].[grade] ([id]);
ALTER TABLE [mp].[position] ADD CONSTRAINT [FK_position_reports_to_id] FOREIGN KEY ([reports_to_id]) REFERENCES [mp].[position] ([id]);
ALTER TABLE [mp].[position] ADD CONSTRAINT [FK_position_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [mp].[position_salary_range] ADD CONSTRAINT [FK_position_salary_range_position_id] FOREIGN KEY ([position_id]) REFERENCES [mp].[position] ([id]);
ALTER TABLE [mp].[manpower_plan] ADD CONSTRAINT [FK_manpower_plan_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [mp].[manpower_plan] ADD CONSTRAINT [FK_manpower_plan_budget_duration_id] FOREIGN KEY ([budget_duration_id]) REFERENCES [mp].[budget_duration] ([id]);
ALTER TABLE [mp].[manpower_plan] ADD CONSTRAINT [FK_manpower_plan_division_id] FOREIGN KEY ([division_id]) REFERENCES [org].[division] ([id]);
ALTER TABLE [mp].[manpower_plan] ADD CONSTRAINT [FK_manpower_plan_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [mp].[manpower_plan] ADD CONSTRAINT [FK_manpower_plan_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [mp].[manpower_plan] ADD CONSTRAINT [FK_manpower_plan_sub_department_id] FOREIGN KEY ([sub_department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [mp].[manpower_plan] ADD CONSTRAINT [FK_manpower_plan_employee_group_id] FOREIGN KEY ([employee_group_id]) REFERENCES [org].[employee_group] ([id]);
ALTER TABLE [mp].[manpower_plan_line] ADD CONSTRAINT [FK_manpower_plan_line_manpower_plan_id] FOREIGN KEY ([manpower_plan_id]) REFERENCES [mp].[manpower_plan] ([id]);
ALTER TABLE [mp].[manpower_plan_line] ADD CONSTRAINT [FK_manpower_plan_line_position_id] FOREIGN KEY ([position_id]) REFERENCES [mp].[position] ([id]);
ALTER TABLE [mp].[manpower_plan_line] ADD CONSTRAINT [FK_manpower_plan_line_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [mp].[manpower_plan_line] ADD CONSTRAINT [FK_manpower_plan_line_e_budget_id] FOREIGN KEY ([e_budget_id]) REFERENCES [mp].[e_budget] ([id]);
ALTER TABLE [mp].[e_budget] ADD CONSTRAINT [FK_e_budget_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [mp].[e_budget] ADD CONSTRAINT [FK_e_budget_budget_duration_id] FOREIGN KEY ([budget_duration_id]) REFERENCES [mp].[budget_duration] ([id]);
ALTER TABLE [mp].[e_budget] ADD CONSTRAINT [FK_e_budget_manpower_plan_id] FOREIGN KEY ([manpower_plan_id]) REFERENCES [mp].[manpower_plan] ([id]);
ALTER TABLE [mp].[e_budget] ADD CONSTRAINT [FK_e_budget_job_title_id] FOREIGN KEY ([job_title_id]) REFERENCES [org].[job_title] ([id]);
ALTER TABLE [mp].[e_budget] ADD CONSTRAINT [FK_e_budget_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [mp].[e_budget] ADD CONSTRAINT [FK_e_budget_decided_by_user_id] FOREIGN KEY ([decided_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [mp].[open_position] ADD CONSTRAINT [FK_open_position_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [mp].[open_position] ADD CONSTRAINT [FK_open_position_e_budget_id] FOREIGN KEY ([e_budget_id]) REFERENCES [mp].[e_budget] ([id]);
ALTER TABLE [mp].[open_position] ADD CONSTRAINT [FK_open_position_manpower_plan_line_id] FOREIGN KEY ([manpower_plan_line_id]) REFERENCES [mp].[manpower_plan_line] ([id]);
ALTER TABLE [mp].[open_position] ADD CONSTRAINT [FK_open_position_position_id] FOREIGN KEY ([position_id]) REFERENCES [mp].[position] ([id]);
ALTER TABLE [mp].[open_position] ADD CONSTRAINT [FK_open_position_job_title_id] FOREIGN KEY ([job_title_id]) REFERENCES [org].[job_title] ([id]);
ALTER TABLE [mp].[open_position] ADD CONSTRAINT [FK_open_position_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [mp].[open_position] ADD CONSTRAINT [FK_open_position_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [mp].[open_position] ADD CONSTRAINT [FK_open_position_jd_file_id] FOREIGN KEY ([jd_file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [core].[stored_file] ADD CONSTRAINT [FK_stored_file_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [core].[stored_file] ADD CONSTRAINT [FK_stored_file_uploaded_by_user_id] FOREIGN KEY ([uploaded_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [core].[attachment] ADD CONSTRAINT [FK_attachment_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [core].[attachment] ADD CONSTRAINT [FK_attachment_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [core].[audit_log] ADD CONSTRAINT [FK_audit_log_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [core].[audit_log] ADD CONSTRAINT [FK_audit_log_performed_by_user_id] FOREIGN KEY ([performed_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [core].[company_setting] ADD CONSTRAINT [FK_company_setting_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [core].[number_sequence] ADD CONSTRAINT [FK_number_sequence_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [core].[filter_preset] ADD CONSTRAINT [FK_filter_preset_user_account_id] FOREIGN KEY ([user_account_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [core].[notification] ADD CONSTRAINT [FK_notification_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [core].[notification] ADD CONSTRAINT [FK_notification_user_account_id] FOREIGN KEY ([user_account_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [core].[webhook] ADD CONSTRAINT [FK_webhook_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [core].[outbox_event] ADD CONSTRAINT [FK_outbox_event_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [core].[webhook_delivery] ADD CONSTRAINT [FK_webhook_delivery_webhook_id] FOREIGN KEY ([webhook_id]) REFERENCES [core].[webhook] ([id]);
ALTER TABLE [core].[webhook_delivery] ADD CONSTRAINT [FK_webhook_delivery_outbox_event_id] FOREIGN KEY ([outbox_event_id]) REFERENCES [core].[outbox_event] ([id]);
ALTER TABLE [eng].[announcement] ADD CONSTRAINT [FK_announcement_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [eng].[announcement] ADD CONSTRAINT [FK_announcement_author_id] FOREIGN KEY ([author_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [eng].[announcement_read] ADD CONSTRAINT [FK_announcement_read_announcement_id] FOREIGN KEY ([announcement_id]) REFERENCES [eng].[announcement] ([id]);
ALTER TABLE [eng].[announcement_read] ADD CONSTRAINT [FK_announcement_read_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [eng].[post] ADD CONSTRAINT [FK_post_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [eng].[post] ADD CONSTRAINT [FK_post_author_id] FOREIGN KEY ([author_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [eng].[post] ADD CONSTRAINT [FK_post_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [eng].[post] ADD CONSTRAINT [FK_post_branch_id] FOREIGN KEY ([branch_id]) REFERENCES [org].[branch] ([id]);
ALTER TABLE [eng].[post] ADD CONSTRAINT [FK_post_pinned_by_user_id] FOREIGN KEY ([pinned_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [eng].[post] ADD CONSTRAINT [FK_post_hidden_by_user_id] FOREIGN KEY ([hidden_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [eng].[post] ADD CONSTRAINT [FK_post_deleted_by_user_id] FOREIGN KEY ([deleted_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [eng].[post_media] ADD CONSTRAINT [FK_post_media_post_id] FOREIGN KEY ([post_id]) REFERENCES [eng].[post] ([id]);
ALTER TABLE [eng].[post_media] ADD CONSTRAINT [FK_post_media_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [eng].[post_reaction] ADD CONSTRAINT [FK_post_reaction_post_id] FOREIGN KEY ([post_id]) REFERENCES [eng].[post] ([id]);
ALTER TABLE [eng].[post_reaction] ADD CONSTRAINT [FK_post_reaction_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [eng].[post_comment] ADD CONSTRAINT [FK_post_comment_post_id] FOREIGN KEY ([post_id]) REFERENCES [eng].[post] ([id]);
ALTER TABLE [eng].[post_comment] ADD CONSTRAINT [FK_post_comment_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [eng].[post_comment] ADD CONSTRAINT [FK_post_comment_parent_id] FOREIGN KEY ([parent_id]) REFERENCES [eng].[post_comment] ([id]);
ALTER TABLE [eng].[post_comment_like] ADD CONSTRAINT [FK_post_comment_like_post_comment_id] FOREIGN KEY ([post_comment_id]) REFERENCES [eng].[post_comment] ([id]);
ALTER TABLE [eng].[post_comment_like] ADD CONSTRAINT [FK_post_comment_like_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [eng].[post_view] ADD CONSTRAINT [FK_post_view_post_id] FOREIGN KEY ([post_id]) REFERENCES [eng].[post] ([id]);
ALTER TABLE [eng].[post_view] ADD CONSTRAINT [FK_post_view_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [eng].[post_mention] ADD CONSTRAINT [FK_post_mention_post_id] FOREIGN KEY ([post_id]) REFERENCES [eng].[post] ([id]);
ALTER TABLE [eng].[post_mention] ADD CONSTRAINT [FK_post_mention_post_comment_id] FOREIGN KEY ([post_comment_id]) REFERENCES [eng].[post_comment] ([id]);
ALTER TABLE [eng].[post_mention] ADD CONSTRAINT [FK_post_mention_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [eng].[survey] ADD CONSTRAINT [FK_survey_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [eng].[survey] ADD CONSTRAINT [FK_survey_published_by_user_id] FOREIGN KEY ([published_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [eng].[survey] ADD CONSTRAINT [FK_survey_closed_by_user_id] FOREIGN KEY ([closed_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [eng].[survey_audience] ADD CONSTRAINT [FK_survey_audience_survey_id] FOREIGN KEY ([survey_id]) REFERENCES [eng].[survey] ([id]);
ALTER TABLE [eng].[survey_question] ADD CONSTRAINT [FK_survey_question_survey_id] FOREIGN KEY ([survey_id]) REFERENCES [eng].[survey] ([id]);
ALTER TABLE [eng].[survey_option] ADD CONSTRAINT [FK_survey_option_survey_question_id] FOREIGN KEY ([survey_question_id]) REFERENCES [eng].[survey_question] ([id]);
ALTER TABLE [eng].[survey_participant] ADD CONSTRAINT [FK_survey_participant_survey_id] FOREIGN KEY ([survey_id]) REFERENCES [eng].[survey] ([id]);
ALTER TABLE [eng].[survey_participant] ADD CONSTRAINT [FK_survey_participant_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [eng].[survey_response] ADD CONSTRAINT [FK_survey_response_survey_id] FOREIGN KEY ([survey_id]) REFERENCES [eng].[survey] ([id]);
ALTER TABLE [eng].[survey_response] ADD CONSTRAINT [FK_survey_response_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [eng].[survey_answer] ADD CONSTRAINT [FK_survey_answer_survey_response_id] FOREIGN KEY ([survey_response_id]) REFERENCES [eng].[survey_response] ([id]);
ALTER TABLE [eng].[survey_answer] ADD CONSTRAINT [FK_survey_answer_survey_question_id] FOREIGN KEY ([survey_question_id]) REFERENCES [eng].[survey_question] ([id]);
ALTER TABLE [eng].[survey_answer] ADD CONSTRAINT [FK_survey_answer_survey_option_id] FOREIGN KEY ([survey_option_id]) REFERENCES [eng].[survey_option] ([id]);
ALTER TABLE [pm].[template_item] ADD CONSTRAINT [FK_template_item_template_id] FOREIGN KEY ([template_id]) REFERENCES [pm].[template] ([id]);
ALTER TABLE [pm].[workspace] ADD CONSTRAINT [FK_workspace_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pm].[workspace] ADD CONSTRAINT [FK_workspace_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [pm].[workspace] ADD CONSTRAINT [FK_workspace_workflow_template_id] FOREIGN KEY ([workflow_template_id]) REFERENCES [pm].[template] ([id]);
ALTER TABLE [pm].[workspace] ADD CONSTRAINT [FK_workspace_status_template_id] FOREIGN KEY ([status_template_id]) REFERENCES [pm].[template] ([id]);
ALTER TABLE [pm].[workspace] ADD CONSTRAINT [FK_workspace_owner_id] FOREIGN KEY ([owner_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[workspace] ADD CONSTRAINT [FK_workspace_cover_file_id] FOREIGN KEY ([cover_file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [pm].[workspace_member] ADD CONSTRAINT [FK_workspace_member_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[workspace_member] ADD CONSTRAINT [FK_workspace_member_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[workspace_status] ADD CONSTRAINT [FK_workspace_status_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[workspace_feature] ADD CONSTRAINT [FK_workspace_feature_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[folder] ADD CONSTRAINT [FK_folder_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[task_list] ADD CONSTRAINT [FK_task_list_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[task_list] ADD CONSTRAINT [FK_task_list_folder_id] FOREIGN KEY ([folder_id]) REFERENCES [pm].[folder] ([id]);
ALTER TABLE [pm].[task_list_member] ADD CONSTRAINT [FK_task_list_member_task_list_id] FOREIGN KEY ([task_list_id]) REFERENCES [pm].[task_list] ([id]);
ALTER TABLE [pm].[task_list_member] ADD CONSTRAINT [FK_task_list_member_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[sprint] ADD CONSTRAINT [FK_sprint_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[task] ADD CONSTRAINT [FK_task_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pm].[task] ADD CONSTRAINT [FK_task_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[task] ADD CONSTRAINT [FK_task_task_list_id] FOREIGN KEY ([task_list_id]) REFERENCES [pm].[task_list] ([id]);
ALTER TABLE [pm].[task] ADD CONSTRAINT [FK_task_parent_task_id] FOREIGN KEY ([parent_task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[task] ADD CONSTRAINT [FK_task_status_id] FOREIGN KEY ([status_id]) REFERENCES [pm].[workspace_status] ([id]);
ALTER TABLE [pm].[task] ADD CONSTRAINT [FK_task_sprint_id] FOREIGN KEY ([sprint_id]) REFERENCES [pm].[sprint] ([id]);
ALTER TABLE [pm].[task] ADD CONSTRAINT [FK_task_cover_file_id] FOREIGN KEY ([cover_file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [pm].[task_assignee] ADD CONSTRAINT [FK_task_assignee_task_id] FOREIGN KEY ([task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[task_assignee] ADD CONSTRAINT [FK_task_assignee_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[task_dependency] ADD CONSTRAINT [FK_task_dependency_task_id] FOREIGN KEY ([task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[task_dependency] ADD CONSTRAINT [FK_task_dependency_other_task_id] FOREIGN KEY ([other_task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[tag] ADD CONSTRAINT [FK_tag_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[task_tag] ADD CONSTRAINT [FK_task_tag_task_id] FOREIGN KEY ([task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[task_tag] ADD CONSTRAINT [FK_task_tag_tag_id] FOREIGN KEY ([tag_id]) REFERENCES [pm].[tag] ([id]);
ALTER TABLE [pm].[checklist_item] ADD CONSTRAINT [FK_checklist_item_task_id] FOREIGN KEY ([task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[time_entry] ADD CONSTRAINT [FK_time_entry_task_id] FOREIGN KEY ([task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[time_entry] ADD CONSTRAINT [FK_time_entry_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[task_comment] ADD CONSTRAINT [FK_task_comment_task_id] FOREIGN KEY ([task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[task_comment] ADD CONSTRAINT [FK_task_comment_author_id] FOREIGN KEY ([author_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[task_comment] ADD CONSTRAINT [FK_task_comment_parent_id] FOREIGN KEY ([parent_id]) REFERENCES [pm].[task_comment] ([id]);
ALTER TABLE [pm].[task_comment] ADD CONSTRAINT [FK_task_comment_assigned_to_id] FOREIGN KEY ([assigned_to_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[task_comment] ADD CONSTRAINT [FK_task_comment_assigned_by_id] FOREIGN KEY ([assigned_by_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[task_comment] ADD CONSTRAINT [FK_task_comment_resolved_by_id] FOREIGN KEY ([resolved_by_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[comment_mention] ADD CONSTRAINT [FK_comment_mention_comment_id] FOREIGN KEY ([comment_id]) REFERENCES [pm].[task_comment] ([id]);
ALTER TABLE [pm].[comment_mention] ADD CONSTRAINT [FK_comment_mention_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[comment_mention] ADD CONSTRAINT [FK_comment_mention_mentioned_task_id] FOREIGN KEY ([mentioned_task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[comment_reaction] ADD CONSTRAINT [FK_comment_reaction_comment_id] FOREIGN KEY ([comment_id]) REFERENCES [pm].[task_comment] ([id]);
ALTER TABLE [pm].[comment_reaction] ADD CONSTRAINT [FK_comment_reaction_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[reminder] ADD CONSTRAINT [FK_reminder_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[reminder] ADD CONSTRAINT [FK_reminder_owner_id] FOREIGN KEY ([owner_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[reminder] ADD CONSTRAINT [FK_reminder_assignee_id] FOREIGN KEY ([assignee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[task_extension] ADD CONSTRAINT [FK_task_extension_task_id] FOREIGN KEY ([task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[task_extension] ADD CONSTRAINT [FK_task_extension_requested_by_id] FOREIGN KEY ([requested_by_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[task_extension] ADD CONSTRAINT [FK_task_extension_decided_by_id] FOREIGN KEY ([decided_by_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[task_extension] ADD CONSTRAINT [FK_task_extension_request_id] FOREIGN KEY ([request_id]) REFERENCES [req].[request] ([id]);
ALTER TABLE [pm].[custom_field] ADD CONSTRAINT [FK_custom_field_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[column_permission] ADD CONSTRAINT [FK_column_permission_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[column_permission] ADD CONSTRAINT [FK_column_permission_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[task_field_value] ADD CONSTRAINT [FK_task_field_value_task_id] FOREIGN KEY ([task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[task_field_value] ADD CONSTRAINT [FK_task_field_value_custom_field_id] FOREIGN KEY ([custom_field_id]) REFERENCES [pm].[custom_field] ([id]);
ALTER TABLE [pm].[list_view] ADD CONSTRAINT [FK_list_view_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[list_view] ADD CONSTRAINT [FK_list_view_task_list_id] FOREIGN KEY ([task_list_id]) REFERENCES [pm].[task_list] ([id]);
ALTER TABLE [pm].[list_view] ADD CONSTRAINT [FK_list_view_owner_id] FOREIGN KEY ([owner_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[share_link] ADD CONSTRAINT [FK_share_link_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[share_member] ADD CONSTRAINT [FK_share_member_share_link_id] FOREIGN KEY ([share_link_id]) REFERENCES [pm].[share_link] ([id]);
ALTER TABLE [pm].[share_member] ADD CONSTRAINT [FK_share_member_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[share_access] ADD CONSTRAINT [FK_share_access_share_link_id] FOREIGN KEY ([share_link_id]) REFERENCES [pm].[share_link] ([id]);
ALTER TABLE [pm].[favorite] ADD CONSTRAINT [FK_favorite_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[workspace_overdue_setting] ADD CONSTRAINT [FK_workspace_overdue_setting_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[task_external_file] ADD CONSTRAINT [FK_task_external_file_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pm].[task_external_file] ADD CONSTRAINT [FK_task_external_file_task_id] FOREIGN KEY ([task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[doc] ADD CONSTRAINT [FK_doc_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pm].[doc] ADD CONSTRAINT [FK_doc_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id]);
ALTER TABLE [pm].[doc] ADD CONSTRAINT [FK_doc_folder_id] FOREIGN KEY ([folder_id]) REFERENCES [pm].[folder] ([id]);
ALTER TABLE [pm].[doc] ADD CONSTRAINT [FK_doc_task_list_id] FOREIGN KEY ([task_list_id]) REFERENCES [pm].[task_list] ([id]);
ALTER TABLE [pm].[doc] ADD CONSTRAINT [FK_doc_owner_id] FOREIGN KEY ([owner_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[doc] ADD CONSTRAINT [FK_doc_cover_file_id] FOREIGN KEY ([cover_file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [pm].[doc_contributor] ADD CONSTRAINT [FK_doc_contributor_doc_id] FOREIGN KEY ([doc_id]) REFERENCES [pm].[doc] ([id]);
ALTER TABLE [pm].[doc_contributor] ADD CONSTRAINT [FK_doc_contributor_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[doc_task] ADD CONSTRAINT [FK_doc_task_doc_id] FOREIGN KEY ([doc_id]) REFERENCES [pm].[doc] ([id]);
ALTER TABLE [pm].[doc_task] ADD CONSTRAINT [FK_doc_task_task_id] FOREIGN KEY ([task_id]) REFERENCES [pm].[task] ([id]);
ALTER TABLE [pm].[doc_comment] ADD CONSTRAINT [FK_doc_comment_doc_id] FOREIGN KEY ([doc_id]) REFERENCES [pm].[doc] ([id]);
ALTER TABLE [pm].[doc_comment] ADD CONSTRAINT [FK_doc_comment_author_id] FOREIGN KEY ([author_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [pm].[doc_comment] ADD CONSTRAINT [FK_doc_comment_parent_id] FOREIGN KEY ([parent_id]) REFERENCES [pm].[doc_comment] ([id]);
ALTER TABLE [pm].[note] ADD CONSTRAINT [FK_note_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pm].[note] ADD CONSTRAINT [FK_note_user_account_id] FOREIGN KEY ([user_account_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [pm].[note_version] ADD CONSTRAINT [FK_note_version_note_id] FOREIGN KEY ([note_id]) REFERENCES [pm].[note] ([id]);
ALTER TABLE [pm].[note_version] ADD CONSTRAINT [FK_note_version_edited_by_user_id] FOREIGN KEY ([edited_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [pm].[personal_item] ADD CONSTRAINT [FK_personal_item_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pm].[personal_item] ADD CONSTRAINT [FK_personal_item_user_account_id] FOREIGN KEY ([user_account_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [pm].[recent_item] ADD CONSTRAINT [FK_recent_item_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [pm].[recent_item] ADD CONSTRAINT [FK_recent_item_user_account_id] FOREIGN KEY ([user_account_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [att].[warning_policy] ADD CONSTRAINT [FK_warning_policy_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [att].[warning_policy_rule] ADD CONSTRAINT [FK_warning_policy_rule_warning_policy_id] FOREIGN KEY ([warning_policy_id]) REFERENCES [att].[warning_policy] ([id]);
ALTER TABLE [att].[penalty_rule] ADD CONSTRAINT [FK_penalty_rule_warning_policy_id] FOREIGN KEY ([warning_policy_id]) REFERENCES [att].[warning_policy] ([id]);
ALTER TABLE [att].[penalty_rule] ADD CONSTRAINT [FK_penalty_rule_leave_type_id] FOREIGN KEY ([leave_type_id]) REFERENCES [lv].[leave_type] ([id]);
ALTER TABLE [att].[warning] ADD CONSTRAINT [FK_warning_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [att].[warning] ADD CONSTRAINT [FK_warning_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [att].[warning] ADD CONSTRAINT [FK_warning_warning_policy_id] FOREIGN KEY ([warning_policy_id]) REFERENCES [att].[warning_policy] ([id]);
ALTER TABLE [att].[warning] ADD CONSTRAINT [FK_warning_warning_policy_rule_id] FOREIGN KEY ([warning_policy_rule_id]) REFERENCES [att].[warning_policy_rule] ([id]);
ALTER TABLE [att].[warning] ADD CONSTRAINT [FK_warning_timesheet_day_id] FOREIGN KEY ([timesheet_day_id]) REFERENCES [att].[timesheet_day] ([id]);
ALTER TABLE [att].[warning] ADD CONSTRAINT [FK_warning_penalty_rule_id] FOREIGN KEY ([penalty_rule_id]) REFERENCES [att].[penalty_rule] ([id]);
ALTER TABLE [att].[warning] ADD CONSTRAINT [FK_warning_payslip_id] FOREIGN KEY ([payslip_id]) REFERENCES [pay].[payslip] ([id]);
ALTER TABLE [ben].[plan_year] ADD CONSTRAINT [FK_plan_year_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [ben].[benefit_plan] ADD CONSTRAINT [FK_benefit_plan_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [ben].[plan_year_plan] ADD CONSTRAINT [FK_plan_year_plan_plan_year_id] FOREIGN KEY ([plan_year_id]) REFERENCES [ben].[plan_year] ([id]);
ALTER TABLE [ben].[plan_year_plan] ADD CONSTRAINT [FK_plan_year_plan_benefit_plan_id] FOREIGN KEY ([benefit_plan_id]) REFERENCES [ben].[benefit_plan] ([id]);
ALTER TABLE [ben].[enrollment_window] ADD CONSTRAINT [FK_enrollment_window_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [ben].[enrollment_window] ADD CONSTRAINT [FK_enrollment_window_plan_year_id] FOREIGN KEY ([plan_year_id]) REFERENCES [ben].[plan_year] ([id]);
ALTER TABLE [ben].[enrollment_window_plan] ADD CONSTRAINT [FK_enrollment_window_plan_enrollment_window_id] FOREIGN KEY ([enrollment_window_id]) REFERENCES [ben].[enrollment_window] ([id]);
ALTER TABLE [ben].[enrollment_window_plan] ADD CONSTRAINT [FK_enrollment_window_plan_benefit_plan_id] FOREIGN KEY ([benefit_plan_id]) REFERENCES [ben].[benefit_plan] ([id]);
ALTER TABLE [ben].[enrollment_window_employee] ADD CONSTRAINT [FK_enrollment_window_employee_enrollment_window_id] FOREIGN KEY ([enrollment_window_id]) REFERENCES [ben].[enrollment_window] ([id]);
ALTER TABLE [ben].[enrollment_window_employee] ADD CONSTRAINT [FK_enrollment_window_employee_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [ben].[election] ADD CONSTRAINT [FK_election_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [ben].[election] ADD CONSTRAINT [FK_election_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [ben].[election] ADD CONSTRAINT [FK_election_plan_year_id] FOREIGN KEY ([plan_year_id]) REFERENCES [ben].[plan_year] ([id]);
ALTER TABLE [ben].[election] ADD CONSTRAINT [FK_election_enrollment_window_id] FOREIGN KEY ([enrollment_window_id]) REFERENCES [ben].[enrollment_window] ([id]);
ALTER TABLE [ben].[election] ADD CONSTRAINT [FK_election_decided_by_user_id] FOREIGN KEY ([decided_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [ben].[election_plan] ADD CONSTRAINT [FK_election_plan_election_id] FOREIGN KEY ([election_id]) REFERENCES [ben].[election] ([id]);
ALTER TABLE [ben].[election_plan] ADD CONSTRAINT [FK_election_plan_benefit_plan_id] FOREIGN KEY ([benefit_plan_id]) REFERENCES [ben].[benefit_plan] ([id]);
ALTER TABLE [ben].[health_benefit] ADD CONSTRAINT [FK_health_benefit_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [ben].[health_benefit] ADD CONSTRAINT [FK_health_benefit_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [ben].[health_benefit] ADD CONSTRAINT [FK_health_benefit_document_file_id] FOREIGN KEY ([document_file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [ben].[perk] ADD CONSTRAINT [FK_perk_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [ben].[perk] ADD CONSTRAINT [FK_perk_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [perf].[rating_scale] ADD CONSTRAINT [FK_rating_scale_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [perf].[rating_scale_level] ADD CONSTRAINT [FK_rating_scale_level_rating_scale_id] FOREIGN KEY ([rating_scale_id]) REFERENCES [perf].[rating_scale] ([id]);
ALTER TABLE [perf].[kpi] ADD CONSTRAINT [FK_kpi_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [perf].[kpi] ADD CONSTRAINT [FK_kpi_department_id] FOREIGN KEY ([department_id]) REFERENCES [org].[department] ([id]);
ALTER TABLE [perf].[kpi] ADD CONSTRAINT [FK_kpi_job_title_id] FOREIGN KEY ([job_title_id]) REFERENCES [org].[job_title] ([id]);
ALTER TABLE [perf].[appraisal_form] ADD CONSTRAINT [FK_appraisal_form_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [perf].[appraisal_form] ADD CONSTRAINT [FK_appraisal_form_rating_scale_id] FOREIGN KEY ([rating_scale_id]) REFERENCES [perf].[rating_scale] ([id]);
ALTER TABLE [perf].[appraisal_criterion] ADD CONSTRAINT [FK_appraisal_criterion_appraisal_form_id] FOREIGN KEY ([appraisal_form_id]) REFERENCES [perf].[appraisal_form] ([id]);
ALTER TABLE [perf].[appraisal_criterion] ADD CONSTRAINT [FK_appraisal_criterion_kpi_id] FOREIGN KEY ([kpi_id]) REFERENCES [perf].[kpi] ([id]);
ALTER TABLE [perf].[appraisal_cycle] ADD CONSTRAINT [FK_appraisal_cycle_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [perf].[appraisal_cycle] ADD CONSTRAINT [FK_appraisal_cycle_appraisal_form_id] FOREIGN KEY ([appraisal_form_id]) REFERENCES [perf].[appraisal_form] ([id]);
ALTER TABLE [perf].[appraisal] ADD CONSTRAINT [FK_appraisal_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [perf].[appraisal] ADD CONSTRAINT [FK_appraisal_appraisal_cycle_id] FOREIGN KEY ([appraisal_cycle_id]) REFERENCES [perf].[appraisal_cycle] ([id]);
ALTER TABLE [perf].[appraisal] ADD CONSTRAINT [FK_appraisal_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [perf].[appraisal] ADD CONSTRAINT [FK_appraisal_reviewer_employee_id] FOREIGN KEY ([reviewer_employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [perf].[appraisal] ADD CONSTRAINT [FK_appraisal_finalised_by_user_id] FOREIGN KEY ([finalised_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [perf].[appraisal] ADD CONSTRAINT [FK_appraisal_letter_file_id] FOREIGN KEY ([letter_file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [perf].[appraisal_rating] ADD CONSTRAINT [FK_appraisal_rating_appraisal_id] FOREIGN KEY ([appraisal_id]) REFERENCES [perf].[appraisal] ([id]);
ALTER TABLE [perf].[appraisal_rating] ADD CONSTRAINT [FK_appraisal_rating_appraisal_criterion_id] FOREIGN KEY ([appraisal_criterion_id]) REFERENCES [perf].[appraisal_criterion] ([id]);
ALTER TABLE [perf].[goal] ADD CONSTRAINT [FK_goal_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [perf].[goal] ADD CONSTRAINT [FK_goal_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [perf].[goal] ADD CONSTRAINT [FK_goal_appraisal_cycle_id] FOREIGN KEY ([appraisal_cycle_id]) REFERENCES [perf].[appraisal_cycle] ([id]);
ALTER TABLE [perf].[goal] ADD CONSTRAINT [FK_goal_kpi_id] FOREIGN KEY ([kpi_id]) REFERENCES [perf].[kpi] ([id]);
ALTER TABLE [perf].[goal] ADD CONSTRAINT [FK_goal_set_by_user_id] FOREIGN KEY ([set_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [perf].[goal_check_in] ADD CONSTRAINT [FK_goal_check_in_goal_id] FOREIGN KEY ([goal_id]) REFERENCES [perf].[goal] ([id]);
ALTER TABLE [perf].[increment_proposal] ADD CONSTRAINT [FK_increment_proposal_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [perf].[increment_proposal] ADD CONSTRAINT [FK_increment_proposal_appraisal_id] FOREIGN KEY ([appraisal_id]) REFERENCES [perf].[appraisal] ([id]);
ALTER TABLE [perf].[increment_proposal] ADD CONSTRAINT [FK_increment_proposal_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [perf].[increment_proposal] ADD CONSTRAINT [FK_increment_proposal_employee_salary_id] FOREIGN KEY ([employee_salary_id]) REFERENCES [hr].[employee_salary] ([id]);
ALTER TABLE [perf].[increment_proposal] ADD CONSTRAINT [FK_increment_proposal_decided_by_user_id] FOREIGN KEY ([decided_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [trn].[training_category] ADD CONSTRAINT [FK_training_category_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [trn].[training_program] ADD CONSTRAINT [FK_training_program_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [trn].[training_program] ADD CONSTRAINT [FK_training_program_training_category_id] FOREIGN KEY ([training_category_id]) REFERENCES [trn].[training_category] ([id]);
ALTER TABLE [trn].[training_session] ADD CONSTRAINT [FK_training_session_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [trn].[training_session] ADD CONSTRAINT [FK_training_session_training_program_id] FOREIGN KEY ([training_program_id]) REFERENCES [trn].[training_program] ([id]);
ALTER TABLE [trn].[training_session] ADD CONSTRAINT [FK_training_session_trainer_employee_id] FOREIGN KEY ([trainer_employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [trn].[training_enrolment] ADD CONSTRAINT [FK_training_enrolment_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [trn].[training_enrolment] ADD CONSTRAINT [FK_training_enrolment_training_session_id] FOREIGN KEY ([training_session_id]) REFERENCES [trn].[training_session] ([id]);
ALTER TABLE [trn].[training_enrolment] ADD CONSTRAINT [FK_training_enrolment_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [trn].[training_enrolment] ADD CONSTRAINT [FK_training_enrolment_nominated_by_user_id] FOREIGN KEY ([nominated_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [trn].[training_enrolment] ADD CONSTRAINT [FK_training_enrolment_decided_by_user_id] FOREIGN KEY ([decided_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [trn].[training_enrolment] ADD CONSTRAINT [FK_training_enrolment_certificate_file_id] FOREIGN KEY ([certificate_file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [trn].[training_attendance] ADD CONSTRAINT [FK_training_attendance_training_enrolment_id] FOREIGN KEY ([training_enrolment_id]) REFERENCES [trn].[training_enrolment] ([id]);
ALTER TABLE [trn].[training_feedback] ADD CONSTRAINT [FK_training_feedback_training_enrolment_id] FOREIGN KEY ([training_enrolment_id]) REFERENCES [trn].[training_enrolment] ([id]);
ALTER TABLE [frm].[form] ADD CONSTRAINT [FK_form_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [frm].[form] ADD CONSTRAINT [FK_form_published_by_user_id] FOREIGN KEY ([published_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [frm].[form] ADD CONSTRAINT [FK_form_closed_by_user_id] FOREIGN KEY ([closed_by_user_id]) REFERENCES [auth].[user_account] ([id]);
ALTER TABLE [frm].[form_section] ADD CONSTRAINT [FK_form_section_form_id] FOREIGN KEY ([form_id]) REFERENCES [frm].[form] ([id]);
ALTER TABLE [frm].[form_field] ADD CONSTRAINT [FK_form_field_form_id] FOREIGN KEY ([form_id]) REFERENCES [frm].[form] ([id]);
ALTER TABLE [frm].[form_field] ADD CONSTRAINT [FK_form_field_form_section_id] FOREIGN KEY ([form_section_id]) REFERENCES [frm].[form_section] ([id]);
ALTER TABLE [frm].[form_field_option] ADD CONSTRAINT [FK_form_field_option_form_field_id] FOREIGN KEY ([form_field_id]) REFERENCES [frm].[form_field] ([id]);
ALTER TABLE [frm].[form_audience] ADD CONSTRAINT [FK_form_audience_form_id] FOREIGN KEY ([form_id]) REFERENCES [frm].[form] ([id]);
ALTER TABLE [frm].[form_response] ADD CONSTRAINT [FK_form_response_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]);
ALTER TABLE [frm].[form_response] ADD CONSTRAINT [FK_form_response_form_id] FOREIGN KEY ([form_id]) REFERENCES [frm].[form] ([id]);
ALTER TABLE [frm].[form_response] ADD CONSTRAINT [FK_form_response_employee_id] FOREIGN KEY ([employee_id]) REFERENCES [hr].[employee] ([id]);
ALTER TABLE [frm].[form_answer] ADD CONSTRAINT [FK_form_answer_form_response_id] FOREIGN KEY ([form_response_id]) REFERENCES [frm].[form_response] ([id]);
ALTER TABLE [frm].[form_answer] ADD CONSTRAINT [FK_form_answer_form_field_id] FOREIGN KEY ([form_field_id]) REFERENCES [frm].[form_field] ([id]);
ALTER TABLE [frm].[form_answer] ADD CONSTRAINT [FK_form_answer_file_id] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]);
ALTER TABLE [frm].[form_answer_option] ADD CONSTRAINT [FK_form_answer_option_form_answer_id] FOREIGN KEY ([form_answer_id]) REFERENCES [frm].[form_answer] ([id]);
ALTER TABLE [frm].[form_answer_option] ADD CONSTRAINT [FK_form_answer_option_form_field_option_id] FOREIGN KEY ([form_field_option_id]) REFERENCES [frm].[form_field_option] ([id]);
GO

-- Indexes
CREATE NONCLUSTERED INDEX [IX_company_logo_file_id] ON [org].[company] ([logo_file_id]);
CREATE NONCLUSTERED INDEX [IX_company_country_id] ON [org].[company] ([country_id]);
CREATE NONCLUSTERED INDEX [IX_state_country_id] ON [org].[state] ([country_id]);
CREATE NONCLUSTERED INDEX [IX_area_company_id] ON [org].[area] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_branch_location_id] ON [org].[branch] ([location_id]);
CREATE NONCLUSTERED INDEX [IX_branch_area_id] ON [org].[branch] ([area_id]);
CREATE NONCLUSTERED INDEX [IX_branch_manager_id] ON [org].[branch] ([manager_id]);
CREATE NONCLUSTERED INDEX [IX_branch_country_id] ON [org].[branch] ([country_id]);
CREATE NONCLUSTERED INDEX [IX_branch_state_id] ON [org].[branch] ([state_id]);
CREATE NONCLUSTERED INDEX [IX_branch_city_id] ON [org].[branch] ([city_id]);
CREATE NONCLUSTERED INDEX [IX_department_parent_id] ON [org].[department] ([parent_id]);
CREATE NONCLUSTERED INDEX [IX_department_head_id] ON [org].[department] ([head_id]);
CREATE UNIQUE NONCLUSTERED INDEX [UQ_employee_company_id_cnic] ON [hr].[employee] ([company_id], [cnic]) WHERE [cnic] IS NOT NULL;
CREATE NONCLUSTERED INDEX [IX_employee_home_city_id] ON [hr].[employee] ([home_city_id]);
CREATE NONCLUSTERED INDEX [IX_employee_photo_file_id] ON [hr].[employee] ([photo_file_id]);
CREATE NONCLUSTERED INDEX [IX_employee_branch_id] ON [hr].[employee] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_employee_location_id] ON [hr].[employee] ([location_id]);
CREATE NONCLUSTERED INDEX [IX_employee_area_id] ON [hr].[employee] ([area_id]);
CREATE NONCLUSTERED INDEX [IX_employee_department_id] ON [hr].[employee] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_employee_division_id] ON [hr].[employee] ([division_id]);
CREATE NONCLUSTERED INDEX [IX_employee_cost_center_id] ON [hr].[employee] ([cost_center_id]);
CREATE NONCLUSTERED INDEX [IX_employee_designation_id] ON [hr].[employee] ([designation_id]);
CREATE NONCLUSTERED INDEX [IX_employee_job_title_id] ON [hr].[employee] ([job_title_id]);
CREATE NONCLUSTERED INDEX [IX_employee_grade_id] ON [hr].[employee] ([grade_id]);
CREATE NONCLUSTERED INDEX [IX_employee_job_level_id] ON [hr].[employee] ([job_level_id]);
CREATE NONCLUSTERED INDEX [IX_employee_employee_group_id] ON [hr].[employee] ([employee_group_id]);
CREATE NONCLUSTERED INDEX [IX_employee_employment_type_id] ON [hr].[employee] ([employment_type_id]);
CREATE NONCLUSTERED INDEX [IX_employee_line_manager_id] ON [hr].[employee] ([line_manager_id]);
CREATE NONCLUSTERED INDEX [IX_employee_final_authority_id] ON [hr].[employee] ([final_authority_id]);
CREATE NONCLUSTERED INDEX [IX_employee_default_time_slot_id] ON [hr].[employee] ([default_time_slot_id]);
CREATE NONCLUSTERED INDEX [IX_employment_period_employee_id] ON [hr].[employment_period] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employment_period_end_of_employment_id] ON [hr].[employment_period] ([end_of_employment_id]);
CREATE NONCLUSTERED INDEX [IX_employee_history_employee_id] ON [hr].[employee_history] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employee_history_location_id] ON [hr].[employee_history] ([location_id]);
CREATE NONCLUSTERED INDEX [IX_employee_history_branch_id] ON [hr].[employee_history] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_employee_history_department_id] ON [hr].[employee_history] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_employee_history_designation_id] ON [hr].[employee_history] ([designation_id]);
CREATE NONCLUSTERED INDEX [IX_employee_history_job_title_id] ON [hr].[employee_history] ([job_title_id]);
CREATE NONCLUSTERED INDEX [IX_employee_history_grade_id] ON [hr].[employee_history] ([grade_id]);
CREATE NONCLUSTERED INDEX [IX_employee_history_job_level_id] ON [hr].[employee_history] ([job_level_id]);
CREATE NONCLUSTERED INDEX [IX_employee_history_line_manager_id] ON [hr].[employee_history] ([line_manager_id]);
CREATE NONCLUSTERED INDEX [IX_employee_history_final_authority_id] ON [hr].[employee_history] ([final_authority_id]);
CREATE NONCLUSTERED INDEX [IX_employee_history_source_request_id] ON [hr].[employee_history] ([source_request_id]);
CREATE NONCLUSTERED INDEX [IX_employee_salary_employee_id] ON [hr].[employee_salary] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employee_salary_source_request_id] ON [hr].[employee_salary] ([source_request_id]);
CREATE NONCLUSTERED INDEX [IX_employee_pay_item_employee_id] ON [hr].[employee_pay_item] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employee_pay_item_pay_item_id] ON [hr].[employee_pay_item] ([pay_item_id]);
CREATE NONCLUSTERED INDEX [IX_employee_document_employee_id] ON [hr].[employee_document] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employee_document_file_id] ON [hr].[employee_document] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_employee_experience_employee_id] ON [hr].[employee_experience] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employee_agreement_employee_id] ON [hr].[employee_agreement] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employee_agreement_file_id] ON [hr].[employee_agreement] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_employee_emergency_contact_employee_id] ON [hr].[employee_emergency_contact] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employee_dependent_employee_id] ON [hr].[employee_dependent] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employee_education_employee_id] ON [hr].[employee_education] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employee_education_file_id] ON [hr].[employee_education] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_employee_contract_employee_id] ON [hr].[employee_contract] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employee_contract_file_id] ON [hr].[employee_contract] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_employee_change_request_company_id] ON [hr].[employee_change_request] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_employee_change_request_employee_id] ON [hr].[employee_change_request] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employee_change_request_decided_by_user_id] ON [hr].[employee_change_request] ([decided_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_user_account_employee_id] ON [auth].[user_account] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_user_account_company_id] ON [auth].[user_account] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_role_permission_permission_id] ON [auth].[role_permission] ([permission_id]);
CREATE NONCLUSTERED INDEX [IX_role_permission_unit_permission_id] ON [auth].[role_permission_unit] ([permission_id]);
CREATE NONCLUSTERED INDEX [IX_role_default_offer_permission_id] ON [auth].[role_default_offer] ([permission_id]);
CREATE NONCLUSTERED INDEX [IX_user_role_role_id] ON [auth].[user_role] ([role_id]);
CREATE NONCLUSTERED INDEX [IX_user_permission_override_user_account_id] ON [auth].[user_permission_override] ([user_account_id]);
CREATE NONCLUSTERED INDEX [IX_user_permission_override_permission_id] ON [auth].[user_permission_override] ([permission_id]);
CREATE NONCLUSTERED INDEX [IX_user_company_company_id] ON [auth].[user_company] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_user_session_user_account_id] ON [auth].[user_session] ([user_account_id]);
CREATE NONCLUSTERED INDEX [IX_user_session_company_id] ON [auth].[user_session] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_time_slot_break_time_slot_id] ON [sch].[time_slot_break] ([time_slot_id]);
CREATE NONCLUSTERED INDEX [IX_time_slot_break_break_type_id] ON [sch].[time_slot_break] ([break_type_id]);
CREATE NONCLUSTERED INDEX [IX_roster_group_day_time_slot_id] ON [sch].[roster_group_day] ([time_slot_id]);
CREATE NONCLUSTERED INDEX [IX_roster_group_member_roster_group_id] ON [sch].[roster_group_member] ([roster_group_id]);
CREATE NONCLUSTERED INDEX [IX_roster_group_member_employee_id] ON [sch].[roster_group_member] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_schedule_batch_company_id] ON [sch].[schedule_batch] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_schedule_batch_time_slot_id] ON [sch].[schedule_batch] ([time_slot_id]);
CREATE NONCLUSTERED INDEX [IX_schedule_batch_roster_group_id] ON [sch].[schedule_batch] ([roster_group_id]);
CREATE NONCLUSTERED INDEX [IX_schedule_batch_geo_fence_id] ON [sch].[schedule_batch] ([geo_fence_id]);
CREATE NONCLUSTERED INDEX [IX_schedule_company_id] ON [sch].[schedule] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_schedule_time_slot_id] ON [sch].[schedule] ([time_slot_id]);
CREATE NONCLUSTERED INDEX [IX_schedule_schedule_batch_id] ON [sch].[schedule] ([schedule_batch_id]);
CREATE NONCLUSTERED INDEX [IX_schedule_geo_fence_id] ON [sch].[schedule] ([geo_fence_id]);
CREATE NONCLUSTERED INDEX [IX_schedule_break_schedule_id] ON [sch].[schedule_break] ([schedule_id]);
CREATE NONCLUSTERED INDEX [IX_schedule_break_break_type_id] ON [sch].[schedule_break] ([break_type_id]);
CREATE NONCLUSTERED INDEX [IX_rest_day_rule_company_id] ON [sch].[rest_day_rule] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_rest_day_rule_employee_employee_id] ON [sch].[rest_day_rule_employee] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_rest_day_company_id] ON [sch].[rest_day] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_rest_day_rest_day_rule_id] ON [sch].[rest_day] ([rest_day_rule_id]);
CREATE NONCLUSTERED INDEX [IX_rest_day_request_id] ON [sch].[rest_day] ([request_id]);
CREATE NONCLUSTERED INDEX [IX_holiday_rule_holiday_id] ON [sch].[holiday_rule] ([holiday_id]);
CREATE NONCLUSTERED INDEX [IX_holiday_rule_employee_id] ON [sch].[holiday_rule] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_holiday_rule_location_id] ON [sch].[holiday_rule] ([location_id]);
CREATE NONCLUSTERED INDEX [IX_holiday_rule_branch_id] ON [sch].[holiday_rule] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_holiday_rule_country_id] ON [sch].[holiday_rule] ([country_id]);
CREATE NONCLUSTERED INDEX [IX_holiday_rule_state_id] ON [sch].[holiday_rule] ([state_id]);
CREATE NONCLUSTERED INDEX [IX_holiday_rule_city_id] ON [sch].[holiday_rule] ([city_id]);
CREATE NONCLUSTERED INDEX [IX_device_branch_id] ON [att].[device] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_device_enrolment_employee_id] ON [att].[device_enrolment] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_geo_fence_target_geo_fence_id] ON [att].[geo_fence_target] ([geo_fence_id]);
CREATE NONCLUSTERED INDEX [IX_ip_restriction_target_ip_restriction_id] ON [att].[ip_restriction_target] ([ip_restriction_id]);
CREATE NONCLUSTERED INDEX [IX_punch_company_id] ON [att].[punch] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_punch_break_type_id] ON [att].[punch] ([break_type_id]);
CREATE NONCLUSTERED INDEX [IX_punch_device_id] ON [att].[punch] ([device_id]);
CREATE NONCLUSTERED INDEX [IX_punch_photo_file_id] ON [att].[punch] ([photo_file_id]);
CREATE NONCLUSTERED INDEX [IX_punch_request_id] ON [att].[punch] ([request_id]);
CREATE NONCLUSTERED INDEX [IX_timesheet_day_company_id] ON [att].[timesheet_day] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_timesheet_day_schedule_id] ON [att].[timesheet_day] ([schedule_id]);
CREATE NONCLUSTERED INDEX [IX_timesheet_day_leave_request_id] ON [att].[timesheet_day] ([leave_request_id]);
CREATE NONCLUSTERED INDEX [IX_timesheet_flag_timesheet_day_id] ON [att].[timesheet_flag] ([timesheet_day_id]);
CREATE NONCLUSTERED INDEX [IX_timesheet_break_timesheet_day_id] ON [att].[timesheet_break] ([timesheet_day_id]);
CREATE NONCLUSTERED INDEX [IX_timesheet_break_break_type_id] ON [att].[timesheet_break] ([break_type_id]);
CREATE NONCLUSTERED INDEX [IX_overtime_policy_slab_overtime_policy_id] ON [att].[overtime_policy_slab] ([overtime_policy_id]);
CREATE NONCLUSTERED INDEX [IX_overtime_policy_slab_leave_type_id] ON [att].[overtime_policy_slab] ([leave_type_id]);
CREATE UNIQUE NONCLUSTERED INDEX [UQ_leave_type_company_id_short_code] ON [lv].[leave_type] ([company_id], [short_code]) WHERE [short_code] IS NOT NULL;
CREATE NONCLUSTERED INDEX [IX_leave_type_experience_slab_leave_type_id] ON [lv].[leave_type_experience_slab] ([leave_type_id]);
CREATE NONCLUSTERED INDEX [IX_leave_type_short_slab_leave_type_id] ON [lv].[leave_type_short_slab] ([leave_type_id]);
CREATE NONCLUSTERED INDEX [IX_leave_policy_type_leave_type_id] ON [lv].[leave_policy_type] ([leave_type_id]);
CREATE NONCLUSTERED INDEX [IX_leave_policy_employee_employee_id] ON [lv].[leave_policy_employee] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_leave_ledger_employee_id] ON [lv].[leave_ledger] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_leave_ledger_leave_type_id] ON [lv].[leave_ledger] ([leave_type_id]);
CREATE NONCLUSTERED INDEX [IX_leave_ledger_request_id] ON [lv].[leave_ledger] ([request_id]);
CREATE NONCLUSTERED INDEX [IX_leave_ledger_leave_encashment_id] ON [lv].[leave_ledger] ([leave_encashment_id]);
CREATE NONCLUSTERED INDEX [IX_leave_ledger_warning_id] ON [lv].[leave_ledger] ([warning_id]);
CREATE NONCLUSTERED INDEX [IX_leave_encashment_company_id] ON [lv].[leave_encashment] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_leave_encashment_leave_type_id] ON [lv].[leave_encashment] ([leave_type_id]);
CREATE NONCLUSTERED INDEX [IX_leave_encashment_employee_employee_id] ON [lv].[leave_encashment_employee] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_leave_encashment_employee_payslip_id] ON [lv].[leave_encashment_employee] ([payslip_id]);
CREATE NONCLUSTERED INDEX [IX_request_request_type_id] ON [req].[request] ([request_type_id]);
CREATE NONCLUSTERED INDEX [IX_request_employee_id] ON [req].[request] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_request_created_by_user_id] ON [req].[request] ([created_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_request_approval_flow_id] ON [req].[request] ([approval_flow_id]);
CREATE NONCLUSTERED INDEX [IX_request_current_node_id] ON [req].[request] ([current_node_id]);
CREATE NONCLUSTERED INDEX [IX_request_day_schedule_id] ON [req].[request_day] ([schedule_id]);
CREATE NONCLUSTERED INDEX [IX_req_leave_leave_type_id] ON [req].[req_leave] ([leave_type_id]);
CREATE NONCLUSTERED INDEX [IX_req_time_window_time_slot_id] ON [req].[req_time_window] ([time_slot_id]);
CREATE NONCLUSTERED INDEX [IX_req_rest_day_department_id] ON [req].[req_rest_day] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_req_rest_day_roster_group_id] ON [req].[req_rest_day] ([roster_group_id]);
CREATE NONCLUSTERED INDEX [IX_req_overtime_department_id] ON [req].[req_overtime] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_req_overtime_location_id] ON [req].[req_overtime] ([location_id]);
CREATE NONCLUSTERED INDEX [IX_req_overtime_branch_id] ON [req].[req_overtime] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_req_overtime_bulk_id] ON [req].[req_overtime] ([bulk_id]);
CREATE NONCLUSTERED INDEX [IX_req_overtime_overtime_policy_id] ON [req].[req_overtime] ([overtime_policy_id]);
CREATE NONCLUSTERED INDEX [IX_req_overtime_encashment_leave_type_id] ON [req].[req_overtime] ([encashment_leave_type_id]);
CREATE NONCLUSTERED INDEX [IX_request_bulk_company_id] ON [req].[request_bulk] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_request_bulk_request_type_id] ON [req].[request_bulk] ([request_type_id]);
CREATE NONCLUSTERED INDEX [IX_req_loan_loan_type_id] ON [req].[req_loan] ([loan_type_id]);
CREATE NONCLUSTERED INDEX [IX_req_loan_loan_category_id] ON [req].[req_loan] ([loan_category_id]);
CREATE NONCLUSTERED INDEX [IX_req_promotion_grade_id] ON [req].[req_promotion] ([grade_id]);
CREATE NONCLUSTERED INDEX [IX_req_promotion_job_level_id] ON [req].[req_promotion] ([job_level_id]);
CREATE NONCLUSTERED INDEX [IX_req_promotion_designation_id] ON [req].[req_promotion] ([designation_id]);
CREATE NONCLUSTERED INDEX [IX_req_promotion_job_title_id] ON [req].[req_promotion] ([job_title_id]);
CREATE NONCLUSTERED INDEX [IX_req_transfer_location_id] ON [req].[req_transfer] ([location_id]);
CREATE NONCLUSTERED INDEX [IX_req_transfer_branch_id] ON [req].[req_transfer] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_req_transfer_department_id] ON [req].[req_transfer] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_req_transfer_line_manager_id] ON [req].[req_transfer] ([line_manager_id]);
CREATE NONCLUSTERED INDEX [IX_req_transfer_final_authority_id] ON [req].[req_transfer] ([final_authority_id]);
CREATE NONCLUSTERED INDEX [IX_req_shift_swap_from_schedule_id] ON [req].[req_shift_swap] ([from_schedule_id]);
CREATE NONCLUSTERED INDEX [IX_req_shift_swap_time_slot_id] ON [req].[req_shift_swap] ([time_slot_id]);
CREATE NONCLUSTERED INDEX [IX_req_shift_swap_with_employee_id] ON [req].[req_shift_swap] ([with_employee_id]);
CREATE NONCLUSTERED INDEX [IX_req_shift_swap_to_schedule_id] ON [req].[req_shift_swap] ([to_schedule_id]);
CREATE NONCLUSTERED INDEX [IX_loan_guarantor_request_id] ON [req].[loan_guarantor] ([request_id]);
CREATE NONCLUSTERED INDEX [IX_loan_guarantor_file_id] ON [req].[loan_guarantor] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_travel_advance_request_id] ON [req].[travel_advance] ([request_id]);
CREATE NONCLUSTERED INDEX [IX_travel_leg_request_id] ON [req].[travel_leg] ([request_id]);
CREATE NONCLUSTERED INDEX [IX_travel_stay_request_id] ON [req].[travel_stay] ([request_id]);
CREATE NONCLUSTERED INDEX [IX_travel_ticket_request_id] ON [req].[travel_ticket] ([request_id]);
CREATE NONCLUSTERED INDEX [IX_travel_ticket_file_id] ON [req].[travel_ticket] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_req_promotion_benefit_pay_item_id] ON [req].[req_promotion_benefit] ([pay_item_id]);
CREATE NONCLUSTERED INDEX [IX_expense_line_expense_category_id] ON [req].[expense_line] ([expense_category_id]);
CREATE NONCLUSTERED INDEX [IX_expense_line_file_id] ON [req].[expense_line] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_expense_line_opening_balance_id] ON [req].[expense_line] ([opening_balance_id]);
CREATE NONCLUSTERED INDEX [IX_req_air_ticket_file_id] ON [req].[req_air_ticket] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_req_air_ticket_opening_balance_id] ON [req].[req_air_ticket] ([opening_balance_id]);
CREATE NONCLUSTERED INDEX [IX_expense_category_pay_item_id] ON [req].[expense_category] ([pay_item_id]);
CREATE NONCLUSTERED INDEX [IX_reimbursement_setting_expense_pay_item_id] ON [req].[reimbursement_setting] ([expense_pay_item_id]);
CREATE NONCLUSTERED INDEX [IX_reimbursement_setting_air_ticket_pay_item_id] ON [req].[reimbursement_setting] ([air_ticket_pay_item_id]);
CREATE NONCLUSTERED INDEX [IX_approval_flow_company_id] ON [req].[approval_flow] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_approval_flow_request_type_id] ON [req].[approval_flow] ([request_type_id]);
CREATE NONCLUSTERED INDEX [IX_approval_node_approver_employee_id] ON [req].[approval_node] ([approver_employee_id]);
CREATE NONCLUSTERED INDEX [IX_approval_node_role_id] ON [req].[approval_node] ([role_id]);
CREATE NONCLUSTERED INDEX [IX_approval_node_next_node_id] ON [req].[approval_node] ([next_node_id]);
CREATE NONCLUSTERED INDEX [IX_approval_node_true_node_id] ON [req].[approval_node] ([true_node_id]);
CREATE NONCLUSTERED INDEX [IX_approval_node_false_node_id] ON [req].[approval_node] ([false_node_id]);
CREATE NONCLUSTERED INDEX [IX_approval_authority_company_id] ON [req].[approval_authority] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_approval_authority_employee_id] ON [req].[approval_authority] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_approval_authority_request_type_id] ON [req].[approval_authority] ([request_type_id]);
CREATE NONCLUSTERED INDEX [IX_approval_authority_branch_id] ON [req].[approval_authority] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_approval_authority_department_id] ON [req].[approval_authority] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_delegation_company_id] ON [req].[delegation] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_delegation_delegator_id] ON [req].[delegation] ([delegator_id]);
CREATE NONCLUSTERED INDEX [IX_delegation_delegatee_id] ON [req].[delegation] ([delegatee_id]);
CREATE NONCLUSTERED INDEX [IX_delegation_request_type_id] ON [req].[delegation] ([request_type_id]);
CREATE NONCLUSTERED INDEX [IX_request_restriction_company_id] ON [req].[request_restriction] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_request_restriction_request_type_id] ON [req].[request_restriction] ([request_type_id]);
CREATE NONCLUSTERED INDEX [IX_request_step_request_id] ON [req].[request_step] ([request_id]);
CREATE NONCLUSTERED INDEX [IX_request_step_approval_node_id] ON [req].[request_step] ([approval_node_id]);
CREATE NONCLUSTERED INDEX [IX_request_step_approver_id] ON [req].[request_step] ([approver_id]);
CREATE NONCLUSTERED INDEX [IX_request_step_approver_role_id] ON [req].[request_step] ([approver_role_id]);
CREATE NONCLUSTERED INDEX [IX_request_step_acted_by_id] ON [req].[request_step] ([acted_by_id]);
CREATE NONCLUSTERED INDEX [IX_loan_type_formula_id] ON [loan].[loan_type] ([formula_id]);
CREATE NONCLUSTERED INDEX [IX_loan_type_deduction_pay_item_id] ON [loan].[loan_type] ([deduction_pay_item_id]);
CREATE NONCLUSTERED INDEX [IX_loan_type_employment_type_employment_type_id] ON [loan].[loan_type_employment_type] ([employment_type_id]);
CREATE UNIQUE NONCLUSTERED INDEX [UQ_loan_request_id] ON [loan].[loan] ([request_id]) WHERE [request_id] IS NOT NULL;
CREATE NONCLUSTERED INDEX [IX_loan_company_id] ON [loan].[loan] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_loan_employee_id] ON [loan].[loan] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_loan_loan_type_id] ON [loan].[loan] ([loan_type_id]);
CREATE NONCLUSTERED INDEX [IX_loan_loan_category_id] ON [loan].[loan] ([loan_category_id]);
CREATE NONCLUSTERED INDEX [IX_loan_installment_payslip_id] ON [loan].[loan_installment] ([payslip_id]);
CREATE NONCLUSTERED INDEX [IX_tax_slab_tax_structure_id] ON [pay].[tax_slab] ([tax_structure_id]);
CREATE NONCLUSTERED INDEX [IX_tax_rebate_employee_id] ON [pay].[tax_rebate] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_tax_rebate_file_id] ON [pay].[tax_rebate] ([file_id]);
CREATE UNIQUE NONCLUSTERED INDEX [UQ_pay_item_company_id_system_code] ON [pay].[pay_item] ([company_id], [system_code]) WHERE [system_code] IS NOT NULL;
CREATE NONCLUSTERED INDEX [IX_pay_item_employee_formula_id] ON [pay].[pay_item] ([employee_formula_id]);
CREATE NONCLUSTERED INDEX [IX_pay_item_employer_formula_id] ON [pay].[pay_item] ([employer_formula_id]);
CREATE NONCLUSTERED INDEX [IX_pay_rule_account_type_id] ON [pay].[pay_rule] ([account_type_id]);
CREATE NONCLUSTERED INDEX [IX_reward_benefit_pay_item_id] ON [pay].[reward_benefit] ([pay_item_id]);
CREATE NONCLUSTERED INDEX [IX_reward_benefit_formula_id] ON [pay].[reward_benefit] ([formula_id]);
CREATE NONCLUSTERED INDEX [IX_reward_benefit_member_reward_benefit_id] ON [pay].[reward_benefit_member] ([reward_benefit_id]);
CREATE NONCLUSTERED INDEX [IX_reward_benefit_member_employee_id] ON [pay].[reward_benefit_member] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_reward_benefit_member_employee_group_id] ON [pay].[reward_benefit_member] ([employee_group_id]);
CREATE NONCLUSTERED INDEX [IX_reward_benefit_field_reward_benefit_id] ON [pay].[reward_benefit_field] ([reward_benefit_id]);
CREATE NONCLUSTERED INDEX [IX_sales_incentive_company_id] ON [pay].[sales_incentive] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_sales_incentive_branch_id] ON [pay].[sales_incentive] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_payroll_time_slot_id] ON [pay].[payroll] ([time_slot_id]);
CREATE NONCLUSTERED INDEX [IX_payroll_tax_structure_id] ON [pay].[payroll] ([tax_structure_id]);
CREATE NONCLUSTERED INDEX [IX_payroll_disbursement_bank_id] ON [pay].[payroll] ([disbursement_bank_id]);
CREATE NONCLUSTERED INDEX [IX_payroll_closed_by_user_id] ON [pay].[payroll] ([closed_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_payroll_pay_item_pay_item_id] ON [pay].[payroll_pay_item] ([pay_item_id]);
CREATE NONCLUSTERED INDEX [IX_payroll_employee_employee_id] ON [pay].[payroll_employee] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_payroll_run_log_payroll_id] ON [pay].[payroll_run_log] ([payroll_id]);
CREATE NONCLUSTERED INDEX [IX_payroll_run_log_run_by_user_id] ON [pay].[payroll_run_log] ([run_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_payroll_run_error_payroll_run_log_id] ON [pay].[payroll_run_error] ([payroll_run_log_id]);
CREATE NONCLUSTERED INDEX [IX_payroll_run_error_employee_id] ON [pay].[payroll_run_error] ([employee_id]);
CREATE UNIQUE NONCLUSTERED INDEX [UQ_payslip_payroll_id_employee_id] ON [pay].[payslip] ([payroll_id], [employee_id]) WHERE [payroll_id] IS NOT NULL;
CREATE NONCLUSTERED INDEX [IX_payslip_company_id] ON [pay].[payslip] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_payslip_employee_id] ON [pay].[payslip] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_payslip_line_pay_item_id] ON [pay].[payslip_line] ([pay_item_id]);
CREATE NONCLUSTERED INDEX [IX_opening_balance_employee_id] ON [pay].[opening_balance] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_opening_balance_pay_item_id] ON [pay].[opening_balance] ([pay_item_id]);
CREATE NONCLUSTERED INDEX [IX_employee_account_entry_employee_id] ON [pay].[employee_account_entry] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_employee_account_entry_account_type_id] ON [pay].[employee_account_entry] ([account_type_id]);
CREATE NONCLUSTERED INDEX [IX_employee_account_entry_payslip_id] ON [pay].[employee_account_entry] ([payslip_id]);
CREATE NONCLUSTERED INDEX [IX_employee_account_entry_pay_rule_id] ON [pay].[employee_account_entry] ([pay_rule_id]);
CREATE UNIQUE NONCLUSTERED INDEX [UQ_voucher_payroll_id_employee_id] ON [pay].[voucher] ([payroll_id], [employee_id]) WHERE [payroll_id] IS NOT NULL;
CREATE NONCLUSTERED INDEX [IX_voucher_employee_id] ON [pay].[voucher] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_voucher_file_id] ON [pay].[voucher] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_voucher_requested_by_id] ON [pay].[voucher] ([requested_by_id]);
CREATE NONCLUSTERED INDEX [IX_voucher_approved_by_id] ON [pay].[voucher] ([approved_by_id]);
CREATE NONCLUSTERED INDEX [IX_voucher_decided_by_user_id] ON [pay].[voucher] ([decided_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_voucher_verified_by_id] ON [pay].[voucher] ([verified_by_id]);
CREATE NONCLUSTERED INDEX [IX_voucher_verified_by_user_id] ON [pay].[voucher] ([verified_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_mail_outbox_company_id] ON [pay].[mail_outbox] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_mail_outbox_employee_id] ON [pay].[mail_outbox] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_mail_outbox_entity_type_entity_id] ON [pay].[mail_outbox] ([entity_type], [entity_id]);
CREATE UNIQUE NONCLUSTERED INDEX [UQ_asset_company_id_identification_no] ON [sep].[asset] ([company_id], [identification_no]) WHERE [identification_no] IS NOT NULL;
CREATE NONCLUSTERED INDEX [IX_asset_asset_type_id] ON [sep].[asset] ([asset_type_id]);
CREATE NONCLUSTERED INDEX [IX_asset_file_id] ON [sep].[asset] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_asset_allocation_company_id] ON [sep].[asset_allocation] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_asset_allocation_asset_id] ON [sep].[asset_allocation] ([asset_id]);
CREATE NONCLUSTERED INDEX [IX_asset_allocation_employee_id] ON [sep].[asset_allocation] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_asset_allocation_file_id] ON [sep].[asset_allocation] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_asset_allocation_asset_clearance_id] ON [sep].[asset_allocation] ([asset_clearance_id]);
CREATE UNIQUE NONCLUSTERED INDEX [UQ_end_of_employment_resignation_request_id] ON [sep].[end_of_employment] ([resignation_request_id]) WHERE [resignation_request_id] IS NOT NULL;
CREATE NONCLUSTERED INDEX [IX_end_of_employment_company_id] ON [sep].[end_of_employment] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_end_of_employment_employee_id] ON [sep].[end_of_employment] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_end_of_employment_replacement_id] ON [sep].[end_of_employment] ([replacement_id]);
CREATE NONCLUSTERED INDEX [IX_end_of_employment_delegatee_id] ON [sep].[end_of_employment] ([delegatee_id]);
CREATE NONCLUSTERED INDEX [IX_end_of_employment_file_id] ON [sep].[end_of_employment] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_asset_clearance_company_id] ON [sep].[asset_clearance] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_asset_clearance_employee_id] ON [sep].[asset_clearance] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_asset_clearance_end_of_employment_id] ON [sep].[asset_clearance] ([end_of_employment_id]);
CREATE NONCLUSTERED INDEX [IX_asset_clearance_checked_by_id] ON [sep].[asset_clearance] ([checked_by_id]);
CREATE NONCLUSTERED INDEX [IX_asset_clearance_approved_by_id] ON [sep].[asset_clearance] ([approved_by_id]);
CREATE NONCLUSTERED INDEX [IX_asset_clearance_file_id] ON [sep].[asset_clearance] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_asset_clearance_item_asset_allocation_id] ON [sep].[asset_clearance_item] ([asset_allocation_id]);
CREATE NONCLUSTERED INDEX [IX_final_settlement_company_id] ON [sep].[final_settlement] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_final_settlement_payslip_id] ON [sep].[final_settlement] ([payslip_id]);
CREATE NONCLUSTERED INDEX [IX_final_settlement_file_id] ON [sep].[final_settlement] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_checklist_answer_checklist_field_id] ON [sep].[checklist_answer] ([checklist_field_id]);
CREATE NONCLUSTERED INDEX [IX_job_opening_open_position_id] ON [rec].[job_opening] ([open_position_id]);
CREATE NONCLUSTERED INDEX [IX_job_opening_job_title_id] ON [rec].[job_opening] ([job_title_id]);
CREATE NONCLUSTERED INDEX [IX_job_opening_designation_id] ON [rec].[job_opening] ([designation_id]);
CREATE NONCLUSTERED INDEX [IX_job_opening_department_id] ON [rec].[job_opening] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_job_opening_branch_id] ON [rec].[job_opening] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_job_opening_employment_type_id] ON [rec].[job_opening] ([employment_type_id]);
CREATE NONCLUSTERED INDEX [IX_job_opening_hiring_manager_id] ON [rec].[job_opening] ([hiring_manager_id]);
CREATE NONCLUSTERED INDEX [IX_job_opening_city_id] ON [rec].[job_opening] ([city_id]);
CREATE NONCLUSTERED INDEX [IX_applicant_city_id] ON [rec].[applicant] ([city_id]);
CREATE NONCLUSTERED INDEX [IX_applicant_referred_by_employee_id] ON [rec].[applicant] ([referred_by_employee_id]);
CREATE NONCLUSTERED INDEX [IX_applicant_cv_file_id] ON [rec].[applicant] ([cv_file_id]);
CREATE NONCLUSTERED INDEX [IX_application_company_id] ON [rec].[application] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_application_applicant_id] ON [rec].[application] ([applicant_id]);
CREATE NONCLUSTERED INDEX [IX_application_rejection_reason_id] ON [rec].[application] ([rejection_reason_id]);
CREATE NONCLUSTERED INDEX [IX_application_employee_id] ON [rec].[application] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_application_stage_history_application_id] ON [rec].[application_stage_history] ([application_id]);
CREATE NONCLUSTERED INDEX [IX_application_stage_history_changed_by_user_id] ON [rec].[application_stage_history] ([changed_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_interview_company_id] ON [rec].[interview] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_interview_application_id] ON [rec].[interview] ([application_id]);
CREATE NONCLUSTERED INDEX [IX_interview_interviewer_employee_id] ON [rec].[interview_interviewer] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_interview_evaluation_employee_id] ON [rec].[interview_evaluation] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_interview_evaluation_evaluated_by_user_id] ON [rec].[interview_evaluation] ([evaluated_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_offer_company_id] ON [rec].[offer] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_offer_application_id] ON [rec].[offer] ([application_id]);
CREATE NONCLUSTERED INDEX [IX_offer_job_title_id] ON [rec].[offer] ([job_title_id]);
CREATE NONCLUSTERED INDEX [IX_offer_designation_id] ON [rec].[offer] ([designation_id]);
CREATE NONCLUSTERED INDEX [IX_offer_department_id] ON [rec].[offer] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_offer_branch_id] ON [rec].[offer] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_offer_employment_type_id] ON [rec].[offer] ([employment_type_id]);
CREATE NONCLUSTERED INDEX [IX_offer_offer_letter_file_id] ON [rec].[offer] ([offer_letter_file_id]);
CREATE NONCLUSTERED INDEX [IX_position_branch_id] ON [mp].[position] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_position_job_title_id] ON [mp].[position] ([job_title_id]);
CREATE NONCLUSTERED INDEX [IX_position_employee_group_id] ON [mp].[position] ([employee_group_id]);
CREATE NONCLUSTERED INDEX [IX_position_division_id] ON [mp].[position] ([division_id]);
CREATE NONCLUSTERED INDEX [IX_position_department_id] ON [mp].[position] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_position_sub_department_id] ON [mp].[position] ([sub_department_id]);
CREATE NONCLUSTERED INDEX [IX_position_cost_center_id] ON [mp].[position] ([cost_center_id]);
CREATE NONCLUSTERED INDEX [IX_position_grade_id] ON [mp].[position] ([grade_id]);
CREATE NONCLUSTERED INDEX [IX_position_reports_to_id] ON [mp].[position] ([reports_to_id]);
CREATE NONCLUSTERED INDEX [IX_position_employee_id] ON [mp].[position] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_manpower_plan_company_id] ON [mp].[manpower_plan] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_manpower_plan_budget_duration_id] ON [mp].[manpower_plan] ([budget_duration_id]);
CREATE NONCLUSTERED INDEX [IX_manpower_plan_division_id] ON [mp].[manpower_plan] ([division_id]);
CREATE NONCLUSTERED INDEX [IX_manpower_plan_branch_id] ON [mp].[manpower_plan] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_manpower_plan_department_id] ON [mp].[manpower_plan] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_manpower_plan_sub_department_id] ON [mp].[manpower_plan] ([sub_department_id]);
CREATE NONCLUSTERED INDEX [IX_manpower_plan_employee_group_id] ON [mp].[manpower_plan] ([employee_group_id]);
CREATE NONCLUSTERED INDEX [IX_manpower_plan_line_manpower_plan_id] ON [mp].[manpower_plan_line] ([manpower_plan_id]);
CREATE NONCLUSTERED INDEX [IX_manpower_plan_line_position_id] ON [mp].[manpower_plan_line] ([position_id]);
CREATE NONCLUSTERED INDEX [IX_manpower_plan_line_employee_id] ON [mp].[manpower_plan_line] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_manpower_plan_line_e_budget_id] ON [mp].[manpower_plan_line] ([e_budget_id]);
CREATE NONCLUSTERED INDEX [IX_e_budget_company_id] ON [mp].[e_budget] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_e_budget_budget_duration_id] ON [mp].[e_budget] ([budget_duration_id]);
CREATE NONCLUSTERED INDEX [IX_e_budget_manpower_plan_id] ON [mp].[e_budget] ([manpower_plan_id]);
CREATE NONCLUSTERED INDEX [IX_e_budget_job_title_id] ON [mp].[e_budget] ([job_title_id]);
CREATE NONCLUSTERED INDEX [IX_e_budget_department_id] ON [mp].[e_budget] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_e_budget_decided_by_user_id] ON [mp].[e_budget] ([decided_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_open_position_company_id] ON [mp].[open_position] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_open_position_e_budget_id] ON [mp].[open_position] ([e_budget_id]);
CREATE NONCLUSTERED INDEX [IX_open_position_manpower_plan_line_id] ON [mp].[open_position] ([manpower_plan_line_id]);
CREATE NONCLUSTERED INDEX [IX_open_position_position_id] ON [mp].[open_position] ([position_id]);
CREATE NONCLUSTERED INDEX [IX_open_position_job_title_id] ON [mp].[open_position] ([job_title_id]);
CREATE NONCLUSTERED INDEX [IX_open_position_department_id] ON [mp].[open_position] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_open_position_branch_id] ON [mp].[open_position] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_open_position_jd_file_id] ON [mp].[open_position] ([jd_file_id]);
CREATE NONCLUSTERED INDEX [IX_stored_file_company_id] ON [core].[stored_file] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_stored_file_uploaded_by_user_id] ON [core].[stored_file] ([uploaded_by_user_id]);
CREATE UNIQUE NONCLUSTERED INDEX [UQ_attachment_entity_type_entity_id_file_id] ON [core].[attachment] ([entity_type], [entity_id], [file_id]) WHERE [file_id] IS NOT NULL;
CREATE NONCLUSTERED INDEX [IX_attachment_company_id] ON [core].[attachment] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_attachment_file_id] ON [core].[attachment] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_audit_log_company_id] ON [core].[audit_log] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_audit_log_performed_by_user_id] ON [core].[audit_log] ([performed_by_user_id]);
CREATE UNIQUE NONCLUSTERED INDEX [UQ_company_setting_company_id_module_setting_key] ON [core].[company_setting] ([company_id], [module], [setting_key]) WHERE [module] IS NOT NULL AND [setting_key] IS NOT NULL;
CREATE UNIQUE NONCLUSTERED INDEX [UQ_number_sequence_company_id_prefix] ON [core].[number_sequence] ([company_id], [prefix]) WHERE [prefix] IS NOT NULL;
CREATE NONCLUSTERED INDEX [IX_filter_preset_user_account_id] ON [core].[filter_preset] ([user_account_id]);
CREATE NONCLUSTERED INDEX [IX_notification_company_id] ON [core].[notification] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_notification_user_account_id] ON [core].[notification] ([user_account_id]);
CREATE NONCLUSTERED INDEX [IX_webhook_company_id] ON [core].[webhook] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_outbox_event_company_id] ON [core].[outbox_event] ([company_id]);
CREATE UNIQUE NONCLUSTERED INDEX [UQ_webhook_delivery_webhook_id_outbox_event_id] ON [core].[webhook_delivery] ([webhook_id], [outbox_event_id]) WHERE [outbox_event_id] IS NOT NULL;
CREATE NONCLUSTERED INDEX [IX_webhook_delivery_outbox_event_id] ON [core].[webhook_delivery] ([outbox_event_id]);
CREATE NONCLUSTERED INDEX [IX_announcement_company_id] ON [eng].[announcement] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_announcement_author_id] ON [eng].[announcement] ([author_id]);
CREATE NONCLUSTERED INDEX [IX_announcement_read_employee_id] ON [eng].[announcement_read] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_post_company_id] ON [eng].[post] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_post_author_id] ON [eng].[post] ([author_id]);
CREATE NONCLUSTERED INDEX [IX_post_department_id] ON [eng].[post] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_post_branch_id] ON [eng].[post] ([branch_id]);
CREATE NONCLUSTERED INDEX [IX_post_pinned_by_user_id] ON [eng].[post] ([pinned_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_post_hidden_by_user_id] ON [eng].[post] ([hidden_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_post_deleted_by_user_id] ON [eng].[post] ([deleted_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_post_company_id_is_deleted_posted_at] ON [eng].[post] ([company_id], [is_deleted], [posted_at]);
CREATE NONCLUSTERED INDEX [IX_post_media_file_id] ON [eng].[post_media] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_post_reaction_employee_id] ON [eng].[post_reaction] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_post_comment_post_id] ON [eng].[post_comment] ([post_id]);
CREATE NONCLUSTERED INDEX [IX_post_comment_employee_id] ON [eng].[post_comment] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_post_comment_parent_id] ON [eng].[post_comment] ([parent_id]);
CREATE NONCLUSTERED INDEX [IX_post_comment_like_employee_id] ON [eng].[post_comment_like] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_post_view_employee_id] ON [eng].[post_view] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_post_mention_post_id] ON [eng].[post_mention] ([post_id]);
CREATE NONCLUSTERED INDEX [IX_post_mention_post_comment_id] ON [eng].[post_mention] ([post_comment_id]);
CREATE NONCLUSTERED INDEX [IX_post_mention_employee_id] ON [eng].[post_mention] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_survey_company_id] ON [eng].[survey] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_survey_published_by_user_id] ON [eng].[survey] ([published_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_survey_closed_by_user_id] ON [eng].[survey] ([closed_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_survey_question_survey_id] ON [eng].[survey_question] ([survey_id]);
CREATE NONCLUSTERED INDEX [IX_survey_option_survey_question_id] ON [eng].[survey_option] ([survey_question_id]);
CREATE NONCLUSTERED INDEX [IX_survey_participant_employee_id] ON [eng].[survey_participant] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_survey_response_survey_id] ON [eng].[survey_response] ([survey_id]);
CREATE NONCLUSTERED INDEX [IX_survey_response_employee_id] ON [eng].[survey_response] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_survey_answer_survey_response_id] ON [eng].[survey_answer] ([survey_response_id]);
CREATE NONCLUSTERED INDEX [IX_survey_answer_survey_question_id] ON [eng].[survey_answer] ([survey_question_id]);
CREATE NONCLUSTERED INDEX [IX_survey_answer_survey_option_id] ON [eng].[survey_answer] ([survey_option_id]);
CREATE NONCLUSTERED INDEX [IX_template_item_template_id] ON [pm].[template_item] ([template_id]);
CREATE NONCLUSTERED INDEX [IX_workspace_department_id] ON [pm].[workspace] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_workspace_workflow_template_id] ON [pm].[workspace] ([workflow_template_id]);
CREATE NONCLUSTERED INDEX [IX_workspace_status_template_id] ON [pm].[workspace] ([status_template_id]);
CREATE NONCLUSTERED INDEX [IX_workspace_owner_id] ON [pm].[workspace] ([owner_id]);
CREATE NONCLUSTERED INDEX [IX_workspace_cover_file_id] ON [pm].[workspace] ([cover_file_id]);
CREATE NONCLUSTERED INDEX [IX_workspace_member_employee_id] ON [pm].[workspace_member] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_task_list_folder_id] ON [pm].[task_list] ([folder_id]);
CREATE NONCLUSTERED INDEX [IX_task_list_member_employee_id] ON [pm].[task_list_member] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_sprint_workspace_id] ON [pm].[sprint] ([workspace_id]);
CREATE NONCLUSTERED INDEX [IX_task_workspace_id] ON [pm].[task] ([workspace_id]);
CREATE NONCLUSTERED INDEX [IX_task_task_list_id] ON [pm].[task] ([task_list_id]);
CREATE NONCLUSTERED INDEX [IX_task_parent_task_id] ON [pm].[task] ([parent_task_id]);
CREATE NONCLUSTERED INDEX [IX_task_status_id] ON [pm].[task] ([status_id]);
CREATE NONCLUSTERED INDEX [IX_task_sprint_id] ON [pm].[task] ([sprint_id]);
CREATE NONCLUSTERED INDEX [IX_task_cover_file_id] ON [pm].[task] ([cover_file_id]);
CREATE NONCLUSTERED INDEX [IX_task_assignee_employee_id] ON [pm].[task_assignee] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_task_dependency_other_task_id] ON [pm].[task_dependency] ([other_task_id]);
CREATE NONCLUSTERED INDEX [IX_task_tag_tag_id] ON [pm].[task_tag] ([tag_id]);
CREATE NONCLUSTERED INDEX [IX_checklist_item_task_id] ON [pm].[checklist_item] ([task_id]);
CREATE NONCLUSTERED INDEX [IX_time_entry_task_id] ON [pm].[time_entry] ([task_id]);
CREATE NONCLUSTERED INDEX [IX_time_entry_employee_id] ON [pm].[time_entry] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_task_comment_task_id] ON [pm].[task_comment] ([task_id]);
CREATE NONCLUSTERED INDEX [IX_task_comment_author_id] ON [pm].[task_comment] ([author_id]);
CREATE NONCLUSTERED INDEX [IX_task_comment_parent_id] ON [pm].[task_comment] ([parent_id]);
CREATE NONCLUSTERED INDEX [IX_task_comment_assigned_to_id] ON [pm].[task_comment] ([assigned_to_id]);
CREATE NONCLUSTERED INDEX [IX_task_comment_assigned_by_id] ON [pm].[task_comment] ([assigned_by_id]);
CREATE NONCLUSTERED INDEX [IX_task_comment_resolved_by_id] ON [pm].[task_comment] ([resolved_by_id]);
CREATE NONCLUSTERED INDEX [IX_comment_mention_comment_id] ON [pm].[comment_mention] ([comment_id]);
CREATE NONCLUSTERED INDEX [IX_comment_mention_employee_id] ON [pm].[comment_mention] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_comment_mention_mentioned_task_id] ON [pm].[comment_mention] ([mentioned_task_id]);
CREATE NONCLUSTERED INDEX [IX_comment_reaction_employee_id] ON [pm].[comment_reaction] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_reminder_workspace_id] ON [pm].[reminder] ([workspace_id]);
CREATE NONCLUSTERED INDEX [IX_reminder_owner_id] ON [pm].[reminder] ([owner_id]);
CREATE NONCLUSTERED INDEX [IX_reminder_assignee_id] ON [pm].[reminder] ([assignee_id]);
CREATE NONCLUSTERED INDEX [IX_task_extension_task_id] ON [pm].[task_extension] ([task_id]);
CREATE NONCLUSTERED INDEX [IX_task_extension_requested_by_id] ON [pm].[task_extension] ([requested_by_id]);
CREATE NONCLUSTERED INDEX [IX_task_extension_decided_by_id] ON [pm].[task_extension] ([decided_by_id]);
CREATE NONCLUSTERED INDEX [IX_task_extension_request_id] ON [pm].[task_extension] ([request_id]);
CREATE NONCLUSTERED INDEX [IX_column_permission_workspace_id] ON [pm].[column_permission] ([workspace_id]);
CREATE NONCLUSTERED INDEX [IX_column_permission_employee_id] ON [pm].[column_permission] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_task_field_value_custom_field_id] ON [pm].[task_field_value] ([custom_field_id]);
CREATE NONCLUSTERED INDEX [IX_list_view_workspace_id] ON [pm].[list_view] ([workspace_id]);
CREATE NONCLUSTERED INDEX [IX_list_view_task_list_id] ON [pm].[list_view] ([task_list_id]);
CREATE NONCLUSTERED INDEX [IX_list_view_owner_id] ON [pm].[list_view] ([owner_id]);
CREATE NONCLUSTERED INDEX [IX_share_link_workspace_id] ON [pm].[share_link] ([workspace_id]);
CREATE NONCLUSTERED INDEX [IX_share_member_share_link_id] ON [pm].[share_member] ([share_link_id]);
CREATE NONCLUSTERED INDEX [IX_share_member_employee_id] ON [pm].[share_member] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_share_access_share_link_id] ON [pm].[share_access] ([share_link_id]);
CREATE NONCLUSTERED INDEX [IX_task_external_file_company_id] ON [pm].[task_external_file] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_doc_company_id] ON [pm].[doc] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_doc_workspace_id] ON [pm].[doc] ([workspace_id]);
CREATE NONCLUSTERED INDEX [IX_doc_folder_id] ON [pm].[doc] ([folder_id]);
CREATE NONCLUSTERED INDEX [IX_doc_task_list_id] ON [pm].[doc] ([task_list_id]);
CREATE NONCLUSTERED INDEX [IX_doc_owner_id] ON [pm].[doc] ([owner_id]);
CREATE NONCLUSTERED INDEX [IX_doc_cover_file_id] ON [pm].[doc] ([cover_file_id]);
CREATE NONCLUSTERED INDEX [IX_doc_workspace_id_archived_at] ON [pm].[doc] ([workspace_id], [archived_at]);
CREATE NONCLUSTERED INDEX [IX_doc_contributor_employee_id] ON [pm].[doc_contributor] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_doc_task_task_id] ON [pm].[doc_task] ([task_id]);
CREATE NONCLUSTERED INDEX [IX_doc_comment_doc_id] ON [pm].[doc_comment] ([doc_id]);
CREATE NONCLUSTERED INDEX [IX_doc_comment_author_id] ON [pm].[doc_comment] ([author_id]);
CREATE NONCLUSTERED INDEX [IX_doc_comment_parent_id] ON [pm].[doc_comment] ([parent_id]);
CREATE NONCLUSTERED INDEX [IX_note_company_id] ON [pm].[note] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_note_user_account_id] ON [pm].[note] ([user_account_id]);
CREATE NONCLUSTERED INDEX [IX_note_version_edited_by_user_id] ON [pm].[note_version] ([edited_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_personal_item_company_id] ON [pm].[personal_item] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_personal_item_user_account_id] ON [pm].[personal_item] ([user_account_id]);
CREATE NONCLUSTERED INDEX [IX_recent_item_company_id] ON [pm].[recent_item] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_recent_item_user_account_id_opened_at] ON [pm].[recent_item] ([user_account_id], [opened_at]);
CREATE NONCLUSTERED INDEX [IX_penalty_rule_leave_type_id] ON [att].[penalty_rule] ([leave_type_id]);
CREATE NONCLUSTERED INDEX [IX_warning_company_id] ON [att].[warning] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_warning_employee_id] ON [att].[warning] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_warning_warning_policy_id] ON [att].[warning] ([warning_policy_id]);
CREATE NONCLUSTERED INDEX [IX_warning_timesheet_day_id] ON [att].[warning] ([timesheet_day_id]);
CREATE NONCLUSTERED INDEX [IX_warning_penalty_rule_id] ON [att].[warning] ([penalty_rule_id]);
CREATE NONCLUSTERED INDEX [IX_warning_payslip_id] ON [att].[warning] ([payslip_id]);
CREATE NONCLUSTERED INDEX [IX_plan_year_plan_benefit_plan_id] ON [ben].[plan_year_plan] ([benefit_plan_id]);
CREATE NONCLUSTERED INDEX [IX_enrollment_window_company_id] ON [ben].[enrollment_window] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_enrollment_window_plan_year_id] ON [ben].[enrollment_window] ([plan_year_id]);
CREATE NONCLUSTERED INDEX [IX_enrollment_window_plan_benefit_plan_id] ON [ben].[enrollment_window_plan] ([benefit_plan_id]);
CREATE NONCLUSTERED INDEX [IX_enrollment_window_employee_employee_id] ON [ben].[enrollment_window_employee] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_election_company_id] ON [ben].[election] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_election_plan_year_id] ON [ben].[election] ([plan_year_id]);
CREATE NONCLUSTERED INDEX [IX_election_enrollment_window_id] ON [ben].[election] ([enrollment_window_id]);
CREATE NONCLUSTERED INDEX [IX_election_decided_by_user_id] ON [ben].[election] ([decided_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_election_plan_benefit_plan_id] ON [ben].[election_plan] ([benefit_plan_id]);
CREATE NONCLUSTERED INDEX [IX_health_benefit_company_id] ON [ben].[health_benefit] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_health_benefit_employee_id] ON [ben].[health_benefit] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_health_benefit_document_file_id] ON [ben].[health_benefit] ([document_file_id]);
CREATE NONCLUSTERED INDEX [IX_perk_company_id] ON [ben].[perk] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_kpi_department_id] ON [perf].[kpi] ([department_id]);
CREATE NONCLUSTERED INDEX [IX_kpi_job_title_id] ON [perf].[kpi] ([job_title_id]);
CREATE NONCLUSTERED INDEX [IX_appraisal_form_rating_scale_id] ON [perf].[appraisal_form] ([rating_scale_id]);
CREATE NONCLUSTERED INDEX [IX_appraisal_criterion_appraisal_form_id] ON [perf].[appraisal_criterion] ([appraisal_form_id]);
CREATE NONCLUSTERED INDEX [IX_appraisal_criterion_kpi_id] ON [perf].[appraisal_criterion] ([kpi_id]);
CREATE NONCLUSTERED INDEX [IX_appraisal_cycle_appraisal_form_id] ON [perf].[appraisal_cycle] ([appraisal_form_id]);
CREATE NONCLUSTERED INDEX [IX_appraisal_company_id] ON [perf].[appraisal] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_appraisal_employee_id] ON [perf].[appraisal] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_appraisal_reviewer_employee_id] ON [perf].[appraisal] ([reviewer_employee_id]);
CREATE NONCLUSTERED INDEX [IX_appraisal_finalised_by_user_id] ON [perf].[appraisal] ([finalised_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_appraisal_letter_file_id] ON [perf].[appraisal] ([letter_file_id]);
CREATE NONCLUSTERED INDEX [IX_appraisal_rating_appraisal_criterion_id] ON [perf].[appraisal_rating] ([appraisal_criterion_id]);
CREATE NONCLUSTERED INDEX [IX_goal_company_id] ON [perf].[goal] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_goal_employee_id] ON [perf].[goal] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_goal_appraisal_cycle_id] ON [perf].[goal] ([appraisal_cycle_id]);
CREATE NONCLUSTERED INDEX [IX_goal_kpi_id] ON [perf].[goal] ([kpi_id]);
CREATE NONCLUSTERED INDEX [IX_goal_set_by_user_id] ON [perf].[goal] ([set_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_goal_check_in_goal_id] ON [perf].[goal_check_in] ([goal_id]);
CREATE NONCLUSTERED INDEX [IX_increment_proposal_company_id] ON [perf].[increment_proposal] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_increment_proposal_employee_id] ON [perf].[increment_proposal] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_increment_proposal_employee_salary_id] ON [perf].[increment_proposal] ([employee_salary_id]);
CREATE NONCLUSTERED INDEX [IX_increment_proposal_decided_by_user_id] ON [perf].[increment_proposal] ([decided_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_training_program_training_category_id] ON [trn].[training_program] ([training_category_id]);
CREATE NONCLUSTERED INDEX [IX_training_session_company_id] ON [trn].[training_session] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_training_session_training_program_id] ON [trn].[training_session] ([training_program_id]);
CREATE NONCLUSTERED INDEX [IX_training_session_trainer_employee_id] ON [trn].[training_session] ([trainer_employee_id]);
CREATE NONCLUSTERED INDEX [IX_training_enrolment_company_id] ON [trn].[training_enrolment] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_training_enrolment_employee_id] ON [trn].[training_enrolment] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_training_enrolment_nominated_by_user_id] ON [trn].[training_enrolment] ([nominated_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_training_enrolment_decided_by_user_id] ON [trn].[training_enrolment] ([decided_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_training_enrolment_certificate_file_id] ON [trn].[training_enrolment] ([certificate_file_id]);
CREATE NONCLUSTERED INDEX [IX_form_company_id] ON [frm].[form] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_form_published_by_user_id] ON [frm].[form] ([published_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_form_closed_by_user_id] ON [frm].[form] ([closed_by_user_id]);
CREATE NONCLUSTERED INDEX [IX_form_company_id_status] ON [frm].[form] ([company_id], [status]);
CREATE NONCLUSTERED INDEX [IX_form_section_form_id] ON [frm].[form_section] ([form_id]);
CREATE NONCLUSTERED INDEX [IX_form_field_form_id] ON [frm].[form_field] ([form_id]);
CREATE NONCLUSTERED INDEX [IX_form_field_form_section_id] ON [frm].[form_field] ([form_section_id]);
CREATE NONCLUSTERED INDEX [IX_form_field_option_form_field_id] ON [frm].[form_field_option] ([form_field_id]);
CREATE NONCLUSTERED INDEX [IX_form_response_company_id] ON [frm].[form_response] ([company_id]);
CREATE NONCLUSTERED INDEX [IX_form_response_form_id] ON [frm].[form_response] ([form_id]);
CREATE NONCLUSTERED INDEX [IX_form_response_employee_id] ON [frm].[form_response] ([employee_id]);
CREATE NONCLUSTERED INDEX [IX_form_response_form_id_submitted_at] ON [frm].[form_response] ([form_id], [submitted_at]);
CREATE NONCLUSTERED INDEX [IX_form_response_employee_id_form_id] ON [frm].[form_response] ([employee_id], [form_id]);
CREATE NONCLUSTERED INDEX [IX_form_answer_form_field_id] ON [frm].[form_answer] ([form_field_id]);
CREATE NONCLUSTERED INDEX [IX_form_answer_file_id] ON [frm].[form_answer] ([file_id]);
CREATE NONCLUSTERED INDEX [IX_form_answer_option_form_field_option_id] ON [frm].[form_answer_option] ([form_field_option_id]);
GO

-- Descriptions (visible in SSMS and to anyone reading the database)
EXEC sys.sp_addextendedproperty N'MS_Description', N'organisation name shown in the app (General Settings)', N'SCHEMA', N'org', N'TABLE', N'company', N'COLUMN', N'name';
EXEC sys.sp_addextendedproperty N'MS_Description', N'registered name', N'SCHEMA', N'org', N'TABLE', N'company', N'COLUMN', N'legal_name';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: where the company is registered', N'SCHEMA', N'org', N'TABLE', N'company', N'COLUMN', N'country_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'ISO 4217; PKR for a Pakistani company, AED for a UAE one', N'SCHEMA', N'org', N'TABLE', N'company', N'COLUMN', N'currency';
EXEC sys.sp_addextendedproperty N'MS_Description', N'IANA name; Asia/Karachi, Asia/Dubai', N'SCHEMA', N'org', N'TABLE', N'company', N'COLUMN', N'timezone';
EXEC sys.sp_addextendedproperty N'MS_Description', N'dd/MM/yyyy, MM/dd/yyyy, yyyy-MM-dd, dd MMM yyyy', N'SCHEMA', N'org', N'TABLE', N'company', N'COLUMN', N'date_format';
EXEC sys.sp_addextendedproperty N'MS_Description', N'monday, saturday, sunday', N'SCHEMA', N'org', N'TABLE', N'company', N'COLUMN', N'week_start_day';
EXEC sys.sp_addextendedproperty N'MS_Description', N'1 to 12; 7 (July) in Pakistan', N'SCHEMA', N'org', N'TABLE', N'company', N'COLUMN', N'fiscal_year_start_month';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one legal entity; a customer database holds several (e.g. a Pakistani company and a Dubai FZ-LLC)', N'SCHEMA', N'org', N'TABLE', N'company';
EXEC sys.sp_addextendedproperty N'MS_Description', N'ISO 3166-1', N'SCHEMA', N'org', N'TABLE', N'country';
EXEC sys.sp_addextendedproperty N'MS_Description', N'province, emirate or territory; code is the ISO 3166-2 subdivision code', N'SCHEMA', N'org', N'TABLE', N'state';
EXEC sys.sp_addextendedproperty N'MS_Description', N'part of a location', N'SCHEMA', N'org', N'TABLE', N'area';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional', N'SCHEMA', N'org', N'TABLE', N'branch', N'COLUMN', N'area_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'sub-department', N'SCHEMA', N'org', N'TABLE', N'department', N'COLUMN', N'parent_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'HOD', N'SCHEMA', N'org', N'TABLE', N'department', N'COLUMN', N'head_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'sort_order ranks grades, so a promotion can be told from a demotion', N'SCHEMA', N'org', N'TABLE', N'grade';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a new company starts with Permanent, Contractual, Daily Wager, Management Trainee', N'SCHEMA', N'org', N'TABLE', N'employment_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'prefix from branch/location + number', N'SCHEMA', N'hr', N'TABLE', N'employee', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Personal tab / Benefits "Home Address"; changed by HR or an approved Update Information request', N'SCHEMA', N'hr', N'TABLE', N'employee', N'COLUMN', N'home_address';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional', N'SCHEMA', N'hr', N'TABLE', N'employee', N'COLUMN', N'home_city_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'profile photo (an image upload); responses give photoUrl, a signed link', N'SCHEMA', N'hr', N'TABLE', N'employee', N'COLUMN', N'photo_file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'no cycles: nobody manages their own manager', N'SCHEMA', N'hr', N'TABLE', N'employee', N'COLUMN', N'line_manager_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'active, probation, notice, left, inactive (switched off by HR)', N'SCHEMA', N'hr', N'TABLE', N'employee', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'monthly, daily, hourly', N'SCHEMA', N'hr', N'TABLE', N'employee', N'COLUMN', N'salary_frequency';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one row per joining; rehire adds a row', N'SCHEMA', N'hr', N'TABLE', N'employment_period';
EXEC sys.sp_addextendedproperty N'MS_Description', N'joining, transfer, promotion, demotion, edit', N'SCHEMA', N'hr', N'TABLE', N'employee_history', N'COLUMN', N'change_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'JSON of the placement before this change; a cancelled request puts it back', N'SCHEMA', N'hr', N'TABLE', N'employee_history', N'COLUMN', N'previous_values';
EXEC sys.sp_addextendedproperty N'MS_Description', N'set when the request behind it is cancelled after approval', N'SCHEMA', N'hr', N'TABLE', N'employee_history', N'COLUMN', N'is_reverted';
EXEC sys.sp_addextendedproperty N'MS_Description', N'what changed and when: joining, transfer, promotion, demotion, edit', N'SCHEMA', N'hr', N'TABLE', N'employee_history';
EXEC sys.sp_addextendedproperty N'MS_Description', N'flat, percent', N'SCHEMA', N'hr', N'TABLE', N'employee_salary', N'COLUMN', N'change_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'joining, revision, promotion, import', N'SCHEMA', N'hr', N'TABLE', N'employee_salary', N'COLUMN', N'source';
EXEC sys.sp_addextendedproperty N'MS_Description', N'salary over time; the Salary Revision screen lists this', N'SCHEMA', N'hr', N'TABLE', N'employee_salary';
EXEC sys.sp_addextendedproperty N'MS_Description', N'fixed allowances / deductions per person', N'SCHEMA', N'hr', N'TABLE', N'employee_pay_item';
EXEC sys.sp_addextendedproperty N'MS_Description', N'sensitive (employees.bank_accounts)', N'SCHEMA', N'hr', N'TABLE', N'employee_bank_account';
EXEC sys.sp_addextendedproperty N'MS_Description', N'cnic, passport, driving_licence (identity: employees.identity too);', N'SCHEMA', N'hr', N'TABLE', N'employee_document', N'COLUMN', N'document_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'set when the employee was told it expires soon (hr.usp_employee_document_expiry_notify)', N'SCHEMA', N'hr', N'TABLE', N'employee_document', N'COLUMN', N'expiry_notified_at';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Documents tab (SRS EMP-3, APP Documents): CNIC copy, degree, letters', N'SCHEMA', N'hr', N'TABLE', N'employee_document';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Professional experience: Company Name, Job Title, From / To (to empty = present)', N'SCHEMA', N'hr', N'TABLE', N'employee_experience';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Emergency Contact # on the Personal tab is the primary contact''s phone', N'SCHEMA', N'hr', N'TABLE', N'employee_emergency_contact';
EXEC sys.sp_addextendedproperty N'MS_Description', N'spouse, son, daughter, father, mother, brother, sister, other', N'SCHEMA', N'hr', N'TABLE', N'employee_dependent', N'COLUMN', N'relation';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Dependents tab: First Name, Last Name, Relation, Occupation', N'SCHEMA', N'hr', N'TABLE', N'employee_dependent';
EXEC sys.sp_addextendedproperty N'MS_Description', N'beginner, intermediate, advanced, expert', N'SCHEMA', N'hr', N'TABLE', N'employee_skill', N'COLUMN', N'skill_level';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Skills tab: Skill Title, Skill Level', N'SCHEMA', N'hr', N'TABLE', N'employee_skill';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Add Academic: Academic Title, Institute, From / To, In Process, document', N'SCHEMA', N'hr', N'TABLE', N'employee_education';
EXEC sys.sp_addextendedproperty N'MS_Description', N'permanent, temporary, contractual, probation, internship, consultant', N'SCHEMA', N'hr', N'TABLE', N'employee_contract', N'COLUMN', N'contract_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'empty = custom dates', N'SCHEMA', N'hr', N'TABLE', N'employee_contract', N'COLUMN', N'duration_months';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Add Contract: Contract Type, Duration in Months (or Custom), From / To, attachment.', N'SCHEMA', N'hr', N'TABLE', N'employee_contract';
EXEC sys.sp_addextendedproperty N'MS_Description', N'pending, approved, rejected, cancelled', N'SCHEMA', N'hr', N'TABLE', N'employee_change_request', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'JSON of the asked values (snake_case keys): date_of_birth, marital_status,', N'SCHEMA', N'hr', N'TABLE', N'employee_change_request', N'COLUMN', N'changes';
EXEC sys.sp_addextendedproperty N'MS_Description', N'JSON of the same fields when asked', N'SCHEMA', N'hr', N'TABLE', N'employee_change_request', N'COLUMN', N'previous_values';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Update Information": an employee asks, HR approves; approval writes hr.employee', N'SCHEMA', N'hr', N'TABLE', N'employee_change_request';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: blank for system users', N'SCHEMA', N'auth', N'TABLE', N'user_account', N'COLUMN', N'employee_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'home company: the one active after sign-in', N'SCHEMA', N'auth', N'TABLE', N'user_account', N'COLUMN', N'company_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'used when there is no employee', N'SCHEMA', N'auth', N'TABLE', N'user_account', N'COLUMN', N'display_name';
EXEC sys.sp_addextendedproperty N'MS_Description', N'leave.requests.approve', N'SCHEMA', N'auth', N'TABLE', N'permission', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'leave', N'SCHEMA', N'auth', N'TABLE', N'permission', N'COLUMN', N'module';
EXEC sys.sp_addextendedproperty N'MS_Description', N'leave.requests', N'SCHEMA', N'auth', N'TABLE', N'permission', N'COLUMN', N'screen';
EXEC sys.sp_addextendedproperty N'MS_Description', N'view, create, edit, delete, approve, reject, export, import ...', N'SCHEMA', N'auth', N'TABLE', N'permission', N'COLUMN', N'action_code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'salary, bank, CNIC, loan and payslip figures', N'SCHEMA', N'auth', N'TABLE', N'permission', N'COLUMN', N'is_sensitive';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the catalogue: one row per view or button (module.screen.action)', N'SCHEMA', N'auth', N'TABLE', N'permission';
EXEC sys.sp_addextendedproperty N'MS_Description', N'per company; default roles are copied in when a company is created', N'SCHEMA', N'auth', N'TABLE', N'role';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one tick on the role screen', N'SCHEMA', N'auth', N'TABLE', N'role_permission';
EXEC sys.sp_addextendedproperty N'MS_Description', N'when scope = selected_units', N'SCHEMA', N'auth', N'TABLE', N'role_permission_unit';
EXEC sys.sp_addextendedproperty N'MS_Description', N'codes a default role has already been offered; one the customer removed is not offered again', N'SCHEMA', N'auth', N'TABLE', N'role_default_offer';
EXEC sys.sp_addextendedproperty N'MS_Description', N'grant, deny', N'SCHEMA', N'auth', N'TABLE', N'user_permission_override', N'COLUMN', N'effect';
EXEC sys.sp_addextendedproperty N'MS_Description', N'for grants', N'SCHEMA', N'auth', N'TABLE', N'user_permission_override', N'COLUMN', N'scope';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a grant or a denial for one person in one company; a denial wins', N'SCHEMA', N'auth', N'TABLE', N'user_permission_override';
EXEC sys.sp_addextendedproperty N'MS_Description', N'which companies a user may see', N'SCHEMA', N'auth', N'TABLE', N'user_company';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one sign-in; the token names it, so ending it signs that device out', N'SCHEMA', N'auth', N'TABLE', N'user_session';
EXEC sys.sp_addextendedproperty N'MS_Description', N'TS-00004, from core.number_sequence prefix TS-', N'SCHEMA', N'sch', N'TABLE', N'time_slot', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'local time; for a flexible slot the window the hours may fall in', N'SCHEMA', N'sch', N'TABLE', N'time_slot', N'COLUMN', N'start_time';
EXEC sys.sp_addextendedproperty N'MS_Description', N'an end at or before the start ends the next day', N'SCHEMA', N'sch', N'TABLE', N'time_slot', N'COLUMN', N'end_time';
EXEC sys.sp_addextendedproperty N'MS_Description', N'end minus start, overnight counted into the next day', N'SCHEMA', N'sch', N'TABLE', N'time_slot', N'COLUMN', N'duration_minutes';
EXEC sys.sp_addextendedproperty N'MS_Description', N'flexible: hours to work per day; fixed: duration minus breaks that are not inclusive', N'SCHEMA', N'sch', N'TABLE', N'time_slot', N'COLUMN', N'workable_minutes';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a shift template (Attendance settings, Time Slots)', N'SCHEMA', N'sch', N'TABLE', N'time_slot';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Lunch, Prayer, Tea ...; identifiers are what a device or log sends', N'SCHEMA', N'sch', N'TABLE', N'break_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the slot''s planned breaks', N'SCHEMA', N'sch', N'TABLE', N'time_slot_break';
EXEC sys.sp_addextendedproperty N'MS_Description', N'open-ended when blank', N'SCHEMA', N'sch', N'TABLE', N'roster_group', N'COLUMN', N'to_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a named weekly pattern employees are enrolled in for a period', N'SCHEMA', N'sch', N'TABLE', N'roster_group';
EXEC sys.sp_addextendedproperty N'MS_Description', N'1 = Monday ... 7 = Sunday', N'SCHEMA', N'sch', N'TABLE', N'roster_group_day', N'COLUMN', N'weekday';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: blank on a day off', N'SCHEMA', N'sch', N'TABLE', N'roster_group_day', N'COLUMN', N'time_slot_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one row per weekday of the pattern', N'SCHEMA', N'sch', N'TABLE', N'roster_group_day';
EXEC sys.sp_addextendedproperty N'MS_Description', N'open-ended when blank; set when discontinued', N'SCHEMA', N'sch', N'TABLE', N'roster_group_member', N'COLUMN', N'end_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'an enrolment; one roster per employee at a time', N'SCHEMA', N'sch', N'TABLE', N'roster_group_member';
EXEC sys.sp_addextendedproperty N'MS_Description', N'create, default_shift, import', N'SCHEMA', N'sch', N'TABLE', N'schedule_batch', N'COLUMN', N'batch_kind';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: one slot for every day', N'SCHEMA', N'sch', N'TABLE', N'schedule_batch', N'COLUMN', N'time_slot_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: each weekday''s slot from the roster pattern', N'SCHEMA', N'sch', N'TABLE', N'schedule_batch', N'COLUMN', N'roster_group_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'1..7 comma separated; blank = every day', N'SCHEMA', N'sch', N'TABLE', N'schedule_batch', N'COLUMN', N'weekdays';
EXEC sys.sp_addextendedproperty N'MS_Description', N'0 = never, 1..8', N'SCHEMA', N'sch', N'TABLE', N'schedule_batch', N'COLUMN', N'repeat_every_weeks';
EXEC sys.sp_addextendedproperty N'MS_Description', N'weeks on in each repeat cycle', N'SCHEMA', N'sch', N'TABLE', N'schedule_batch', N'COLUMN', N'step';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional', N'SCHEMA', N'sch', N'TABLE', N'schedule_batch', N'COLUMN', N'geo_fence_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one "Create Scheduling" or "Apply Default Shift" action', N'SCHEMA', N'sch', N'TABLE', N'schedule_batch';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the business date the shift belongs to (its start)', N'SCHEMA', N'sch', N'TABLE', N'schedule', N'COLUMN', N'work_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional', N'SCHEMA', N'sch', N'TABLE', N'schedule', N'COLUMN', N'schedule_batch_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional', N'SCHEMA', N'sch', N'TABLE', N'schedule', N'COLUMN', N'geo_fence_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'flexible: workable minutes; fixed: shift minus breaks that are not inclusive', N'SCHEMA', N'sch', N'TABLE', N'schedule', N'COLUMN', N'planned_minutes';
EXEC sys.sp_addextendedproperty N'MS_Description', N'planned shift: one employee, one shift', N'SCHEMA', N'sch', N'TABLE', N'schedule';
EXEC sys.sp_addextendedproperty N'MS_Description', N'1..7 comma separated (1 = Monday)', N'SCHEMA', N'sch', N'TABLE', N'rest_day_rule', N'COLUMN', N'weekdays';
EXEC sys.sp_addextendedproperty N'MS_Description', N'0 = every week in the range, 1..8 = every n weeks', N'SCHEMA', N'sch', N'TABLE', N'rest_day_rule', N'COLUMN', N'repeat_every_weeks';
EXEC sys.sp_addextendedproperty N'MS_Description', N'weeks on in each repeat cycle', N'SCHEMA', N'sch', N'TABLE', N'rest_day_rule', N'COLUMN', N'step';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Create New Rest Day": employees, dates, repeat, step, weekdays, payable', N'SCHEMA', N'sch', N'TABLE', N'rest_day_rule';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: from a rule', N'SCHEMA', N'sch', N'TABLE', N'rest_day', N'COLUMN', N'rest_day_rule_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: from an approved rest-day request', N'SCHEMA', N'sch', N'TABLE', N'rest_day', N'COLUMN', N'request_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'each resulting rest day; wins over a shift on the same date', N'SCHEMA', N'sch', N'TABLE', N'rest_day';
EXEC sys.sp_addextendedproperty N'MS_Description', N'public, local', N'SCHEMA', N'sch', N'TABLE', N'holiday', N'COLUMN', N'holiday_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'on: the day is a holiday in the time sheet; off: listed, still worked', N'SCHEMA', N'sch', N'TABLE', N'holiday', N'COLUMN', N'attendance_exempt';
EXEC sys.sp_addextendedproperty N'MS_Description', N'employee, org_structure, geo_location, religion', N'SCHEMA', N'sch', N'TABLE', N'holiday_rule', N'COLUMN', N'rule_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: rule_type employee', N'SCHEMA', N'sch', N'TABLE', N'holiday_rule', N'COLUMN', N'employee_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: rule_type org_structure', N'SCHEMA', N'sch', N'TABLE', N'holiday_rule', N'COLUMN', N'location_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: rule_type org_structure', N'SCHEMA', N'sch', N'TABLE', N'holiday_rule', N'COLUMN', N'branch_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: rule_type geo_location (employee''s branch)', N'SCHEMA', N'sch', N'TABLE', N'holiday_rule', N'COLUMN', N'country_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: rule_type geo_location', N'SCHEMA', N'sch', N'TABLE', N'holiday_rule', N'COLUMN', N'state_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: rule_type geo_location', N'SCHEMA', N'sch', N'TABLE', N'holiday_rule', N'COLUMN', N'city_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'rule_type religion', N'SCHEMA', N'sch', N'TABLE', N'holiday_rule', N'COLUMN', N'religion';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who the holiday applies to; no rules = everyone', N'SCHEMA', N'sch', N'TABLE', N'holiday_rule';
EXEC sys.sp_addextendedproperty N'MS_Description', N'MCH-00001, from core.number_sequence prefix MCH-', N'SCHEMA', N'att', N'TABLE', N'device', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: where the machine stands', N'SCHEMA', N'att', N'TABLE', N'device', N'COLUMN', N'branch_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'where the machine stands, as text', N'SCHEMA', N'att', N'TABLE', N'device', N'COLUMN', N'address';
EXEC sys.sp_addextendedproperty N'MS_Description', N'active, inactive', N'SCHEMA', N'att', N'TABLE', N'device', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'last time punches arrived from it', N'SCHEMA', N'att', N'TABLE', N'device', N'COLUMN', N'last_synced_at';
EXEC sys.sp_addextendedproperty N'MS_Description', N'biometric machine (ATT-1 to ATT-3); fingerprints stay on the device (NFR-10)', N'SCHEMA', N'att', N'TABLE', N'device';
EXEC sys.sp_addextendedproperty N'MS_Description', N'an employee''s user number on a machine', N'SCHEMA', N'att', N'TABLE', N'device_enrolment';
EXEC sys.sp_addextendedproperty N'MS_Description', N'GF-00001, from core.number_sequence prefix GF-', N'SCHEMA', N'att', N'TABLE', N'geo_fence', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'circle, polygon', N'SCHEMA', N'att', N'TABLE', N'geo_fence', N'COLUMN', N'shape';
EXEC sys.sp_addextendedproperty N'MS_Description', N'polygon: JSON list of lat and lng points, at least 3', N'SCHEMA', N'att', N'TABLE', N'geo_fence', N'COLUMN', N'polygon_points';
EXEC sys.sp_addextendedproperty N'MS_Description', N'on: everyone; off: the employees the targets select', N'SCHEMA', N'att', N'TABLE', N'geo_fence', N'COLUMN', N'applies_to_all';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"For Shift": offered when scheduling shifts', N'SCHEMA', N'att', N'TABLE', N'geo_fence', N'COLUMN', N'is_for_shift';
EXEC sys.sp_addextendedproperty N'MS_Description', N'where web and mobile punches are allowed (ATT-6); Scheduling offers the ones marked for shifts', N'SCHEMA', N'att', N'TABLE', N'geo_fence';
EXEC sys.sp_addextendedproperty N'MS_Description', N'employee, country, location, branch, area, department, designation, grade, job_title, religion, nationality', N'SCHEMA', N'att', N'TABLE', N'geo_fence_target', N'COLUMN', N'target_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the id, for every type except religion and nationality', N'SCHEMA', N'att', N'TABLE', N'geo_fence_target', N'COLUMN', N'target_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'religion, nationality', N'SCHEMA', N'att', N'TABLE', N'geo_fence_target', N'COLUMN', N'target_value';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who the fence applies to: one value per row; rows of one type are OR, types are AND', N'SCHEMA', N'att', N'TABLE', N'geo_fence_target';
EXEC sys.sp_addextendedproperty N'MS_Description', N'IPR-00001, from core.number_sequence prefix IPR-', N'SCHEMA', N'att', N'TABLE', N'ip_restriction', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'subnet mask for ipv4, e.g. 255.255.255.0', N'SCHEMA', N'att', N'TABLE', N'ip_restriction', N'COLUMN', N'netmask';
EXEC sys.sp_addextendedproperty N'MS_Description', N'on: everyone; off: the employees the targets select', N'SCHEMA', N'att', N'TABLE', N'ip_restriction', N'COLUMN', N'applies_to_all';
EXEC sys.sp_addextendedproperty N'MS_Description', N'addresses web and mobile punches must come from (ATT-6)', N'SCHEMA', N'att', N'TABLE', N'ip_restriction';
EXEC sys.sp_addextendedproperty N'MS_Description', N'employee, country, location, branch, area, department, designation, grade, job_title, religion, nationality', N'SCHEMA', N'att', N'TABLE', N'ip_restriction_target', N'COLUMN', N'target_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who the restriction applies to; same rules as geo_fence_target', N'SCHEMA', N'att', N'TABLE', N'ip_restriction_target';
EXEC sys.sp_addextendedproperty N'MS_Description', N'local wall-clock time', N'SCHEMA', N'att', N'TABLE', N'punch', N'COLUMN', N'punched_at';
EXEC sys.sp_addextendedproperty N'MS_Description', N'check_in, check_out, break_out, break_in', N'SCHEMA', N'att', N'TABLE', N'punch', N'COLUMN', N'punch_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'biometric, mobile, web, manual, import_file, punch_request', N'SCHEMA', N'att', N'TABLE', N'punch', N'COLUMN', N'source';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Take Picture For Attendance For Dashboard"', N'SCHEMA', N'att', N'TABLE', N'punch', N'COLUMN', N'photo_file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'when it came from an approved punch request', N'SCHEMA', N'att', N'TABLE', N'punch', N'COLUMN', N'request_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a manual or imported punch changed after it was entered', N'SCHEMA', N'att', N'TABLE', N'punch', N'COLUMN', N'is_manually_updated';
EXEC sys.sp_addextendedproperty N'MS_Description', N'left out of the time sheet (a device punch cannot be edited, only ignored)', N'SCHEMA', N'att', N'TABLE', N'punch', N'COLUMN', N'is_ignored';
EXEC sys.sp_addextendedproperty N'MS_Description', N'every raw clock event', N'SCHEMA', N'att', N'TABLE', N'punch';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the first shift of the day; several shifts are one day from first start to last end', N'SCHEMA', N'att', N'TABLE', N'timesheet_day', N'COLUMN', N'schedule_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'planned minutes of the day''s shifts', N'SCHEMA', N'att', N'TABLE', N'timesheet_day', N'COLUMN', N'expected_minutes';
EXEC sys.sp_addextendedproperty N'MS_Description', N'from approved overtime requests, or the computed overtime when approval is not required', N'SCHEMA', N'att', N'TABLE', N'timesheet_day', N'COLUMN', N'approved_overtime_minutes';
EXEC sys.sp_addextendedproperty N'MS_Description', N'present, absent, holiday, weekend, rest_day, leave, half_day, short_day, wfh, official_visit, sandwich, yet_to_start', N'SCHEMA', N'att', N'TABLE', N'timesheet_day', N'COLUMN', N'day_status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'what HR marked on the day: absent, half_day, short_day', N'SCHEMA', N'att', N'TABLE', N'timesheet_day', N'COLUMN', N'marked_status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the approved leave covering the day', N'SCHEMA', N'att', N'TABLE', N'timesheet_day', N'COLUMN', N'leave_request_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'HR edited the day; processing keeps the edited times unless told to overwrite', N'SCHEMA', N'att', N'TABLE', N'timesheet_day', N'COLUMN', N'is_manually_updated';
EXEC sys.sp_addextendedproperty N'MS_Description', N'locked once payroll has used it; processing and edits leave it alone', N'SCHEMA', N'att', N'TABLE', N'timesheet_day', N'COLUMN', N'is_frozen';
EXEC sys.sp_addextendedproperty N'MS_Description', N'computed result for one employee, one day', N'SCHEMA', N'att', N'TABLE', N'timesheet_day';
EXEC sys.sp_addextendedproperty N'MS_Description', N'several per day: late, early, grace, overtime, missing_punch, relaxation, official_visit, half_leave, short_leave', N'SCHEMA', N'att', N'TABLE', N'timesheet_flag';
EXEC sys.sp_addextendedproperty N'MS_Description', N'breaks taken on the day, from punches or entered by HR', N'SCHEMA', N'att', N'TABLE', N'timesheet_break';
EXEC sys.sp_addextendedproperty N'MS_Description', N'daily, monthly', N'SCHEMA', N'att', N'TABLE', N'overtime_policy', N'COLUMN', N'period';
EXEC sys.sp_addextendedproperty N'MS_Description', N'how overtime minutes convert to leave or a day (design: Overtime Policy)', N'SCHEMA', N'att', N'TABLE', N'overtime_policy';
EXEC sys.sp_addextendedproperty N'MS_Description', N'full_day, leave', N'SCHEMA', N'att', N'TABLE', N'overtime_policy_slab', N'COLUMN', N'encashment_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'when encashment_type is leave', N'SCHEMA', N'att', N'TABLE', N'overtime_policy_slab', N'COLUMN', N'leave_type_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'No of Leaves Allowed, per tenure', N'SCHEMA', N'lv', N'TABLE', N'leave_type', N'COLUMN', N'allowance';
EXEC sys.sp_addextendedproperty N'MS_Description', N'refuse, note (Do When Attachment is Required)', N'SCHEMA', N'lv', N'TABLE', N'leave_type', N'COLUMN', N'attachment_rule';
EXEC sys.sp_addextendedproperty N'MS_Description', N'any, male, female', N'SCHEMA', N'lv', N'TABLE', N'leave_type', N'COLUMN', N'gender';
EXEC sys.sp_addextendedproperty N'MS_Description', N'any, single, married', N'SCHEMA', N'lv', N'TABLE', N'leave_type', N'COLUMN', N'marital_status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'yearly, monthly, employment', N'SCHEMA', N'lv', N'TABLE', N'leave_type', N'COLUMN', N'tenure';
EXEC sys.sp_addextendedproperty N'MS_Description', N'flat, experience', N'SCHEMA', N'lv', N'TABLE', N'leave_type', N'COLUMN', N'balance_basis';
EXEC sys.sp_addextendedproperty N'MS_Description', N'tenures unused days may pile up over; NULL = no cap', N'SCHEMA', N'lv', N'TABLE', N'leave_type', N'COLUMN', N'accumulative_count';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Settings -> Leave Types ("Add Leave Types")', N'SCHEMA', N'lv', N'TABLE', N'leave_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Balance According to = Experience', N'SCHEMA', N'lv', N'TABLE', N'leave_type_experience_slab';
EXEC sys.sp_addextendedproperty N'MS_Description', N'with Short Leave', N'SCHEMA', N'lv', N'TABLE', N'leave_type_short_slab';
EXEC sys.sp_addextendedproperty N'MS_Description', N'distribution, half_short', N'SCHEMA', N'lv', N'TABLE', N'leave_policy', N'COLUMN', N'policy_kind';
EXEC sys.sp_addextendedproperty N'MS_Description', N'company (everyone), employee (the enrolled)', N'SCHEMA', N'lv', N'TABLE', N'leave_policy', N'COLUMN', N'policy_level';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Settings -> Leave Policies', N'SCHEMA', N'lv', N'TABLE', N'leave_policy';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the types a distribution policy gives, with its own allowance', N'SCHEMA', N'lv', N'TABLE', N'leave_policy_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'enrolment in an employee-level policy', N'SCHEMA', N'lv', N'TABLE', N'leave_policy_employee';
EXEC sys.sp_addextendedproperty N'MS_Description', N'leave year (year the company fiscal year starts in)', N'SCHEMA', N'lv', N'TABLE', N'leave_ledger', N'COLUMN', N'fiscal_year';
EXEC sys.sp_addextendedproperty N'MS_Description', N'+ credit, − debit', N'SCHEMA', N'lv', N'TABLE', N'leave_ledger', N'COLUMN', N'days';
EXEC sys.sp_addextendedproperty N'MS_Description', N'opening, allotment, earned, carry_forward, adjustment, overtime, availed, encashed, penalty, restored', N'SCHEMA', N'lv', N'TABLE', N'leave_ledger', N'COLUMN', N'reason';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional; availed and restored postings', N'SCHEMA', N'lv', N'TABLE', N'leave_ledger', N'COLUMN', N'request_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional; penalty postings', N'SCHEMA', N'lv', N'TABLE', N'leave_ledger', N'COLUMN', N'warning_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'every change to a balance; balance = sum', N'SCHEMA', N'lv', N'TABLE', N'leave_ledger';
EXEC sys.sp_addextendedproperty N'MS_Description', N'overtime, earned_salary, per_hour_rate, overnight', N'SCHEMA', N'lv', N'TABLE', N'leave_encashment', N'COLUMN', N'basis';
EXEC sys.sp_addextendedproperty N'MS_Description', N'payroll, manual', N'SCHEMA', N'lv', N'TABLE', N'leave_encashment', N'COLUMN', N'mode';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Payroll -> Leave Encashment (one run for a type and year)', N'SCHEMA', N'lv', N'TABLE', N'leave_encashment';
EXEC sys.sp_addextendedproperty N'MS_Description', N'leave, punch, relaxation, official_visit, work_from_home, overtime, rest_day, shift_swap, promotion, transfer, resignation, loan, travel, expense, air_ticket, requisition, task_extension', N'SCHEMA', N'req', N'TABLE', N'request_type', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'detail table req_<kind> and effect <schema>.usp_request_apply_<kind>', N'SCHEMA', N'req', N'TABLE', N'request_type', N'COLUMN', N'kind';
EXEC sys.sp_addextendedproperty N'MS_Description', N'request code prefix: RQ-<prefix>-0001', N'SCHEMA', N'req', N'TABLE', N'request_type', N'COLUMN', N'prefix';
EXEC sys.sp_addextendedproperty N'MS_Description', N'filed by HR for an employee, never for oneself (promotion, transfer)', N'SCHEMA', N'req', N'TABLE', N'request_type', N'COLUMN', N'is_admin_only';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the fixed list of request types (reference data, every company); see comparison/04-requests.md', N'SCHEMA', N'req', N'TABLE', N'request_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'RQ-LV-0001', N'SCHEMA', N'req', N'TABLE', N'request', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who it is for', N'SCHEMA', N'req', N'TABLE', N'request', N'COLUMN', N'employee_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the Count column: days (leave, WFH, rest days) or 1', N'SCHEMA', N'req', N'TABLE', N'request', N'COLUMN', N'days';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the application text (written by hand or generated)', N'SCHEMA', N'req', N'TABLE', N'request', N'COLUMN', N'application';
EXEC sys.sp_addextendedproperty N'MS_Description', N'pending, approved, rejected, cancelling, cancelled', N'SCHEMA', N'req', N'TABLE', N'request', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the flow (version) the request is walking now; cancellation flow while cancelling', N'SCHEMA', N'req', N'TABLE', N'request', N'COLUMN', N'approval_flow_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'WFH cancellation: the days asked for, a JSON list of yyyy-MM-dd (stored only; open product question R2)', N'SCHEMA', N'req', N'TABLE', N'request', N'COLUMN', N'cancel_dates';
EXEC sys.sp_addextendedproperty N'MS_Description', N'WFH cancellation: from this time (stored only; R2)', N'SCHEMA', N'req', N'TABLE', N'request', N'COLUMN', N'cancel_start_time';
EXEC sys.sp_addextendedproperty N'MS_Description', N'WFH cancellation: to this time (stored only; R2)', N'SCHEMA', N'req', N'TABLE', N'request', N'COLUMN', N'cancel_end_time';
EXEC sys.sp_addextendedproperty N'MS_Description', N'deleted by the requester before anyone acted (kept for audit)', N'SCHEMA', N'req', N'TABLE', N'request', N'COLUMN', N'is_deleted';
EXEC sys.sp_addextendedproperty N'MS_Description', N'shared header for every request', N'SCHEMA', N'req', N'TABLE', N'request';
EXEC sys.sp_addextendedproperty N'MS_Description', N'each day a multi-day request covers (leave, work from home, rest days)', N'SCHEMA', N'req', N'TABLE', N'request_day';
EXEC sys.sp_addextendedproperty N'MS_Description', N'mandatory, voluntary (the bulk form''s Type; empty on a single application)', N'SCHEMA', N'req', N'TABLE', N'req_overtime', N'COLUMN', N'overtime_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'filed together with others (Create Bulk Overtime Request)', N'SCHEMA', N'req', N'TABLE', N'req_overtime', N'COLUMN', N'bulk_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the slab they fell in, copied (policy edits replace slabs)', N'SCHEMA', N'req', N'TABLE', N'req_overtime', N'COLUMN', N'slab_min_minutes';
EXEC sys.sp_addextendedproperty N'MS_Description', N'full_day, leave (copied from the slab)', N'SCHEMA', N'req', N'TABLE', N'req_overtime', N'COLUMN', N'encashment_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one overtime request (the Apply form, or one person of a bulk filing)', N'SCHEMA', N'req', N'TABLE', N'req_overtime';
EXEC sys.sp_addextendedproperty N'MS_Description', N'requests filed together for several people in one all-or-nothing call (bulk overtime)', N'SCHEMA', N'req', N'TABLE', N'request_bulk';
EXEC sys.sp_addextendedproperty N'MS_Description', N'benefits ticked on a promotion (many to many)', N'SCHEMA', N'req', N'TABLE', N'req_promotion_benefit';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one expense request = the claims prepared together ("Generate Claim", "Submit All")', N'SCHEMA', N'req', N'TABLE', N'req_expense';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Expense Claim Title*', N'SCHEMA', N'req', N'TABLE', N'expense_line', N'COLUMN', N'title';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Expense Claim Date (today when empty)', N'SCHEMA', N'req', N'TABLE', N'expense_line', N'COLUMN', N'claim_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the approver may lower it (0 = not reimbursed); the amount when left empty', N'SCHEMA', N'req', N'TABLE', N'expense_line', N'COLUMN', N'approved_amount';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the receipt', N'SCHEMA', N'req', N'TABLE', N'expense_line', N'COLUMN', N'file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one claim of an expense request, each with its own receipt', N'SCHEMA', N'req', N'TABLE', N'expense_line';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the ticket', N'SCHEMA', N'req', N'TABLE', N'req_air_ticket', N'COLUMN', N'file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'an air ticket the employee paid and claims back', N'SCHEMA', N'req', N'TABLE', N'req_air_ticket';
EXEC sys.sp_addextendedproperty N'MS_Description', N'stationery, it_equipment, furniture, asset, consumable, service, other', N'SCHEMA', N'req', N'TABLE', N'req_requisition', N'COLUMN', N'requisition_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the lines'' quantity x estimated unit cost', N'SCHEMA', N'req', N'TABLE', N'req_requisition', N'COLUMN', N'estimated_amount';
EXEC sys.sp_addextendedproperty N'MS_Description', N'items, assets or stationery wanted; approval only, then fulfilled by the admin side', N'SCHEMA', N'req', N'TABLE', N'req_requisition';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the reimbursement pay item claims of this category are paid under; empty: the default below', N'SCHEMA', N'req', N'TABLE', N'expense_category', N'COLUMN', N'pay_item_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'per claim; empty: no limit', N'SCHEMA', N'req', N'TABLE', N'expense_category', N'COLUMN', N'max_amount';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Request Settings -> Expense Categories (Travel Fee, Tech & Soft, Venue Rental ...)', N'SCHEMA', N'req', N'TABLE', N'expense_category';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Request Settings -> Reimbursement: how approved claims reach payroll (one row per company)', N'SCHEMA', N'req', N'TABLE', N'reimbursement_setting';
EXEC sys.sp_addextendedproperty N'MS_Description', N'request, cancellation', N'SCHEMA', N'req', N'TABLE', N'approval_flow', N'COLUMN', N'purpose';
EXEC sys.sp_addextendedproperty N'MS_Description', N'company, branch, department, employee (the most specific active flow wins)', N'SCHEMA', N'req', N'TABLE', N'approval_flow', N'COLUMN', N'scope_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the branch, department or employee; empty for company', N'SCHEMA', N'req', N'TABLE', N'approval_flow', N'COLUMN', N'scope_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'0 once a newer version replaced it or it was deleted', N'SCHEMA', N'req', N'TABLE', N'approval_flow', N'COLUMN', N'is_current';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one version of a flow; editing saves a new version so requests on the way keep theirs', N'SCHEMA', N'req', N'TABLE', N'approval_flow';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the node number shown in the editor; Next / If True / If False point at these', N'SCHEMA', N'req', N'TABLE', N'approval_node', N'COLUMN', N'step_no';
EXEC sys.sp_addextendedproperty N'MS_Description', N'employee, line_manager, hod, branch_manager, final_authority, role, or an authority (team_lead, hr_manager, finance_manager ...)', N'SCHEMA', N'req', N'TABLE', N'approval_node', N'COLUMN', N'approver_kind';
EXEC sys.sp_addextendedproperty N'MS_Description', N'when approver_kind = role: anyone holding the role decides', N'SCHEMA', N'req', N'TABLE', N'approval_node', N'COLUMN', N'role_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'as typed: days > 3, amount >= 100000, department_id = 12', N'SCHEMA', N'req', N'TABLE', N'approval_node', N'COLUMN', N'expression';
EXEC sys.sp_addextendedproperty N'MS_Description', N'parsed from expression: days, amount, minutes, department_id, branch_id, location_id, grade_id, designation_id, employment_type_id', N'SCHEMA', N'req', N'TABLE', N'approval_node', N'COLUMN', N'condition_field';
EXEC sys.sp_addextendedproperty N'MS_Description', N'=, <>, >, >=, <, <=', N'SCHEMA', N'req', N'TABLE', N'approval_node', N'COLUMN', N'condition_operator';
EXEC sys.sp_addextendedproperty N'MS_Description', N'empty: the next node by number', N'SCHEMA', N'req', N'TABLE', N'approval_node', N'COLUMN', N'next_node_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the approver may change the request''s details', N'SCHEMA', N'req', N'TABLE', N'approval_node', N'COLUMN', N'can_edit';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a consent step: agree or disagree, the flow goes on either way', N'SCHEMA', N'req', N'TABLE', N'approval_node', N'COLUMN', N'can_disagree';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"On Looker": informed only, does not decide', N'SCHEMA', N'req', N'TABLE', N'approval_node', N'COLUMN', N'is_observer';
EXEC sys.sp_addextendedproperty N'MS_Description', N'team_lead, hr_manager, operations_manager, finance_manager, director, compliance_officer, project_manager, admin_supervisor, it_administrator, area_manager, admin_manager', N'SCHEMA', N'req', N'TABLE', N'approval_authority', N'COLUMN', N'authority';
EXEC sys.sp_addextendedproperty N'MS_Description', N'empty: every request type', N'SCHEMA', N'req', N'TABLE', N'approval_authority', N'COLUMN', N'request_type_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'empty: every branch', N'SCHEMA', N'req', N'TABLE', N'approval_authority', N'COLUMN', N'branch_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'empty: every department', N'SCHEMA', N'req', N'TABLE', N'approval_authority', N'COLUMN', N'department_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who holds an authority (HR Manager, Finance Manager ...): the Request Flow screen of the requirements', N'SCHEMA', N'req', N'TABLE', N'approval_authority';
EXEC sys.sp_addextendedproperty N'MS_Description', N'block a request type for a company between two dates', N'SCHEMA', N'req', N'TABLE', N'request_restriction';
EXEC sys.sp_addextendedproperty N'MS_Description', N'empty for the submit, cancel and colleague-consent rows', N'SCHEMA', N'req', N'TABLE', N'request_step', N'COLUMN', N'approval_node_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'request, cancellation', N'SCHEMA', N'req', N'TABLE', N'request_step', N'COLUMN', N'purpose';
EXEC sys.sp_addextendedproperty N'MS_Description', N'copied from the node (or colleague, requester)', N'SCHEMA', N'req', N'TABLE', N'request_step', N'COLUMN', N'approver_kind';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who should act', N'SCHEMA', N'req', N'TABLE', N'request_step', N'COLUMN', N'approver_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'when any holder of a role may act', N'SCHEMA', N'req', N'TABLE', N'request_step', N'COLUMN', N'approver_role_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who did act (delegate if different)', N'SCHEMA', N'req', N'TABLE', N'request_step', N'COLUMN', N'acted_by_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a consent step (Can Disagree node, or the colleague of a shift swap)', N'SCHEMA', N'req', N'TABLE', N'request_step', N'COLUMN', N'is_consent';
EXEC sys.sp_addextendedproperty N'MS_Description', N'submitted, pending, approved, rejected, consented, disagreed, forwarded, skipped, informed, cancel_requested, withdrawn, cancelled', N'SCHEMA', N'req', N'TABLE', N'request_step', N'COLUMN', N'action_taken';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one row per event and approver action; the Flow and History popups', N'SCHEMA', N'req', N'TABLE', N'request_step';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional until payroll formulas exist (Formula* in the requirements)', N'SCHEMA', N'loan', N'TABLE', N'loan_type', N'COLUMN', N'formula_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Loan & Advance Types settings', N'SCHEMA', N'loan', N'TABLE', N'loan_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Employment Contract Type*: the contract types that may apply', N'SCHEMA', N'loan', N'TABLE', N'loan_type_employment_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'bank, cash, pay_order, cheque', N'SCHEMA', N'loan', N'TABLE', N'loan', N'COLUMN', N'payment_method';
EXEC sys.sp_addextendedproperty N'MS_Description', N'first installment month (from the repayment date)', N'SCHEMA', N'loan', N'TABLE', N'loan', N'COLUMN', N'start_month';
EXEC sys.sp_addextendedproperty N'MS_Description', N'active, settled, non_payable, written_off', N'SCHEMA', N'loan', N'TABLE', N'loan', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'created when a loan request is finally approved', N'SCHEMA', N'loan', N'TABLE', N'loan';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the Repayment tab; payroll marks rows paid', N'SCHEMA', N'loan', N'TABLE', N'loan_installment';
EXEC sys.sp_addextendedproperty N'MS_Description', N'TXS-0004, from core.number_sequence prefix TXS-', N'SCHEMA', N'pay', N'TABLE', N'tax_structure', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'flat, percentage (optional)', N'SCHEMA', N'pay', N'TABLE', N'tax_structure', N'COLUMN', N'surcharge_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Settings -> Tax -> Tax Structure', N'SCHEMA', N'pay', N'TABLE', N'tax_structure';
EXEC sys.sp_addextendedproperty N'MS_Description', N'tax = fixed_amount + (annual taxable - min_amount) x percentage / 100', N'SCHEMA', N'pay', N'TABLE', N'tax_slab';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Settings -> Tax -> Tax Rebate; lowers the year''s tax', N'SCHEMA', N'pay', N'TABLE', N'tax_rebate';
EXEC sys.sp_addextendedproperty N'MS_Description', N'0 for the formulas the system adds for its own pay items', N'SCHEMA', N'pay', N'TABLE', N'formula', N'COLUMN', N'is_custom';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Pay Components -> Formulas; {variables}, pay items and other formulas', N'SCHEMA', N'pay', N'TABLE', N'formula';
EXEC sys.sp_addextendedproperty N'MS_Description', N'earning, deduction, reimbursement, employee_data, other', N'SCHEMA', N'pay', N'TABLE', N'pay_item', N'COLUMN', N'item_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'fixed (per-person amount), manual (typed on the payslip), formula', N'SCHEMA', N'pay', N'TABLE', N'pay_item', N'COLUMN', N'calculation_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'current_month, remaining_months', N'SCHEMA', N'pay', N'TABLE', N'pay_item', N'COLUMN', N'tax_distribution';
EXEC sys.sp_addextendedproperty N'MS_Description', N'default for the Taxable tick when the item is added to a payroll', N'SCHEMA', N'pay', N'TABLE', N'pay_item', N'COLUMN', N'is_taxable';
EXEC sys.sp_addextendedproperty N'MS_Description', N'true/false expression; blank = everyone', N'SCHEMA', N'pay', N'TABLE', N'pay_item', N'COLUMN', N'eligibility_expression';
EXEC sys.sp_addextendedproperty N'MS_Description', N'salary, overtime, absent_deduction, leave_deduction, short_deduction, penalty_deduction, loan_deduction, leave_encashment, tax', N'SCHEMA', N'pay', N'TABLE', N'pay_item', N'COLUMN', N'system_code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Pay Components -> Pay Items', N'SCHEMA', N'pay', N'TABLE', N'pay_item';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Pay Components -> Rules: evaluated per person on every run, posts to an employee account', N'SCHEMA', N'pay', N'TABLE', N'pay_rule';
EXEC sys.sp_addextendedproperty N'MS_Description', N'ACT-0001, from core.number_sequence prefix ACT-', N'SCHEMA', N'pay', N'TABLE', N'account_type', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'benefit, leave_quota, custom_pay_item', N'SCHEMA', N'pay', N'TABLE', N'account_type', N'COLUMN', N'category';
EXEC sys.sp_addextendedproperty N'MS_Description', N'reward_benefit, lv.leave_type or pay_item, by category', N'SCHEMA', N'pay', N'TABLE', N'account_type', N'COLUMN', N'ref_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Settings -> Account Type', N'SCHEMA', N'pay', N'TABLE', N'account_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Settings -> Rewards -> Benefits ("Benefit Create")', N'SCHEMA', N'pay', N'TABLE', N'reward_benefit';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who gets it: employees, or employee groups when is_group', N'SCHEMA', N'pay', N'TABLE', N'reward_benefit_member';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Additional Information" fields of a benefit', N'SCHEMA', N'pay', N'TABLE', N'reward_benefit_field';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Settings -> Rewards -> Incentives (stored; no sales source yet)', N'SCHEMA', N'pay', N'TABLE', N'sales_incentive';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Settings -> Disbursement Banks (the company''s paying accounts)', N'SCHEMA', N'pay', N'TABLE', N'disbursement_bank';
EXEC sys.sp_addextendedproperty N'MS_Description', N'PR-00008, from core.number_sequence prefix PR-', N'SCHEMA', N'pay', N'TABLE', N'payroll', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'monthly, daily_wage', N'SCHEMA', N'pay', N'TABLE', N'payroll', N'COLUMN', N'kind';
EXEC sys.sp_addextendedproperty N'MS_Description', N'monthly runs: first day of the month', N'SCHEMA', N'pay', N'TABLE', N'payroll', N'COLUMN', N'payroll_month';
EXEC sys.sp_addextendedproperty N'MS_Description', N'daily-wage runs', N'SCHEMA', N'pay', N'TABLE', N'payroll', N'COLUMN', N'work_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'from_date, month_end', N'SCHEMA', N'pay', N'TABLE', N'payroll', N'COLUMN', N'processing_mode';
EXEC sys.sp_addextendedproperty N'MS_Description', N'actual, fixed', N'SCHEMA', N'pay', N'TABLE', N'payroll', N'COLUMN', N'applicable_days';
EXEC sys.sp_addextendedproperty N'MS_Description', N'open, running, on_hold, closed', N'SCHEMA', N'pay', N'TABLE', N'payroll', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Payrolls -> Monthly and Daily Wages', N'SCHEMA', N'pay', N'TABLE', N'payroll';
EXEC sys.sp_addextendedproperty N'MS_Description', N'which pay items this run uses', N'SCHEMA', N'pay', N'TABLE', N'payroll_pay_item';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who is in the run', N'SCHEMA', N'pay', N'TABLE', N'payroll_employee';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Payrolls History', N'SCHEMA', N'pay', N'TABLE', N'payroll_run_log';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Payrolls History Error', N'SCHEMA', N'pay', N'TABLE', N'payroll_run_error';
EXEC sys.sp_addextendedproperty N'MS_Description', N'ready, on_hold, released', N'SCHEMA', N'pay', N'TABLE', N'payslip', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'bank, cash', N'SCHEMA', N'pay', N'TABLE', N'payslip', N'COLUMN', N'payment_method';
EXEC sys.sp_addextendedproperty N'MS_Description', N'daily wages: totals typed by hand', N'SCHEMA', N'pay', N'TABLE', N'payslip', N'COLUMN', N'is_manually_updated';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one per person per run; final settlement slips have no run', N'SCHEMA', N'pay', N'TABLE', N'payslip';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Balances -> Opening Balance; added to the pay item in that month''s run', N'SCHEMA', N'pay', N'TABLE', N'opening_balance';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Provident Fund, EOBI, medical … ledger (Employee Accounts, Statement)', N'SCHEMA', N'pay', N'TABLE', N'employee_account_entry';
EXEC sys.sp_addextendedproperty N'MS_Description', N'expense_reimbursement, salary_advance, bonus, travel_allowance, daily_wage', N'SCHEMA', N'pay', N'TABLE', N'voucher', N'COLUMN', N'voucher_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'attachment', N'SCHEMA', N'pay', N'TABLE', N'voucher', N'COLUMN', N'file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'daily-wage voucher', N'SCHEMA', N'pay', N'TABLE', N'voucher', N'COLUMN', N'payroll_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'approver''s or verifier''s remarks', N'SCHEMA', N'pay', N'TABLE', N'voucher', N'COLUMN', N'remarks';
EXEC sys.sp_addextendedproperty N'MS_Description', N'pending, approved, rejected, processed', N'SCHEMA', N'pay', N'TABLE', N'voucher', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Vouchers / Employee Voucher; daily-wage vouchers', N'SCHEMA', N'pay', N'TABLE', N'voucher';
EXEC sys.sp_addextendedproperty N'MS_Description', N'disabled (mail not set up: nothing sent), queued, sent, failed', N'SCHEMA', N'pay', N'TABLE', N'payroll_close_email', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'people with a released payslip and an e-mail address when it closed', N'SCHEMA', N'pay', N'TABLE', N'payroll_close_email', N'COLUMN', N'recipient_count';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Payroll close e-mail (one per closed monthly run); the people are rows of mail_outbox', N'SCHEMA', N'pay', N'TABLE', N'payroll_close_email';
EXEC sys.sp_addextendedproperty N'MS_Description', N'pay.payroll (close e-mail), hr.employee_salary (salary revision letter)', N'SCHEMA', N'pay', N'TABLE', N'mail_outbox', N'COLUMN', N'entity_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'no FK: the revision row belongs to hr and may be deleted there', N'SCHEMA', N'pay', N'TABLE', N'mail_outbox', N'COLUMN', N'entity_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'disabled, queued, sent, failed', N'SCHEMA', N'pay', N'TABLE', N'mail_outbox', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'payroll e-mails, one row per person: close e-mails and salary revision letters', N'SCHEMA', N'pay', N'TABLE', N'mail_outbox';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Assets -> Asset Types', N'SCHEMA', N'sep', N'TABLE', N'asset_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'AST-00001', N'SCHEMA', N'sep', N'TABLE', N'asset', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'serial / identification number', N'SCHEMA', N'sep', N'TABLE', N'asset', N'COLUMN', N'identification_no';
EXEC sys.sp_addextendedproperty N'MS_Description', N'old, new, fair (condition when recorded)', N'SCHEMA', N'sep', N'TABLE', N'asset', N'COLUMN', N'asset_condition';
EXEC sys.sp_addextendedproperty N'MS_Description', N'active, damaged, lost, decommissioned; who holds it comes from the open asset_allocation', N'SCHEMA', N'sep', N'TABLE', N'asset', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'attachment', N'SCHEMA', N'sep', N'TABLE', N'asset', N'COLUMN', N'file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Assets -> Company Assets', N'SCHEMA', N'sep', N'TABLE', N'asset';
EXEC sys.sp_addextendedproperty N'MS_Description', N'allocated, deallocated', N'SCHEMA', N'sep', N'TABLE', N'asset_allocation', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'good, fair, damaged (at deallocation)', N'SCHEMA', N'sep', N'TABLE', N'asset_allocation', N'COLUMN', N'return_condition';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one row per hand-over; deallocated_on NULL while the employee holds it', N'SCHEMA', N'sep', N'TABLE', N'asset_allocation';
EXEC sys.sp_addextendedproperty N'MS_Description', N'resignation, termination, retirement, other', N'SCHEMA', N'sep', N'TABLE', N'end_of_employment', N'COLUMN', N'reason';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the Notice Period tick', N'SCHEMA', N'sep', N'TABLE', N'end_of_employment', N'COLUMN', N'serve_notice';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the day it is made when there is no notice period', N'SCHEMA', N'sep', N'TABLE', N'end_of_employment', N'COLUMN', N'last_working_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'off-boarding checklist "Asset Clear" date', N'SCHEMA', N'sep', N'TABLE', N'end_of_employment', N'COLUMN', N'asset_clear_by_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'attachment', N'SCHEMA', N'sep', N'TABLE', N'end_of_employment', N'COLUMN', N'file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'pending, completed', N'SCHEMA', N'sep', N'TABLE', N'end_of_employment', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'End of Employment (All / Pending / Completed)', N'SCHEMA', N'sep', N'TABLE', N'end_of_employment';
EXEC sys.sp_addextendedproperty N'MS_Description', N'in_progress, approved', N'SCHEMA', N'sep', N'TABLE', N'asset_clearance', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Asset Clearance Form, one per leaver at a time', N'SCHEMA', N'sep', N'TABLE', N'asset_clearance';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one Asset Details block: an allocation being cleared', N'SCHEMA', N'sep', N'TABLE', N'asset_clearance_item';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the signed settlement letter, given on Close FS', N'SCHEMA', N'sep', N'TABLE', N'final_settlement', N'COLUMN', N'file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'started by end of employment; payroll fills the payslip and closes it', N'SCHEMA', N'sep', N'TABLE', N'final_settlement';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Settings -> Off Boarding Checklist (ECL-00001)', N'SCHEMA', N'sep', N'TABLE', N'offboarding_checklist';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Additional Information": number, string, date, boolean', N'SCHEMA', N'sep', N'TABLE', N'checklist_field';
EXEC sys.sp_addextendedproperty N'MS_Description', N'given, or the next JOB-0001 number', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Marketing Executive"', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'title';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: the Manpower seat it fills (vacancies cannot exceed its open seats)', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'open_position_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: org.job_title, given to the employee on hire', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'job_title_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'designation_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: scope and the hired employee''s department', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'department_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: "Station"; scope and the hired employee''s branch', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'branch_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: "Enter City" (its state is "Enter State")', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'city_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'on_site, remote, hybrid', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'work_mode';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Experience From"', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'experience_from_years';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Experience To"', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'experience_to_years';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"No. of Vacancies"', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'vacancies';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Posted Date"; set on publish when blank', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'posted_on';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Last Date to Apply"', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'apply_by';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Close Date"', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'close_on';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Salary From"', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'salary_from';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Salary To"', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'salary_to';
EXEC sys.sp_addextendedproperty N'MS_Description', N'show the range on the careers page', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'is_salary_visible';
EXEC sys.sp_addextendedproperty N'MS_Description', N'rich text (HTML) "Job Description" editor', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'description';
EXEC sys.sp_addextendedproperty N'MS_Description', N'skills and qualifications', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'requirements';
EXEC sys.sp_addextendedproperty N'MS_Description', N'draft, open, on_hold, closed', N'SCHEMA', N'rec', N'TABLE', N'job_opening', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"New Job Position": a vacancy advertised and recruited for', N'SCHEMA', N'rec', N'TABLE', N'job_opening';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional', N'SCHEMA', N'rec', N'TABLE', N'applicant', N'COLUMN', N'city_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'total years of experience', N'SCHEMA', N'rec', N'TABLE', N'applicant', N'COLUMN', N'experience_years';
EXEC sys.sp_addextendedproperty N'MS_Description', N'career_site, referral, job_board, linkedin, walk_in, agency, other', N'SCHEMA', N'rec', N'TABLE', N'applicant', N'COLUMN', N'source';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the CV, uploaded first through /api/files', N'SCHEMA', N'rec', N'TABLE', N'applicant', N'COLUMN', N'cv_file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a candidate in the talent pool; one per e-mail address per company', N'SCHEMA', N'rec', N'TABLE', N'applicant';
EXEC sys.sp_addextendedproperty N'MS_Description', N'how this application came; defaults to the applicant''s source', N'SCHEMA', N'rec', N'TABLE', N'application', N'COLUMN', N'source';
EXEC sys.sp_addextendedproperty N'MS_Description', N'applied, screening, shortlisted, interview, offer, hired, rejected, withdrawn', N'SCHEMA', N'rec', N'TABLE', N'application', N'COLUMN', N'stage';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the stage it was rejected or withdrawn at ("non qualified" = rejected at screening)', N'SCHEMA', N'rec', N'TABLE', N'application', N'COLUMN', N'rejected_stage';
EXEC sys.sp_addextendedproperty N'MS_Description', N'set on hire: the employee created from this application', N'SCHEMA', N'rec', N'TABLE', N'application', N'COLUMN', N'employee_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one applicant for one opening, moving through the pipeline', N'SCHEMA', N'rec', N'TABLE', N'application';
EXEC sys.sp_addextendedproperty N'MS_Description', N'every stage change, for the pipeline timeline and the dashboard', N'SCHEMA', N'rec', N'TABLE', N'application_stage_history';
EXEC sys.sp_addextendedproperty N'MS_Description', N'1, 2, 3 ... per application', N'SCHEMA', N'rec', N'TABLE', N'interview', N'COLUMN', N'round_no';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"HR interview", "Technical"', N'SCHEMA', N'rec', N'TABLE', N'interview', N'COLUMN', N'title';
EXEC sys.sp_addextendedproperty N'MS_Description', N'in_person, phone, video', N'SCHEMA', N'rec', N'TABLE', N'interview', N'COLUMN', N'mode';
EXEC sys.sp_addextendedproperty N'MS_Description', N'local wall-clock time, like attendance times', N'SCHEMA', N'rec', N'TABLE', N'interview', N'COLUMN', N'scheduled_at';
EXEC sys.sp_addextendedproperty N'MS_Description', N'address or meeting link', N'SCHEMA', N'rec', N'TABLE', N'interview', N'COLUMN', N'venue';
EXEC sys.sp_addextendedproperty N'MS_Description', N'scheduled, completed, cancelled, no_show', N'SCHEMA', N'rec', N'TABLE', N'interview', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'passed, failed, on_hold (set when completed)', N'SCHEMA', N'rec', N'TABLE', N'interview', N'COLUMN', N'result';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one round with one candidate ("re-interview" is a further round)', N'SCHEMA', N'rec', N'TABLE', N'interview';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the panel of an interview', N'SCHEMA', N'rec', N'TABLE', N'interview_interviewer';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the interviewer', N'SCHEMA', N'rec', N'TABLE', N'interview_evaluation', N'COLUMN', N'employee_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'1 to 5', N'SCHEMA', N'rec', N'TABLE', N'interview_evaluation', N'COLUMN', N'rating';
EXEC sys.sp_addextendedproperty N'MS_Description', N'strong_hire, hire, no_hire, strong_no_hire', N'SCHEMA', N'rec', N'TABLE', N'interview_evaluation', N'COLUMN', N'recommendation';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one interviewer''s feedback on one interview', N'SCHEMA', N'rec', N'TABLE', N'interview_evaluation';
EXEC sys.sp_addextendedproperty N'MS_Description', N'gross a month (or a day / an hour by salary_frequency)', N'SCHEMA', N'rec', N'TABLE', N'offer', N'COLUMN', N'offered_salary';
EXEC sys.sp_addextendedproperty N'MS_Description', N'monthly, daily, hourly', N'SCHEMA', N'rec', N'TABLE', N'offer', N'COLUMN', N'salary_frequency';
EXEC sys.sp_addextendedproperty N'MS_Description', N'0 = no probation', N'SCHEMA', N'rec', N'TABLE', N'offer', N'COLUMN', N'probation_months';
EXEC sys.sp_addextendedproperty N'MS_Description', N'draft, sent, accepted, declined, withdrawn', N'SCHEMA', N'rec', N'TABLE', N'offer', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the candidate''s answer, the reason for declining', N'SCHEMA', N'rec', N'TABLE', N'offer', N'COLUMN', N'response_remarks';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the offer made to a candidate; a revised offer is a new row', N'SCHEMA', N'rec', N'TABLE', N'offer';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Settings -> Rejection reasons', N'SCHEMA', N'rec', N'TABLE', N'rejection_reason';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"2024", "2024-2025"', N'SCHEMA', N'mp', N'TABLE', N'budget_duration', N'COLUMN', N'name';
EXEC sys.sp_addextendedproperty N'MS_Description', N'IsCurrentBudgetDurationPeriod: at most one per company (kept by mp.usp_budget_duration_save)', N'SCHEMA', N'mp', N'TABLE', N'budget_duration', N'COLUMN', N'is_current';
EXEC sys.sp_addextendedproperty N'MS_Description', N'E-Budget Settings -> Budget Duration; the "Plan Year" of plans and budgets', N'SCHEMA', N'mp', N'TABLE', N'budget_duration';
EXEC sys.sp_addextendedproperty N'MS_Description', N'given, or the next POS-0001 number', N'SCHEMA', N'mp', N'TABLE', N'position', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'shown as "Station" (required on the form)', N'SCHEMA', N'mp', N'TABLE', N'position', N'COLUMN', N'branch_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'shown as "Position Title" (org.job_title)', N'SCHEMA', N'mp', N'TABLE', N'position', N'COLUMN', N'job_title_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional', N'SCHEMA', N'mp', N'TABLE', N'position', N'COLUMN', N'division_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who holds it, blank if open', N'SCHEMA', N'mp', N'TABLE', N'position', N'COLUMN', N'employee_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'active, inactive', N'SCHEMA', N'mp', N'TABLE', N'position', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'E-Budget Settings -> Employee Position: an approved seat', N'SCHEMA', N'mp', N'TABLE', N'position';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the band in force is the latest one on or before the day asked about', N'SCHEMA', N'mp', N'TABLE', N'position_salary_range', N'COLUMN', N'effective_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the Min / Max Salary of the Employee Position form, kept over time', N'SCHEMA', N'mp', N'TABLE', N'position_salary_range';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan', N'COLUMN', N'division_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Station"', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan', N'COLUMN', N'branch_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'sum of the lines'' total_salary (computed by the procedure)', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan', N'COLUMN', N'monthly_amount';
EXEC sys.sp_addextendedproperty N'MS_Description', N'sum of the lines'' annual_gross (computed by the procedure)', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan', N'COLUMN', N'annual_amount';
EXEC sys.sp_addextendedproperty N'MS_Description', N'pending, approved, rejected (follows its budgets)', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Add Planning"; saving submits it and makes its budgets', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan';
EXEC sys.sp_addextendedproperty N'MS_Description', N'new_position, existing_employee', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan_line', N'COLUMN', N'kind';
EXEC sys.sp_addextendedproperty N'MS_Description', N'new-position lines', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan_line', N'COLUMN', N'position_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'existing-employee lines', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan_line', N'COLUMN', N'employee_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the budget this line is counted in', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan_line', N'COLUMN', N'e_budget_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'vacancies on a new-position line; 1 on an existing-employee line', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan_line', N'COLUMN', N'headcount';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Plan Date" from (first day of the month)', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan_line', N'COLUMN', N'start_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Plan Date" to; both inside the plan year', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan_line', N'COLUMN', N'end_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'calendar months from start to end, both counted', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan_line', N'COLUMN', N'months';
EXEC sys.sp_addextendedproperty N'MS_Description', N'existing employees: defaulted from hr.employee_salary', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan_line', N'COLUMN', N'monthly_salary';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a month: (max_salary + allowance) x headcount, or monthly_salary + allowance', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan_line', N'COLUMN', N'total_salary';
EXEC sys.sp_addextendedproperty N'MS_Description', N'total_salary x months', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan_line', N'COLUMN', N'annual_gross';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Plan for New Positions (kind new_position) / Existing Positions (existing_employee)', N'SCHEMA', N'mp', N'TABLE', N'manpower_plan_line';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: blank for a budget added by hand', N'SCHEMA', N'mp', N'TABLE', N'e_budget', N'COLUMN', N'manpower_plan_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the position title the money is for', N'SCHEMA', N'mp', N'TABLE', N'e_budget', N'COLUMN', N'job_title_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'rows are per department in the samples', N'SCHEMA', N'mp', N'TABLE', N'e_budget', N'COLUMN', N'department_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'new seats it opens once approved', N'SCHEMA', N'mp', N'TABLE', N'e_budget', N'COLUMN', N'total_positions';
EXEC sys.sp_addextendedproperty N'MS_Description', N'pending, approved, rejected', N'SCHEMA', N'mp', N'TABLE', N'e_budget', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"E-Budgeting" list and "Budget Approvals"', N'SCHEMA', N'mp', N'TABLE', N'e_budget';
EXEC sys.sp_addextendedproperty N'MS_Description', N'seats the budget approved', N'SCHEMA', N'mp', N'TABLE', N'open_position', N'COLUMN', N'approved_positions';
EXEC sys.sp_addextendedproperty N'MS_Description', N'seats open now (Edit)', N'SCHEMA', N'mp', N'TABLE', N'open_position', N'COLUMN', N'total_positions';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"JD''s" download', N'SCHEMA', N'mp', N'TABLE', N'open_position', N'COLUMN', N'jd_file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'active, closed', N'SCHEMA', N'mp', N'TABLE', N'open_position', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'positions released for hiring when a budget is approved', N'SCHEMA', N'mp', N'TABLE', N'open_position';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the uploading module; also the folder it is stored in', N'SCHEMA', N'core', N'TABLE', N'stored_file', N'COLUMN', N'module';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the original file name, used for downloads only', N'SCHEMA', N'core', N'TABLE', N'stored_file', N'COLUMN', N'name';
EXEC sys.sp_addextendedproperty N'MS_Description', N'relative to the upload root: <company>/<module>/<yyyy>/<mm>/<uuid>.<ext>', N'SCHEMA', N'core', N'TABLE', N'stored_file', N'COLUMN', N'storage_path';
EXEC sys.sp_addextendedproperty N'MS_Description', N'an uploaded file: the bytes on the server''s disk, this row in the database', N'SCHEMA', N'core', N'TABLE', N'stored_file';
EXEC sys.sp_addextendedproperty N'MS_Description', N'any file on any record', N'SCHEMA', N'core', N'TABLE', N'attachment';
EXEC sys.sp_addextendedproperty N'MS_Description', N'every "History" popup reads this; also the access change history (ACC-15)', N'SCHEMA', N'core', N'TABLE', N'audit_log';
EXEC sys.sp_addextendedproperty N'MS_Description', N'switches and values: attendance basic, the 22 payroll options, leave general, overtime', N'SCHEMA', N'core', N'TABLE', N'company_setting';
EXEC sys.sp_addextendedproperty N'MS_Description', N'codes like RQ-, PR-, AST-, TS-', N'SCHEMA', N'core', N'TABLE', N'number_sequence';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Save Preset" on every list', N'SCHEMA', N'core', N'TABLE', N'filter_preset';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the inbox; any module adds rows through core.usp_notification_add', N'SCHEMA', N'core', N'TABLE', N'notification';
EXEC sys.sp_addextendedproperty N'MS_Description', N'HMAC-SHA256 key; shown once when the webhook is created', N'SCHEMA', N'core', N'TABLE', N'webhook', N'COLUMN', N'secret';
EXEC sys.sp_addextendedproperty N'MS_Description', N'JSON list of event types, "module.*" or "*"', N'SCHEMA', N'core', N'TABLE', N'webhook', N'COLUMN', N'events';
EXEC sys.sp_addextendedproperty N'MS_Description', N'consecutive failed deliveries', N'SCHEMA', N'core', N'TABLE', N'webhook', N'COLUMN', N'failure_count';
EXEC sys.sp_addextendedproperty N'MS_Description', N'an outside system told about events (Settings → Integrations); signed with its secret', N'SCHEMA', N'core', N'TABLE', N'webhook';
EXEC sys.sp_addextendedproperty N'MS_Description', N'notification.created, request.approved ...', N'SCHEMA', N'core', N'TABLE', N'outbox_event', N'COLUMN', N'event_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'JSON', N'SCHEMA', N'core', N'TABLE', N'outbox_event', N'COLUMN', N'payload';
EXEC sys.sp_addextendedproperty N'MS_Description', N'every event a module publishes, written in the same transaction as the change', N'SCHEMA', N'core', N'TABLE', N'outbox_event';
EXEC sys.sp_addextendedproperty N'MS_Description', N'pending, delivered, failed', N'SCHEMA', N'core', N'TABLE', N'webhook_delivery', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one event to one webhook, retried with back-off', N'SCHEMA', N'core', N'TABLE', N'webhook_delivery';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: blank when posted by a user with no employee record', N'SCHEMA', N'eng', N'TABLE', N'announcement', N'COLUMN', N'author_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'notice, event', N'SCHEMA', N'eng', N'TABLE', N'announcement', N'COLUMN', N'kind';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the day an event happens (kind event)', N'SCHEMA', N'eng', N'TABLE', N'announcement', N'COLUMN', N'event_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Announcements" list; the dashboards'' Notice Board (kind notice) and Upcoming Events (kind event)', N'SCHEMA', N'eng', N'TABLE', N'announcement';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Mark as read" / "Mark all as read" / "Clear All", per employee', N'SCHEMA', N'eng', N'TABLE', N'announcement_read';
EXEC sys.sp_addextendedproperty N'MS_Description', N'text, up to 5000 characters; blank when the post is only photos or videos', N'SCHEMA', N'eng', N'TABLE', N'post', N'COLUMN', N'body';
EXEC sys.sp_addextendedproperty N'MS_Description', N'public (chip "Public"), department, branch', N'SCHEMA', N'eng', N'TABLE', N'post', N'COLUMN', N'visibility';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the audience when visibility is department (sub-departments included)', N'SCHEMA', N'eng', N'TABLE', N'post', N'COLUMN', N'department_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the audience when visibility is branch', N'SCHEMA', N'eng', N'TABLE', N'post', N'COLUMN', N'branch_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Edit Post" on My Posts', N'SCHEMA', N'eng', N'TABLE', N'post', N'COLUMN', N'edited_at';
EXEC sys.sp_addextendedproperty N'MS_Description', N'pinned posts open the feed', N'SCHEMA', N'eng', N'TABLE', N'post', N'COLUMN', N'is_pinned';
EXEC sys.sp_addextendedproperty N'MS_Description', N'hidden by a moderator: only the author and moderators see it', N'SCHEMA', N'eng', N'TABLE', N'post', N'COLUMN', N'is_hidden';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Delete" on My Posts, or a moderator; kept for the audit trail', N'SCHEMA', N'eng', N'TABLE', N'post', N'COLUMN', N'is_deleted';
EXEC sys.sp_addextendedproperty N'MS_Description', N'newsfeed post ("What would you like to share?")', N'SCHEMA', N'eng', N'TABLE', N'post';
EXEC sys.sp_addextendedproperty N'MS_Description', N'several photos and videos per post, in order', N'SCHEMA', N'eng', N'TABLE', N'post_media';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Liked" and the "Reactions on Post" list; one per person per post', N'SCHEMA', N'eng', N'TABLE', N'post_reaction';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the top-level comment a reply belongs to', N'SCHEMA', N'eng', N'TABLE', N'post_comment', N'COLUMN', N'parent_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'up to 2000 characters', N'SCHEMA', N'eng', N'TABLE', N'post_comment', N'COLUMN', N'body';
EXEC sys.sp_addextendedproperty N'MS_Description', N'comments with Reply (one level: a reply to a reply joins the same thread)', N'SCHEMA', N'eng', N'TABLE', N'post_comment';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Like" on a comment', N'SCHEMA', N'eng', N'TABLE', N'post_comment_like';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"2.5k Views": counted once per person', N'SCHEMA', N'eng', N'TABLE', N'post_view';
EXEC sys.sp_addextendedproperty N'MS_Description', N'@person in a post (post_comment_id blank) or in a comment', N'SCHEMA', N'eng', N'TABLE', N'post_mention';
EXEC sys.sp_addextendedproperty N'MS_Description', N'answers are kept without the employee (survey_participant records who answered)', N'SCHEMA', N'eng', N'TABLE', N'survey', N'COLUMN', N'is_anonymous';
EXEC sys.sp_addextendedproperty N'MS_Description', N'draft, published, closed (a published survey past its closing date reads as closed)', N'SCHEMA', N'eng', N'TABLE', N'survey', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'blank: from publishing', N'SCHEMA', N'eng', N'TABLE', N'survey', N'COLUMN', N'opens_on';
EXEC sys.sp_addextendedproperty N'MS_Description', N'last day to respond', N'SCHEMA', N'eng', N'TABLE', N'survey', N'COLUMN', N'closes_on';
EXEC sys.sp_addextendedproperty N'MS_Description', N'survey builder: title, closing date, questions; "Survey Available" popup for the audience', N'SCHEMA', N'eng', N'TABLE', N'survey';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who is asked; no rows = everyone in the company', N'SCHEMA', N'eng', N'TABLE', N'survey_audience';
EXEC sys.sp_addextendedproperty N'MS_Description', N'single (Multiple Choice), dropdown, multiple (Check Boxes), text (Short Answer), paragraph, rating (Linear Scale)', N'SCHEMA', N'eng', N'TABLE', N'survey_question', N'COLUMN', N'question_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"What would you like to ask?"', N'SCHEMA', N'eng', N'TABLE', N'survey_question', N'COLUMN', N'question_text';
EXEC sys.sp_addextendedproperty N'MS_Description', N'rating: lowest value (0 or 1)', N'SCHEMA', N'eng', N'TABLE', N'survey_question', N'COLUMN', N'scale_min';
EXEC sys.sp_addextendedproperty N'MS_Description', N'rating: highest value (2 to 10)', N'SCHEMA', N'eng', N'TABLE', N'survey_question', N'COLUMN', N'scale_max';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Add New Option"', N'SCHEMA', N'eng', N'TABLE', N'survey_option';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one per employee per survey: answered or skipped ("Skip" on the popup)', N'SCHEMA', N'eng', N'TABLE', N'survey_participant';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the answers of one person; employee blank when the survey is anonymous', N'SCHEMA', N'eng', N'TABLE', N'survey_response';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one row per chosen option, or one with the text or rating', N'SCHEMA', N'eng', N'TABLE', N'survey_answer';
EXEC sys.sp_addextendedproperty N'MS_Description', N'reference data: the four workflow templates (Define Workflow) and the five status templates (Edit Statuses)', N'SCHEMA', N'pm', N'TABLE', N'template';
EXEC sys.sp_addextendedproperty N'MS_Description', N'view, status, feature', N'SCHEMA', N'pm', N'TABLE', N'template_item', N'COLUMN', N'item_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'view or feature code; blank for a status', N'SCHEMA', N'pm', N'TABLE', N'template_item', N'COLUMN', N'item_code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'status name, or the label of the view or feature', N'SCHEMA', N'pm', N'TABLE', N'template_item', N'COLUMN', N'name';
EXEC sys.sp_addextendedproperty N'MS_Description', N'statuses: not_started, active, done, closed', N'SCHEMA', N'pm', N'TABLE', N'template_item', N'COLUMN', N'status_group';
EXEC sys.sp_addextendedproperty N'MS_Description', N'views: the view a workspace opens on', N'SCHEMA', N'pm', N'TABLE', N'template_item', N'COLUMN', N'is_default';
EXEC sys.sp_addextendedproperty N'MS_Description', N'what a template starts with: a view, a status or an organizer feature', N'SCHEMA', N'pm', N'TABLE', N'template_item';
EXEC sys.sp_addextendedproperty N'MS_Description', N'3 to 50 characters, unique in the company', N'SCHEMA', N'pm', N'TABLE', N'workspace', N'COLUMN', N'name';
EXEC sys.sp_addextendedproperty N'MS_Description', N'up to 300 characters', N'SCHEMA', N'pm', N'TABLE', N'workspace', N'COLUMN', N'description';
EXEC sys.sp_addextendedproperty N'MS_Description', N'private (members only), workspace (everyone in the company), public (everyone in the company reads, members edit)', N'SCHEMA', N'pm', N'TABLE', N'workspace', N'COLUMN', N'privacy';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Define Workflow: Select Your Department', N'SCHEMA', N'pm', N'TABLE', N'workspace', N'COLUMN', N'department_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'work_starter, project_management, marketing_team, product_engineering', N'SCHEMA', N'pm', N'TABLE', N'workspace', N'COLUMN', N'workflow_template_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'default, custom', N'SCHEMA', N'pm', N'TABLE', N'workspace', N'COLUMN', N'status_mode';
EXEC sys.sp_addextendedproperty N'MS_Description', N'custom statuses started from this status template', N'SCHEMA', N'pm', N'TABLE', N'workspace', N'COLUMN', N'status_template_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Workspace Owner; always a member with workspace_admin', N'SCHEMA', N'pm', N'TABLE', N'workspace', N'COLUMN', N'owner_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the workspace''s task statuses, in four groups', N'SCHEMA', N'pm', N'TABLE', N'workspace_status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'organizer features switched on (priority, tags, time_tracking, story_points, wip_limits ...)', N'SCHEMA', N'pm', N'TABLE', N'workspace_feature';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a list (the BRD''s "project"): colour, description up to 500, priority, start and end', N'SCHEMA', N'pm', N'TABLE', N'task_list';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who may see a private list (besides workspace admins and HR)', N'SCHEMA', N'pm', N'TABLE', N'task_list_member';
EXEC sys.sp_addextendedproperty N'MS_Description', N'not in the first build (Sprints column marked Skipped in the design)', N'SCHEMA', N'pm', N'TABLE', N'sprint';
EXEC sys.sp_addextendedproperty N'MS_Description', N'blank: at the workspace''s top level', N'SCHEMA', N'pm', N'TABLE', N'task', N'COLUMN', N'task_list_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'subtask', N'SCHEMA', N'pm', N'TABLE', N'task', N'COLUMN', N'parent_task_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'HR000000001, per company', N'SCHEMA', N'pm', N'TABLE', N'task', N'COLUMN', N'code';
EXEC sys.sp_addextendedproperty N'MS_Description', N'task, milestone', N'SCHEMA', N'pm', N'TABLE', N'task', N'COLUMN', N'task_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'urgent, high, normal, low', N'SCHEMA', N'pm', N'TABLE', N'task', N'COLUMN', N'priority';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the due date before an approved extension', N'SCHEMA', N'pm', N'TABLE', N'task', N'COLUMN', N'original_due_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'1 Fair, 2 Good, 3 Excellent Results', N'SCHEMA', N'pm', N'TABLE', N'task', N'COLUMN', N'rating';
EXEC sys.sp_addextendedproperty N'MS_Description', N'URL Connection', N'SCHEMA', N'pm', N'TABLE', N'task', N'COLUMN', N'url';
EXEC sys.sp_addextendedproperty N'MS_Description', N'JSON: every, unit, weekdays, ends', N'SCHEMA', N'pm', N'TABLE', N'task', N'COLUMN', N'recurrence';
EXEC sys.sp_addextendedproperty N'MS_Description', N'set when the status moves into the done or closed group', N'SCHEMA', N'pm', N'TABLE', N'task', N'COLUMN', N'closed_at';
EXEC sys.sp_addextendedproperty N'MS_Description', N'completed after the due date without an approved extension (story point impact)', N'SCHEMA', N'pm', N'TABLE', N'task', N'COLUMN', N'is_closed_late';
EXEC sys.sp_addextendedproperty N'MS_Description', N'stored as "task waits on other task"; Blocking is the same row seen from the other side', N'SCHEMA', N'pm', N'TABLE', N'task_dependency';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a running timer has no end_at yet', N'SCHEMA', N'pm', N'TABLE', N'time_entry';
EXEC sys.sp_addextendedproperty N'MS_Description', N'reply', N'SCHEMA', N'pm', N'TABLE', N'task_comment', N'COLUMN', N'parent_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Assigned to ... by ...', N'SCHEMA', N'pm', N'TABLE', N'task_comment', N'COLUMN', N'assigned_to_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Mark as Resolve', N'SCHEMA', N'pm', N'TABLE', N'task_comment', N'COLUMN', N'resolved_by_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'@person or #task in a comment', N'SCHEMA', N'pm', N'TABLE', N'comment_mention';
EXEC sys.sp_addextendedproperty N'MS_Description', N'like or emoji, one per person per comment', N'SCHEMA', N'pm', N'TABLE', N'comment_reaction';
EXEC sys.sp_addextendedproperty N'MS_Description', N'task, task_list, workspace', N'SCHEMA', N'pm', N'TABLE', N'reminder', N'COLUMN', N'entity_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'soft, hard', N'SCHEMA', N'pm', N'TABLE', N'reminder', N'COLUMN', N'reminder_kind';
EXEC sys.sp_addextendedproperty N'MS_Description', N'delivered by pm.usp_reminder_deliver_due (inbox notification, then notified_at)', N'SCHEMA', N'pm', N'TABLE', N'reminder';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Request Extension: up to the workspace''s max_extensions per task (default 1); approved keeps story points', N'SCHEMA', N'pm', N'TABLE', N'task_extension';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Add Fields', N'SCHEMA', N'pm', N'TABLE', N'custom_field';
EXEC sys.sp_addextendedproperty N'MS_Description', N'built-in column key, or cf_<custom_field id>', N'SCHEMA', N'pm', N'TABLE', N'column_permission', N'COLUMN', N'column_key';
EXEC sys.sp_addextendedproperty N'MS_Description', N'blank, or one workspace role', N'SCHEMA', N'pm', N'TABLE', N'column_permission', N'COLUMN', N'member_role';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a custom permission for one member', N'SCHEMA', N'pm', N'TABLE', N'column_permission', N'COLUMN', N'employee_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'can_edit, can_view, private', N'SCHEMA', N'pm', N'TABLE', N'column_permission', N'COLUMN', N'permission_level';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Set Role Permission on a List view column; blank role and person = the workspace default', N'SCHEMA', N'pm', N'TABLE', N'column_permission';
EXEC sys.sp_addextendedproperty N'MS_Description', N'views of a workspace (task_list_id blank) or of one list', N'SCHEMA', N'pm', N'TABLE', N'list_view';
EXEC sys.sp_addextendedproperty N'MS_Description', N'task, task_list, workspace', N'SCHEMA', N'pm', N'TABLE', N'share_link', N'COLUMN', N'entity_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'list (single list view), page (whole page)', N'SCHEMA', N'pm', N'TABLE', N'share_link', N'COLUMN', N'share_scope';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Share link with anyone', N'SCHEMA', N'pm', N'TABLE', N'share_link', N'COLUMN', N'is_public';
EXEC sys.sp_addextendedproperty N'MS_Description', N'JSON: task properties shown', N'SCHEMA', N'pm', N'TABLE', N'share_link', N'COLUMN', N'properties';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Sharing and Permissions; public links open /api/public/shares/{token}; invitations are not sent yet', N'SCHEMA', N'pm', N'TABLE', N'share_link';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one row per opening of a public share link (page or task); counts against max_access', N'SCHEMA', N'pm', N'TABLE', N'share_access';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Add to Favorites and Hide, per person', N'SCHEMA', N'pm', N'TABLE', N'favorite';
EXEC sys.sp_addextendedproperty N'MS_Description', N'0 to 100; share of a closed-late task''s story points taken off', N'SCHEMA', N'pm', N'TABLE', N'workspace_overdue_setting', N'COLUMN', N'penalty_percent';
EXEC sys.sp_addextendedproperty N'MS_Description', N'extension requests allowed per task (0 to 10)', N'SCHEMA', N'pm', N'TABLE', N'workspace_overdue_setting', N'COLUMN', N'max_extensions';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Overdue settings of a workspace: story point penalty for work closed late, extensions allowed per task', N'SCHEMA', N'pm', N'TABLE', N'workspace_overdue_setting';
EXEC sys.sp_addextendedproperty N'MS_Description', N'google_drive, dropbox, box, onedrive', N'SCHEMA', N'pm', N'TABLE', N'task_external_file', N'COLUMN', N'provider';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the provider''s file id', N'SCHEMA', N'pm', N'TABLE', N'task_external_file', N'COLUMN', N'external_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a task attachment that is a link to Google Drive, Dropbox, Box or OneDrive', N'SCHEMA', N'pm', N'TABLE', N'task_external_file';
EXEC sys.sp_addextendedproperty N'MS_Description', N'1 to 50 characters', N'SCHEMA', N'pm', N'TABLE', N'doc', N'COLUMN', N'title';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the editor''s JSON document', N'SCHEMA', N'pm', N'TABLE', N'doc', N'COLUMN', N'content';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the same content as HTML (search, export, public view)', N'SCHEMA', N'pm', N'TABLE', N'doc', N'COLUMN', N'content_html';
EXEC sys.sp_addextendedproperty N'MS_Description', N'private (owner only), workspace (everyone who opens the workspace), public', N'SCHEMA', N'pm', N'TABLE', N'doc', N'COLUMN', N'visibility';
EXEC sys.sp_addextendedproperty N'MS_Description', N'JSON: fontFamily, fontSize, header (cover, title, subtitle, owner, contributors, updatedAt, toc)', N'SCHEMA', N'pm', N'TABLE', N'doc', N'COLUMN', N'settings';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Docs: a rich text page in a workspace (optionally in a folder or list)', N'SCHEMA', N'pm', N'TABLE', N'doc';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who has edited a doc besides its owner', N'SCHEMA', N'pm', N'TABLE', N'doc_contributor';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Docs linked to tasks', N'SCHEMA', N'pm', N'TABLE', N'doc_task';
EXEC sys.sp_addextendedproperty N'MS_Description', N'comments on a doc (as task comments: threads by parent_id)', N'SCHEMA', N'pm', N'TABLE', N'doc_comment';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the latest version in note_version', N'SCHEMA', N'pm', N'TABLE', N'note', N'COLUMN', N'version_no';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Notepad: a person''s own notes (per sign-in, not per workspace)', N'SCHEMA', N'pm', N'TABLE', N'note';
EXEC sys.sp_addextendedproperty N'MS_Description', N'every saved version of a note (Notepad history)', N'SCHEMA', N'pm', N'TABLE', N'note_version';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Home dashboard Personal List: a person''s own to-dos, not tied to a workspace', N'SCHEMA', N'pm', N'TABLE', N'personal_item';
EXEC sys.sp_addextendedproperty N'MS_Description', N'no foreign key: deleted items drop out of the list', N'SCHEMA', N'pm', N'TABLE', N'recent_item', N'COLUMN', N'workspace_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'what a person opened lately (workspace, folder, task_list, task, doc); newest 50 kept', N'SCHEMA', N'pm', N'TABLE', N'recent_item';
EXEC sys.sp_addextendedproperty N'MS_Description', N'late_arrival, early_departure, overtime, half_day_leave', N'SCHEMA', N'att', N'TABLE', N'warning_policy', N'COLUMN', N'applies_to';
EXEC sys.sp_addextendedproperty N'MS_Description', N'day, week, month, year', N'SCHEMA', N'att', N'TABLE', N'warning_policy', N'COLUMN', N'period';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Total Grace Minutes in a period before days count', N'SCHEMA', N'att', N'TABLE', N'warning_policy', N'COLUMN', N'grace_minutes';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Warning -> Policy', N'SCHEMA', N'att', N'TABLE', N'warning_policy';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one per clock event', N'SCHEMA', N'att', N'TABLE', N'warning_policy_rule';
EXEC sys.sp_addextendedproperty N'MS_Description', N'week, month, year', N'SCHEMA', N'att', N'TABLE', N'penalty_rule', N'COLUMN', N'period';
EXEC sys.sp_addextendedproperty N'MS_Description', N'half_day, full_day, percentage', N'SCHEMA', N'att', N'TABLE', N'penalty_rule', N'COLUMN', N'penalty_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'share of a day: 50, 100 or the given percentage', N'SCHEMA', N'att', N'TABLE', N'penalty_rule', N'COLUMN', N'percentage';
EXEC sys.sp_addextendedproperty N'MS_Description', N'payroll, leave, both', N'SCHEMA', N'att', N'TABLE', N'penalty_rule', N'COLUMN', N'deduction';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the balance a leave deduction is taken from', N'SCHEMA', N'att', N'TABLE', N'penalty_rule', N'COLUMN', N'leave_type_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Warning -> Penalty: what the n-th warning in a period costs', N'SCHEMA', N'att', N'TABLE', N'penalty_rule';
EXEC sys.sp_addextendedproperty N'MS_Description', N'minutes measured that day', N'SCHEMA', N'att', N'TABLE', N'warning', N'COLUMN', N'minutes';
EXEC sys.sp_addextendedproperty N'MS_Description', N'n-th occurrence in the policy period', N'SCHEMA', N'att', N'TABLE', N'warning', N'COLUMN', N'occurrence_no';
EXEC sys.sp_addextendedproperty N'MS_Description', N'payroll, leave, both', N'SCHEMA', N'att', N'TABLE', N'warning', N'COLUMN', N'deduction';
EXEC sys.sp_addextendedproperty N'MS_Description', N'where the penalty was deducted', N'SCHEMA', N'att', N'TABLE', N'warning', N'COLUMN', N'payslip_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a warning actually raised (att.usp_warning_raise)', N'SCHEMA', N'att', N'TABLE', N'warning';
EXEC sys.sp_addextendedproperty N'MS_Description', N'immediately, waiting_period, per_employee', N'SCHEMA', N'ben', N'TABLE', N'plan_year', N'COLUMN', N'new_hire_start';
EXEC sys.sp_addextendedproperty N'MS_Description', N'when new_hire_start = waiting_period', N'SCHEMA', N'ben', N'TABLE', N'plan_year', N'COLUMN', N'waiting_period_days';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"How long do new employees have to complete elections?"', N'SCHEMA', N'ben', N'TABLE', N'plan_year', N'COLUMN', N'election_period';
EXEC sys.sp_addextendedproperty N'MS_Description', N'day, week, month', N'SCHEMA', N'ben', N'TABLE', N'plan_year', N'COLUMN', N'election_unit';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Benefit Plan Years"', N'SCHEMA', N'ben', N'TABLE', N'plan_year';
EXEC sys.sp_addextendedproperty N'MS_Description', N'medical, dental, vision, retirement, hsa, life, others', N'SCHEMA', N'ben', N'TABLE', N'benefit_plan', N'COLUMN', N'category';
EXEC sys.sp_addextendedproperty N'MS_Description', N'EPO, HMO, PPO ... per category', N'SCHEMA', N'ben', N'TABLE', N'benefit_plan', N'COLUMN', N'plan_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Plan Type ID"', N'SCHEMA', N'ben', N'TABLE', N'benefit_plan', N'COLUMN', N'plan_type_ref';
EXEC sys.sp_addextendedproperty N'MS_Description', N'active, inactive', N'SCHEMA', N'ben', N'TABLE', N'benefit_plan', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Benefit Plans" (Add {Category} Plan)', N'SCHEMA', N'ben', N'TABLE', N'benefit_plan';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the plans offered in a year (many to many)', N'SCHEMA', N'ben', N'TABLE', N'plan_year_plan';
EXEC sys.sp_addextendedproperty N'MS_Description', N'open_enrollment, life_event, new_hire', N'SCHEMA', N'ben', N'TABLE', N'enrollment_window', N'COLUMN', N'kind';
EXEC sys.sp_addextendedproperty N'MS_Description', N'inside the plan year', N'SCHEMA', N'ben', N'TABLE', N'enrollment_window', N'COLUMN', N'effective_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the last day to enrol; open until then', N'SCHEMA', N'ben', N'TABLE', N'enrollment_window', N'COLUMN', N'closes_on';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"New Open Enrollment Window" (also Qualifying Life Event, New Hire)', N'SCHEMA', N'ben', N'TABLE', N'enrollment_window';
EXEC sys.sp_addextendedproperty N'MS_Description', N'none listed = everyone', N'SCHEMA', N'ben', N'TABLE', N'enrollment_window_employee';
EXEC sys.sp_addextendedproperty N'MS_Description', N'incomplete, pending, approved, rejected, waived', N'SCHEMA', N'ben', N'TABLE', N'election', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'an employee''s elections for a plan year ("Employee Elections")', N'SCHEMA', N'ben', N'TABLE', N'election';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the cover', N'SCHEMA', N'ben', N'TABLE', N'health_benefit', N'COLUMN', N'coverage_amount';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Life Cover"', N'SCHEMA', N'ben', N'TABLE', N'health_benefit', N'COLUMN', N'life_cover_amount';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Annual Payment"', N'SCHEMA', N'ben', N'TABLE', N'health_benefit', N'COLUMN', N'annual_payment';
EXEC sys.sp_addextendedproperty N'MS_Description', N'availed, not_availed', N'SCHEMA', N'ben', N'TABLE', N'health_benefit', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the policy document or insurance card (an upload)', N'SCHEMA', N'ben', N'TABLE', N'health_benefit', N'COLUMN', N'document_file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Health Benefits": the insurance an employee holds', N'SCHEMA', N'ben', N'TABLE', N'health_benefit';
EXEC sys.sp_addextendedproperty N'MS_Description', N'eid_ul_adha, eid_ul_fitr, birthday, ramadan, new_year', N'SCHEMA', N'ben', N'TABLE', N'perk', N'COLUMN', N'occasion';
EXEC sys.sp_addextendedproperty N'MS_Description', N'availed, not_availed', N'SCHEMA', N'ben', N'TABLE', N'perk', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"Perks": occasion gifts', N'SCHEMA', N'ben', N'TABLE', N'perk';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the scale a new appraisal form starts with', N'SCHEMA', N'perf', N'TABLE', N'rating_scale', N'COLUMN', N'is_default';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Performance settings -> Rating Scales (1 Unsatisfactory ... 5 Outstanding)', N'SCHEMA', N'perf', N'TABLE', N'rating_scale';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one step on a scale; ratings may fall between steps', N'SCHEMA', N'perf', N'TABLE', N'rating_scale_level';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the KRA the KPI belongs to (Sales, Quality, People ...)', N'SCHEMA', N'perf', N'TABLE', N'kpi', N'COLUMN', N'key_result_area';
EXEC sys.sp_addextendedproperty N'MS_Description', N'percentage, number, amount, rating, yes_no', N'SCHEMA', N'perf', N'TABLE', N'kpi', N'COLUMN', N'measure_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional; suggested for this department', N'SCHEMA', N'perf', N'TABLE', N'kpi', N'COLUMN', N'department_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional; suggested for this job title', N'SCHEMA', N'perf', N'TABLE', N'kpi', N'COLUMN', N'job_title_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Performance -> KPIs: the KPI library, grouped by key result area', N'SCHEMA', N'perf', N'TABLE', N'kpi';
EXEC sys.sp_addextendedproperty N'MS_Description', N'employees rate themselves before their manager does', N'SCHEMA', N'perf', N'TABLE', N'appraisal_form', N'COLUMN', N'has_self_review';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Performance settings -> Appraisal Forms: what a cycle rates and the weights', N'SCHEMA', N'perf', N'TABLE', N'appraisal_form';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional', N'SCHEMA', N'perf', N'TABLE', N'appraisal_criterion', N'COLUMN', N'kpi_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a line on a form: a KPI from the library or a competency written on the form', N'SCHEMA', N'perf', N'TABLE', N'appraisal_criterion';
EXEC sys.sp_addextendedproperty N'MS_Description', N'fixed once the cycle is launched', N'SCHEMA', N'perf', N'TABLE', N'appraisal_cycle', N'COLUMN', N'appraisal_form_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the period under review', N'SCHEMA', N'perf', N'TABLE', N'appraisal_cycle', N'COLUMN', N'start_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'draft, active, closed', N'SCHEMA', N'perf', N'TABLE', N'appraisal_cycle', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Performance -> Appraisals: one review round ("Annual 2026")', N'SCHEMA', N'perf', N'TABLE', N'appraisal_cycle';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the line manager when the person joined the cycle', N'SCHEMA', N'perf', N'TABLE', N'appraisal', N'COLUMN', N'reviewer_employee_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'draft, self_review, manager_review, reviewed, finalised', N'SCHEMA', N'perf', N'TABLE', N'appraisal', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the scale level nearest the final score', N'SCHEMA', N'perf', N'TABLE', N'appraisal', N'COLUMN', N'final_rating_label';
EXEC sys.sp_addextendedproperty N'MS_Description', N'training the manager recommends (read by Training)', N'SCHEMA', N'perf', N'TABLE', N'appraisal', N'COLUMN', N'development_needs';
EXEC sys.sp_addextendedproperty N'MS_Description', N'no_change, increment, promotion, improvement_plan', N'SCHEMA', N'perf', N'TABLE', N'appraisal', N'COLUMN', N'outcome';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the appraisal letter (Documents: "Appraisal Letter")', N'SCHEMA', N'perf', N'TABLE', N'appraisal', N'COLUMN', N'letter_file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one employee in one cycle: self review, manager review, final rating, outcome', N'SCHEMA', N'perf', N'TABLE', N'appraisal';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one criterion rated on one appraisal, by the employee and by the manager', N'SCHEMA', N'perf', N'TABLE', N'appraisal_rating';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional; the cycle it counts in (otherwise the cycle its due date falls in)', N'SCHEMA', N'perf', N'TABLE', N'goal', N'COLUMN', N'appraisal_cycle_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional', N'SCHEMA', N'perf', N'TABLE', N'goal', N'COLUMN', N'kpi_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Goal Name', N'SCHEMA', N'perf', N'TABLE', N'goal', N'COLUMN', N'title';
EXEC sys.sp_addextendedproperty N'MS_Description', N'not_started, in_progress, completed, cancelled', N'SCHEMA', N'perf', N'TABLE', N'goal', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'My Performance -> Goals (Goal Name, Due Date, Completed); project tasks link to goals', N'SCHEMA', N'perf', N'TABLE', N'goal';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a progress update on a goal (its history)', N'SCHEMA', N'perf', N'TABLE', N'goal_check_in';
EXEC sys.sp_addextendedproperty N'MS_Description', N'flat, percent (as pay.usp_salary_revision_save)', N'SCHEMA', N'perf', N'TABLE', N'increment_proposal', N'COLUMN', N'change_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the salary in force on the effective date when proposed', N'SCHEMA', N'perf', N'TABLE', N'increment_proposal', N'COLUMN', N'current_salary';
EXEC sys.sp_addextendedproperty N'MS_Description', N'proposed, applied, rejected', N'SCHEMA', N'perf', N'TABLE', N'increment_proposal', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the salary revision written when applied', N'SCHEMA', N'perf', N'TABLE', N'increment_proposal', N'COLUMN', N'employee_salary_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'an increment a finalised appraisal proposes; applied as payroll''s salary revision', N'SCHEMA', N'perf', N'TABLE', N'increment_proposal';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Training settings -> Categories (Technical, Soft skills, Compliance, HSE)', N'SCHEMA', N'trn', N'TABLE', N'training_category';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional', N'SCHEMA', N'trn', N'TABLE', N'training_program', N'COLUMN', N'training_category_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'classroom, online, blended, on_the_job', N'SCHEMA', N'trn', N'TABLE', N'training_program', N'COLUMN', N'delivery_mode';
EXEC sys.sp_addextendedproperty N'MS_Description', N'internal, external', N'SCHEMA', N'trn', N'TABLE', N'training_program', N'COLUMN', N'provider_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a certificate expires after this many months; empty = never', N'SCHEMA', N'trn', N'TABLE', N'training_program', N'COLUMN', N'certificate_validity_months';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Training -> Programs: a course the company runs or buys', N'SCHEMA', N'trn', N'TABLE', N'training_program';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the program''s title unless given', N'SCHEMA', N'trn', N'TABLE', N'training_session', N'COLUMN', N'title';
EXEC sys.sp_addextendedproperty N'MS_Description', N'classroom, online', N'SCHEMA', N'trn', N'TABLE', N'training_session', N'COLUMN', N'delivery_mode';
EXEC sys.sp_addextendedproperty N'MS_Description', N'internal, external', N'SCHEMA', N'trn', N'TABLE', N'training_session', N'COLUMN', N'trainer_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'an internal trainer', N'SCHEMA', N'trn', N'TABLE', N'training_session', N'COLUMN', N'trainer_employee_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'an external trainer', N'SCHEMA', N'trn', N'TABLE', N'training_session', N'COLUMN', N'trainer_name';
EXEC sys.sp_addextendedproperty N'MS_Description', N'seats; empty = no limit', N'SCHEMA', N'trn', N'TABLE', N'training_session', N'COLUMN', N'capacity';
EXEC sys.sp_addextendedproperty N'MS_Description', N'scheduled, completed, cancelled', N'SCHEMA', N'trn', N'TABLE', N'training_session', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Training -> Sessions: one scheduled run of a program', N'SCHEMA', N'trn', N'TABLE', N'training_session';
EXEC sys.sp_addextendedproperty N'MS_Description', N'requested, enrolled, rejected, withdrawn, cancelled, completed, not_completed', N'SCHEMA', N'trn', N'TABLE', N'training_enrolment', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'self, manager, hr', N'SCHEMA', N'trn', N'TABLE', N'training_enrolment', N'COLUMN', N'nomination_source';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a nomination or a seat on a session, and its result', N'SCHEMA', N'trn', N'TABLE', N'training_enrolment';
EXEC sys.sp_addextendedproperty N'MS_Description', N'attendance per day of a session', N'SCHEMA', N'trn', N'TABLE', N'training_attendance';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the participant''s evaluation of a session (1-5)', N'SCHEMA', N'trn', N'TABLE', N'training_feedback';
EXEC sys.sp_addextendedproperty N'MS_Description', N'free text: Onboarding, IT, Feedback ...', N'SCHEMA', N'frm', N'TABLE', N'form', N'COLUMN', N'category';
EXEC sys.sp_addextendedproperty N'MS_Description', N'draft, published, closed (a published form past closes_on reads as closed)', N'SCHEMA', N'frm', N'TABLE', N'form', N'COLUMN', N'status';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the last day to answer; blank: open until closed', N'SCHEMA', N'frm', N'TABLE', N'form', N'COLUMN', N'closes_on';
EXEC sys.sp_addextendedproperty N'MS_Description', N'everyone, departments, branches, people (the targets are form_audience rows)', N'SCHEMA', N'frm', N'TABLE', N'form', N'COLUMN', N'audience_kind';
EXEC sys.sp_addextendedproperty N'MS_Description', N'"One response per person"', N'SCHEMA', N'frm', N'TABLE', N'form', N'COLUMN', N'is_one_per_person';
EXEC sys.sp_addextendedproperty N'MS_Description', N'HR sees the answers without the respondent; fixed once there are responses', N'SCHEMA', N'frm', N'TABLE', N'form', N'COLUMN', N'is_anonymous';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Forms list and the builder ("New Form", "Edit")', N'SCHEMA', N'frm', N'TABLE', N'form';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a titled group of questions, in order', N'SCHEMA', N'frm', N'TABLE', N'form_section';
EXEC sys.sp_addextendedproperty N'MS_Description', N'optional: blank = before the first section', N'SCHEMA', N'frm', N'TABLE', N'form_field', N'COLUMN', N'form_section_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'order in the whole form (position in its section is derived)', N'SCHEMA', N'frm', N'TABLE', N'form_field', N'COLUMN', N'sort_order';
EXEC sys.sp_addextendedproperty N'MS_Description', N'short_text, long_text, number, date, single_choice, multiple_choice, dropdown, checkbox, file, rating', N'SCHEMA', N'frm', N'TABLE', N'form_field', N'COLUMN', N'field_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'text: length; number: value; multiple_choice: picks', N'SCHEMA', N'frm', N'TABLE', N'form_field', N'COLUMN', N'min_value';
EXEC sys.sp_addextendedproperty N'MS_Description', N'as min_value; rating: the scale (3 to 10)', N'SCHEMA', N'frm', N'TABLE', N'form_field', N'COLUMN', N'max_value';
EXEC sys.sp_addextendedproperty N'MS_Description', N'a question', N'SCHEMA', N'frm', N'TABLE', N'form_field';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the options of single_choice, multiple_choice and dropdown questions', N'SCHEMA', N'frm', N'TABLE', N'form_field_option';
EXEC sys.sp_addextendedproperty N'MS_Description', N'department (with sub-departments), branch, employee', N'SCHEMA', N'frm', N'TABLE', N'form_audience', N'COLUMN', N'unit_type';
EXEC sys.sp_addextendedproperty N'MS_Description', N'who the form is for when audience_kind is not everyone', N'SCHEMA', N'frm', N'TABLE', N'form_audience';
EXEC sys.sp_addextendedproperty N'MS_Description', N'kept for anonymous forms too; never shown to HR then', N'SCHEMA', N'frm', N'TABLE', N'form_response', N'COLUMN', N'employee_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one submission', N'SCHEMA', N'frm', N'TABLE', N'form_response';
EXEC sys.sp_addextendedproperty N'MS_Description', N'short_text, long_text', N'SCHEMA', N'frm', N'TABLE', N'form_answer', N'COLUMN', N'answer_text';
EXEC sys.sp_addextendedproperty N'MS_Description', N'number, rating', N'SCHEMA', N'frm', N'TABLE', N'form_answer', N'COLUMN', N'answer_number';
EXEC sys.sp_addextendedproperty N'MS_Description', N'date', N'SCHEMA', N'frm', N'TABLE', N'form_answer', N'COLUMN', N'answer_date';
EXEC sys.sp_addextendedproperty N'MS_Description', N'checkbox', N'SCHEMA', N'frm', N'TABLE', N'form_answer', N'COLUMN', N'answer_bool';
EXEC sys.sp_addextendedproperty N'MS_Description', N'file', N'SCHEMA', N'frm', N'TABLE', N'form_answer', N'COLUMN', N'file_id';
EXEC sys.sp_addextendedproperty N'MS_Description', N'one answered question of a response; the column used depends on the type', N'SCHEMA', N'frm', N'TABLE', N'form_answer';
EXEC sys.sp_addextendedproperty N'MS_Description', N'the chosen option(s) of a single_choice, dropdown or multiple_choice answer', N'SCHEMA', N'frm', N'TABLE', N'form_answer_option';
GO
