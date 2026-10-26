"""Permission codes for the inbox (the signed-in user's own notifications)."""

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("inbox.notifications", "Notifications", ("view",), False),
]
