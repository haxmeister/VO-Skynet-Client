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

-- VO's original Skynet chat prompt is bound to A during initialization.
local function activate_chat()
    sync_visibility()
    if not ui.visible then return end
    open_chat_prompt()
end

-- /skynetui hide|show|demo|chat|native probe|dock|restore
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

print("Skynet UI prototype loaded; A opens chat; /skynetui native probe|dock|restore")
