# Tab Group Architecture

## Overview

iTerm2 tab groups allow users to visually organise tabs in the vertical tab bar into collapsible, colour-coded groups with optional names. Groups are rendered as virtual header cells above their member tabs, with support for drag-and-drop reordering of both individual tabs and entire groups.

---

## Data Model

### iTermTabGroup (`sources/iTermTabGroup.h`, `.m`)

The core model object representing a tab group.

| Property | Type | Description |
|----------|------|-------------|
| `identifier` | `NSString *` (readonly) | UUID, generated at init |
| `name` | `NSString *` (nullable) | User-visible display name |
| `color` | `NSColor *` | Group colour from preset palette |
| `collapsed` | `BOOL` | Whether members are hidden |
| `tabs` | `NSArray<PTYTab *> *` (readonly) | Mutable backing array of members |

**Key methods:**
- `addTab:` / `removeTab:` / `insertTab:atIndex:` -- manage membership and set `tab.tabGroup`
- `containsTab:` / `isEmpty` -- query helpers
- `iTermTabGroupPresetColors()` -- C function returning colour palette from `tabColorMenuOptions` setting

### PTYTab integration (`sources/PTYTab.h:93`)

Each `PTYTab` has a weak `tabGroup` property pointing to its owning `iTermTabGroup` (or nil if ungrouped).

---

## Cell Architecture: `_cells` vs `_displayCells`

This distinction is fundamental to understanding everything below.

### `_cells` (NSMutableArray<PSMTabBarCell *>)
- **1:1 with NSTabViewItems** -- every tab view item has exactly one cell
- During drag: placeholders are inserted between real cells; the dragged cell is replaced by an expanded placeholder
- Group headers are **NOT** in `_cells`
- Source of truth for tab ordering

### `_displayCells` (NSMutableArray<PSMTabBarCell *>)
- **Derived** from `_cells` by `rebuildDisplayCells`
- Contains everything in `_cells` PLUS virtual group header cells
- Collapsed group members are excluded
- Used by `cellForPoint:` for hit testing
- Used by `calculateDragAnimationForTabBar:` for layout and animation
- Used by drawing code

### `rebuildDisplayCells` (`PSMTabBarControl.m:1160`)

Iterates `_cells` and builds `_displayCells`:

1. For each cell, resolves its group via `tabGroupForTabViewItem:` (or `cell.groupIdentifier` fallback for placeholders)
2. When entering a new group (`group != currentGroup`):
   - Creates/retrieves a cached header cell
   - Updates header state (name, colour, collapsed, member count) from delegate
   - Displaces preceding placeholder to after header (for drag slot positioning)
   - Adds header to `_displayCells`
3. Skips collapsed group members (`if (currentGroupCollapsed) continue`)
4. Sets `groupColor` on cells for rendering
5. Prunes stale header cache entries

---

## Rendering

### Group Header Cells (`PSMTabBarCell`)

Created via `initGroupHeaderWithFrame:name:color:collapsed:memberCount:inControlView:`. Properties: `isGroupHeader`, `groupIdentifier`, `groupName`, `groupColor`, `groupCollapsed`, `groupMemberCount`.

### Drawing (`PSMYosemiteTabStyle.m:790`, `PSMTahoeTabStyle.swift:450`)

Group headers render as:
- **Background pill**: rounded rect, group colour at 0.3 alpha
- **Chevron**: right-pointing (collapsed) or down-pointing (expanded), 0.8 alpha
- **Name text**: 10pt medium system font
- **Member count badge** (collapsed only): bold 9pt white on full-colour pill, top-right

### Vertical Layout (`PSMTabBarControl.m:1322`)

Headers get 22px height; regular cells get standard height. Origins are calculated sequentially in `finishUpdateWithRegularWidths:`.

---

## Collapse/Expand

### Toggle (`PseudoTerminal.m:7999`)

`tabView:toggleCollapseForGroup:` flips `group.collapsed` and calls `updateTabBar`. If the selected tab is in the collapsed group, selects the first visible tab outside the group.

### Display filtering

In `rebuildDisplayCells`, when `currentGroupCollapsed == YES`, all subsequent cells in that group are skipped with `continue` until the group context changes.

---

## Group Management (PseudoTerminal.m)

| Method | Line | Description |
|--------|------|-------------|
| `createTabGroupWithTab:` | 12378 | Create group with next available colour |
| `addTab:toGroup:` | 12391 | Add tab, reposition to end of group |
| `removeTab:fromGroup:` | 12444 | Remove tab, dissolve if empty |
| `dissolveGroup:` | 12453 | Remove group, keep tabs |
| `closeGroup:` | 12461 | Close all tabs and remove group |
| `reorderTabsToMakeGroupContiguous:` | 12421 | Ensure group members are adjacent |
| `nextAvailableGroupColor:` | 12470 | Pick unused colour from palette |

### Context Menus

