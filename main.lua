-- VO plugin entry point. Demonstration data only; Skynet networking comes later.
local UI = dofile("ui.lua")
local NativeChat = dofile("native_chat.lua") -- opt-in HUD reparent experiment
-- RmlUi resolves relative paths in the plugin's initialization scope.
-- Load the RML from the entry point, not from a secondary dofile() module.
-- Start hidden. VO loads plugins even on the login screen.
local ui = UI.new({ visible = false })
-- Keep the UI instance local; Vendetta Online does not expose _G.

local context = rmlui and rmlui.contexts
    and (rmlui.contexts["main"] or rmlui.contexts[1])
if not context then
    print("Skynet UI: no RmlUi context available")
    return
end

-- VO's LoadDocument() path resolution is scoped to the calling plugin.
local document = context:LoadDocument("panel.rml")
if not document then
    print("Skynet UI: could not load panel.rml from plugin main.lua")
    return
end

local ok, err = ui:mount(context, document)
if not ok then
    print("Skynet UI: " .. tostring(err))
    return
end

local now = os.time()
ui:set_alliance_color("itani", "#65c6ff")
ui:set_alliance_color("serco", "#ff8282")
ui:set_alliance_color("uit", "#80e5a6")
ui:set_player_alliance("Falcon", "itani")
ui:set_player_alliance("Raven", "serco")
ui:set_player_alliance("Wraith", "uit")
ui:set_player_alliance("Specter", "itani")
ui:set_player_alliance("Drake", "serco")
ui:set_sector_owner("Odia M-14", "serco")
ui:set_sector_owner("Sedina B-8", "itani")
ui:replace_online({ "Wraith", "Falcon", "Raven", "Specter" })
ui:add_chat("Falcon", "Anyone near Sedina?")
ui:add_chat("Raven", "Two hostiles spotted.")
ui:add_chat("Wraith", "Heading there now.")
ui:add_chat("Falcon", "I'll hold position.")
ui:add_sighting("Drake", "Vult", "Odia M-14", now - 8)
ui:add_sighting("Specter", "Prom", "Sedina B-8", now - 17)
ui:set_connected(true) -- Demo indicator; NOT a real server connection.
-- No network send yet: submitting only echoes a message locally for UI testing.
ui:set_chat_submit_handler(function(message)
    ui:add_chat("LOCAL TEST", message)
end)

-- Flight visibility: keep the RML loaded but never display it outside
-- the ship HUD. This preserves chat, roster and sighting state while docked.
local user_wants_visible = true

local function is_flying()
    if type(PlayerInStation) ~= "function" or type(HasActiveShip) ~= "function" then
        return false
    end
    local station_ok, in_station = pcall(PlayerInStation)
    local ship_ok, active_ship = pcall(HasActiveShip)
    return station_ok and in_station == false and ship_ok and active_ship == true
end

-- Reversible keyboard routing test based on Draugath's MDI-Core:
-- Game.SetInputMode(false) while interacting; true for normal flight.
-- The previous Game.SetInputMode(0) test was NOT equivalent: Lua 0 is true.
-- We do not touch HUD.dlg or move the native IUP chat widget.
local chat_input_mode = "native" -- default remains the proven VO prompt
local flight_input_paused = false
local input_trial_serial = 0
local input_recovery_timer = Timer()

ui:set_chat_focus_handler(function(open)
    input_trial_serial = input_trial_serial + 1
    if open then
        if not Game or type(Game.SetInputMode) ~= "function" then
            print("Skynet UI: Game.SetInputMode unavailable; RmlUi input test aborted")
            return false
        end
        local ok_mode, mode_err = pcall(Game.SetInputMode, false)
        if not ok_mode then
            print("Skynet UI: cannot switch to UI input: " .. tostring(mode_err))
            return false
        end
        flight_input_paused = true
        print("Skynet UI: Game.SetInputMode(false); RmlUi input requested")
        -- Independent of Enter/Escape working: never trap flight input forever.
        local this_trial = input_trial_serial
        input_recovery_timer:SetTimeout(12000, function()
            if input_trial_serial == this_trial and ui.chat_input_open then
                print("Skynet UI: RmlUi input test timed out; restoring flight controls")
                ui:cancel_chat()
            end
        end)
        return true
    end

    if flight_input_paused then
        flight_input_paused = false
        local ok_mode, mode_err = pcall(Game.SetInputMode, true)
        if not ok_mode then
            print("Skynet UI: FAILED to restore Game.SetInputMode(true): "
                .. tostring(mode_err))
        else
            print("Skynet UI: Game.SetInputMode(true); flight controls restored")
        end
        if is_flying() and gkinterface
            and type(gkinterface.HideMouse) == "function" then
            pcall(gkinterface.HideMouse)
        end
    end
    return true
end)

-- Original Skynet/skynet2 used VO's built-in chat prompt instead of an
-- IUP dialog. This lets VO handle typing, Enter, Escape, and flight focus.
-- Keep the colored command name EXACTLY in sync with the prompt alias.
local prompt_command = "\12737c8abSkynet:"
local prompt_alias = "skynetui_prompt"
RegisterUserCommand(prompt_command, function(_, words)
    if type(words) ~= "table" then return end
    ui:deliver_chat(table.concat(words, " "))
end)

