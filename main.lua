-- VO plugin entry point. Demonstration data only; Skynet networking comes later.
local UI = dofile("ui.lua")
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

-- RmlUi Focus() alone is not enough while VO routes keys to flight.
-- The native HUD historically selects Game.SetInputMode(1) for flight controls.
-- Mode 0 is a limited experimental handoff to UI input (verify in client).
local input_mode_active = false
local focus_generation = 0
local focus_timer = Timer()

ui:set_chat_focus_handler(function(open)
    focus_generation = focus_generation + 1
    if open then
        if not Game or type(Game.SetInputMode) ~= "function" then
            print("Skynet UI: Game.SetInputMode unavailable; keyboard routing unchanged")
        else
            local ok_mode, mode_err = pcall(Game.SetInputMode, 0)
            if ok_mode then
                input_mode_active = true
                print("Skynet UI: requested UI input mode (0)")
            else
                print("Skynet UI: cannot switch keyboard mode: " .. tostring(mode_err))
            end
        end
        -- Experimental focus handoff: always recover flight input if neither
        -- Enter nor Escape reaches RmlUi. Remove when validated in VO.
        local generation = focus_generation
        focus_timer:SetTimeout(20000, function()
            if ui.chat_input_open and focus_generation == generation then
                print("Skynet UI: chat input safety timeout; restoring controls")
                ui:cancel_chat()
            end
        end)
    elseif input_mode_active then
        input_mode_active = false
        -- Don't force flight mode onto the login, station, or other HUD views.
        if is_flying() then
            local ok_mode, mode_err = pcall(Game.SetInputMode, 1)
            if not ok_mode then
                print("Skynet UI: cannot restore flight input: " .. tostring(mode_err))
            else
                print("Skynet UI: restored flight input mode (1)")
            end
        end
    end
end)

-- Bootstrapping from getters also handles ReloadInterface() while flying.
local ship_hud_visible = is_flying()

local function sync_visibility()
    if user_wants_visible and ship_hud_visible and is_flying() then
        ui:show()
    else
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
    ticker:SetTimeout(1000, refresh)
end
ticker:SetTimeout(1000, refresh)

-- Do not bind a key automatically: the player should choose a free key.
local function toggle_chat()
    sync_visibility()
    if ui.chat_input_open then
        ui:cancel_chat()
    else
        ui:begin_chat()
    end
end

-- /skynetui hide|show|demo|chat
RegisterUserCommand("skynetui", function(_, args)
    local command = args and args[1] or "show"
    if command == "hide" then
        user_wants_visible = false
    elseif command == "demo" then
        user_wants_visible = true
        ui:add_chat("Raven", "New demo message.")
        ui:add_sighting("Drake", "Vult", "Odia M-14")
    elseif command == "chat" then
        toggle_chat()
        return
    else
        user_wants_visible = true
    end
    sync_visibility()
end)

-- VO's /bind can target this command: /bind F8 skynetui_chat
RegisterUserCommand("skynetui_chat", function()
    toggle_chat()
end)

print("Skynet UI prototype loaded; /skynetui hide|show|demo|chat")
