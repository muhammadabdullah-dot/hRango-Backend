"""Payroll, under /api/payroll. The endpoints live in four files by area; this one joins them.

  payroll_settings.py   Settings: general options, tax, rewards, pay components, account types, banks
  payroll_runs.py       Monthly and daily-wage payrolls, salary sheet, payslips
  payroll_records.py    Vouchers, final settlement, balances, salary revision, leave encashment
  payroll_reports.py    Reports and the payroll dashboard
"""
from fastapi import APIRouter

from app.routers import payroll_records, payroll_reports, payroll_runs, payroll_settings

router = APIRouter(prefix="/payroll", tags=["payroll"])
router.include_router(payroll_settings.router)
router.include_router(payroll_runs.router)
router.include_router(payroll_records.router)
router.include_router(payroll_reports.router)
