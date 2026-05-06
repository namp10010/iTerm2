#!/usr/bin/env python3
# Usage: python3 tests/test_create_tab_badge.py
#   Run from api/library/python/iterm2/ so the iterm2 package is on the path.
#
# Verifies that Window.async_create_tab(badge=...) overrides the badge on the
# new session at runtime without modifying the profile.

import iterm2

BADGE = "hello-from-sdk"


async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_terminal_window
    if window is None:
        print("No current terminal window")
        return

    # Happy path: badge is applied to the new session.
    tab = await window.async_create_tab(badge=BADGE)
    assert tab is not None, "expected a Tab"
    session = tab.current_session
    label = await session.async_get_variable("badge")
    print("badge with override:", label)            # expect: hello-from-sdk
    assert label == BADGE, f"expected {BADGE!r}, got {label!r}"

    # Regression: omitting `badge` falls back to the profile's badge.
    default_tab = await window.async_create_tab()
    assert default_tab is not None
    default_label = await default_tab.current_session.async_get_variable("badge")
    print("badge with default:", default_label)


iterm2.run_until_complete(main)
