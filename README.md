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

### Chat entry — first interactive milestone

The existing chat history remains visible in flight; the **text-entry field is hidden** until activated. Use `/skynetui chat` to toggle it, or bind an unused key to the dedicated command:

```text
/bind F8 skynetui_chat
```

**F8 is only an example**; check existing binds and choose a key you are comfortable overriding. No key is rebound by the plugin itself. Binding a command is important because entering `/skynetui chat` in the console may leave focus in VO's own console.

While in flight, activate the hotkey, type a message, and press **Enter** to submit or **Escape** to cancel. The field clears and disappears after either action. Docking, logging out, hiding the Skynet panel, or switching HUDs also cancels the entry. Outside flight, the command does not open the input.

**This is a UI-only demo.** Submitted text appears as `LOCAL TEST: ...` in the Skynet chat list. It is **not sent** over VO chat, TCP, Skynet, or a VO custom event. The reusable UI exposes `ui:set_chat_submit_handler(function(message) ... end)` so a networking plugin can supply its own handler later.

**Keyboard routing experiment (November 14, 2026):** An in-client test showed a blinking RmlUi cursor while all typed keys still triggered flight controls. This means RmlUi element focus alone does not transfer VO's keyboard routing. The VO entry point now experimentally calls `Game.SetInputMode(0)` when input opens and restores `Game.SetInputMode(1)` on close **only if still in flight**. The historical meaning of these modes is documented by community plugin research, but we have not yet confirmed that mode 0 delivers input to RmlUi in the current VO client. It is deliberately implemented in `main.lua`, leaving `ui.lua` renderer/game-agnostic. The UI exposes `ui:set_chat_focus_handler(function(open) ... end)` for this integration.

**Safety:** During this unverified experiment, a 20-second timeout closes the input and attempts to restore flight controls if Enter/Escape do not work. Do not test this in combat. The log prints `requested UI input mode (0)`, `restored flight input mode (1)`, or an error if the API is unavailable. RmlUi's `keydown` identifiers have known limitations on some Linux keys; a form `submit` listener provides an alternate Enter path. Report whether flight keys stop and whether typing reaches the field; send the errors log for failures.

This prototype selects `rmlui.contexts["main"]`, falling back to the first registered context. It must be tested in VO to confirm that this is the right context for the flight HUD and that it is visible above the game UI. VO's IUP HUD can render over RmlUi.

**RML loading:** VO 1.8.775+ documents are intended to load relative to the plugin's directory **during plugin initialization**. Early tests showed repeated plugin-prefix paths when `LoadDocument()` was called from inside a helper module, and a leading `/plugins/...` path also failed. The entry point now calls `context:LoadDocument("panel.rml")` directly from `main.lua` and supplies the resulting document to `ui:mount(context, document)`. The change still needs an in-game verification. The UI controller also accepts a document directly, so it can remain reusable across plugins.

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
2. Validate the new chat-entry hotkey, input focus, Enter submission, Escape cancellation, and flight-control restoration in a running VO client.
3. Define and consume custom VO events for chat, roster, sightings, colors, ownership and connection state.
4. Replace provisional radar margins with bounds that accurately fit between both radar widgets.

### Notes

- No modification to the game's RLB files is required.
- Styling is embedded in `panel.rml` to avoid the reported RmlUi external stylesheet cache issue during rapid iteration.
- The demo's green CONNECTED text is simulated; it does not indicate an active server.
- User text is HTML-escaped before being placed into the RmlUi document.
- Chat-entry listeners and keyboard focus have been added, but are not yet verified by a VO runtime test.
