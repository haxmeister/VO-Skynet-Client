-- Exercise the real entry point and modules with VO/RmlUi API stand-ins.
-- Run from the repository root: lua tests/test_main.lua
local original_dofile, original_time = dofile, os.time
local captured, commands, events, timers, processed, modes = {}, {}, {}, {}, {}, {}
local persisted, legacy, in_station, active_ship = nil, nil, false, true
local nodes = {}
local function node(id)
    if nodes[id] then return nodes[id] end
    local n = {style = {}, attrs = {}, listeners = {}, inner_rml = "",
        scroll_top = 0, client_height = 80, scroll_height = 80}
    function n:SetAttribute(key, value) self.attrs[key] = value end
    function n:GetAttribute(key) return self.attrs[key] end
    function n:SetClass(key, value) self.attrs[key] = value end
    function n:AddEventListener(kind, callback) self.listeners[kind] = callback end
    function n:Focus() self.focused = true end
    function n:Blur() self.focused = false end
    function n:dispatch(kind, parameters)
        local event = {parameters = parameters or {}}
        function event:StopPropagation() self.stopped = true end
        assert(self.listeners[kind], kind)(event)
        return event
    end
    nodes[id] = n
    return n
end
local document = {shows = 0, hides = 0}
function document:GetElementById(id) return node(id) end
function document:Show() self.shows = self.shows + 1; self.visible = true end
function document:Hide() self.hides = self.hides + 1; self.visible = false end
function document:Close() self.closed = true end
local context = {dimensions = {x = 1024, y = 806}, keys = {}}
function context:LoadDocument(path)
    assert(path == "panel.rml")
    return document
