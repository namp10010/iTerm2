# High memory use with many parked tabs — iTerm2 retains the full per-session model

**Date:** 2026-06-07
**Measured on:** iTerm2 3.6.20260607, macOS 26.5.1, 37 live sessions (all parked), scrollback = 15,000 lines/profile.

## Summary

Parking a tab kills the **child process** (shell + descendants) but deliberately keeps iTerm2's entire **in-process model** of the session alive — `VT100Screen`, the `LineBuffer` scrollback, the DVR (Instant Replay) ring, `PTYTextView`/`SessionView`, and the `PTYSession` itself — so the tab can still render and revive instantly. The freed memory therefore belongs to the *killed child processes* (separate OS processes), which barely moves iTerm2's own RSS. With ~37 parked sessions the app sat at a **1.3 GB physical footprint** (peak 1.9 GB; ~645 MB resident + ~744 MB compressed/swapped, which is why Activity Monitor reports ~1.5 GB).

Measurement (`heap`/`vmmap`) shows the heap is dominated by three roughly-equal blocks, each ~250–300 MB, **none of which parking frees**:

| Subsystem | Bytes | What it is |
|---|---:|---|
| **Instant Replay (DVR)** | **~296 MB** | `DVRBuffer.store_`, 37 × **8 MB rings**, malloc'd up-front at session init |
| **Live scrollback** | **~256 MB** | `iTermCharacterBuffer._buffer` — the 15k-line history (12 B/`screen_char_t`) |
| **Restorable-state copy of scrollback** | **~254 MB** | A *second* full copy of all scrollback, retained in memory for incremental restorable-state delta-saves |
| Per-line scrollback metadata + small-object tail | ~150–200 MB | external attributes, full-line caches, per-line `CFString`/`NSData`/dict |
| Command history (CoreData) | ~40–100 MB | ~64,000 `CommandHistory` rows loaded in memory |
| Metal / images | **~12 MB** | negligible — **not** a factor |

**Two of the three big blocks are redundant or eager:** roughly **half a gigabyte is two full copies of the scrollback** (live + restorable-state), and **~300 MB is Instant Replay buffers allocated for every session even if Instant Replay is never opened**.

Metal/GPU is *not* a contributor: background (non-foreground) tabs already tear their Metal driver/view down, and the glyph atlas is a single shared per-GPU cache.

## Context / Background

- "Parking" (recent feature) idles unused tabs by killing their shell after a timeout. `-[PTYSession park]` SIGHUPs the process group; the parked broken-pipe branch sets `_exited = YES` and returns **without** calling `hardStop` or disconnecting the textview, so the full terminal model is retained.
- macOS compresses the idle parked memory (744 MB swapped/compressed in this snapshot), so resident size understates the logical footprint. The "memory" figure in Activity Monitor includes compressed pages.

## Measurement / Reproduction

```
pid=$(pgrep -x iTerm2)
vmmap --summary "$pid"          # Physical footprint + region breakdown (MALLOC vs IOAccelerator vs images)
heap --sortBySize "$pid"        # Per-class / per-allocation byte totals — the decisive tool
leaks "$pid"                    # Confirms it is retained-by-design, not a leak
```

Key `heap` rows observed (1,265,460,710 bytes live across 8 zones, 37 `PTYSession`/`VT100Screen`/`DVR`):

```
   37  310378496  8388608.0   DVRBuffer.store_ (char[])                       iTerm2
 2629  268795904   102242.6   iTermCharacterBuffer._buffer (screen_char_t)    iTerm2
 2677  266286976    99472.2   CFData (Bytes Storage)                          CoreFoundation
```

The `vmmap` `DefaultMallocZone` held ~1.2 GB allocated; graphics regions were ~11 MB — confirming the cost is C-heap, not GPU.

## Root cause (per block)

### 1. Instant Replay / DVR — ~296 MB, eager and unconditional

Every `VT100Screen` allocates a DVR at init, and `DVRBuffer` mallocs the **entire** `IRMemory`-sized ring immediately (8 MB here), regardless of whether Instant Replay is ever used. 37 sessions × 8 MB = ~296 MB, retained while parked.

