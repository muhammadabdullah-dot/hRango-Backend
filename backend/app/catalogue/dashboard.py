"""Permission codes for the dashboards. Each dashboard's figures cover the employees the
permission's scope reaches (own, team, department, branch, selected units or company)."""

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("dashboard.ceo", "CEO dashboard", ("view",), False),
    ("dashboard.hr", "HR dashboard", ("view",), False),
    ("dashboard.employee", "My dashboard", ("view",), False),
]
