# VO Skynet Client UI — RmlUi prototype

A standalone, translucent **Vendetta Online RmlUi HUD panel** for a future Skynet client. It currently shows simulated alliance presence, chat, and recent sightings. **There is no Skynet networking or real message delivery yet.**

The maintenance refactor is on `refactor/simplify-hud`; **do not merge into main without explicit approval**. See [the refactoring audit](docs/REFACTOR.md) for changes, measurements, tests and remaining in-game checks.

## Features

- Flight-only panel arranged between the game's native radar widgets. It hides when navigation/PDA menus take over and returns when the ship HUD is visible again.
- Online roster with alliance colors, a **bounded scrollable chat history**, and sightings with age/expiry.
- **Movable/resizable panel** with draggable column separators. Position, size, and column widths persist across interface reloads; the online roster can shrink to 40px.
- **Low-chrome flight HUD:** the orange **SKYNET:** title and live colored status sit side by side at the left of a borderless title row, while the outer window outline is hidden during flight.
- **No column headings:** the roster, chat, and sightings keep their existing columns and use the reclaimed vertical space for content. Each has **8px of top padding** (about half a text line), with 3px retained at the bottom. The 1px blue divider guides now fade in over their first 12px and fade out over their last 12px, and brighten in layout mode.
- **Scrollbars hidden in flight:** chat history still scrolls and follows new messages, but the scrollbar is transparent until layout-edit mode.
- **Simple navy HUD:** a single uniform **35%-transparent** (~65%-opaque) navy fill (RmlUi `rgba(7, 20, 36, 166)`) spans all three columns and the splitter gutters. The columns themselves remain untinted to avoid stacking opacity. **SKYNET: DISCONNECTED** remains in its separate fully rounded pill, with the same navy background and a small gap beneath it. No column or chat fades.
- **Newest sightings at the top:** unlike chat (which follows its bottom), Sightings automatically scrolls to the top whenever a new sighting arrives. Entries are newest-first, including multiple events received in the same second. Manual scrolling remains possible until the next arrival.
- **Fading sightings:** sightings remain fully visible for the first 85% of their lifespan, then fade toward 12% opacity only during the final 15% before expiry. The once-per-second refresh updates age labels and expiration; a separate game-time-driven timer animates opacity at about 25 frames per second during the fading window.
- The text-entry row remains fully visible below the chat scrollbar.
- **Shift+A** opens the RmlUi chat text field; Enter submits a local `LOCAL TEST` message, Escape cancels.
- The native HUD and radar **remain visible** while typing.
- Tab completes player names using VO's **existing `TabCompleteName()` cache**. Multi-word completions keep the caret at the end via a delayed RmlUi `KI_END` event.
- The native VO `prompt` can still be selected if needed.

The HUD, layout, scrolling, fading and input behavior were verified in the VO client before this refactor. **The refactored branch still requires in-game regression testing.**

## Install and test

Place the runtime files in `plugins/skynetui/`, **including `dev/demo.lua` at that relative path**, so the plugin entry point is `plugins/skynetui/main.lua`. Reload the interface if you have already started VO. The demo module still supplies the same initial samples, local chat echo and `/skynetui demo` commands; separating it does not disable them.

1. In flight, press **Shift+A**. The RmlUi input should open without hiding the native HUD.
2. Type some text, then press **Enter**. The panel should display a `LOCAL TEST` message.
3. Type `lost` (after encountering a player called Lost Crow), press **Tab**, and continue typing. The caret should be after `Lost Crow`, not in its middle.
4. Press **Escape** during another message. Flight controls should return.
5. Enter `/skynetui layout`; mouse-drag the SKYNET title, two slim column dividers, and the bottom-right grip. Click **DONE** when finished.
6. Use `/skynetui demo flood` to insert 40 long test messages **and six sightings aged 0%, 70%, 85%, 90%, 95%, and 98% through their TTL**, including three in the final fading window. The sightings should show progressively fainter rows and expire naturally. Chat must stay within the panel and scroll to the latest message. The scrollbar should be invisible during normal flight and reappear in `/skynetui layout`. While chatting, the input row must stay visible beneath the history.
7. To test the other two scrollers, run `/skynetui demo scroll` to generate **32 online pilots and 24 fresh sightings**, enough to overflow both. Enter `/skynetui layout` to enable mouse input and show scrollbar thumbs. Move the wheel over **Online**, then **Sightings**: each list must scroll independently without moving the others or the HUD. Run `/skynetui demo scrollcheck` to print their `scroll_top`, viewport height and content height. Check that the scroll position increases after using the wheel and can return to zero at the top. Demo sightings expire normally after the configured TTL (60 seconds by default), so repeat `/skynetui demo scroll` to refresh the test. For top-follow verification, scroll Sightings down in layout mode, then run `/skynetui demo` or `/skynetui demo scroll`: the newest entry should appear immediately at the top, with the scroll position returning to zero. Chat should retain its own follow-to-bottom behavior.
8. **PDA regression:** While flying with Skynet visible, press **N** to open navigation. Skynet should disappear and the PDA should respond to mouse clicks. Close the PDA; Skynet should return. Repeat with `/skynetui layout` active, and again while Skynet's Shift+A chat input is open: on entering the PDA, Skynet must release its input ownership, hide, and never force flight controls over the PDA. Finish with docking/undocking and `ReloadInterface()` tests.

