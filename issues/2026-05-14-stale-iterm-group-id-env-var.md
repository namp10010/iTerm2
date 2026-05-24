# Stale `ITERM_GROUP_ID` env var causes `cc-spawn` to fail with INVALID_GROUP_ID

**Date:** 2026-05-14

## Summary

When `cc-group close` (or any teardown of an iTerm2 tab group) runs from a shell, the iTerm tab group is destroyed but the `ITERM_GROUP_ID` environment variable remains set in the still-running shell. A subsequent `cc-spawn` then passes that stale UUID to iTerm's `async_create_tab(tab_group_id=...)`, which raises `INVALID_GROUP_ID` and the spawn fails.

## Context / Background

- ccorch is a multi-agent orchestration tool at `/Users/nam/work/ai/iterm-claude-orchestration` that drives iTerm2 to spawn worker tabs grouped under a "lead" tab.
- `cc-group init` creates an iTerm2 tab group, exports `ITERM_GROUP_ID=<uuid>` into the shell, and subsequent `cc-spawn` calls read that env var to place new tabs into the same group.
- `cc-group close` destroys the underlying iTerm2 tab group.

## Reproduction

```
$ env | grep -i iterm_group
ITERM_GROUP_ID=427BDBE4-D89D-4AE1-BDEF-D969BE5438AD   # stale from a prior teardown
$ cc-spawn --badge-text reviewer reviewer '<task>'
# fails:
iterm2.window.CreateTabException: INVALID_GROUP_ID
$ unset ITERM_GROUP_ID
$ cc-spawn --badge-text reviewer reviewer '<task>'
# succeeds, but the worker tab is standalone (not grouped with the lead)
```

Workers spawned without a group are visually scattered across iTerm windows, defeating the purpose of grouping a multi-agent session under one parent.

## Root cause

Env vars in a running shell cannot be cleared from outside that shell. `cc-group close` correctly destroys the iTerm group but has no way to unset env vars in the parent shell. The stale `ITERM_GROUP_ID` then persists into the next `cc-group init` / `cc-spawn` unless the shell is restarted.

## Suggested fixes

1. `cc-group init` validates the existing `ITERM_GROUP_ID` (via iTerm's Python API: attempt to fetch the group, catch `INVALID_GROUP_ID`) **before** creating a new group, and `unset`/overwrites the stale value via a shell hook or a sourceable file the user can `source`.
2. `cc-spawn` validates the auto-detected `ITERM_GROUP_ID` before passing it to `async_create_tab`. If invalid, either spawn standalone with a warning, or fall back to a default group from the active iTerm window.
3. Document the gotcha in the ccorch README: "If you tore down a group and immediately re-init, `unset ITERM_GROUP_ID` first."
4. After `cc-group close`, print a hint like: `Note: run "unset ITERM_GROUP_ID" or open a new shell before re-initialising.`

## Affected code paths

- [/Users/nam/work/ai/iterm-claude-orchestration/src/ccorch/iterm_real.py:29](/Users/nam/work/ai/iterm-claude-orchestration/src/ccorch/iterm_real.py) — `async_create_tab(**kwargs)` raises `CreateTabException` when the supplied group id is unknown to iTerm.
- The `cc-spawn` entrypoint that auto-detects `$ITERM_GROUP_ID`.
