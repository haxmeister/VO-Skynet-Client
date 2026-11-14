-- VO plugin entry point. Demonstration data only; Skynet networking comes later.
local UI = dofile("ui.lua")
-- RmlUi resolves relative paths in the plugin's initialization scope.
-- Load the RML from the entry point, not from a secondary dofile() module.
local ui = UI.new()
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

local ticker = Timer()
local function refresh()
    ui:tick()
    ticker:SetTimeout(1000, refresh)
end
ticker:SetTimeout(1000, refresh)

-- /skynetui hide|show|demo
-- /skynetui demo can add new sample sightings/messages after launch.
RegisterUserCommand("skynetui", function(_, args)
    local command = args and args[1] or "show"
    if command == "hide" then
        ui:hide()
    elseif command == "demo" then
        ui:show()
        ui:add_chat("Raven", "New demo message.")
        ui:add_sighting("Drake", "Vult", "Odia M-14")
    else
        ui:show()
    end
end)
print("Skynet UI prototype loaded; /skynetui hide|show|demo")
