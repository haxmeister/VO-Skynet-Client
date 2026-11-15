-- VO plugin entry point. Demo data only; no Skynet transport yet.
-- The native HUD stays visible while RmlUi text controls own keyboard focus.
local UI = dofile("ui.lua")
local InputRouter = dofile("rmlui_input.lua")
local TextEntry = dofile("rmlui_text_entry.lua")

local CHAT_RECOVERY_TIMEOUT_MS = 12000 -- 0 disables automatic recovery.

-- Persistent layout is shared across characters. gkini is VO's
-- supported plugin configuration store; the old Game preference path is
-- read as a migration fallback for anyone who already saved a layout.
local LAYOUT_SECTION = "skynetui"
local LAYOUT_KEY = "layout_v1"
local LEGACY_LAYOUT_PREF = "skynetui.layout.v1"
local LAYOUT_FIELDS = {"left", "top", "width", "height", "online", "sightings"}

local function read_geometry_value()
    if gkini and type(gkini.ReadString) == "function" then
        local ok, value = pcall(gkini.ReadString,
            LAYOUT_SECTION, LAYOUT_KEY, "")
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end
    -- The previous release used Game.GetPrefString. Import it if present,
    -- then write through gkini at the next drag or DONE click.
    if Game and type(Game.GetPrefString) == "function" then
        local ok, value = pcall(Game.GetPrefString,
            LEGACY_LAYOUT_PREF, "")
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end
end