- [/Users/nam/work/swift/iTerm2/sources/VT100Screen.m:86](/Users/nam/work/swift/iTerm2/sources/VT100Screen.m) — `dvr_ = [DVR alloc] initWithBufferCapacity:IRMemory*1024*1024]` (unconditional).
- [/Users/nam/work/swift/iTerm2/sources/DVRBuffer.m:72](/Users/nam/work/swift/iTerm2/sources/DVRBuffer.m) — `store_ = iTermMalloc(maxsize)` allocates the full ring up-front.
- [/Users/nam/work/swift/iTerm2/sources/iTermPreferences.m:482](/Users/nam/work/swift/iTerm2/sources/iTermPreferences.m) — `IRMemory` default (`@4`; the measured app used 8 MB).

**Status:** Disabled via Prefs → General → Instant Replay memory usage = 0. Capacity-0 DVRBuffer still allocates via `iTermMalloc(0)` (non-null POSIX `malloc(0)`) but records nothing and uses no meaningful memory.

### 2. Live scrollback — ~256 MB, uncompressed

Scrollback chars are stored uncompressed in `iTermCharacterBuffer` (plain malloc'd `screen_char_t` buffer, 12 B/char) at one buffer per `LineBlock` (~72 blocks/session at 15k lines). There is no compression or eviction for idle/hidden/parked sessions.

- [/Users/nam/work/swift/iTerm2/sources/iTermCharacterBuffer.h](/Users/nam/work/swift/iTerm2/sources/iTermCharacterBuffer.h), [/Users/nam/work/swift/iTerm2/sources/iTermCharacterBuffer.m:51](/Users/nam/work/swift/iTerm2/sources/iTermCharacterBuffer.m) — `iTermUninitializedCalloc(size, sizeof(screen_char_t))`.
- A run-length-compressing alternative exists but was abandoned in the hot path for performance: [/Users/nam/work/swift/iTerm2/sources/CompressibleCharacterBuffer.swift](/Users/nam/work/swift/iTerm2/sources/CompressibleCharacterBuffer.swift); see the note at [/Users/nam/work/swift/iTerm2/sources/LineBlock.mm:45](/Users/nam/work/swift/iTerm2/sources/LineBlock.mm) ("could be compressed. No longer supported because overhead … was too slow").

**Status:** Reduced by lowering scrollback to 3,000 lines/profile.

### 3. Restorable-state copy of scrollback — ~254 MB, redundant

iTerm2 keeps a **persistent in-memory copy of the entire scrollback** to compute incremental restorable-state delta-saves. This is the `self.record` property on `iTermGraphDatabase` — an `iTermEncoderGraphRecord` tree that mirrors every row currently in the SQLite `Node` table. Each leaf node corresponding to a `LineBlock` holds the `NSData` produced by `_characterBuffer.data` inside its `_pod` dictionary.

#### How the redundant copy arises

Every save runs this chain:

```
iTermGraphDatabase.updateSynchronously:
  └─ iTermGraphDeltaEncoder(previousRevision: self.record)   ← keeps last snapshot
        └─ LineBuffer.encodeBlocks:
               └─ for each LineBlock:
                     block.dictionary                         ← _characterBuffer.data
                     │   = NSData copy of the block's chars
                     │   stored in the record's _pod dict
                     │
                     └─ compare generation with previousRevision
                           unchanged → skip the DB write, re-use old record
                           changed   → write new row to SQLite

  after save: self.record = encoder.record    ← new snapshot becomes the baseline
```

The delta encoder uses the previous revision **only for generation-number comparison** — it never reads the `_pod` content of unchanged records. But the `NSData` blobs stay in `_pod` because `iTermEncoderGraphRecord` has no mechanism to drop them after a save.

Key files:
- [/Users/nam/work/swift/iTerm2/sources/LineBlock.mm:2697](/Users/nam/work/swift/iTerm2/sources/LineBlock.mm) — `@{ kLineBlockRawBufferV3Key: _characterBuffer.data, … }` — creates a full `NSData` copy of the block on each encode.
- [/Users/nam/work/swift/iTerm2/sources/LineBuffer.m:1858](/Users/nam/work/swift/iTerm2/sources/LineBuffer.m) — `-encodeBlocks:` merges each block's dictionary into the encoder.
- [/Users/nam/work/swift/iTerm2/sources/iTermGraphDatabase.m:147](/Users/nam/work/swift/iTerm2/sources/iTermGraphDatabase.m) — `initWithPreviousRevision:self.record` — passes the retained snapshot to the next delta encoder.
- [/Users/nam/work/swift/iTerm2/sources/iTermGraphDatabase.m:272](/Users/nam/work/swift/iTerm2/sources/iTermGraphDatabase.m) — `self.record = encoder.record` — replaces the snapshot after each save; the new tree also carries full pods.
- [/Users/nam/work/swift/iTerm2/sources/iTermEncoderGraphRecord.m:75](/Users/nam/work/swift/iTerm2/sources/iTermEncoderGraphRecord.m) — `_pod` ivar stores the `NSDictionary` (containing the `NSData` blobs); `data` property (`:392`) serialises `_pod` on demand but does not cache — so the cost is `_pod` itself, not a cached `NSData`.

#### Why the delta skipping doesn't help memory

The delta encoder skips **writing to SQLite** for unchanged blocks (`iTermGraphDatabase.m:424-428`), but the `_pod` dicts (containing the char `NSData`) remain in `self.record`'s tree to populate the next encoder's `previousRevision`. The optimisation reduces disk I/O, not RAM.

#### What `self.record` is actually used for after a save

After a successful save, `self.record` is read in exactly two ways:
1. **Next delta save** — `iTermGraphDeltaEncoder` walks the tree comparing `record.generation`, `record.key`, `record.identifier`, and `record.rowid`. It calls `encodeGraph:record` for unchanged nodes, which just appends the record to a children array without touching `_pod`. **Pod content is never read.**
2. **App-startup restoration** — `iTermRestorableStateSQLite` reads `_db.record` (`:162, 174, 224, 249`) to reconstruct windows and sessions, walking deep into the graph tree. **Pod content is read here.** This happens once at startup, before any regular save has run.

### 4. Command history (CoreData) — ~40–100 MB, global

~64,000 `CommandHistory` rows (`_CDSnapshot_CommandHistoryEntry_`, `NSSQLRow`, `iTermCommandHistory*MO`, faulting sets) are resident. Not per-parked-tab, but a notable always-on cost that grows with history.

## Why parking doesn't help iTerm2's RSS

- [/Users/nam/work/swift/iTerm2/sources/PTYSession.m:3752](/Users/nam/work/swift/iTerm2/sources/PTYSession.m) — `-park` only SIGHUPs the process group.
- [/Users/nam/work/swift/iTerm2/sources/PTYSession.m:4360](/Users/nam/work/swift/iTerm2/sources/PTYSession.m) — parked broken-pipe branch sets `_exited = YES` and returns; does **not** call `hardStop` (contrast `:3667`, `:3693`, `:13701`) — so `VT100Screen`/`LineBuffer`/DVR/view all stay alive.
- [/Users/nam/work/swift/iTerm2/sources/PTYTab.m:6801](/Users/nam/work/swift/iTerm2/sources/PTYTab.m) + [/Users/nam/work/swift/iTerm2/sources/SessionView.m:891](/Users/nam/work/swift/iTerm2/sources/SessionView.m) — Metal is already disabled and `removeMetalView` (`_driver`/`_metalView = nil`) for non-foreground tabs, so Metal is not part of the per-parked-tab cost.

## Proposed solutions (in impact order)

### A. Instant Replay (DVR) — ~296 MB ✅ mitigated

**Interim fix applied:** Instant Replay disabled (Prefs → General → memory usage = 0). Eliminates the 37 × 8 MB rings.

**Proper code fix (future):** allocate the `DVRBuffer` ring lazily — only on the first recorded frame — rather than up-front at session init (`VT100Screen.m:86` → `DVRBuffer.m:72`). Alternatively, release `dvr_` on park and re-create on revive.

Trade-off: lazy DVR means Instant Replay history is unavailable until the session records its first frame. Acceptable; gate on the existing IR preference.

### B. Drop pods from `self.record` after each successful save — ~254 MB

This is the highest-confidence code fix remaining. **Effort: ~25 lines across 3 files.**

#### Why it is safe

The delta comparison path in `iTermGraphDeltaEncoder` only reads `record.generation`, `record.key`, `record.identifier`, `record.rowid`, and `record.graphRecords`. It calls `encodeGraph:record` (`:iTermGraphEncoder.m:166`) for unchanged nodes, which just appends the record to an array — `_pod` is never accessed. `after.data` (which serialises `_pod`) is only called for **changed** records, which come from the freshly-encoded "after" tree, not from `self.record`. Recovery (`trySaveEncoder:`, `:245-246`) also uses `originalEncoder.record` (the fresh tree), not `self.record`.

The one path that genuinely needs pod content — startup restoration (`iTermRestorableStateSQLite.m:224, 249`) — runs **before** the first regular save completes, so dropping pods after-save never races with it.

#### The change

**`iTermEncoderGraphRecord.h/.m`** — add a recursive `dropPods` method:

```objc
- (void)dropPods {
    _pod = nil;
    _podLoaded = NO;
    for (iTermEncoderGraphRecord *child in _graphRecords) {
        [child dropPods];
    }
}
```

**`iTermGraphDatabase.m:272`** — call it immediately after the snapshot is replaced:

```objc
self.record = encoder.record;
if (_restorationComplete) {
    [self.record dropPods];
}
```

**`iTermGraphDatabase.h/.m`** — add `markRestorationComplete`:

```objc
- (void)markRestorationComplete { _restorationComplete = YES; }
```

**`iTermRestorableStateSQLite.m`** — call it once after the last restoration call completes (after `restoreApplicationState` and the last `restoreWindowWithRecord:completion:` callback).

#### The one risk: restoration timing

`markRestorationComplete` must be called **after** the last use of `_db.record`'s pod data. The restoration path is:
1. `loadRestorableStateIndexWithCompletion:` (`:166`) — reads `record.recordArrayWithKey:@"windows"`, which reads `_pod[@"__order"]` on array nodes. Needs pod.
2. `restoreWindowWithRecord:completion:` (`:208`) — walks deep into the graph tree to reconstruct sessions/scrollback. Needs pod.
3. `restoreApplicationState` (`:245`) — reads `_db.record` for app-level state. Needs pod.

After all three are done, pods are safe to drop. The right call site is wherever the app-delegate signals "restoration is complete" — likely after `NSApplicationDidFinishLaunchingNotification` or the last window-restoration callback.

#### Files to change

- [/Users/nam/work/swift/iTerm2/sources/iTermEncoderGraphRecord.h](/Users/nam/work/swift/iTerm2/sources/iTermEncoderGraphRecord.h) — declare `dropPods`
- [/Users/nam/work/swift/iTerm2/sources/iTermEncoderGraphRecord.m](/Users/nam/work/swift/iTerm2/sources/iTermEncoderGraphRecord.m) — implement `dropPods`
- [/Users/nam/work/swift/iTerm2/sources/iTermGraphDatabase.h](/Users/nam/work/swift/iTerm2/sources/iTermGraphDatabase.h) — declare `markRestorationComplete`
- [/Users/nam/work/swift/iTerm2/sources/iTermGraphDatabase.m](/Users/nam/work/swift/iTerm2/sources/iTermGraphDatabase.m) — implement flag + call `dropPods` at `:272`
- [/Users/nam/work/swift/iTerm2/sources/iTermRestorableStateSQLite.m](/Users/nam/work/swift/iTerm2/sources/iTermRestorableStateSQLite.m) — call `markRestorationComplete` after restoration

### C. Compress live scrollback on park — ~256 MB (reduced by scrollback limit)

**Interim mitigation applied:** scrollback reduced from 15,000 to 3,000 lines, cutting per-session live scrollback by ~80%.

**Code fix (future):** repurpose the dormant `CompressibleCharacterBuffer` (`sources/CompressibleCharacterBuffer.swift`) to compress idle/parked `LineBlock` char buffers. The performance objection that removed it from the hot path (`LineBlock.mm:45`) is far weaker for parked sessions (rarely accessed). Decompress lazily on revive or scroll.

Trade-off: scope strictly to parked/idle blocks; benchmark decompression latency on first scroll after revive.

### D. Command history (CoreData) — ~40–100 MB, separate investigation

Investigate why ~64,000 rows are resident (faulting / caching behaviour); consider bounding the in-memory working set.

## Verification for any future fix

- Re-run the differential: `vmmap --summary`/`heap --sortBySize` at ~2 tabs vs ~37 parked tabs, before and after the change; the targeted block's bytes should drop by the predicted amount with no new large allocations elsewhere.
- `leaks <pid>` stays clean.
- Functional: parked tabs still display correctly and revive (and, for A/B, Instant Replay + window restoration still behave as expected).

## Evidence

Raw captures from this session: `/tmp/iterm_vmmap_50tabs.txt`, `/tmp/iterm_heap_50tabs.txt`.
