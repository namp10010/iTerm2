#!/usr/bin/env python3
# Usage: python3 tests/test_create_tab_background.py
#   Run from api/library/python/iterm2/ so the iterm2 package is on the path.
#
# Verifies that Window.async_create_tab(background=True) creates a tab without
# changing the active tab of the window, and that Window.async_create(
# background=True) creates a new window without making it key.

import iterm2


async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_terminal_window
    if window is None:
        print("No current terminal window")
        return

    original_tab = window.current_tab
    assert original_tab is not None

    # Background tab does not change the active tab of the window.
    bg_tab = await window.async_create_tab(background=True)
    assert bg_tab is not None, "expected a Tab"
    assert bg_tab.tab_id != original_tab.tab_id, "expected a new tab"
    await app.async_refresh()
    refreshed_window = app.get_window_by_id(window.window_id)
    assert refreshed_window is not None
    assert refreshed_window.current_tab.tab_id == original_tab.tab_id, (
        f"expected original tab {original_tab.tab_id} to remain selected, "
        f"got {refreshed_window.current_tab.tab_id}")
    print("background tab: original tab kept focus -", original_tab.tab_id)

    # Foreground tab (default) does switch the active tab.
    fg_tab = await window.async_create_tab()
    assert fg_tab is not None
    await app.async_refresh()
    refreshed_window = app.get_window_by_id(window.window_id)
    assert refreshed_window.current_tab.tab_id == fg_tab.tab_id, (
        "expected default behavior to switch to the new tab")
    print("foreground tab: switched to new tab -", fg_tab.tab_id)

    # Background window: new window is created but not made key.
    bg_window = await iterm2.Window.async_create(connection, background=True)
    assert bg_window is not None
    await app.async_refresh()
    current = app.current_terminal_window
    assert current is not None
    assert current.window_id != bg_window.window_id, (
        f"expected key window to remain {window.window_id}, "
        f"got {current.window_id}")
    print("background window: original window kept focus -", current.window_id)


iterm2.run_until_complete(main)
