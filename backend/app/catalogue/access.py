"""Permission codes for users, roles and sessions (Mini SRS 3.1, ACC-1 to ACC-16).

Switching a user off is the users screen's delete action; giving users roles is roles.assign.
"""

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("access.users", "Users", ("view", "create", "edit", "delete"), False),
    ("access.roles", "Roles", ("view", "create", "edit", "delete", "assign"), False),
    ("access.overrides", "User grants and denials", ("view", "edit"), False),
    ("access.sessions", "Sessions", ("view", "end_session"), False),
    ("access.audit", "Change history", ("view", "export"), False),
]
