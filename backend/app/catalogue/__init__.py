"""The permission catalogue, one file per module. Each file defines SCREENS:
    (screen code, label, actions, sensitive)
The screen code is module.screen (module.settings.<tab> for settings pages). Every action makes
one permission code: module.screen.action. See app/core/permissions.py.
"""