local prompt_ready = false
if gkinterface and type(gkinterface.GKProcessCommand) == "function" then
    local command = "alias " .. prompt_alias .. " 'prompt " .. prompt_command .. " '"
    local ok_alias, alias_err = pcall(gkinterface.GKProcessCommand, command)
    prompt_ready = ok_alias
    if not ok_alias then
        print("Skynet UI: cannot register VO chat prompt alias: " .. tostring(alias_err))
    end
else
    print("Skynet UI: gkinterface.GKProcessCommand is unavailable")
end

local function open_chat_prompt()
    if not prompt_ready then
        print("Skynet UI: native chat prompt is unavailable")
        return
    end
    local ok_prompt, prompt_err = pcall(gkinterface.GKProcessCommand, prompt_alias)
    if not ok_prompt then
        print("Skynet UI: cannot open chat prompt: " .. tostring(prompt_err))
    end
end

-- Bootstrapping from getters also handles ReloadInterface() while flying.
local ship_hud_visible = is_flying()

local function sync_visibility()
    if user_wants_visible and ship_hud_visible and is_flying() then
        ui:show()
    else
        -- Never keep a reparented VO chat control after leaving the ship HUD.
        NativeChat.restore(ui)
        ui:hide()
    end
end

-- The observer form is used by our VO APIProbe plugin and requires no metatables.
local lifecycle = {}
function lifecycle:OnEvent(event, view)
    if event == "HUD_SHOW" then
        ship_hud_visible = (view == "ship")
    elseif event == "HUD_HIDE"
        or event == "ENTERING_STATION"
        or event == "ENTERED_STATION"
        or event == "SHOW_STATION"
        or event == "PLAYER_LOGGED_OUT"
        or event == "SERVER_DISCONNECTED" then
        ship_hud_visible = false
    elseif event == "LEAVING_STATION"
        or event == "SHIP_SPAWNED"
        or event == "PLAYER_ENTERED_GAME" then
        -- Recheck actual ship/station state before displaying the panel.
        ship_hud_visible = is_flying()
    end
    sync_visibility()
end

for _, event in ipairs({
    "HUD_SHOW", "HUD_HIDE",
    "ENTERING_STATION", "ENTERED_STATION", "SHOW_STATION",
    "LEAVING_STATION", "SHIP_SPAWNED", "PLAYER_ENTERED_GAME",
    "PLAYER_LOGGED_OUT", "SERVER_DISCONNECTED",
}) do
    local registered, reason = pcall(RegisterEvent, lifecycle, event)
    if not registered then
        print("Skynet UI: cannot watch " .. event .. ": " .. tostring(reason))
    end
end

sync_visibility()

local ticker = Timer()
local function refresh()
    ui:tick()
    sync_visibility()
    NativeChat.realign(ui) -- keeps the overlay aligned after viewport changes
    ticker:SetTimeout(1000, refresh)
end
ticker:SetTimeout(1000, refresh)

-- A always remains the hard-coded chat hotkey. In the test mode it
-- opens the inline RmlUi field instead of VO's normal chat prompt.
local function activate_chat()
    sync_visibility()
    if not ui.visible then return end
    if ui.chat_input_open then
        ui:cancel_chat()
    elseif chat_input_mode == "rml" then
        if not ui:begin_chat() then
            print("Skynet UI: RmlUi chat input could not open; "
                .. "use /skynetui input native to revert")
        end
    else
        open_chat_prompt()
    end
end

-- /skynetui hide|show|demo|chat|input rml|native|native probe|dock|restore
RegisterUserCommand("skynetui", function(_, args)
    local command = args and args[1] or "show"
    if command == "hide" then
        user_wants_visible = false
    elseif command == "demo" then
        user_wants_visible = true
        ui:add_chat("Raven", "New demo message.")
        ui:add_sighting("Drake", "Vult", "Odia M-14")
    elseif command == "chat" then
        activate_chat()
        return
    elseif command == "input" then
        local mode = args and args[2]
        if mode == "rml" then
            -- Never combine this test with the unverified IUP relocation test.
            if not NativeChat.restore(ui) then
                print("Skynet UI: restore IUP chat first; input mode unchanged")
                return
            end
            ui:cancel_chat()
            chat_input_mode = "rml"
            print("Skynet UI: A now tests inline RmlUi input; "
                .. "auto-recovery after 12 seconds")
        elseif mode == "native" then
            ui:cancel_chat()
            chat_input_mode = "native"
            print("Skynet UI: A restored to native VO prompt")
        else
            print("Skynet UI: /skynetui input rml|native")
        end
        return
    elseif command == "native" then
        local action = args and args[2] or "probe"
        if action == "probe" then
            NativeChat.probe(ui)
        elseif action == "dock" then
            sync_visibility()
            NativeChat.dock(ui)
        elseif action == "restore" then
            NativeChat.restore(ui)
        else
            print("Skynet UI: /skynetui native probe|dock|restore")
        end
        return
    else
        user_wants_visible = true
    end
    sync_visibility()
end)

-- Hard-code the chat hotkey to A, matching the requested behavior.
-- This deliberately replaces any existing binding for the A key.
RegisterUserCommand("skynetui_chat", function()
    activate_chat()
end)

if gkinterface and type(gkinterface.GKProcessCommand) == "function" then
    local ok_bind, bind_err = pcall(gkinterface.GKProcessCommand, "bind A skynetui_chat")
    if not ok_bind then
        print("Skynet UI: cannot bind A to chat: " .. tostring(bind_err))
    end
end

print("Skynet UI prototype loaded; A opens native chat; /skynetui input rml|native")
