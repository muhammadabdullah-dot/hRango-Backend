"""Permission codes for the Assets menu: asset types, company assets, allocations, clearance forms.

Asset types and company assets are company records, not employee records: the service refuses them
to a caller who holds the code with own scope only. Allocating and deallocating is "assign", so the
Employee role (view own) sees the assets they hold but cannot hand assets to themselves.
"""
from app.catalogue._actions import CRUD

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("assets.types", "Asset types", CRUD, False),
    ("assets.company_assets", "Company assets", CRUD, False),
    ("assets.allocations", "Asset allocations", ("view", "assign", "export"), False),
    ("assets.clearance", "Asset clearance form", ("view", "create", "edit", "delete", "approve", "export"), False),
]

# Events this module publishes (core.usp_event_publish); webhooks subscribe to them.
EVENTS: list[tuple[str, str]] = [
    ("assets.allocated", "An asset was handed to an employee; the employee is notified."),
    ("assets.returned", "An employee gave an asset back (Deallocate); the employee is notified."),
    ("assets.clearance_approved", "An asset clearance form was approved: the assets it closed and how they came back."),
]
