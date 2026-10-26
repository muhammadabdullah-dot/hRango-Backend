"""Permission codes for Loans: the loans approved loan requests made (My / All, schedule,
repayments) and Loan & Advance Settings. Loan figures are sensitive (Mini SRS ACC-9). Asking for a
loan is a request: requests.loan.* in app/catalogue/requests.py."""
from app.catalogue._actions import CRUD

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("loans.loans", "Loans and repayments", ("view", "export"), True),
    ("loans.settings.types", "Loan settings: Types", CRUD, False),
    ("loans.settings.categories", "Loan settings: Categories", CRUD, False),
]
