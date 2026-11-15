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

-- VO's IUP dialogs handle keyboard focus in flight. The failed
-- Game.SetInputMode(0) experiment was removed; native dialogs should
-- restore flight controls through VO's own ShowDialog/HideDialog logic.
local native_chat_open = false
local native_chat_dialog = nil
local native_chat_input = nil

local function close_native_chat(submit)
    if not native_chat_open then return end
    local message = native_chat_input and tostring(native_chat_input.value or "") or ""
    native_chat_open = false
    if native_chat_dialog then
        local ok_hide, hide_err = pcall(HideDialog, native_chat_dialog)
        if not ok_hide then
            print("Skynet UI: HideDialog failed: " .. tostring(hide_err))
        end
        -- Guard against an IUP dialog remaining mapped when the wrapper fails.
        if not ok_hide or native_chat_dialog.visible == "YES" then
            local ok_fallback, fallback_err = pcall(function()
                native_chat_dialog:hide()
            end)
            if not ok_fallback then
                print("Skynet UI: direct dialog hide failed: " .. tostring(fallback_err))
            end
        end
    end
    if submit then
        message = message:match("^%s*(.-)%s*$")
        if message ~= "" then
            ui:add_chat("LOCAL TEST", message) -- never sends to VO chat
        end
    end
end

local function open_native_chat()
    if type(iup) ~= "table" and type(iup) ~= "userdata" then
        print("Skynet UI: IUP is unavailable")
        return false
    end
    if type(ShowDialog) ~= "function" or type(HideDialog) ~= "function" then
        print("Skynet UI: ShowDialog/HideDialog unavailable")
        return false
    end
    if not native_chat_dialog then
        local input = iup.text {
            value = "",
            size = "340x",
            expand = "HORIZONTAL",
        }
        local send_button = iup.button { title = "Send", size = "64x" }
        local cancel_button = iup.button { title = "Cancel", size = "64x" }
        local dialog = iup.dialog {
            iup.vbox {
                iup.label { title = "Skynet alliance chat" },
                input,
                iup.hbox {
                    iup.fill {},
                    send_button,
                    cancel_button,
                    gap = "6",
                },
                margin = "8x8",
                gap = "5",
            },
            title = "Skynet chat",
            resize = "NO",
            maxbox = "NO",
            minbox = "NO",
            -- IUP reserves Enter/Escape for DEFAULTENTER/DEFAULTESC.
            -- These attributes refer directly to the buttons.
            defaultenter = send_button,
            defaultesc = cancel_button,
        }
        function send_button:action()
            close_native_chat(true)
            return iup.DEFAULT
        end
        function cancel_button:action()
            close_native_chat(false)
            return iup.DEFAULT
        end
        function dialog:close_cb()
            close_native_chat(false)
            return iup.IGNORE
        end
        native_chat_input = input
        native_chat_dialog = dialog
    end
    native_chat_input.value = ""
    local shown, show_err = pcall(ShowDialog, native_chat_dialog, iup.CENTER, iup.CENTER)
    if not shown then
        print("Skynet UI: cannot open native chat dialog: " .. tostring(show_err))
        return false
    end
    native_chat_open = true
    if type(iup.SetFocus) == "function" then
        local focused, focus_err = pcall(iup.SetFocus, native_chat_input)
        if not focused then
            print("Skynet UI: cannot focus native chat input: " .. tostring(focus_err))
        end
    end
    return true
end

-- Bootstrapping from getters also handles ReloadInterface() while flying.
local ship_hud_visible = is_flying()

local function sync_visibility()
    local flying = is_flying()
    if not user_wants_visible or not flying then
        -- A real dock/logout or user hide must close the text entry.
        close_native_chat(false)
        ui:hide()
    elseif ship_hud_visible then
        ui:show()
    else
        -- Some native dialogs may hide the ship HUD temporarily.
        -- Do not close our own dialog just because HUD_HIDE fired.
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
    -- The native dialog may hide the ship HUD, so close it BEFORE
    -- checking the HUD's visibility. Otherwise the hotkey cannot rescue it.
    if native_chat_open then
        close_native_chat(false)
        return
    end
    sync_visibility()
    if not ui.visible then return end
    open_native_chat()
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
    elseif command == "close" then
        close_native_chat(false)
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
-- An independent escape hatch even if VO hides the ship HUD for the dialog.
RegisterUserCommand("skynetui_close", function()
    close_native_chat(false)
end)

print("Skynet UI prototype loaded; /skynetui hide|show|demo|chat|close")
