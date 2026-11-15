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

### Chat entry — native IUP focus test (November 14, 2026)

A real VO flight test showed that the RmlUi inline input had a blinking caret, but all keystrokes still controlled the ship. An attempted `Game.SetInputMode(0)` switch **did not fix this**: the game still handled all keys and RmlUi received no characters. That unverified input-mode experiment and its 20-second timer were removed.

The same `/skynetui chat` command, or an existing bind like:

```text
/bind F8 skynetui_chat
```

now opens a small **native IUP text dialog**. The initial field accepted typing but did not respond to Enter or Escape, leaving the dialog stuck. Its IUP `k_any` handler was insufficient; the current code sets `defaultenter` and `defaultesc` on real **Send**/**Cancel** buttons, following IUP's documented convention. Buttons also provide mouse-accessible exits. Enter adds a `LOCAL TEST: ...` message to Skynet's RmlUi chat history, and Escape cancels. Docking or hiding Skynet should also close the dialog. **Nothing is sent to VO chat or a network server.**

No key is rebound automatically. Testing while stationary in a safe sector is recommended. Verify Enter/Escape, clicking **Send**/**Cancel**, and flight control restoration. If either key fails, click Cancel or press the chat hotkey again to dismiss the dialog. An additional `/skynetui close` or `/skynetui_close` command can dismiss it without submitting anything, including when the native dialog hides the Skynet HUD. As a last resort, an open test dialog now automatically cancels after **120 seconds**, even if its keyboard callbacks fail. If a previous plugin version has trapped focus so the console cannot be reached, the VO console command `/lua ReloadInterface()` (when available) or a client restart is needed to load the new code. Please include the errors log for any further failure.

**Long-term UI goal remains the compact inline RmlUi input.** We are leaving its hidden form and controller methods in place until we understand how VO forwards keyboard events from its flight HUD to the RmlUi context. The IUP dialog is a fallback, not a claim that RmlUi input now works in flight.

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
2. Validate native IUP chat-entry focus, Enter/Escape, and flight-control restoration; investigate a future inline RmlUi input once VO's keyboard routing is understood.
3. Define and consume custom VO events for chat, roster, sightings, colors, ownership and connection state.
4. Replace provisional radar margins with bounds that accurately fit between both radar widgets.

### Notes

- No modification to the game's RLB files is required.
- Styling is embedded in `panel.rml` to avoid the reported RmlUi external stylesheet cache issue during rapid iteration.
- The demo's green CONNECTED text is simulated; it does not indicate an active server.
- User text is HTML-escaped before being placed into the RmlUi document.
- An inline RmlUi chat form exists but does not receive flight-mode keyboard input in the tested VO client. The native IUP fallback is currently used for entry.