**Ungrouped tab**: "Add to New Group", "Add to Group >" submenu (existing groups with colour swatches)

**Grouped tab**: "Remove from Group"

**Group header** (`tabView:menuForGroupHeaderCell:` at line 7957): "Rename Group...", separator, "Collapse/Expand Group", "Ungroup Tabs", "Close Group"

---

## Delegate Protocol

PSMTabBarControlDelegate methods implemented in PseudoTerminal.m:

| Method | Line | Returns |
|--------|------|---------|
| `tabGroupForTabViewItem:` | 7932 | `tab.tabGroup` |
| `isGroupCollapsed:` | 7937 | `group.isCollapsed` |
| `colorForGroup:` | 7942 | `group.color` |
| `nameForGroup:` | 7947 | `group.name` |
| `memberCountForGroup:` | 7952 | `group.tabs.count` |
| `tabView:menuForGroupHeaderCell:` | 7957 | Context menu |
| `tabView:toggleCollapseForGroup:` | 7999 | Toggle collapse |

---

## Drag and Drop

### Single-Tab Drag (existing, pre-group)

1. `mouseDragged:` detects drag threshold, calls `startDraggingCell:fromTabBar:withMouseDownEvent:`
2. `distributePlaceholdersInTabBar:` inserts collapsed placeholders between every pair of cells
3. `distributePlaceholdersInTabBar:withDraggedCell:` replaces the dragged cell with an expanded placeholder, removes adjacent collapsed PHs
4. Animation timer runs `calculateDragAnimationForTabBar:` each frame:
   - `cellForPoint:` finds cell under mouse (searches `_displayCells`)
   - For real cells: resolves to adjacent placeholder in `_cells`
   - Target placeholder expands (currentStep++); others collapse (currentStep--)
   - All cells repositioned sequentially
5. On drop: `performDragOperation:` puts dragged cell at target index, removes all PHs
6. `didDropTabViewItem:inTabBar:` in PseudoTerminal handles group membership inference

### Group-Aware Single-Tab Drop (`PseudoTerminal.m:7051`)

The `targetInsideGroup` flag (direction-aware, placeholder-transparent) determines whether a drop joins or leaves a group:

- **Hovering on group header**: `targetInsideGroup = YES`
- **Hovering on grouped tab**: `targetInsideGroup = (groupColor != nil)`
- **Hovering on placeholder**: keeps previous value (transparent to approach direction)
- **At margins**: `targetInsideGroup = NO`

