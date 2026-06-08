# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

- When in a new worktree, init all git submodules before building: `git submodule update --init --recursive`
- `make run` -- build Development config and launch the app
- `tools/build.sh` (or `tools/build.sh Development`) -- debug build only, logs to `tmp/build.log`
- `make install` -- build Deployment config and install to `/Applications/iTerm.app`
- `make test` -- run all unit tests
- `tools/run_tests.expect ModernTests/TestClass/testMethod` -- run a single test
- `tools/add_file_to_xcodeproj.rb <file_path> <target_name>` -- add a new file to the Xcode project (e.g., `tools/add_file_to_xcodeproj.rb sources/Example.swift iTerm2SharedARC`)

### Fixing stale precompiled header errors

If `make install` (Deployment config) fails with `AST Deserialization Issue: file has been modified since the precompiled header was built`, the shared PCH cache is stale. This typically happens after a `make run` (Development) regenerates `BrowserExtensionShared.modulemap`. The `Deployment` Makefile target now clears `SharedPrecompiledHeaders` automatically before each build, so simply re-running `make install` should resolve it. If it persists, manually clear the cache:

```sh
/bin/rm -rf ~/Library/Developer/Xcode/DerivedData/iTerm2-*/Build/Intermediates.noindex/PrecompiledHeaders/SharedPrecompiledHeaders
make install
```

## Architecture

### Core Object Hierarchy

```
iTermController (app singleton)
  └── PseudoTerminal (NSWindowController, one per window)
        ├── PSMTabBarControl (tab bar UI, ThirdParty, MRC)
        ├── PTYTab (one per tab, manages split pane layout)
        │     └── PTYSession (one per terminal pane)
        │           ├── PTYTask (subprocess I/O)
        │           ├── PTYTextView (terminal text rendering)
        │           ├── VT100Terminal (ANSI sequence parser)
        │           └── VT100Screen (screen buffer model)
        └── iTermTabGroup (optional, runtime-only tab grouping)
```

### Memory Management: ARC vs MRC

The codebase is split across two targets with different memory management:

- **iTerm2SharedARC** -- ARC enabled. Most new code goes here.
- **iTerm2** (main target) -- MRC (manual retain/release). Legacy ObjC code.
- **ThirdParty/PSMTabBarControl/** -- MRC. All tab bar control code uses manual retain/release.

When adding files, choose the target based on memory management needs. When editing PSMTabBarControl or other MRC code, use `retain`/`release`/`autorelease` explicitly.

### Rendering

GPU-accelerated rendering via Metal:
- **iTermMetalDriver** (`sources/Metal/`) -- main rendering engine, coordinates ~39 specialised cell renderers
- Metal shaders in `.metal` files alongside their renderers
- Fallback to non-Metal path exists for compatibility

### Tab Bar Control (ThirdParty/PSMTabBarControl/)

The tab bar is a heavily customised third-party control. Key concepts:

- **`_cells`** -- 1:1 array with NSTabViewItems. Source of truth for tab ordering.
- **`_displayCells`** -- derived from `_cells` by `rebuildDisplayCells`. Includes virtual group header cells, excludes collapsed group members. Used for hit testing (`cellForPoint:`) and drawing.
- **Placeholders** -- during drag, collapsed placeholders are inserted between cells. The dragged cell is replaced by an expanded placeholder. The animation loop (`calculateDragAnimationForTabBar:`) expands/collapses placeholders based on mouse position.
- **Tab styles** -- `PSMYosemiteTabStyle.m` (ObjC) and `PSMTahoeTabStyle.swift` (Swift) implement the visual appearance.

### Project Structure

```
sources/           ~2000 files (Swift + ObjC), including sources/Metal/ for GPU rendering
ThirdParty/        PSMTabBarControl (tab bar), Sparkle (updates), NMSSH (SSH), fmdb (SQLite), etc.
ModernTests/       Swift XCTest unit tests (~60 files)
iTerm2XCTests/     ObjC XCTest unit tests (~44 files)
tests/             Manual test data and scripts (not unit tests)
tools/             Build scripts (build.sh, add_file_to_xcodeproj.rb, run_tests.expect)
submodules/        Git submodules (Sparkle, CoreParse, NMSSH, etc.)
```

## Python SDK Local Testing

The iTerm2 Python runtime (`iterm2env-78`) is a pre-built zip downloaded on first launch. It does **not** pick up source changes from `api/library/python/iterm2/` automatically. `make run` handles this -- it runs `make python-sdk` before launching, which pip-installs the source package into all runtime Python environments. You can also run `make python-sdk` independently. Restart the Python console (Scripts → Manage → Console) to pick up changes in a running app.

## Code Best Practices

- Don’t write more than one line of inline javascript, html, or CSS. Instead create a new file and load it using iTermBrowserTemplateLoader.swift.
- After creating a new file, `git add` it immediately.
- In Swift, use `it_fatalError` and `it_assert` instead of `fatalError` and `assert`, which do not create useful crash logs. In ObjC, `assert` is ok although `ITAssertWithMessage` is preferable.
- Don’t create dependency cycles. Use delegates or closures instead.
- When renaming a file tracked by git, use `git mv` instead of `mv`.
- Little scripts or text files that are used for manual testing of features go in `tests/`.
- The deployment target is macOS 12. Don’t add availability checks for 12 and lower.
- Don’t replace curly quotes with straight quotes. Same for apostrophes and single quotes. Copy these if needed: \u2018\u2019\u201c\u201d
- In user-visible strings do not use “ except as a shorthand for inch. Prefer curly quotes like \u201c and \u201d.
- Never use auto layout in the terminal window (including the toolbelt). It virally spreads and breaks autoresizing. Fine in other windows (e.g., AI chat window).
- Never `git add` submodules without express written permission.
- Don’t include AI-generated markdown files (summaries, plans, etc.) in commits \u2014 only ship code.
- Avoid duplicate expressions; hoist shared computations into a named `const` before branching.
- Don’t change defaults silently.
- Use `[iTermUserDefaults userDefaults]` instead of `[NSUserDefaults standardUserDefaults]`.
- Do not use associated objects (`objc_getAssociatedObject`/`objc_setAssociatedObject`) without express written permission.
- Treat warnings as errors. If your changes introduce compiler warnings, fix them.
- If you get stuck, ask for help. It’s better to ask the user to look at something in the debugger than to flail around.