Console commands:

```text
/skynetui chat
/skynetui hide
/skynetui show
/skynetui demo
/skynetui demo flood
/skynetui demo scroll
/skynetui demo scrollcheck
/skynetui layout
/skynetui resetlayout
/skynetui input rml
/skynetui input native
```

`/skynetui input native` is a fallback to VO's normal prompt; `/skynetui input rml` restores the inline RmlUi field. The old `/skynetui input active` also maps to RmlUi input for compatibility, but **there are no longer separate experimental HUD modes**.

### Move, resize and scroll

The panel starts at its original radar-safe position. To interact with its frame, enter:

```text
/skynetui layout
```

In normal flight, the orange **SKYNET:** label sits immediately before the live **CONNECTED** or **DISCONNECTED** status inside a fully rounded navy **pill** (all four corners use an 11px radius). The 22px-high pill has its own constant `rgba(7, 20, 36, 166)` background and sits 3px above the column row. A single uniform fill of that same color covers the three columns and both 8px splitter gutters; individual columns are transparent to avoid double-tinting. The broader outer panel remains clear, and the outer border stays hidden except during layout editing. Column headings are absent. Two **one-pixel, muted steel-blue guides** run the full height of the columns, with short 12px transparent-to-solid and solid-to-transparent gradients at the top and bottom. Their centers remain solid, and they brighten in layout mode. The 8px surrounding gutters remain draggable. All columns now have 8px top padding rather than 3px; the lists are 5px shorter to keep the saved panel geometry and reserved chat-entry row intact.

**RmlUi transparency:** RCSS uses **byte alpha (0–255)** for `rgba(r, g, b, a)`, unlike browser CSS's 0–1. The current alpha 166 gives approximately **35% transparency** (65% opacity). The layout tests verify that the SKYNET pill and shared column row use this same fill, the sections do not double-tint it, that only the separator tips use gradient decorators, and that there is no chat mask or background fade. Other UI alpha colors include splitter hover (~204), input (~240) and layout gutter (~64).


**Sighting arrival and scrolling:** The newest sighting goes at the top, with later arrivals before earlier sightings even when they share the same second. On new sightings, `scroll_top` goes to zero immediately, with one 40ms retry after the client finishes layout. Chat still follows its bottom. The sighting fade timer, age updates, and expirations do not initiate top-follow; you can scroll down to inspect older sightings until another arrives.

**Sighting expiration fade:** Each sighting row uses RmlUi's inherited `opacity` property (0–1, unlike RGBA alpha), based on its elapsed age divided by its configured TTL. Opacity stays at 1.00 through 85% of the TTL, then declines linearly toward 0.12 over the remaining 15% and applies to the pilot, ship, sector, and age label. During the fade window, a dedicated VO `Timer` updates existing RmlUi row elements about every 40 milliseconds (25 FPS), using `gkmisc.GetGameTime()` for millisecond precision. The original one-second `tick()` updates only the age labels and handles expiry; it no longer reconstructs each row on every tick, which had caused the visible stuttering. The high-rate timer stays mostly idle before fade starts and is stopped when the panel is hidden or unloaded. Expired rows are removed on schedule. `/skynetui demo flood` generates six sightings with three near expiry so the fade is easy to compare in-game.

All three content lists are independent RmlUi scroll containers. **Online** and **Sightings** use `overflow-y: auto` and an explicitly sized viewport; chat uses `overflow-y: scroll` and automatic follow-to-bottom. Their scrollbar paint is **visually transparent outside layout mode**; RmlUi still creates bars when needed. In layout-edit mode, the tracks and thumbs regain their colors, making it possible to inspect each overflow area without changing scroll mechanics. A `layout-edit` class on the panel controls the scrollbar styling. The `demo scrollcheck` command reports `scroll_top`, viewport height and content height from the actual RmlUi elements to diagnose missing overflow or wheel input.

