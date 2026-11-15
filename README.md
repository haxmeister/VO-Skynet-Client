# VO Skynet Client UI — RmlUi prototype

This repository holds a reusable, standalone **Vendetta Online RmlUi HUD component** for a future Skynet client. It does **not** connect to Skynet or use VO custom events yet.

## Current milestone

A small, translucent bar sits along the bottom between the radar areas:

**Online roster | Alliance chat | Recent sightings**

- Online names sort alphabetically and truncate at 20 characters.
- Chat is newest-at-bottom, wraps, has no timestamps and retains up to 200 messages. Auto-scroll stops while scrolled up.
- Sightings are keyed by pilot, ordered newest-first, show abbreviated ship type, sector and age, and expire after 60 seconds.
- Player names use alliance colors; sector labels use owning-alliance colors. Unowned/unknown sectors use a neutral color.
- Outer sections size to their content; the center chat section grows to use the remainder.
- The component has no networking dependency and is fed with simulated data for now.

### Install and test in Vendetta Online

Copy the contents of this repository into a folder named `skynetui` under VO's `plugins` folder, so the client sees `plugins/skynetui/main.lua`, `ui.lua`, and `panel.rml` together. Start the game or reload the interface.

Use `/skynetui hide`, `/skynetui show`, or `/skynetui demo` in the VO console. The demo command adds a sample chat message and refreshes a sighting.

### Chat entry — original Skynet-style VO prompt

