"""Permission codes for the organisation's own subscription and billing (Settings -> Subscription): its plan,
invoices and billing details, and sending proof of a bank transfer. Company Administrators (and so the Account
Owner) hold them; HR roles do not. Sensitive: managers never get it for others."""

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("billing.subscription", "Subscription and billing", ("view", "edit", "submit"), True),
]