While editing, the **outer border**, brighter single-line dividers, corner resize grip, and DONE control reappear. The SKYNET title and connection status remain present in both modes, with **no line under the title row**. The native HUD **remains visible** but its IUP input is temporarily disabled so RmlUi can receive mouse drag events. The cursor is shown, and the flight-control input mode is temporarily disabled.

- **Drag the SKYNET header** to move the entire panel.
- **Drag the lower-right square** to change width and height.
- **Drag the two thin dividers** to change the online/chat/sightings column proportions.
- **Click DONE** to restore the native HUD's input and flight controls.
- **`/skynetui resetlayout`** restores the original position and sizes.

**PDA visibility and input ownership:** A ship can remain active while its navigation/PDA menu is open. Skynet therefore checks both the existing `HUD_SHOW`/`HUD_HIDE` events and the native `HUD.dlg.visible` flag, with a separate 125ms visibility check (the one-second data-update timer remains unchanged). When the HUD disappears, Skynet closes its own input or layout owner, hides the RmlUi document, and avoids calling `Game.SetInputMode(true)` over an active PDA. It returns to the flight HUD automatically. In client versions without `HUD.dlg.visible`, existing HUD events are the fallback. This path requires an in-game PDA regression test.

**Styling test:** Compare normal flight with `/skynetui layout`. The header should show **SKYNET: DISCONNECTED** inside a detached four-corner rounded pill. The three columns and splitter gutters should have a **uniform 35%-transparent navy background**, including at the top: there is intentionally a hard edge instead of an experimental fade. Chat text remains fully readable while scrolling and follows the latest message after `/skynetui demo flood`. There are no ONLINE, ALLIANCE CHAT or SIGHTINGS headings. The column divider guides remain full height but gradually disappear at both ends, and text begins about 8px below the top of each column. The outer border appears only in layout mode, and Shift+A still opens the input without hiding the native HUD. The demo flood still injects six different-age sightings, which smoothly fade only during the final 15% of their lifetime.

Panel position, size, and the online/sightings widths are saved after each drag, on DONE, and on `/skynetui resetlayout`. The online roster can now be narrowed to **40px** (previously 95px); the chat keeps its 160px minimum. All six layout values persist using VO's plugin configuration API, `gkini.WriteString("skynetui", "layout_v1", ...)`, and are restored via `gkini.ReadString` on startup or `ReloadInterface()`. A previously saved `Game.GetPrefString("skynetui.layout.v1", ...)` value is still accepted for migration, and the old Game save API remains a fallback if `gkini` is unavailable. For verification: enter `/skynetui layout`, move the HUD and drag the left separator nearly all the way left, click DONE, run `ReloadInterface()`, and confirm all positions and widths are restored. The `gkini` store is normally shared across characters.

The chat list now has an explicit pixel height separate from the fixed 29px input row, with `overflow-y: scroll`. Its vertical scrollbar is explicitly styled because RmlUi provides no built-in scrollbar appearance. The scroll area shrinks when Shift+A opens the input, then grows back when input closes. The rest of the panel is clipped so text cannot paint past the bottom of the window.

**Follow-up fixes:** Each movable column separator now draws one line, not two border lines. The bottom-right resize square is shown **only during `/skynetui layout`**; it is hidden in normal flight/chat mode. New messages follow the bottom after RmlUi recalculates their scroll height. A user who manually scrolls upward stays at the chosen position; returning to the bottom re-enables following.

**Flood-specific correction:** RmlUi generates `scroll` events for DOM relayout as well as actual user scrolling. The plugin now changes follow mode only in response to user mouse scrolling/dragging rather than treating relayout as manual input. `/skynetui demo flood` inserts all 40 messages with one chat render and explicitly follows the latest message. The game log showed only immediate `pass=0` attempts because the code mistakenly required `type(Timer) == "function"`: VO exposes a callable `Timer()` that can also be a table. The code now constructs the timer under `pcall` and retries at 40ms, then 120ms and 240ms. The log also showed `ScrollIntoView(false)` moving the scroll backwards (from 2580 to 1823), so that was removed in favor of setting the measured bottom position on each delayed pass. Ordinary messages still preserve your position when you intentionally scroll up.

If the flood still fails to reach message 40, include the three `Skynet UI: chat follow pass=` lines from the game's error log. They report the target position, successful write, and actual scroll position/content height before and after each attempt **without printing chat text**. These measurements distinguish timer scheduling failures from scroll-binding or layout behavior.

**Mouse interactions require layout-edit mode or another active RmlUi input owner.** This is necessary because the normal IUP flight HUD intercepts mouse input. Use `/skynetui layout` to drag the window and scrollbar; no RLB modification is required.

