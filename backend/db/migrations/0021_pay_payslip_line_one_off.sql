-- Edit Pay Slip can add a one-off line (any pay item not on the slip yet, with its own label such as
-- "Test bonus") and remove it again. is_one_off marks a line added by hand (only those can be removed); label
-- is shown on the slip instead of the pay item's name. Both are kept when the slip is recalculated. Checks
-- first, like 0002, so it also runs on a baseline rebuilt from the ERD.

IF COL_LENGTH(N'pay.payslip_line', N'label') IS NULL
    ALTER TABLE [pay].[payslip_line] ADD [label] NVARCHAR(100) NULL;
GO

IF COL_LENGTH(N'pay.payslip_line', N'is_one_off') IS NULL
    ALTER TABLE [pay].[payslip_line] ADD [is_one_off] BIT NOT NULL
        CONSTRAINT [DF_payslip_line_is_one_off] DEFAULT 0;
GO