end
function context:ProcessKeyDown(key) self.keys[#self.keys + 1] = key end
function context:ProcessKeyUp(key) self.keys[#self.keys + 1] = key end
HUD = {dlg = {active = "YES", visible = "YES"}}
rmlui = {contexts = {main = context}, key_identifier = {KI_END = 88}}
Game = {
    SetInputMode = function(value) modes[#modes + 1] = value end,
    GetPrefString = function(key, default)
        assert(key == "skynetui.layout.v1")
        return legacy or default
    end,
    SetPrefString = function(key, value)
        assert(key == "skynetui.layout.v1")
        legacy = value
    end,
}
gkini = {
    ReadString = function(section, key, default)
        assert(section == "skynetui" and key == "layout_v1")
        return persisted or default
    end,
    WriteString = function(section, key, value)
        assert(section == "skynetui" and key == "layout_v1")
        persisted = value
    end,
}
gkinterface = {
    GKProcessCommand = function(command) processed[#processed + 1] = command end,
    ShowMouse = function() end,
    HideMouse = function() end,
}
function PlayerInStation() return in_station end
function HasActiveShip() return active_ship end
function RegisterUserCommand(name, callback) commands[name] = callback end
function RegisterEvent(listener, event) events[event] = listener end
function TabCompleteName(fragment)
    if fragment == "lost" then return "Lost Crow" end
end
-- Build a callable Timer before removing metatables from the plugin sandbox.
Timer = setmetatable({}, {__call = function()
    local timer = {}
    function timer:SetTimeout(ms, callback)
        self.duration, self.callback = ms, callback
    end
    function timer:Kill() self.callback = nil end
    timers[#timers + 1] = timer
    return timer
end})
setmetatable = nil
os.time = function() return 7000 end
function dofile(path)
    local module = original_dofile(path)
    if path == "ui.lua" or path == "rmlui_input.lua" then
        local new = module.new
        module.new = function(options)
            local instance = new(options)
            captured[path] = instance
            return instance
        end
    end
    return module
end
dofile("main.lua")
local ui, router = captured["ui.lua"], captured["rmlui_input.lua"]
local function command(...)
    commands.skynetui(nil, {...})
end
local function event(kind, view) events[kind]:OnEvent(kind, view) end
local function poll()
    for _, timer in ipairs(timers) do
        if timer.duration == 125 and timer.callback then timer.callback(); return end
    end
    error("125ms HUD visibility timer missing")
end
local registered = 0
for _ in pairs(events) do registered = registered + 1 end
assert(registered == 11)
assert(ui.visible and document.visible and ui.connected)
assert(#ui.chat == 4 and ui.online.Falcon and ui.online.Wraith)
assert(ui.sightings.Drake.seen_at == 6992)
assert(ui.sightings.Specter.seen_at == 6983)
assert(processed[#processed] == "bind A skynetui_chat")

-- Real chat controller: delayed completion, single submit across both phases,
-- cleared drafts, native HUD stays visible, Escape and watchdog restore input.
commands.skynetui_chat()
assert(ui.chat_input_open and HUD.dlg.active == "NO")
assert(HUD.dlg.visible == "YES" and modes[#modes] == false)
local input = node("chat-input")
input:dispatch("change", {value = "lost"})
assert(input:dispatch("keydown", {key_identifier = 70}).stopped)
assert(input:dispatch("keyup", {key_identifier = 70}).stopped)
ui.chat_entry.caret_timer.callback()
assert(context.keys[1] == 88 and context.keys[2] == 88)
local count = #ui.chat
input:dispatch("keydown", {key_identifier = 72})
input:dispatch("keyup", {key_identifier = 72})
assert(#ui.chat == count + 1 and ui.chat[#ui.chat].message == "Lost Crow")
assert(not ui.chat_input_open and input.attrs.value == "")
assert(HUD.dlg.active == "YES" and modes[#modes] == true)
commands.skynetui_chat()
assert(input.attrs.value == "")
input:dispatch("change", {value = "cancel me"})
input:dispatch("keydown", {key_identifier = 81})
input:dispatch("keyup", {key_identifier = 81})
assert(#ui.chat == count + 1 and not ui.chat_input_open)
commands.skynetui_chat()
assert(router.owners.chat.timer.duration == 12000)
router.owners.chat.timer.callback()
assert(not ui.chat_input_open and not router:is_active())

-- submit_chat without an explicit message reads the entry's authoritative draft.
commands.skynetui_chat()
input:dispatch("change", {value = "  direct draft  "})
assert(ui:submit_chat("integration-test"))
assert(ui.chat[#ui.chat].message == "direct draft")
assert(not ui.chat_input_open and ui.chat_entry.draft == "")

-- PDA can take over with an active ship and no HUD_HIDE event, in each mode.
for _, mode in ipairs({"idle", "chat", "layout"}) do
    if mode ~= "idle" then command(mode) end
    local before = #modes
    HUD.dlg.visible = "NO"
    poll()
    assert(not ui.visible and not document.visible and not router:is_active())
    assert(not ui.chat_input_open and not ui.layout_editing)
    assert(HUD.dlg.active == "YES" and #modes == before)
    local hides = document.hides
    poll()
    assert(document.hides == hides)
    HUD.dlg.visible = "YES"
    poll()
    assert(ui.visible and document.visible)
end
HUD.dlg.visible = false
poll()
assert(not ui.visible)
HUD.dlg.visible = nil -- Legacy clients rely on HUD events.
poll()
assert(ui.visible)
command("chat")
local before = #modes
event("HUD_HIDE")
assert(not ui.visible and not router:is_active() and #modes == before)
event("HUD_SHOW", "pda")
assert(not ui.visible)
event("HUD_SHOW", "ship")
assert(ui.visible)
command("hide")
poll()
assert(not ui.visible)
command("show")
assert(ui.visible)
in_station = true
event("ENTERING_STATION")
assert(not ui.visible)
event("ENTERED_STATION")
in_station = false
event("LEAVING_STATION")
assert(ui.visible)
for _, hidden in ipairs({"SHOW_STATION", "PLAYER_LOGGED_OUT", "SERVER_DISCONNECTED"}) do
    command("chat")
    before = #modes
    event(hidden)
    assert(not ui.visible and not router:is_active() and #modes == before)
    event("SHIP_SPAWNED")
    assert(ui.visible)
end
active_ship = false
event("PLAYER_ENTERED_GAME")
assert(not ui.visible)
active_ship = true
event("PLAYER_ENTERED_GAME")
assert(ui.visible)

-- Native prompt fallback and compatibility alias still use the same delivery.
command("input", "native")
commands.skynetui_chat()
assert(processed[#processed] == "skynetui_prompt" and not ui.chat_input_open)
commands["\12737c8abSkynet:"](nil, {"native", "message"})
assert(ui.chat[#ui.chat].message == "native message")
command("input", "active")
commands.skynetui_chat()
assert(ui.chat_input_open)
commands.skynetui_chat()
assert(not ui.chat_input_open)

-- Demonstration behavior is unchanged after moving its implementation.
local renders, original_render = 0, ui.render_chat
function ui:render_chat() renders = renders + 1; return original_render(self) end
count = #ui.chat
command("demo", "flood")
assert(#ui.chat == count + 40 and renders == 1 and ui.chat_follow_bottom)
for i, phase in ipairs({0, 0.70, 0.85, 0.90, 0.95, 0.98}) do
    assert(ui.sightings["Fade-" .. i].seen_at == 7000 - math.floor(60 * phase))
end
command("demo", "scroll")
local online, sightings = 0, 0
for _ in pairs(ui.online) do online = online + 1 end
for name in pairs(ui.sightings) do
    if name:match("^TestSight%-%d+$") then sightings = sightings + 1 end
end
assert(online == 32 and sightings == 24)
assert(node("sightings-list").scroll_top == 0)
local original_print, diagnostics = print, {}
print = function(line) diagnostics[#diagnostics + 1] = line end
command("demo", "scrollcheck")
print = original_print
assert(#diagnostics == 2)
for _, line in ipairs(diagnostics) do
    assert(line:find("scroll_top=0 viewport=80 content=80 max=0", 1, true))
end
command("demo")
assert(ui.chat[#ui.chat].message == "New demo message.")
assert(ui.sightings.Drake.seen_at == 7000)

-- Use the callbacks supplied by main.lua, not extracted source fragments.
local geometry = {left = 220, top = 585, width = 650, height = 216,
    online = 40, sightings = 190}
persisted = nil
assert(ui.load_geometry() == nil)
assert(ui.save_geometry(geometry))
assert(persisted == "220,585,650,216,40,190")
for key, value in pairs(geometry) do assert(ui.load_geometry()[key] == value) end
persisted, legacy = nil, "220,585,650,216,40,190"
local migrated = assert(ui.load_geometry())
assert(migrated.online == 40 and migrated.sightings == 190)
assert(ui.save_geometry(migrated) and persisted == legacy)
local config = gkini
gkini, legacy = nil, nil
assert(ui.save_geometry(geometry) and legacy == "220,585,650,216,40,190")
assert(ui.load_geometry().online == 40)
gkini = config
legacy = nil
for _, invalid in ipairs({"", "1,2,3", "1,2,3,4,no,6"}) do
    persisted = invalid
    assert(ui.load_geometry() == nil)
end
command("resetlayout")
assert(ui.geometry.left == 190 and ui.geometry.online == 180)
event("UNLOAD_INTERFACE")
assert(document.closed and ui.document == nil and not router:is_active())
os.time, dofile = original_time, original_dofile
print("PASS: actual main startup, demo, preferences, chat, PDA, station and unload")
