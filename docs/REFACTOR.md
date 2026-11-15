# HUD simplification audit

Branch: `refactor/simplify-hud`

Baseline: latest `main` when work began, `ab71e7beebf1a7d2e5ed21fa365e28c4694c2169`.
No merge to `main` is part of this work.

## Changes and reasons

| File | Complexity removed or retained | Reason |
| --- | --- | --- |
| `main.lua` | Moved initial sample data, local echo and demo commands to `dev/demo.lua`. | Startup now shows integration and lifecycle logic without embedding the demo implementation. Startup samples and every demo command remain enabled. |
| `main.lua` | One event map drives registration and hide/show/flight handling. | Removes duplicate event lists while retaining all 11 events and their effects. |
| `main.lua` | One ordered list defines persisted geometry fields; input mode aliases share a branch. | Removes repeated field mappings and duplicated cancellation while keeping preference format, migration and native fallback intact. |
| `ui.lua` | Removed the duplicate chat draft and listener-bound flag. | The successfully bound text-entry object owns the draft and proves that listeners were bound. Failed open/focus and normal close still release ownership. |
| `ui.lua` | Shared column sizing, edit-control visibility and rounded geometry copying. | Removes repeated operations without introducing another component framework. |
| `ui.lua` | Removed constant style assignments already present in `panel.rml`. | Header display/border, transparent panel background, splitter border and guide margin have one source. Dynamic geometry and mode-dependent inline styling remain. |
| `ui.lua` | Shared safe timer creation/cleanup and sighting timer shutdown; one fade scheduling path. | Removes duplicated engine-boundary code. Callable-table construction, injected timers, delayed retries, failure handling and timer cadence remain. |
| `ui.lua` | Removed the layout-handle counter and lookup of `online-count`. | Successful binding already requires every handle; the roster count element disappeared with the old column headings. |
| `rmlui_text_entry.lua`, `ui.lua` | Removed unused opt-in input-event tracing and its state/listeners (`trace`, `set_diagnostics`, `set_chat_diagnostics`). | These were diagnostic remnants of the input experiment, with no caller or command in the current HUD. Functional listeners, error logging and active demo scroll measurements remain. |
| `rmlui_input.lua` | Audited and left unchanged. | Reference counts, per-owner watchdogs, rollback, cancellation ordering and guarded flight restoration protect input ownership. Removing them would trade correctness for fewer lines. |
| `panel.rml` | Audited and left byte-for-byte unchanged. | Its explicit dimensions, scrollbar styles, byte alpha and segmented separator gradients address actual rendering requirements. No new styling or engine capabilities are assumed. |

## Runtime line counts

Physical lines, including comments and blank lines, measured with `wc -l`.
Tests and documentation are excluded. **The relocated demo file is included**:
it is still loaded at startup, so moving it is not claimed as a net reduction.

| Runtime file | Before | After |
| --- | ---: | ---: |
| `main.lua` | 461 | 357 |
| `rmlui_input.lua` | 199 | 199 |
| `rmlui_text_entry.lua` | 228 | 202 |
| `ui.lua` | 1,196 | 1,115 |
| `panel.rml` | 320 | 320 |
| `dev/demo.lua` | 0 | 108 |
| **Total** | **2,404** | **2,301** |

Net reduction: **103 lines (4.3%)**. The entry point is **22.6% shorter**.
This deliberately stops below the approximate 20–30% overall target. Main
already contained previous removals of chat masks, background fade experiments,
and HUD-hiding input modes. Most remaining bulk implements verified behavior or
guards engine calls. Further large cuts would require broader restructuring or
removing safeguards; neither is justified merely to meet a line target.

## Regression validation

The original two regression scripts passed on the baseline. The new full-entry-
point harness also passed against the baseline before runtime changes.

Run all four scripts from the checkout:

```sh
sh tests/run.sh
# Select a specific interpreter if needed:
LUA=texlua sh tests/run.sh
```

- `test_input.lua`: reference counts, rollback, PDA-safe restoration, watchdogs,
  text changes, Tab completion, delayed caret positioning, Enter/Escape,
  numpad Enter, form submission, stale completion and watchdog failure.
- `test_layout.lua`: geometry, 40px online minimum, persistence round-trip,
  manual versus automatic scrolling, delayed bottom-follow, newest-first/top-
  following sightings, smooth fade values, preserved DOM rows, and appearance
  contracts. Static styles are read from the actual RML rather than requiring
  duplicate inline assignments.
- `test_main.lua`: loads the actual entry point and modules; tests startup,
  Shift+A binding, local echo, cleared drafts, native prompt, all lifecycle
  events, PDA polling while idle/chatting/editing, docking, preferences,
  legacy migration/fallback, demo commands and unload. It uses a callable-table
  Timer and removes `setmetatable` before loading runtime code.
- `test_timers.lua`: cached/callable timers, exact 40/120/240ms chat retries,
  40ms sighting top correction, fade scheduling, constructor/scheduling
  failures and cleanup on hide/unmount.

All four scripts pass under **Lua 5.1.5** and the host's `texlua` interpreter.
Lua 5.1.5 `luac -p` accepts every runtime Lua file. The interpreter was built
outside the repository for validation; it is not a plugin dependency.
`git diff --check` passes. Tests now total 1,236 Lua lines versus 935 previously; no tests were
removed to improve runtime counts. The old source-slicing demo/PDA/preference
checks were replaced with broader execution of the actual entry point.

## Confirmed engine workarounds retained

- Load `panel.rml` from `main.lua`, preserving VO's plugin-relative path rules.
- Copy methods to objects; runtime code does not require metatables.
- Keep native IUP HUD visible; disable only its input while RmlUi owns it.
- Restore IUP state before cancellation callbacks; never force flight input
  over a PDA/menu. Keep both HUD events and 125ms visibility polling.
- Read typed values from change/submit event parameters, not generic `.value`.
- Use native `TabCompleteName` and a guarded delayed synthetic `KI_END`.
- Construct callable `Timer()` under protection; retain all scroll retries and
  distinguish mouse intent from layout-generated scroll events.
- Keep explicit list heights, the reserved 29px input row, invisible-but-present
  flight scrollbars, 8px splitter hit targets and 40px online minimum.
- Keep millisecond-anchored sighting opacity on existing rows, 85% fade start,
  12% final opacity, 40ms fade pulses, one-second age/expiry updates and top-follow
  only on arrival.

## Remaining in-game verification

Automated tests simulate VO APIs; they cannot render the actual client or
establish real keyboard/mouse ownership. Before merging, repeat these checks:

1. Install `dev/demo.lua` with the rest of the plugin; reload and verify the same
   initial roster/chat/sightings, local echo and demo commands.
2. Drag/move/resize, shrink Online to 40px, click DONE and reload. Check saved
   geometry, independent scrolling, separators, padding, pill, transparency
   and flight/layout appearance against `main`.
3. Shift+A, multi-word Tab completion followed by typing, Enter, Escape and
   watchdog recovery. The native HUD/radars must stay visible throughout.
4. Open navigation/PDA while idle, chatting and editing; Skynet must hide,
   release input without overriding the PDA, and return on exit. Also dock,
   undock and reload.
5. Demo flood: bottom-follow after wrapping/relayout, manual scroll preservation,
   smooth late-life sighting fade and expiry. Demo scroll: newest-first/top-
   follow on new sightings without age updates disturbing manual browsing.

The entry point's recurring refresh/visibility timers retain their baseline
unload behavior; this refactor does not introduce a separate lifecycle change.
