# TODO 16 — Quick-command overlay that runs in a child shell

## Context

TODO item 16 (TODO.md:18) asks for:

> A shortcut to run a quick command, similar to hotkey window but use a sub-shell of the existing shell so it inherits the environment. I do like the composer but in composer when Shift+Enter it just sends the text to existing session terminal.

The user's actual underlying frustration (clarified during planning): when an interactive program (vim, less, top, ssh, …) has the PTY foreground, sending text via the Composer just feeds keystrokes to that program rather than executing them as a shell command. The "child shell" framing is one way to escape that — the goal is "run a shell command without interfering with whatever currently has the PTY foreground", and ideally with the live shell's environment.

The investigation should add the capability as an **option to the existing Composer** rather than a new overlay.

---

## Feasibility findings

### Real "child of the running shell" is impossible

Unix process model: a process can only spawn its own children. iTerm2 cannot inject a process under `/bin/zsh`'s PID — the shell is iTerm2's child, and any new process iTerm2 spawns is a sibling of the shell, not a grandchild. The **only** way to get a true grandchild of the live shell is to send text down the PTY (`( cmd )` group), which means going through the prompt — exactly what the user wants to avoid.

### "Run in the current shell while another program holds the foreground" is also impossible

Only one process at a time owns the PTY foreground process group. While vim/less/top/ssh has it, the shell isn't reading from the PTY at all (it's blocked in `wait()`). Anything written to the PTY goes to that child, not to the shell. There is no kernel mechanism for "send this to the parent of whoever currently owns the PTY".

### Three approximations considered

| Option | Approach | Live env | Aliases/funcs | Doesn't disturb prompt | Works while interactive prog is foreground | Verdict |
|---|---|---|---|---|---|---|
| A — TTY wrap `( cmd )` | Send `( cmd )\n` to PTY | ✅ | ✅ | ❌ injects into prompt | ❌ goes to vim instead | Same problem the user is trying to avoid |
| B — Coprocess (`fork`+`execl /bin/sh -c`) | Spawn sibling-of-shell process; output rendered inline | ❌ launch-time only | ❌ | ✅ | ✅ | **Recommended** |
| C — Smart hybrid | Pick A when shell idle (via shell-integration `OSC 133;C/D` marks), else B | varies | varies | varies | ✅ | Future enhancement |

**Decision:** ship Option B. Option C ("smart") can come later as a sub-mode that switches automatically.

---

## Composer architecture (existing, already extensible)

```
iTermComposerManager  (sources/iTermComposerManager.{h,m})
  ├─ iTermMinimalComposerViewController  (full-overlay variant)
  │    └─ iTermStatusBarLargeComposerViewController
  │         └─ ComposerTextView  (sources/ComposerTextView.swift) -- iTermComposerTextView
  └─ iTermsStatusBarComposerViewController  (compact status-bar variant)

Submit path on Enter / Shift+Enter:
  ComposerTextView
    -> iTermMinimalComposerViewController.delegate (minimalComposer:sendCommand:..., minimalComposer:enqueueCommand:...)
    -> iTermComposerManager.delegate
    -> PTYSession (composerManager:sendCommand:, composerManager:enqueueCommand:, composerManager:sendControl:, composerManager:sendToAdvancedPaste:)
    -> PTYSession.sendCommand: -> reallySendCommand: -> writeTask: -> _shell writeTask:data
```

