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

**The chat hotkey is bound to uppercase `A` (Shift+A).** On plugin startup, `main.lua` runs `bind A skynetui_chat`. Press **Shift+A** in flight to open VO's native chat prompt. The manual `/skynetui chat` command remains available.

The plugin also registers an internal `skynetui_prompt` alias that runs `prompt`. The chat command only opens while the flight HUD is visible. Submitted text is passed to `ui:deliver_chat(message)` and appears as `LOCAL TEST: ...` in the Skynet RmlUi chat history. **It is never transmitted** to VO's regular chat or a network server.

The native prompt remains the default and works as before. The opt-in experiment below temporarily switches Shift+A to the validated inline RmlUi field.

### Experimental RmlUi keyboard input (feature branch)

Draugath's MDI-Core example uses Lua booleans with `Game.SetInputMode(not interaction_mode)`. Unlike C, Lua treats `0` as true. Testing confirmed that `Game.SetInputMode(false)` disables flight controls, but **does not by itself** let RmlUi receive typing. The `hud` test additionally hides the native IUP HUD, which makes text input work. On close, the plugin restores `HUD.dlg` and calls `Game.SetInputMode(true)`. No IUP controls are moved.

The branch preserves the existing **uppercase A / Shift+A** binding. This is intentional and was verified with VO's native prompt; there is no lowercase-A binding change. By default, Shift+A still opens the working native prompt. To opt into the first experiment while flying in a safe sector:

```text
/skynetui input rml
```

Then press **Shift+A**. The entry form appears at the bottom of the Skynet alliance-chat column. You already verified that `Game.SetInputMode(false)` stops flight controls, but typing, clicking the text field, Enter, and Escape did not work in that mode. This indicates a separate input-routing problem, not an incorrectly bound key.

To test whether VO's native IUP HUD intercepts the remaining input events, switch to the **second, opt-in test**:

```text
/skynetui input hud
```

Press **Shift+A** again. This mode temporarily hides `HUD.dlg` using `HideDialog`, calls `Game.SetInputMode(false)`, and focuses the existing RmlUi field. The UI logs up to 30 focus, click, textinput, change, and keydown diagnostics (without recording typed text) so we can distinguish whether any input events are reaching the field. The HUD is restored with `ShowDialog(HUD.dlg)` when input closes.

**Safety:** This is an unverified HUD-level experiment. Test only while stationary in a safe sector. A 12-second timer cancels an open test field, restores the HUD, and calls `Game.SetInputMode(true)` even if neither Enter nor Escape works. If the native HUD fails to reappear, use `ReloadInterface()` or restart the client. You can switch back to VO's working prompt with `/skynetui input native`. Do not use `/skynetui native dock` alongside this experiment.

Both test modes revert to VO's native prompt on the next interface load. Enter/Escape submit or cancel and restore the original controls if RmlUi receives those events.

This is an *unverified flight-client experiment*, not a claim that RmlUi input is supported by the current game. If the test fails, report both whether flight keys still work and whether any text appears in Skynet's input field, plus the VO errors log.

### Native player-name Tab completion experiment

This branch also tests **VO's existing `TabCompleteName(string)` cache** in the inline RmlUi input. It does not build a second player-name list, and it does not modify the game's RLB files.

Use `/skynetui input active`, press **Shift+A**, type the beginning of a player name that the client has already encountered, and press **Tab**. For a name after message text, try something such as `hello Dra` when a player with that prefix is known to the client. Tab should complete the name without submitting or losing focus. **Enter** still locally echoes the message, and **Escape** still cancels.

The Lua listener intercepts `KI_TAB` and tries suffixes of the current draft, longest first, with `TabCompleteName()`. On a match, it writes the new text through `input:SetAttribute("value", ...)`, updates the Lua draft, and attempts to place the caret at the end. This is intentionally a first-pass test for completion **at the end of the text**; arbitrary caret-position edits and cycling through multiple native matches are not yet implemented.

**Report whether the completed name visibly appears, whether you can continue typing after it, and whether Enter echoes the completed message.** The errors log will show `native Tab completion applied`, `native name cache found no match`, or a native/RmlUi method error. `attribute_readback=true` only checks the attribute; it does **not** prove the rendered/live input value changed. The active-HUD focus behavior and its 12-second emergency restore are unchanged.

### ACTIVE attribute experiment (separate feature branch)
The `feature/rmlui-hud-active-test` branch adds a third opt-in mode for the same validated RmlUi form:

```
/skynetui input active
```

While stationary in a safe sector, press **Shift+A** and check whether the native radar and rest of the HUD **stay visible** and whether you can **type in the RmlUi chat field**. Press Enter to echo a `LOCAL TEST` message or Escape to cancel. The experiment sets `HUD.dlg.active = "NO"` instead of calling `HideDialog`, then calls `Game.SetInputMode(false)` and focuses the field. Its console messages report the previous and resulting `active` values, and whether RmlUi receives input events.

On Enter, Escape, failure, or the **12-second safety timeout**, the plugin restores the HUD dialog's prior `active` state (defaulting to `YES` if unset), switches back to `Game.SetInputMode(true)`, and hides the mouse. You can also use `/skynetui input native` to return to the known-good native VO prompt. If the HUD is unresponsive after a failed experiment, use `ReloadInterface()`.

This **does not modify any RLB file**, change the client's native event dispatcher, or guarantee that `ACTIVE=NO` bypasses IUP's input interception. It is an isolated feature-branch test to determine whether a Lua-only solution is possible. The original `hud` hide/restore experiment remains available for comparison. Do not merge this branch to main until it has been tested in game.

### Verified RmlUi text entry (feature branch)

Live VO testing confirmed that the RmlUi chat input accepts typed text and that **Enter submits**, **Escape cancels**, and the input clears when closed. RmlUi exposes edited text through `change` event `event.parameters.value`, not the generic Element's `input.value` property. Submission echoes `LOCAL TEST: ...` in Skynet's chat history. Text is not sent to any server.

The temporary Send and Cancel buttons used for debugging have now been removed. **Shift+A** is the unchanged chat hotkey. Enable the experiment with:

```text
/skynetui input hud
```

The remaining blocker is native-HUD interaction: text entry currently works only when the plugin temporarily hides `HUD.dlg`. Doing so is visually disruptive and is **not acceptable as the final design**. This experiment is opt-in and stays on the feature branch; no changes have been merged to `main`. The next investigation should isolate the IUP element or input interception preventing RmlUi interaction, without toggling the entire ship HUD.

The 12-second recovery timer restores the IUP HUD and flight controls if the RmlUi input remains open. `/skynetui input native` reselects the original working VO chat prompt, which remains the default on reload. No IUP reparenting is necessary for the validated RmlUi typing behavior.

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
