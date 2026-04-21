#!/usr/bin/env python3
# Usage: python3 tests/test_group_tab.py <group_id>
#   Run from api/library/python/iterm2/ so the iterm2 package is on the path.
#   group_id is available in $ITERM_GROUP_ID inside a restored group tab.

import iterm2
import sys

GROUP_ID = sys.argv[1] if len(sys.argv) > 1 else None
if not GROUP_ID:
    print("Usage: python3 tests/test_group_tab.py <group_id>")
    sys.exit(1)


async def main(connection):
    # Happy path: new tab joins the group
    result = await iterm2.rpc.async_create_tab(connection, group_id=GROUP_ID)
    print("status:", result.create_tab_response.status)        # expect 0 (OK)
    print("session:", result.create_tab_response.session_id)

    # Invalid group ID → expect INVALID_GROUP_ID (5)
    bad = await iterm2.rpc.async_create_tab(connection, group_id="not-a-real-id")
    print("bad group status:", bad.create_tab_response.status)  # expect 5


iterm2.run_until_complete(main)
