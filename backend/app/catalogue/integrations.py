"""Permission codes and events for Settings -> Integrations (webhooks)."""

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("integrations.webhooks", "Webhooks", ("view", "create", "edit", "delete"), False),
]

# Events any module publishes with core.usp_event_publish. Each module lists its own events here in
# its catalogue file as EVENTS = [(type, description)]; webhooks subscribe to a type, "module.*" or "*".
EVENTS: list[tuple[str, str]] = [
    ("notification.created", "A notification was added to someone's inbox (title, body, link, employee, email)."),
    ("webhook.ping", "A test event sent from the webhook screen."),
]
