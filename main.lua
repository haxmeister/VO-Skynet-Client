-- VO plugin entry point. Demo data only; no Skynet transport yet.
-- The native HUD stays visible while RmlUi text controls own keyboard focus.
local UI = dofile("ui.lua")
local InputRouter = dofile("rmlui_input.lua")
local TextEntry = dofile("rmlui_text_entry.lua")

local CHAT_RECOVERY_TIMEOUT_MS = 12000 -- 0 disables automatic recovery.
local ui = UI.new({ visible = false, text_entry_class = TextEntry })

-- RmlUi documents must be loaded in this plugin entry point so VO resolves
-- panel.rml relative to this plugin.
local context = rmlui and rmlui.contexts
    and (rmlui.contexts["main"] or rmlui.contexts[1])
if not context then
    print("Skynet UI: no RmlUi context available")
    return
end
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

-- Simulated roster and chat. This plugin does not send any network messages.
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
ui:set_connected(true) -- Demonstration indicator, not a real connection.
ui:set_chat_submit_handler(function(message)
    ui:add_chat("LOCAL TEST", message)
end)

local user_wants_visible = true
local chat_input_mode = "rml" -- Native VO prompt remains an emergency fallback.

local function is_flying()
    if type(PlayerInStation) ~= "function" or type(HasActiveShip) ~= "function" then
        return false
    end
    local station_ok, in_station = pcall(PlayerInStation)
    local ship_ok, active_ship = pcall(HasActiveShip)
    return station_ok and in_station == false and ship_ok and active_ship == true
end

-- Other RmlUi widgets can use the same input router with a different owner:
-- router:acquire("settings", cancel_settings, 0)
-- router:release("settings")
-- The router holds HUD.dlg.active=NO while ANY owner is active.
local router = InputRouter.new({
    timeout_ms = 0,
    hide_mouse = function()
        if is_flying() and gkinterface
            and type(gkinterface.HideMouse) == "function" then
            gkinterface.HideMouse()
        end
    end,
})

ui:set_chat_focus_handler(function(open)
    if open then
        local ok_focus, reason = router:acquire("chat", function(why)
            ui:cancel_chat(why)
        end, CHAT_RECOVERY_TIMEOUT_MS)
        if not ok_focus then
            print("Skynet UI: RmlUi focus denied: " .. tostring(reason))
            return false
        end
        return true
    end
    return router:release("chat")
end)

-- Keep the original VO prompt as a fallback, not as the default chat input.
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
        print("Skynet UI: cannot register native prompt: " .. tostring(alias_err))
    end
end

local function open_chat_prompt()
    if not prompt_ready then
        print("Skynet UI: native VO prompt unavailable")
        return
    end
    local ok_prompt, prompt_err = pcall(gkinterface.GKProcessCommand, prompt_alias)
    if not ok_prompt then
        print("Skynet UI: cannot open native prompt: " .. tostring(prompt_err))
    end
end

-- HUD_SHOW is observed in game; getters handle in-flight ReloadInterface().
local ship_hud_visible = is_flying()
local function sync_visibility()
    if user_wants_visible and is_flying() and ship_hud_visible then
        ui:show()
    else
        ui:hide() -- cancel_chat releases our input ownership if necessary.
    end
end

local lifecycle = {}
function lifecycle:OnEvent(event, view)
    if event == "HUD_SHOW" then
        ship_hud_visible = (view == "ship")
        if not ship_hud_visible then
            router:cancel_all("hud-view-changed")
        end
    elseif event == "HUD_HIDE"
        or event == "ENTERING_STATION"
        or event == "ENTERED_STATION"
        or event == "SHOW_STATION"
        or event == "PLAYER_LOGGED_OUT"
        or event == "SERVER_DISCONNECTED"
        or event == "UNLOAD_INTERFACE" then
        ship_hud_visible = false
        router:cancel_all(event)
    elseif event == "LEAVING_STATION"
        or event == "SHIP_SPAWNED"
        or event == "PLAYER_ENTERED_GAME" then
        ship_hud_visible = is_flying()
    end
    if event == "UNLOAD_INTERFACE" then
        ui:unmount()
        return
    end
    sync_visibility()
end

for _, event in ipairs({
    "HUD_SHOW", "HUD_HIDE",
    "ENTERING_STATION", "ENTERED_STATION", "SHOW_STATION",
    "LEAVING_STATION", "SHIP_SPAWNED", "PLAYER_ENTERED_GAME",
    "PLAYER_LOGGED_OUT", "SERVER_DISCONNECTED", "UNLOAD_INTERFACE",
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

-- Shift+A always opens our inline RmlUi input unless native fallback selected.
local function activate_chat()
    sync_visibility()
    if not ui.visible then return end
    if ui.chat_input_open then
        ui:cancel_chat()
    elseif chat_input_mode == "native" then
        open_chat_prompt()
    elseif not ui:begin_chat() then
        print("Skynet UI: cannot open RmlUi chat; try /skynetui input native")
    end
end

-- /skynetui hide|show|demo|chat|input rml|native
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
        if mode == "rml" or mode == "active" then
            ui:cancel_chat()
            chat_input_mode = "rml"
            print("Skynet UI: RmlUi text input enabled (HUD remains visible)")
        elseif mode == "native" then
            ui:cancel_chat()
            chat_input_mode = "native"
            print("Skynet UI: native VO prompt fallback enabled")
        else
            print("Skynet UI: /skynetui input rml|native")
        end
        return
    else
        user_wants_visible = true
    end
    sync_visibility()
end)

-- Preserve the verified uppercase A (Shift+A) VO binding.
RegisterUserCommand("skynetui_chat", function()
    activate_chat()
end)
if gkinterface and type(gkinterface.GKProcessCommand) == "function" then
    local ok_bind, bind_err = pcall(
        gkinterface.GKProcessCommand, "bind A skynetui_chat")
    if not ok_bind then
        print("Skynet UI: cannot bind Shift+A: " .. tostring(bind_err))
    end
end

print("Skynet UI loaded; Shift+A opens RmlUi chat; /skynetui input rml|native")
