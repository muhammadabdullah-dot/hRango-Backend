-- A verified Salary Advance voucher is a debt of the employee: verifying it debits the person's Salary Advance
-- account (pay.employee_account_entry.voucher_id names the voucher) and makes a loan (loan.loan, no request)
-- whose installments payroll deducts like a Loan & Advance request's; pay.voucher.loan_id names that loan.
-- Each recovery a closed payroll or final settlement makes is credited back to the same account. Checks first,
-- like 0002, so it also runs on a baseline rebuilt from the ERD.

IF COL_LENGTH(N'pay.voucher', N'loan_id') IS NULL
    ALTER TABLE [pay].[voucher] ADD [loan_id] BIGINT NULL
        CONSTRAINT [FK_voucher_loan_id] FOREIGN KEY REFERENCES [loan].[loan] ([id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'pay.voucher') AND name = N'IX_voucher_loan_id')
    CREATE NONCLUSTERED INDEX [IX_voucher_loan_id] ON [pay].[voucher] ([loan_id]);
GO

IF COL_LENGTH(N'pay.employee_account_entry', N'voucher_id') IS NULL
    ALTER TABLE [pay].[employee_account_entry] ADD [voucher_id] BIGINT NULL
        CONSTRAINT [FK_employee_account_entry_voucher_id] FOREIGN KEY REFERENCES [pay].[voucher] ([id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'pay.employee_account_entry') AND name = N'IX_employee_account_entry_voucher_id')
    CREATE NONCLUSTERED INDEX [IX_employee_account_entry_voucher_id] ON [pay].[employee_account_entry] ([voucher_id]);
GO