local function load_geometry()
    local raw = read_geometry_value()
    if not raw then return nil end
    local values = {}
    for value in raw:gmatch("[^,]+") do
        values[#values + 1] = tonumber(value)
    end
    if #values ~= 6 then return nil end
    local geometry = {}
    for i, field in ipairs(LAYOUT_FIELDS) do geometry[field] = values[i] end
    return geometry
end

local function save_geometry(geometry)
    local values = {}
    for i, field in ipairs(LAYOUT_FIELDS) do values[i] = geometry[field] end
    local packed = table.concat(values, ",")
    if gkini and type(gkini.WriteString) == "function" then
        local ok, result = pcall(gkini.WriteString,
            LAYOUT_SECTION, LAYOUT_KEY, packed)
        if ok and result ~= false then return true end
        print("Skynet UI: gkini layout save failed: " .. tostring(result))
    end
    -- Compatibility fallback for clients exposing only the older API.
    if Game and type(Game.SetPrefString) == "function" then
        local ok, result = pcall(Game.SetPrefString,
            LEGACY_LAYOUT_PREF, packed)
        if ok and result ~= false then return true end
        print("Skynet UI: legacy layout save failed: " .. tostring(result))
    end
    print("Skynet UI: no writable persistent layout preference API available")
    return false
end

local ui = UI.new({
    visible = false,
    text_entry_class = TextEntry,
    load_geometry = load_geometry,
    save_geometry = save_geometry,
})

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

-- Keep the current sample display; demo implementation lives outside startup.
local Demo = dofile("dev/demo.lua")
Demo.seed(ui)

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

-- Being in flight is not enough: the navigation/PDA menu can open while
-- PlayerInStation() is false and HasActiveShip() remains true.
-- Check the actual native ship HUD, which becomes hidden for menus.
local function native_ship_hud_visible()
    if not HUD or not HUD.dlg then return true end
    local ok, visible = pcall(function() return HUD.dlg.visible end)
    if not ok or visible == nil then return true end
    return visible == "YES" or visible == true
end

-- HUD_SHOW/HUD_HIDE remain primary; the HUD's VISIBLE property catches
-- PDA transitions that do not emit those events to plugins.
local ship_hud_visible = is_flying()

-- Other RmlUi widgets can use the same input router with a different owner:
-- router:acquire("settings", cancel_settings, 0)
-- router:release("settings")
-- The router holds HUD.dlg.active=NO while ANY owner is active.
local router = InputRouter.new({
    timeout_ms = 0,
    -- A PDA transition must NOT re-enable flight controls. VO will restore
    -- its own flight mode when it returns to the ship HUD.
    should_restore_flight = function()
        return ship_hud_visible and is_flying()
            and native_ship_hud_visible()
    end,
    hide_mouse = function()
        if is_flying() and gkinterface
            and type(gkinterface.HideMouse) == "function" then
            gkinterface.HideMouse()
        end
    end,
})

ui:set_layout_focus_handler(function(open)
    if open then
        local allowed, reason = router:acquire("layout", function()
            ui:set_layout_editing(false)
        end, 0)
        if not allowed then
            print("Skynet UI: cannot enter layout editing: " .. tostring(reason))
            return false
        end
        if gkinterface and type(gkinterface.ShowMouse) == "function" then
            local ok_mouse, mouse_err = pcall(gkinterface.ShowMouse)
            if not ok_mouse then
                print("Skynet UI: unable to show layout mouse: " .. tostring(mouse_err))
            end
        end
        return true
    end
    return router:release("layout")
end)

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

-- Show only in the actual flight HUD, never over the PDA/navigation menu.
-- The visible attribute also covers clients where PDA transitions do not
-- generate HUD_HIDE. Check before restoring native flight input.
local function sync_visibility()
    local hud_visible = native_ship_hud_visible()
    local show = user_wants_visible and is_flying()
        and ship_hud_visible and hud_visible
    if show then
        ui:show()
    else
        if router:is_active() and (not ship_hud_visible or not hud_visible) then
            router:cancel_all("ship-hud-not-visible")
        end
        if ui.visible then ui:hide() end
    end
end

-- One event map drives both registration and the visibility transition.
local hud_events = {
    HUD_SHOW = "show", HUD_HIDE = "hide",
    ENTERING_STATION = "hide", ENTERED_STATION = "hide", SHOW_STATION = "hide",
    PLAYER_LOGGED_OUT = "hide", SERVER_DISCONNECTED = "hide", UNLOAD_INTERFACE = "hide",
    LEAVING_STATION = "flight", SHIP_SPAWNED = "flight", PLAYER_ENTERED_GAME = "flight",
}
local lifecycle = {}
function lifecycle:OnEvent(event, view)
    local action = hud_events[event]
    if action == "show" then
        ship_hud_visible = (view == "ship")
        if not ship_hud_visible then
            router:cancel_all("hud-view-changed")
        end
    elseif action == "hide" then
        ship_hud_visible = false
        router:cancel_all(event)
    elseif action == "flight" then
        ship_hud_visible = is_flying()
    end
    if event == "UNLOAD_INTERFACE" then
        ui:unmount()
        return
    end
    sync_visibility()
end

for event in pairs(hud_events) do
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

-- The navigation/PDA can open without a plugin-visible HUD_HIDE event.
-- Poll only HUD visibility (not the full UI layout) so the Skynet RmlUi
-- document releases the menu promptly instead of obscuring its controls.
local hud_visibility_timer = Timer()
local function check_hud_visibility()
    sync_visibility()
    hud_visibility_timer:SetTimeout(125, check_hud_visibility)
end
hud_visibility_timer:SetTimeout(125, check_hud_visibility)

-- Shift+A always opens our inline RmlUi input unless native fallback selected.
local function activate_chat()
    sync_visibility()
    if not ui.visible then return end
    if ui.layout_editing then
        print("Skynet UI: finish layout editing with DONE before opening chat")
        return
    end
    if ui.chat_input_open then
        ui:cancel_chat()
    elseif chat_input_mode == "native" then
        open_chat_prompt()
    elseif not ui:begin_chat() then
        print("Skynet UI: cannot open RmlUi chat; try /skynetui input native")
    end
end

-- /skynetui hide|show|demo [flood|scroll|scrollcheck]|chat|layout|resetlayout|input rml|native
RegisterUserCommand("skynetui", function(_, args)
    local command = args and args[1] or "show"
    if command == "hide" then
        user_wants_visible = false
    elseif command == "demo" then
        user_wants_visible = true
        Demo.run(ui, args and args[2])
    elseif command == "layout" then
        sync_visibility()
        if not ui.visible then
            print("Skynet UI: layout editing is available while flying")
            return
        end
        ui:cancel_chat()
        local enabled = not ui.layout_editing
        if ui:set_layout_editing(enabled) and enabled then
            print("Skynet UI: drag SKYNET title to move; drag separators to"
                .. " resize columns; drag bottom-right square to resize;"
                .. " click DONE to finish")
        end
        return
    elseif command == "resetlayout" then
        ui:reset_layout()
        return
    elseif command == "chat" then
        activate_chat()
        return
    elseif command == "input" then
        local mode = args and args[2]
        if mode == "active" then mode = "rml" end
        if mode == "rml" or mode == "native" then
            ui:cancel_chat()
            chat_input_mode = mode
            print(mode == "rml"
                and "Skynet UI: RmlUi text input enabled (HUD remains visible)"
                or "Skynet UI: native VO prompt fallback enabled")
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

print("Skynet UI loaded; Shift+A chat; /skynetui layout for drag/resize;"
    .. " /skynetui demo flood tests scrolling and fading sightings")