The original clients at [skynet-client](https://github.com/haxmeister/skynet-client/blob/main/notifier.lua) and [skynet2-client](https://github.com/haxmeister/skynet2-client/blob/main/chat.lua) used Vendetta Online's own `prompt` command for alliance chat. They registered a color-coded command with `RegisterUserCommand`, created a `gkinterface.GKProcessCommand` alias to `prompt`, and bound a hotkey. The prompt invokes the registered command with words as a Lua array, which the handler joins into a message.

We use that proven original design again, **not** the separate IUP dialog or the currently non-functional inline RmlUi input. VO's built-in prompt should provide its normal text focus, Enter and Escape handling.

**The chat hotkey is hard-coded to `A`.** On plugin startup, `main.lua` runs `bind A skynetui_chat`, replacing any existing binding on the A key. Press **A** in flight to open VO's native chat prompt. The manual `/skynetui chat` command remains available.

The plugin also registers an internal `skynetui_prompt` alias that runs `prompt`. The chat command only opens while the flight HUD is visible. Submitted text is passed to `ui:deliver_chat(message)` and appears as `LOCAL TEST: ...` in the Skynet RmlUi chat history. **It is never transmitted** to VO's regular chat or a network server.

The native prompt remains the default and works as before. The opt-in boolean-input experiment below temporarily switches the same A key to the existing inline RmlUi field.

### Experimental RmlUi keyboard input (feature branch)

Draugath's MDI-Core example uses **Lua booleans** with `Game.SetInputMode(not interaction_mode)`. Unlike C, Lua treats `0` as **true**, which means the previous `Game.SetInputMode(0)` test may not have disabled flight input. This branch tests `Game.SetInputMode(false)` while entering chat and `Game.SetInputMode(true)` when leaving the field. It optionally calls `gkinterface.HideMouse()` when restoring flight controls; it does **not** modify the native HUD, show the mouse, or relocate IUP elements.

The branch keeps **A** hard-coded. By default, it still opens VO's working native prompt. To opt into the experiment while flying in a safe sector:

```text
/skynetui input rml
```

Then press **A**. The entry form appears at the bottom of the Skynet alliance-chat column. Test whether letter keys stop controlling the ship **and** whether text appears inside that field. Enter should submit a `LOCAL TEST` line, and Escape should cancel; either should restore normal flight input.

**Safety:** An RmlUi input that remains open for 12 seconds automatically cancels and calls `Game.SetInputMode(true)`, even if no key reaches RmlUi. Hiding Skynet or leaving flight also cancels it. If Enter/Escape work, they restore input immediately. For immediate fallback, use `/skynetui input native`, or reload the interface; the default reverts to the native prompt on each load. Do not run the older `/skynetui native dock` IUP experiment simultaneously.

This is an *unverified flight-client experiment*, not a claim that RmlUi input is supported by the current game. If the test fails, report both whether flight keys still work and whether any text appears in Skynet's input field, plus the VO errors log.

### Flight-only visibility

The prototype is **hidden by default** on the login, character-selection, and station screens. The plugin loads RML while VO is initializing (when relative file resolution works), but displays the document only when the ship HUD is active and the client reports `HasActiveShip() == true` and `PlayerInStation() == false`.

The entry point observes `HUD_SHOW("ship")`, `HUD_HIDE`, `ENTERING_STATION`, `ENTERED_STATION`, `SHOW_STATION`, `LEAVING_STATION`, `SHIP_SPAWNED`, `PLAYER_ENTERED_GAME`, `PLAYER_LOGGED_OUT`, and `SERVER_DISCONNECTED`. VO API observations confirm the key HUD and station events; other event hooks are installed defensively. A one-second check handles state changes and in-flight interface reloads.

`/skynetui hide` turns off manual visibility, while `/skynetui show` re-enables it **only in flight**. `/skynetui demo` adds simulated content but never makes the panel appear at login or in a station.

**Test sequence:** startup/login screen (hidden) → character select (hidden) → docked (hidden) → launch (visible) → dock (hidden) → launch (visible), then try `/skynetui hide` and `/skynetui show` in flight. Neither event timing nor document visibility has yet been validated on the target VO client, so please report any failures with the log and screenshot.

### Sizing

The plugin does not yet have access to real radar boundaries. The default 190-pixel left and right margins are **initial visual estimates** based on a 1040×806 VO screenshot, not direct radar measurements. The controller reads the RmlUi context's viewport width and sets the panel width to `viewport − left margin − right margin`; it checks for resolution changes on each tick. In `main.lua`, change `UI.new()` to something such as:

```lua
local ui = UI.new({
    radar_margin_left = 190,
    radar_margin_right = 190,
    bottom_margin = 5,
    height = 166,
    online_name_limit = 20,
    sighting_ttl = 60,
    chat_limit = 200,
})
```

We can tune the radar-safe margins after seeing the next in-client screenshot, and eventually derive them from actual radar dimensions if VO exposes those bounds. RmlUi's absolute layout did not size the panel from left/right offsets alone; its width must be set explicitly. The plugin prints the viewport and calculated panel width once on load or on resolution changes.

### UI API

`ui.lua` returns an independent constructor:

```lua
local UI = dofile("ui.lua")
local ui = UI.new()
local context = rmlui.contexts["main"]
local document = context:LoadDocument("panel.rml")
ui:mount(context, document)
ui:set_connected(true)
ui:set_alliance_color("itani", "#65c6ff")
ui:set_player_alliance("SomePilot", "itani")
ui:set_sector_owner("Sedina B-8", "itani") -- nil for unowned
ui:replace_online({ "SomePilot" })
ui:add_chat("SomePilot", "Hello alliance")
ui:set_chat_submit_handler(function(message)
    -- Deliver to a future Skynet transport; the UI itself sends nothing.
end)
ui:begin_chat() -- only opens while the panel is visible
ui:cancel_chat()
ui:add_sighting("SomePilot", "Vult", "Sedina B-8", os.time())
ui:tick() -- run every second for expiry and age labels
ui:hide()
ui:show()
ui:unmount()
```

Network plugins will eventually translate **custom VO events** into these calls. No messages are posted to VO's normal chat.

### Next milestones

1. Verify panel visibility, sizing, text rendering and scroll behavior in the VO client.
2. Verify original Skynet-style native VO prompt integration and local message submission, then investigate inline RmlUi input if desired.
3. Define and consume custom VO events for chat, roster, sightings, colors, ownership and connection state.
4. Replace provisional radar margins with bounds that accurately fit between both radar widgets.

### Notes

- No modification to the game's RLB files is required.
- Styling is embedded in `panel.rml` to avoid the reported RmlUi external stylesheet cache issue during rapid iteration.
- The demo's green CONNECTED text is simulated; it does not indicate an active server.
- User text is HTML-escaped before being placed into the RmlUi document.
- An inline RmlUi chat form exists but does not receive flight-mode keyboard input in the tested VO client. The native VO `prompt` is now used for entry; the IUP dialog fallback was removed after causing focus and dismissal problems.