Critical files:
- [sources/iTermComposerManager.h](file:///Users/nam/work/swift/iTerm2/sources/iTermComposerManager.h) — delegate protocol (line 20-80) — extension point
- [sources/iTermComposerManager.m](file:///Users/nam/work/swift/iTerm2/sources/iTermComposerManager.m) — central dispatcher (forwards user submit to PTYSession)
- [sources/ComposerTextView.swift](file:///Users/nam/work/swift/iTerm2/sources/ComposerTextView.swift) — Swift text view; submit modifiers handled here
- [iTermMinimalComposerViewController.{h,m}](file:///Users/nam/work/swift/iTerm2/iTermMinimalComposerViewController.h) — overlay controller (lines 326-380 forward submit to delegate)
- [sources/PTYSession.m](file:///Users/nam/work/swift/iTerm2/sources/PTYSession.m) — implements `iTermComposerManagerDelegate` (line 21491+); `sendCommand:` 21846, `reallySendCommand:` 21892
- [sources/iTermKeyBindingAction.h](file:///Users/nam/work/swift/iTerm2/sources/iTermKeyBindingAction.h) — `KEY_ACTION_COMPOSE = 64` (line 104); we'll add a new action
- [sources/Coprocess.m](file:///Users/nam/work/swift/iTerm2/sources/Coprocess.m) — `fork()` line 91, `execl("/bin/sh", "/bin/sh", "-c", cmd, 0)` line 119
- [sources/PTYSession.m:8563](file:///Users/nam/work/swift/iTerm2/sources/PTYSession.m) — `launchCoprocessWithCommand:` (existing entry point)
- [sources/PTYTask.m:897-899](file:///Users/nam/work/swift/iTerm2/sources/PTYTask.m) — bidirectional pipe (shell PTY output → coprocess stdin)
- [sources/TaskNotifier.m:197-201](file:///Users/nam/work/swift/iTerm2/sources/TaskNotifier.m) — coprocess stdout drain → session

Existing Composer submit modes (we add a fourth that follows the same pattern):

| Mode | Trigger | Delegate method | Effect |
|---|---|---|---|
| Send | Cmd+Enter | `composerManager:sendCommand:` | Writes command to PTY immediately |
| Enqueue | Shift+Enter | `composerManager:enqueueCommand:` | Waits for next shell prompt mark, then writes |
| Send control | Toolbar | `composerManager:sendControl:` | Writes raw control char |
| Advanced paste | Toolbar | `composerManager:sendToAdvancedPaste:` | Routes to advanced paste UI |
| **NEW: Run in child shell** | **Option+Enter** + new toolbar button | `composerManager:runCommandInChildShell:` | Fork+exec via coprocess; output inline; parent prompt untouched |

---

## Coprocess output model (how stdout/stderr/stdin actually flow)

This dictates the exact wrapper shape we need to send to `sh -c`.

```
sh -c "your command"
  ├─ stdout → pipe → TaskNotifier select() loop → [Coprocess read]
  │            → inputBuffer_ (1KB reads, capped at kMaxInputBufferSize)
  │            → [task writeTask:data coprocess:YES]      (TaskNotifier.m:200)
  │            → fed into the session's PTY-write path AS IF the shell emitted it
  │            → VT100 parser → screen buffer → rendered inline
  │
  ├─ stderr → separate dispatch queue (Coprocess.m:194 monitorErrorsOnFileDescriptor:)
  │           → accumulated into a 100KB buffer
  │           → displayed in an NSAlert at coprocess termination via
  │             coprocess:didTerminateWithErrorOutput:    (NOT streamed inline)
  │
  └─ stdin ← receives the shell's PTY output too           (PTYTask.m:897-899)
            (bidirectional design; usually irrelevant for one-shots,
             but commands that read stdin would consume shell output)
```

### Practical implications and required mitigations

| Behaviour | Implication | Mitigation |
|---|---|---|
| stdout goes through VT100 parser | Escape sequences in output WILL affect the screen (colours, `clear`, cursor moves) — usually desired. | None needed. |
| Output interleaves at cursor | Lands wherever the cursor is, with no visual fence. On a prompt line, looks ugly. | Wrapper prefixes `\r\n`; UX may add a leading marker (e.g. dim "↳") in a future polish pass. |
| **stderr buffered until termination** | `git status: fatal: ...` appears in a popup alert *after* the command exits. | **Wrapper appends `2>&1`** — merges stderr into stdout so it streams inline. |
| Coprocess receives shell PTY output on stdin | Commands that read stdin (`grep PATTERN`, `cat`) would consume shell output. | **Wrapper appends `</dev/null`** — coprocess sees EOF on stdin immediately. |
| Only one coprocess per session | iTerm2 already has `NoSyncTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier` (PTYSession.m:364). | Submitting while one runs: show the existing announcement; user can stop or wait. Future: queue option. |
| Rate-limited (1KB reads via select) | Fine for normal output; massive output is throttled but lossless. | None needed. |
| Output to PTY-write path also broadcasts to other tabs if broadcast-input is on | Surprise factor with broadcasted sessions. | Document in tooltip; reuse `writeTask:coprocess:` which already routes correctly. |

### Wrapper shape sent to `sh -c`

```sh
cd "$cwd" && { command ; } </dev/null 2>&1
```

Built in `PTYSession.m` from the live cwd captured via shell integration (`[_screen workingDirectoryOnLine:]` at PTYSession.m:2851), with proper shell escaping via the existing NSString category `stringWithEscapedShellCharactersIncludingNewlines:`.

### Latency expectation

Time-to-first-byte ≈ **10–30 ms** of overhead vs. running the same command at the prompt. Dominated by `fork()` (~1–5 ms) + `execl` of `/bin/sh -c` (~5–15 ms; `sh -c` skips rc files), then `sh` forks the actual command (same as the shell would do). Visually imperceptible. Buffering note: a long-running coprocess may switch to fully-buffered stdio (libc behaviour, not iTerm2); workaround is `stdbuf -oL` if needed.

---

## Implementation steps

### 1. Extend the Composer delegate protocol

**File:** [sources/iTermComposerManager.h](file:///Users/nam/work/swift/iTerm2/sources/iTermComposerManager.h)

Add to `iTermComposerManagerDelegate`:

```objc
- (void)composerManager:(iTermComposerManager *)composerManager
    runCommandInChildShell:(NSString *)command;
```

### 2. Plumb the new submit type through the Composer chain

- [sources/ComposerTextView.swift](file:///Users/nam/work/swift/iTerm2/sources/ComposerTextView.swift) — handle **Option+Enter**, calling new delegate method `composerTextViewRunInChildShell(string:)`. Follow the existing Cmd+Enter / Shift+Enter pattern.
- [iTermMinimalComposerViewController.{h,m}](file:///Users/nam/work/swift/iTerm2/iTermMinimalComposerViewController.h) — forward to `[self.delegate minimalComposer:self runCommandInChildShell:dismiss:]`.
- [sources/iTermComposerManager.m](file:///Users/nam/work/swift/iTerm2/sources/iTermComposerManager.m) — implement the new delegate, forward to `[self.delegate composerManager:self runCommandInChildShell:command]`.

### 3. Implement on PTYSession

**File:** [sources/PTYSession.m](file:///Users/nam/work/swift/iTerm2/sources/PTYSession.m) (near the existing `iTermComposerManagerDelegate` block ~21491+)

```objc
- (void)composerManager:(iTermComposerManager *)composerManager
    runCommandInChildShell:(NSString *)command {
  // Runs `command` via a coprocess (fork+exec /bin/sh -c). The coprocess is a
  // child of iTerm2, NOT of the running shell, so it inherits iTerm2's env (the
  // env the shell saw at launch) plus the live cwd captured via shell
  // integration, but it does NOT see post-launch exports, shell aliases, or
  // shell functions. This is intentional — see plan & user-facing tooltip.
  // True subshell-of-live-shell semantics require sending `( cmd )` through the
  // prompt, which is what the Send/Enqueue modes already do.
  if ([self hasCoprocess]) {
    // Existing announcement infrastructure handles the busy case; do not queue.
    [self showCoprocessBusyAnnouncement];
    return;
  }
  NSString *cwd = [_screen workingDirectoryOnLine:_screen.numberOfLines] ?: NSHomeDirectory();
  NSString *escapedCwd = [cwd stringWithEscapedShellCharactersIncludingNewlines:YES];
  // Wrapper: cd into live cwd, merge stderr->stdout (so it streams inline rather
  // than waiting for termination + alert), close stdin (so commands that read
  // stdin don't consume shell PTY output via the coprocess bidirectional pipe).
  NSString *wrapped = [NSString stringWithFormat:@"cd %@ && { %@ ; } </dev/null 2>&1",
                       escapedCwd, command];
  [self launchCoprocessWithCommand:wrapped mute:NO];
  [composerManager dismiss];
}
```

Reuses:
- `[_screen workingDirectoryOnLine:]` (PTYSession.m:2851) — shell-integration cwd
- `[self launchCoprocessWithCommand:mute:]` (PTYSession.m:8563) — fork+exec + inline render
- `stringWithEscapedShellCharactersIncludingNewlines:` — existing NSString category
- `[self hasCoprocess]` (PTYSession.m:8556) — single-coprocess constraint

### 4. Add a key-binding action so the user can map a global shortcut

- [sources/iTermKeyBindingAction.h](file:///Users/nam/work/swift/iTerm2/sources/iTermKeyBindingAction.h) — add `KEY_ACTION_COMPOSE_CHILD_SHELL` to the action enum.
- [sources/iTermKeyBindingAction.m](file:///Users/nam/work/swift/iTerm2/sources/iTermKeyBindingAction.m) — action display name "Open Composer (run in child shell)".
- [sources/PTYSession.m:10647-10654](file:///Users/nam/work/swift/iTerm2/sources/PTYSession.m) — handle the new case alongside `KEY_ACTION_COMPOSE`: open the Composer pre-marked so Enter dispatches to the child-shell path.
- Preferences → Keys popup — expose the new action in the action list.

### 5. UI affordance in the Composer overlay

[Interfaces/iTermMinimalComposerViewController.xib](file:///Users/nam/work/swift/iTerm2/Interfaces/iTermMinimalComposerViewController.xib) — add a small "Run in child shell" toolbar button next to Send/Enqueue. Tooltip text in step 6.

### 6. Document the inheritance semantics — REQUIRED in same PR

The limitation that **live env vars, aliases, and shell functions are NOT inherited** is the single biggest source of user surprise for this feature. It MUST land in three places, all in the same PR.

#### 6a. Toolbar button tooltip (and accessibility description)

> Runs the command as an iTerm2 child process (not a child of your shell). It inherits the session's environment at launch and the current working directory, but **variables exported after the session started, shell aliases, and shell functions are NOT visible to the command.** Output is shown inline. Use `( command )` in the normal Composer if you need a true subshell of your live shell.

#### 6b. Help / About panel entry

Add a paragraph to the in-app help (locate the Composer help section, e.g. the iTermComposerManager help string or the Help menu's "Composer" entry) with this comparison table:

| Mode | Affects parent prompt? | Inherits live env exports? | Inherits aliases/functions? | Inherits live cwd? |
|---|---|---|---|---|
| Send (Cmd+Enter) | Yes — types into prompt | N/A (runs in parent shell) | Yes | Yes |
| Enqueue (Shift+Enter) | Yes — types into prompt at next prompt | N/A | Yes | Yes |
| Run in child shell (Option+Enter) | **No** | **No** (only session-launch env) | **No** | Yes (via shell integration) |

#### 6c. Inline doc-comment on `composerManager:runCommandInChildShell:`

Already shown in step 3. Stops a future maintainer from "fixing" the missing env inheritance by accident.

---

## Files to modify (summary)

| File | Change |
|---|---|
| sources/iTermComposerManager.h | New delegate method declaration |
| sources/iTermComposerManager.m | Forward new submit type to PTYSession |
| sources/ComposerTextView.swift | New Option+Enter handler |
| iTermMinimalComposerViewController.h/.m | Plumb new submit type through |
| Interfaces/iTermMinimalComposerViewController.xib | New toolbar button + tooltip |
| sources/PTYSession.m | Implement `runCommandInChildShell:` (coprocess + cwd capture + wrapper) |
| sources/iTermKeyBindingAction.h | New `KEY_ACTION_COMPOSE_CHILD_SHELL` action |
| sources/iTermKeyBindingAction.m | Action display name |
| sources/PreferencesWindow… (key bindings UI) | Expose the new action in the Keys preferences popup |

No new files needed — every primitive (overlay, coprocess, cwd tracking, keybinding action, single-coprocess gating, shell escaping) already exists.

---

## Verification plan

1. Build: `make run` (Development).
2. Open a session, `cd /tmp; export FOO=bar`.
3. Open Composer via the new shortcut → confirm Composer appears.
4. Type `pwd && env | grep FOO ; ls /no/such/path` and submit with Option+Enter.
5. Expect:
   - `/tmp` printed inline.
   - `FOO=bar` is **NOT** printed (post-launch export is not inherited — by design, documented).
   - `ls: /no/such/path: No such file or directory` is printed inline (because of `2>&1`), **not in a popup alert**.
   - The prompt line is unchanged — no text was typed into the prompt buffer.
   - Parent shell's `cd` / `export` state is unaffected.
6. Negative test (cwd isolation): in the child-shell composer run `cd /etc`; afterwards `pwd` in the parent shell still returns `/tmp`.
7. Foreground-program test (the actual user motivation): start `vim` in the session. Open Composer with the shortcut. Run `echo hello` via Option+Enter. Expect:
   - vim is **not** disturbed.
   - `hello` appears interleaved on the screen (vim will redraw over it on next refresh — expected).
   - When you `:q` vim, the session is in a normal state.
8. Regression: confirm Send (Cmd+Enter) and Enqueue (Shift+Enter) paths still work unchanged.
9. Bind `KEY_ACTION_COMPOSE_CHILD_SHELL` in Preferences → Keys to a global shortcut; verify it opens Composer in child-shell mode.
10. Documentation gates (must all pass before merge):
    - Hover the toolbar button → tooltip matches §6a verbatim.
    - `export FOO=bar; <Option+Enter> env | grep FOO` produces empty output (proves docs).
    - `alias hi='echo hi'; <Option+Enter> hi` reports "command not found" (proves docs).
    - Help panel entry rendered correctly (visual check).
    - PTYSession.m doc-comment present and unedited.

---

## Confirmed design decisions

- **UX**: extend the existing Composer with a third submit mode (Option+Enter + a toolbar button); not a separate overlay.
- **Env scope**: coprocess inherits the session's launch env + iTerm2's env; live cwd captured via shell integration. Aliases, functions, and post-launch exports are explicitly out of scope and called out in the tooltip and help.
- **Wrapper shape**: `cd "$cwd" && { command ; } </dev/null 2>&1` — handles cwd, stdin contamination, and stderr-buffering-until-termination quirks.
- **Concurrency**: one coprocess per session (existing constraint). Reuse the existing busy announcement; do not queue.
- **Smart hybrid (Option C)**: deferred to a follow-up. The `OSC 133;C/D` shell-integration marks make it a clean future enhancement: when the shell is idle at a prompt, automatically use Send instead of coprocess to get full live-env semantics for free.