The default chat watchdog is **12 seconds** and is configured by `CHAT_RECOVERY_TIMEOUT_MS` in `main.lua`. Set it to `0` to disable the automatic recovery for long-form inputs. On timeout or normal in-flight close, the router closes the field, restores the original IUP `ACTIVE` state, and re-enables flight input. On PDA/HUD shutdown, it does not force flight input over the game menu. In case of a serious input fault, use `ReloadInterface()`.

## Reusable input modules

### `rmlui_input.lua`: HUD / keyboard ownership

This small manager is independent of the chat widget. It disables IUP interaction through `HUD.dlg.active = "NO"` (without hiding the HUD) and calls `Game.SetInputMode(false)` while an RmlUi control needs input. It restores the prior IUP state, calls `Game.SetInputMode(true)`, and hides the flight mouse when the last owner releases.

```lua
local InputRouter = dofile("rmlui_input.lua")
local router = InputRouter.new({ timeout_ms = 0 })

local function close_settings(reason)
    -- Hide your RmlUi settings panel; safe to call router:release("settings").
end

local ok, reason = router:acquire("settings", close_settings, 0)
if ok then
    settings_input:Focus()
else
    print(reason)
end

-- When the settings panel closes:
router:release("settings")

-- On HUD_HIDE, UNLOAD_INTERFACE, disconnect, etc.:
router:cancel_all("hud-unloaded")
```

Different owners may acquire the router simultaneously. Repeated acquisition **by the same owner** is reference-counted. Only the final release restores flight controls. `cancel_all(reason)` restores the HUD before invoking each owner's cancellation callback; callbacks can safely call `release` again. Timeout is per owner (milliseconds); `0` disables it.

Call `router:release(owner)` for every successful `acquire(owner)` if you use nested acquisitions. **A control's request to own input is not the same as focusing its DOM element; call `:Focus()` once the router grants input.**

### `rmlui_text_entry.lua`: reusable field events

Reusable text-field listener handling `change`, `keydown`, `keyup`, and optional form submission. Enter submits, Escape cancels, and an optional completion function handles Tab; after completion a delayed `KI_END` keeps the caret at the end.

```lua
local TextEntry = dofile("rmlui_text_entry.lua")
local entry = TextEntry.new({
    input = document:GetElementById("chat-input"),
    form = document:GetElementById("chat-form"), -- optional
    context = rmlui.contexts["main"],
    completer = TabCompleteName, -- optional
    on_change = function(value) end,
    on_submit = function(message, source) end,
    on_cancel = function(reason) end,
})

assert(entry:bind())
assert(entry:open())
-- First acquire the HUD input router, then:
assert(entry:focus())

-- On closing:
entry:close()
```

The controller reads the live value from `event.parameters.value`; in this VO build, the generic RmlUi element does not expose the input's `.value` or `SetSelection()`. Text completion currently operates on the **end of the draft**; cursor-aware completion in the middle of a message is not implemented.

### `ui.lua`: standalone Skynet panel

The display API remains independent of transport. Supply the reusable text-entry class when constructing the UI:

```lua
local UI = dofile("ui.lua")
local TextEntry = dofile("rmlui_text_entry.lua")
local ui = UI.new({ visible = false, text_entry_class = TextEntry })
local document = rmlui.contexts["main"]:LoadDocument("panel.rml")
ui:mount(rmlui.contexts["main"], document)

ui:set_connected(true)
ui:set_alliance_color("itani", "#65c6ff")
ui:replace_online({ "SomePilot" })
ui:add_chat("SomePilot", "Hello!")
ui:add_sighting("SomePilot", "Vult", "Sedina B-8", os.time())
ui:set_chat_submit_handler(function(message)
    -- Add to a future Skynet transport.
end)
ui:tick()
ui:hide()
ui:show()
ui:unmount()
```

The panel preserves current limits: up to 200 chat messages, 20-character roster labels, and 60-second sightings. Width is calculated from the viewport with 190px default radar margins, adjustable in `UI.new()`.

## Development and safety

- No edits to the game's RLB archives are needed.
- The original native IUP chat-reparent experiment and hide-HUD test modes have been removed from the active plugin path.
- Relative `panel.rml` paths must be loaded from the plugin's `main.lua`.
- RmlUi event handlers are registered with Lua functions rather than string listeners.
- The only chat delivery currently implemented is a local echo, **not** VO chat or a Skynet server.
- UI text is HTML-escaped before rendering.
- Run all regression checks with `sh tests/run.sh` (or `LUA=/path/to/lua sh tests/run.sh`). The existing input/layout tests remain, with additional full-entry-point and timer-failure tests. Then verify interactions in the actual VO client.

## Next milestone

Recheck the preserved behaviors on this refactoring branch using the install/test steps above. Once the refactor is validated and approved, real Skynet events and transport remain a separate milestone.
