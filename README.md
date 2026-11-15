# VO Skynet Client UI — RmlUi prototype

A standalone, translucent **Vendetta Online RmlUi HUD panel** for a future Skynet client. It currently shows simulated alliance presence, chat, and recent sightings. **There is no Skynet networking or real message delivery yet.**

Work is on `feature/rmlui-hud-active-test`; **do not merge into main without a separate decision**.

## Features

- Flight-only panel arranged between the game's native radar widgets.
- Online roster with alliance colors, chat history, and sightings with age/expiry.
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
5. Test docking/undocking, hiding the panel, and `ReloadInterface()` while the chat field is open.

Console commands:

```text
/skynetui chat
/skynetui hide
/skynetui show
/skynetui demo
/skynetui input rml
/skynetui input native
```

`/skynetui input native` is a fallback to VO's normal prompt; `/skynetui input rml` restores the inline RmlUi field. The old `/skynetui input active` also maps to RmlUi input for compatibility, but **there are no longer separate experimental HUD modes**.

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
- Run the module regression checks with `lua tests/test_input.lua` if you have a Lua interpreter installed, then verify the input interactions in the actual VO client.

## Next milestone

Confirm the refactored RmlUi chat and reusable input manager work in flight, including Tab completion, keyboard-focus restoration, timeout, and interface reload. Then integrate actual Skynet events and transport.