Drop logic infers target group from neighbours (left/right tabs' groups) combined with `targetInsideGroup`.

### Group Drag (`PSMTabBarControl.m:1983`)

When the user drags a group header:

1. **Initiation** (`mouseDragged:`):
   - Resolves header to first member cell (searches `_cells` for group membership)
   - Sets `assistant.draggingGroup = YES`, `assistant.draggedGroupIdentifier`
   - Builds composite drag image (header + members, or just header if collapsed)
   - Saves `groupDragOriginFrame` (header's frame for correct cursor offset)
   - Replaces `cell` with `firstMember` for existing drag machinery

2. **Display during drag** (`rebuildDisplayCells`):
   - Group header is suppressed (`skipHeader` flag, NOT `continue`)
   - Expanded PH and all member cells remain in `_displayCells`
   - Members marked `hiddenForGroupDrag = YES` in animation loop
   - `drawWithFrame:inView:` returns early for hidden cells
   - Members keep full frames for `cellForPoint:` hit testing

3. **Placeholder targeting**:
   - `cellForPoint:` finds hidden members (they have full frames)
   - Target-finding code resolves to adjacent PH in `_cells`
   - PH expands normally -- works at original location and elsewhere

4. **Drop** (`didDropTabViewItem:inTabBar:` at line 7058):
   - Detects `draggingGroup && self == term` (same-window group drop)
   - Moves all other group members to follow the representative tab
   - Preserves group membership

5. **Cleanup** (`finishDrag`):
   - Resets `hiddenForGroupDrag` on all cells
   - Resets `_draggingGroup`, `_draggedGroupIdentifier`, `_groupDragImage`, `_groupDragOriginFrame` **BEFORE** `removeAllPlaceholdersFromTabBar:` (critical: the rebuild inside PH removal must see `draggingGroup = NO`)

### Key Properties (PSMTabDragAssistant.h)

| Property | Type | Description |
|----------|------|-------------|
| `targetInsideGroup` | `BOOL` (readonly) | Drop targets inside group |
| `draggingGroup` | `BOOL` | Group drag in progress |
| `draggedGroupIdentifier` | `id` | The group being dragged |
| `groupDragImage` | `NSImage *` | Composite header+members image |
| `groupDragOriginFrame` | `NSRect` | Header frame for offset calc |

---

## Bugs Fixed and Lessons Learned

### 1. Group destroyed when dragging sole member

**Problem**: Dragging the only tab in a group destroyed the group header.

**Root cause**: The expanded placeholder that replaced the dragged cell had no `groupIdentifier`, so `rebuildDisplayCells` didn't create a header for it.

**Fix**: Tag the expanded PH with `groupIdentifier` from the dragged cell's group. Add fallback in `rebuildDisplayCells` to use `cell.groupIdentifier` when `tabGroupForTabViewItem:` returns nil for placeholders.

### 2. Header/placeholder oscillation during drag

**Problem**: When hovering between the group header and first member during drag, the header and placeholder kept swapping positions every frame.

**Root cause**: `_targetInsideGroup` flipped between YES/NO depending on whether the mouse was over the header, placeholder, or gap between them.

**Fix**: Made placeholders "transparent" to `_targetInsideGroup` -- only headers and real tabs update the flag. Placeholders preserve the previous value, reflecting approach direction.

### 3. Drop-above-group incorrectly joining group

**Problem**: Dropping a tab right above a group header would join the group instead of landing outside it.

**Root cause**: After fixing oscillation by setting `groupColor` on the displaced placeholder, hovering on it always set `targetInsideGroup = YES`.

**Fix**: Reverted groupColor on displaced PH. Used direction-aware `_targetInsideGroup` instead.

### 4. "Add to Group" moves group to top

**Problem**: Right-clicking a tab above a group and selecting "Add to Group" moved the entire group to the top of the tab bar.

**Root cause**: `reorderTabsToMakeGroupContiguous:` anchored on `members[0]`. When the new tab (above the group) became the first member, all other members moved up to follow it.

**Fix**: In `addTab:toGroup:`, move the tab to after the last group member before calling `reorderTabsToMakeGroupContiguous:`.

### 5. Group not rendered after drag-and-drop expand

**Problem**: After dragging a collapsed group and expanding it, nothing rendered.

**Root cause**: In `finishDrag`, `removeAllPlaceholdersFromTabBar:` triggers `rebuildDisplayCells`. At that point `_draggingGroup` was still YES, so the group's header and members were skipped. The header cache entry was pruned. No subsequent rebuild occurred with `_draggingGroup = NO`.

**Fix**: Reset `_draggingGroup = NO` and `_draggedGroupIdentifier = nil` **before** calling `removeAllPlaceholdersFromTabBar:`.

### 6. Drag image offset for collapsed groups

**Problem**: When dragging a collapsed group, the cursor appeared offset from the header image.

**Root cause**: `startDraggingCell:` computed `_dragTabOffset` from `[cell frame]`, but `cell` was already reassigned to `firstMember` (whose frame differs from the header).

**Fix**: Added `groupDragOriginFrame` property. Set it to the header's frame before the cell swap. `startDraggingCell:` uses it when set.

### 7. No placeholder at group's original location during drag

**Problem**: Hovering over the group's previous location during group drag showed no drop slot.

**Root cause (attempt 1)**: Skipping members from `_displayCells` left no cells with area for `cellForPoint:`.

**Root cause (attempt 2)**: Giving members zero height had the same result.

**Root cause (attempt 3)**: Removing members from `_cells` also destroyed the expanded PH and broke the cell/tabViewItem 1:1 invariant.

**Actual root cause**: The expanded PH (`pc`) had `groupIdentifier` set, triggering "new group" detection in `rebuildDisplayCells`. The `continue` that skipped header creation also skipped adding `pc` to `_displayCells`. Without `pc`, the animation loop could never expand it as a drop target.

**Fix (two parts)**:
1. Replace `continue` with `skipHeader` flag -- header creation is wrapped in `if (!skipHeader)`, but the cell falls through to be added to `_displayCells`
2. Add `hiddenForGroupDrag` flag on `PSMTabBarCell` -- members keep full frames for hit testing but `drawWithFrame:` returns early. The animation loop marks members each frame; `finishDrag` resets the flag.

---

## Persistence

**Groups are NOT persisted.** There is no NSCoding implementation on `iTermTabGroup`. Groups exist only during the window's lifetime. Closing and reopening loses all group information.

---

## File Reference

| File | Role |
|------|------|
| `sources/iTermTabGroup.h/.m` | Model class |
| `sources/PTYTab.h/.m` | `tabGroup` property |
| `sources/PseudoTerminal.m` | Group CRUD, delegate, drop handling |
| `ThirdParty/PSMTabBarControl/source/PSMTabBarControl.m` | Display cells, layout, drag initiation |
| `ThirdParty/PSMTabBarControl/source/PSMTabBarCell.h/.m` | Cell properties, draw suppression |
| `ThirdParty/PSMTabBarControl/source/PSMTabDragAssistant.h/.m` | Drag state, animation, placeholders |
| `ThirdParty/PSMTabBarControl/source/PSMYosemiteTabStyle.m` | Header rendering (ObjC) |
| `ThirdParty/PSMTabBarControl/source/PSMTahoeTabStyle.swift` | Header rendering (Swift) |
