# VO Skynet Client UI — RmlUi prototype

A standalone, translucent **Vendetta Online RmlUi HUD panel** for a future Skynet client. It currently shows simulated alliance presence, chat, and recent sightings. **There is no Skynet networking or real message delivery yet.**

Work is on `feature/rmlui-hud-active-test`; **do not merge into main without a separate decision**.

## Features

- Flight-only panel arranged between the game's native radar widgets.
- Online roster with alliance colors, a **bounded scrollable chat history**, and sightings with age/expiry.
- **Movable/resizable panel** with draggable column separators and saved layout preferences.
- **Low-chrome flight HUD:** the SKYNET title and live connection status remain visible without a title-bar border; the outer window outline is hidden in flight. Column dividers stay muted and brighten in layout mode.
- **Classic orange and blue:** the ONLINE, ALLIANCE CHAT, and SIGHTINGS headings are orange and underlined; the SKYNET title and window accents retain their blue color.
- **Scrollbars hidden in flight:** chat history still scrolls and follows new messages, but the scrollbar is transparent until layout-edit mode.
- **Modest background tint:** normal flight uses a slightly softer translucent panel (0.72 versus 0.82 in layout mode). The chat input remains dark for readability.
- The text-entry row remains fully visible below the chat scrollbar.
- **Shift+A** opens the RmlUi chat text field; Enter submits a local `LOCAL TEST` message, Escape cancels.
- The native HUD and radar **remain visible** while typing.
- Tab completes player names using VO's **existing `TabCompleteName()` cache**. Multi-word completions keep the caret at the end via a delayed RmlUi `KI_END` event.
- The native VO `prompt` can still be selected if needed.

The HUD/display approach and Tab/caret behavior were independently verified in the VO client before this refactor. **The refactored modules still require in-game regression testing.**

## Install and test

Place these repository files in `plugins/skynetui/`, so the plugin entry point is `plugins/skynetui/main.lua`. Reload the interface if you have already started VO.

1. In flight, press **Shift+A**. The RmlUi input should open without hiding the native HUD.
2. Type some text, then press **Enter**. The panel should display a `LOCAL TEST` message.
3. Type `lost` (after encountering a player called Lost Crow), press **Tab**, and continue typing. The caret should be after `Lost Crow`, not in its middle.
4. Press **Escape** during another message. Flight controls should return.
5. Enter `/skynetui layout`; mouse-drag the SKYNET title, two slim column dividers, and the bottom-right grip. Click **DONE** when finished.
6. Use `/skynetui demo flood` to insert 40 long test messages. The chat must stay within the panel, scroll to the latest message, and retain its visible scrollbar. While chatting, the input row must stay visible beneath the history.
7. Test docking/undocking, hiding the panel, and `ReloadInterface()` while the chat field is open.

Console commands:

```text
/skynetui chat
/skynetui hide
/skynetui show
/skynetui demo
/skynetui demo flood
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

In normal flight, the SKYNET title and CONNECTED/DISCONNECTED status remain visible in a borderless blue title row; the outer window outline is hidden. The two vertical column separators remain as **one-pixel, muted steel-blue guides**. These are real 1px elements (not alpha-blended borders), because the transparent-border approach was invisible in VO. The surrounding 8px gutters still provide the same draggable hit areas. The full panel height belongs to the three content columns, including the chat history and reserved text-entry row. The splitter hit areas remain 8px wide so the saved column geometry does not change.

The chat scrollbar is **visually transparent outside layout mode**; RmlUi still creates it with its original 11px width, and the chat retains overflow scrolling and automatic follow-to-bottom. In layout-edit mode, the scrollbar track and thumb regain their colors, making it easy to inspect or scroll the history while adjusting the panel. A `layout-edit` class on the panel controls scrollbar styling without changing the scroll mechanics.

While editing, the **outer border**, brighter single-line dividers, corner resize grip, and DONE control reappear. The SKYNET title and connection status remain present in both modes, with **no line under the title row**. The native HUD **remains visible** but its IUP input is temporarily disabled so RmlUi can receive mouse drag events. The cursor is shown, and the flight-control input mode is temporarily disabled.

- **Drag the SKYNET header** to move the entire panel.
- **Drag the lower-right square** to change width and height.
- **Drag the two thin dividers** to change the online/chat/sightings column proportions.
- **Click DONE** to restore the native HUD's input and flight controls.
- **`/skynetui resetlayout`** restores the original position and sizes.

**Styling test:** Compare normal flight with `/skynetui layout`. The SKYNET title and actual connection status should stay visible with no bottom border on the title row, and all three column headings should be orange and underlined. The outer border should appear only in edit mode; the two thin blue-grey dividers should brighten, and the scrollbar should switch from invisible to styled. The title row occupies 25px in both modes, while the visible outer border in edit mode uses an additional 2px. Verify that `/skynetui demo flood` still follows the latest message and Shift+A keeps the input field visible. No compact/expanded mode or HUD-hiding behavior was added.

Panel dimensions and divider widths are constrained to remain on-screen when possible. The plugin attempts to store the six layout values in VO's `Game.SetPrefString("skynetui.layout.v1", ...)` preference and to reload them when the interface restarts. The layout remains editable for the current session if the VO build does not persist custom preference keys.

The chat list now has an explicit pixel height separate from the fixed 29px input row, with `overflow-y: scroll`. Its vertical scrollbar is explicitly styled because RmlUi provides no built-in scrollbar appearance. The scroll area shrinks when Shift+A opens the input, then grows back when input closes. The rest of the panel is clipped so text cannot paint past the bottom of the window.

**Follow-up fixes:** Each movable column separator now draws one line, not two border lines. The bottom-right resize square is shown **only during `/skynetui layout`**; it is hidden in normal flight/chat mode. New messages follow the bottom after RmlUi recalculates their scroll height. A user who manually scrolls upward stays at the chosen position; returning to the bottom re-enables following.

**Flood-specific correction:** RmlUi generates `scroll` events for DOM relayout as well as actual user scrolling. The plugin now changes follow mode only in response to user mouse scrolling/dragging rather than treating relayout as manual input. `/skynetui demo flood` inserts all 40 messages with one chat render and explicitly follows the latest message. The game log showed only immediate `pass=0` attempts because the code mistakenly required `type(Timer) == "function"`: VO exposes a callable `Timer()` that can also be a table. The code now constructs the timer under `pcall` and retries at 40ms, then 120ms and 240ms. The log also showed `ScrollIntoView(false)` moving the scroll backwards (from 2580 to 1823), so that was removed in favor of setting the measured bottom position on each delayed pass. Ordinary messages still preserve your position when you intentionally scroll up.

If the flood still fails to reach message 40, include the three `Skynet UI: chat follow pass=` lines from the game's error log. They report the target position, successful write, and actual scroll position/content height before and after each attempt **without printing chat text**. These measurements distinguish timer scheduling failures from scroll-binding or layout behavior.

**Mouse interactions require layout-edit mode or another active RmlUi input owner.** This is necessary because the normal IUP flight HUD intercepts mouse input. Use `/skynetui layout` to drag the window and scrollbar; no RLB modification is required.

The default chat watchdog is **12 seconds** and is configured by `CHAT_RECOVERY_TIMEOUT_MS` in `main.lua`. Set it to `0` to disable the automatic recovery for long-form inputs. On timeout or HUD shutdown, the router closes the field, restores the original IUP `ACTIVE` state, and re-enables flight input. In case of a serious input fault, use `ReloadInterface()`.

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
- Run the module regression checks with `lua tests/test_input.lua` and `lua tests/test_layout.lua` if you have a Lua interpreter installed, then verify interactions in the actual VO client.

## Next milestone

Verify the new panel dragging, column resizing, chat scrollbar, persistent preferences, and visible input row in the actual VO client. The new layout controls have **not** yet been verified in-game. Once validated, integrate real Skynet events and transport.
