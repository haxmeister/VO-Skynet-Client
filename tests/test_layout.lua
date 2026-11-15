-- Geometry / scrolling regression tests with an RmlUi document stub.
-- Run from the repository root: lua tests/test_layout.lua

local UI = dofile("ui.lua")

local function element(id)
    local node = {
        id = id, style = {}, listeners = {}, attrs = {},
        scroll_top = 0, client_height = 80, scroll_height = 80,
        client_width = 100, inner_rml = "",
    }
    function node:AddEventListener(kind, handler)
        self.listeners[kind] = handler
    end
    function node:SetAttribute(key, value)
        self.attrs[key] = value
    end
    function node:GetAttribute(key)
        return self.attrs[key]
    end
    function node:SetClass(name, value)
        self.classes = self.classes or {}
        self.classes[name] = value
        self.class_updates = (self.class_updates or 0) + 1
    end
    function node:Focus() self.focused = true end
    function node:Blur() self.focused = false end
    function node:dispatch(kind, parameters)
        local event = {parameters = parameters or {}, stopped = false}
        function event:StopPropagation() self.stopped = true end
        assert(self.listeners[kind], self.id .. " has no " .. kind .. " handler")(event)
    end
    return node
end

local ids = {
    "skynet-panel", "skynet-header", "skynet-tab", "skynet-identity",
    "skynet-columns", "skynet-title",
    "layout-done", "resize-grip",
    "online-panel", "online-list",
    "chat-panel", "chat-list", "chat-form", "chat-input",
    "sightings-panel", "sightings-list", "connection-status",
    "split-left", "split-right", "split-left-guide", "split-right-guide",
}
local nodes = {}
for _, id in ipairs(ids) do nodes[id] = element(id) end
nodes["chat-form"].style.display = "none"
local doc = {}
function doc:GetElementById(id) return nodes[id] end
function doc:Show() self.visible = true end
function doc:Hide() self.visible = false end
function doc:Close() self.closed = true end

local ctx = {dimensions = {x = 1024, y = 806}}
local entry_class = {}
function entry_class.new()
    local entry = {}
    function entry:bind() return true end
    function entry:open() return true end
    function entry:focus() return true end
    function entry:close() end
    function entry:set_diagnostics() end
    return entry
end
local saves = {}
local focus = {}
local scroll_timer = {}
function scroll_timer:SetTimeout(ms, callback)
    self.duration = ms
    self.callback = callback
    self.schedule_count = (self.schedule_count or 0) + 1
end
function scroll_timer:Kill()
    self.callback = nil
end

-- The follow manager makes three passes to allow RmlUi's layout to settle.
local function flush_follow()
    for _ = 1, 3 do
        local fn = scroll_timer.callback
        assert(type(fn) == "function")
        fn()
    end
end

local ui = UI.new({
    visible = true,
    text_entry_class = entry_class,
    chat_scroll_timer = scroll_timer,
    save_geometry = function(g)
        saves[#saves + 1] = g
    end,
    on_layout_focus = function(open)
        focus[#focus + 1] = open
        return true
    end,
    on_chat_focus = function() return true end,
})
-- One uniform navy background fills the columns and splitter gutters.
-- Only sighting text retains an opacity fade near expiration.
local rml_file = assert(io.open("panel.rml", "r"))
local rml_source = rml_file:read("*a")
rml_file:close()
local tab_css = assert(rml_source:match("#skynet%-identity%s*{([^}]+)}"))
local row_css = assert(rml_source:match("#skynet%-columns%s*{([^}]+)}"))
local section_css = assert(rml_source:match("%.section%s*{([^}]+)}"))
local chat_css = assert(rml_source:match("#chat%-list%s*{([^}]+)}"))
local scroller_css = assert(rml_source:match("%.scroller%s*{([^}]+)}"))
assert(scroller_css:find("overflow-y: auto;", 1, true))
assert(scroller_css:find("overflow-x: hidden;", 1, true))
assert(rml_source:find('id="online-list" class="scroller"', 1, true))
assert(rml_source:find('id="sightings-list" class="scroller"', 1, true))
-- RmlUi rgba alpha is 0..255: 166 is 65% opaque.
local shared_fill = "background-color: rgba(7, 20, 36, 166);"
assert(tab_css:find(shared_fill, 1, true))
assert(row_css:find(shared_fill, 1, true))
assert(section_css:find("background-color: transparent;", 1, true))
assert(section_css:find("padding: 8px 5px 3px;", 1, true))
assert(row_css:find("padding: 0px 3px 4px;", 1, true))
assert(tab_css:find("border-radius: 11px;", 1, true))
assert(tab_css:find("height: 22px;", 1, true))
assert(chat_css:find("overflow-y: scroll;", 1, true))
assert(not chat_css:find("position: relative;", 1, true))
assert(not rml_source:find("columns-top-fade", 1, true))
assert(not rml_source:find("columns-solid-fill", 1, true))
-- Only the 1px separator tips may use visual gradients; column and chat
-- backgrounds stay uniform, and sightings retain the sole text fade.
assert(not row_css:find("vertical-gradient", 1, true))
assert(not section_css:find("vertical-gradient", 1, true))
local guide_css = assert(rml_source:match("%.splitter%-guide%s*{([^}]+)}"))
local middle_css = assert(rml_source:match("%.splitter%-guide%-middle%s*{([^}]+)}"))
local tip_css = assert(rml_source:match("%.splitter%-guide%-end%s*{([^}]+)}"))
local top_css = assert(rml_source:match("%.splitter%-guide%-top%s*{([^}]+)}"))
local bottom_css = assert(rml_source:match("%.splitter%-guide%-bottom%s*{([^}]+)}"))
local edit_middle = assert(rml_source:match(
    "#skynet%-panel%.layout%-edit %.splitter%-guide%-middle%s*{([^}]+)}"))
local edit_top = assert(rml_source:match(
    "#skynet%-panel%.layout%-edit %.splitter%-guide%-top%s*{([^}]+)}"))
local edit_bottom = assert(rml_source:match(
    "#skynet%-panel%.layout%-edit %.splitter%-guide%-bottom%s*{([^}]+)}"))
assert(guide_css:find("width: 1px;", 1, true))
assert(guide_css:find("display: flex;", 1, true))
assert(guide_css:find("background-color: transparent;", 1, true))
assert(tip_css:find("height: 12px;", 1, true))
assert(middle_css:find("flex: 1 1 auto;", 1, true))
assert(middle_css:find("background-color: #4c7188;", 1, true))
assert(edit_middle:find("background-color: #75a9c8;", 1, true))
for _, spec in ipairs({
    {top_css, "rgba(76, 113, 136, 0) rgba(76, 113, 136, 255)"},
    {bottom_css, "rgba(76, 113, 136, 255) rgba(76, 113, 136, 0)"},
    {edit_top, "rgba(117, 169, 200, 0) rgba(117, 169, 200, 255)"},
    {edit_bottom, "rgba(117, 169, 200, 255) rgba(117, 169, 200, 0)"},
}) do
    assert(spec[1]:find("decorator: vertical-gradient(", 1, true))
    assert(spec[1]:find(spec[2], 1, true))
end
for _, class in ipairs({
    "splitter-guide-end splitter-guide-top",
    "splitter-guide-middle",
    "splitter-guide-end splitter-guide-bottom",
}) do
    local needle = 'class="' .. class .. '"'
    local count, cursor = 0, 1
    while true do
        local found = rml_source:find(needle, cursor, true)
        if not found then break end
        count = count + 1
        cursor = found + #needle
    end
    assert(count == 2, "missing separator segment: " .. class)
end
assert(not rml_source:find("mask-image", 1, true))
assert(not rml_source:find("chat-top-fade", 1, true))
assert(rml_source:find(".chat-row {", 1, true))
-- Validate all rgba() declarations to prevent accidental CSS-style alpha
-- values from returning in future visual changes.
for channels in rml_source:gmatch("rgba%(([^)]*)%)") do
    local alpha = channels:match(",%s*(%d+)%s*$")
    assert(alpha and tonumber(alpha) >= 0 and tonumber(alpha) <= 255,
        "RmlUi rgba() requires byte alpha (0..255): " .. channels)
end
local ui_file = assert(io.open("ui.lua", "r"))
local ui_source = ui_file:read("*a")
ui_file:close()
assert(ui_source:find('"rgba(23, 62, 83, 64)"', 1, true))
assert(ui_source:find("local SECTION_PADDING = 11", 1, true))
-- Color belongs to RCSS on the three line pieces, not a full-height
-- inline background on the parent that would hide the faded tips.
assert(not ui_source:find('guide.style["background-color"]', 1, true))
assert(rml_source:find("padding: 0px 3px 4px;", 1, true))
assert(rml_source:find('id="skynet-title">SKYNET:</span>', 1, true))

assert(ui:mount(ctx, doc))
-- Normal flight keeps its title + connection indicator, not the frame.
assert(nodes["skynet-header"].style.display == "flex")
assert(nodes["skynet-header"].style["border-bottom-width"] == "0px")
assert(nodes["connection-status"].inner_rml:find("DISCONNECTED", 1, true))
ui:set_connected(true)
assert(nodes["connection-status"].inner_rml:find(">CONNECTED<", 1, true))
ui:set_connected(false)
assert(nodes["connection-status"].inner_rml:find(">DISCONNECTED<", 1, true))
assert(nodes["skynet-panel"].style["border-width"] == "0px")
assert(nodes["skynet-panel"].style["background-color"] == "transparent")
assert(nodes["split-left"].style["border-width"] == "0px")
assert(nodes["split-right"].style["border-width"] == "0px")
assert(nodes["split-left-guide"].style["background-color"] == nil)
assert(nodes["split-right-guide"].style["background-color"] == nil)
-- No section labels: guides fill the entire height of the 8px splitters.
assert(nodes["split-left-guide"].style["margin-top"] == "0px")
assert(nodes["split-right-guide"].style["margin-top"] == "0px")
assert(nodes["split-left-guide"].style.height == "137px")
assert(nodes["split-right-guide"].style.height == "137px")
assert(nodes["split-left"].style.height == "137px")
assert(nodes["split-right"].style.height == "137px")
assert(nodes["skynet-panel"].classes["layout-edit"] == false)
assert(nodes["resize-grip"].style.display == "none")
-- Initial mount may schedule a follow-to-bottom. Flush it before checking.
assert(scroll_timer.duration == 40 and type(scroll_timer.callback) == "function")
flush_follow()
assert(ui.chat_scroll_pending == false)
assert(ui.chat_follow_bottom == true)

-- Regression: VO's Timer() is callable but may be a TABLE, not a function.
-- The old type(Timer) == "function" guard silently skipped all delayed
-- passes and only performed pass 0.
local original_timer = Timer
local callable_timer = {}
function callable_timer:SetTimeout(delay, callback)
    self.delay = delay
    self.callback = callback
end
Timer = setmetatable({}, {
    __call = function()
        return callable_timer
    end,
})
assert(type(Timer) == "table")
local probe = UI.new({ visible = true })
probe:schedule_chat_follow()
assert(probe.chat_scroll_pending)
assert(probe.chat_scroll_timer == callable_timer)
assert(callable_timer.delay == 40)
Timer = original_timer

-- A large replacement may report an old scroll height at pass 1. Later
-- passes must re-read it, and the numeric scroll must not move backward.
local delayed = nodes["chat-list"]
ui:follow_chat()
delayed.client_height = 80
delayed.scroll_height = 120
delayed.scroll_top = 0
local first_pass = scroll_timer.callback
first_pass()
assert(delayed.scroll_top == 40)
delayed.scroll_height = 900
local second_pass = scroll_timer.callback
second_pass()
assert(delayed.scroll_top == 820)
local third_pass = scroll_timer.callback
third_pass()
assert(delayed.scroll_top == 820)
assert(not ui.chat_scroll_pending)

-- A burst of new messages should scroll to the new measured scroll range,
-- not the old scroll_height before RmlUi's asynchronous relayout.
local list = nodes["chat-list"]
list.client_height = 80
list.scroll_height = 120
ui:add_chat("TEST", "first")
local scheduled = scroll_timer.schedule_count

-- A flood must rebuild the DOM ONCE, not 40 times.
local renders = 0
local previous_render = ui.render_chat
function ui:render_chat()
    renders = renders + 1
    return previous_render(self)
end
local messages = {}
for i = 2, 40 do
    messages[#messages + 1] = {name = "TEST", message = "flood " .. i}
end
ui:add_chat_batch(messages)
assert(renders == 1)
assert(scroll_timer.schedule_count == scheduled) -- one pending scroll
list.scroll_height = 520 -- simulate RmlUi relayout after DOM replacement
list.scroll_top = 0
list:dispatch("scroll") -- synthetic event from reflow is NOT user intent
assert(ui.chat_follow_bottom == true)
flush_follow()
assert(list.scroll_top == 440)
assert(ui.chat_scroll_pending == false)

-- Returning to the very top makes the oldest message completely readable.
list.scroll_top = 0
list:dispatch("mousescroll")
list:dispatch("scroll")
assert(ui.chat_follow_bottom == false)

-- User intentionally scrolls upward: do not snap back on new messages.
list.scroll_top = 100
list:dispatch("mousescroll") -- real mouse-wheel intent precedes scroll
list:dispatch("scroll")
assert(ui.chat_follow_bottom == false)
list.scroll_height = 560
ui:add_chat("TEST", "should stay at manually selected position")
assert(list.scroll_top == 100)
assert(ui.chat_scroll_pending == false)

-- Explicit jump-to-live (used by /skynetui demo flood) resumes following.
ui:follow_chat()
assert(ui.chat_follow_bottom == true)
list.scroll_height = 600
flush_follow()
assert(list.scroll_top == 520)

-- User scrolls up and returns to bottom: follow mode automatically re-engages.
list.scroll_top = 100
list:dispatch("mousescroll")
list:dispatch("scroll")
assert(ui.chat_follow_bottom == false)
list.scroll_top = 520
list:dispatch("mousescroll")
list:dispatch("scroll")
assert(ui.chat_follow_bottom == true)
ui:add_chat("TEST", "follow again")
list.scroll_height = 680
flush_follow()
assert(list.scroll_top == 600)

assert(ui.geometry.left == 190)
assert(ui.geometry.width == 644)
assert(ui.geometry.top == 635)
assert(ui.geometry.height == 166)
assert(ui.geometry.online == 180)
assert(ui.geometry.sightings == 160)
assert(ui.geometry.chat == 280)
-- No unnecessary class reapplication during periodic layout updates.
local class_updates = nodes["skynet-panel"].class_updates
ui:layout()
assert(nodes["skynet-panel"].class_updates == class_updates)
-- The 5px extra top inset comes from the lists, not the drag gutters.
assert(nodes["chat-list"].style.height == "126px")
assert(nodes["online-list"].style.height == "126px")
assert(nodes["sightings-list"].style.height == "126px")
assert(nodes["chat-input"].style.height == nil) -- static RML style
-- Independent scrollers must not be reset by periodic layout or age updates.
nodes["online-list"].scroll_top = 45
nodes["sightings-list"].scroll_top = 63
ui:layout()
ui:tick()
assert(nodes["online-list"].scroll_top == 45)
assert(nodes["sightings-list"].scroll_top == 63)

assert(ui:set_layout_editing(true))
assert(ui.layout_editing)
-- The title and connection status stay visible; layout mode adds an
-- outer border but NOT a rule beneath the header.
assert(nodes["skynet-header"].style.display == "flex")
assert(nodes["skynet-header"].style["border-bottom-width"] == "0px")
assert(nodes["skynet-panel"].style["border-width"] == "1px")
assert(nodes["skynet-panel"].style["background-color"] == "transparent")
assert(nodes["split-left"].style["border-width"] == "0px")
assert(nodes["split-right"].style["border-width"] == "0px")
assert(nodes["split-left-guide"].style["background-color"] == nil)
assert(nodes["split-right-guide"].style["background-color"] == nil)
assert(nodes["split-left-guide"].style["margin-top"] == "0px")
assert(nodes["split-right-guide"].style["margin-top"] == "0px")
assert(nodes["split-left-guide"].style.height == "135px")
assert(nodes["split-right-guide"].style.height == "135px")
assert(nodes["split-left"].style.height == "135px")
assert(nodes["split-right"].style.height == "135px")
assert(nodes["skynet-panel"].classes["layout-edit"] == true)
assert(nodes["chat-list"].style.height == "124px")
assert(nodes["online-list"].style.height == "124px")
assert(nodes["sightings-list"].style.height == "124px")
assert(nodes["layout-done"].style.display == "block")
assert(nodes["resize-grip"].style.display == "block")
assert(focus[#focus] == true)

nodes["skynet-header"]:dispatch("dragstart", {mouse_x = 500, mouse_y = 660})
nodes["skynet-header"]:dispatch("drag", {mouse_x = 530, mouse_y = 610})
nodes["skynet-header"]:dispatch("dragend")
assert(ui.geometry.left == 220)
assert(ui.geometry.top == 585)
assert(#saves == 1)

nodes["resize-grip"]:dispatch("dragstart", {mouse_x = 800, mouse_y = 700})
nodes["resize-grip"]:dispatch("drag", {mouse_x = 870, mouse_y = 750})
nodes["resize-grip"]:dispatch("dragend")
assert(ui.geometry.width == 714)
assert(ui.geometry.height == 216)

nodes["split-left"]:dispatch("dragstart", {mouse_x = 400, mouse_y = 660})
nodes["split-left"]:dispatch("drag", {mouse_x = 435, mouse_y = 660})
nodes["split-left"]:dispatch("dragend")
assert(ui.geometry.online == 215)
assert(ui.geometry.sightings == 160)

nodes["split-right"]:dispatch("dragstart", {mouse_x = 710, mouse_y = 660})
nodes["split-right"]:dispatch("drag", {mouse_x = 680, mouse_y = 660})
nodes["split-right"]:dispatch("dragend")
assert(ui.geometry.sightings == 190)
assert(ui.geometry.chat >= 160)
-- History viewport must shrink exactly by input row height, then recover.
local before = tonumber(nodes["chat-list"].style.height:match("^(%d+)px$"))
assert(ui:begin_chat())
assert(nodes["chat-form"].style.display == "block")
local opened = tonumber(nodes["chat-list"].style.height:match("^(%d+)px$"))
assert(opened == before - 29)
ui:add_chat("TEST", string.rep("long test message ", 20))
assert(nodes["chat-list"].inner_rml:find("TEST:", 1, true))
ui:cancel_chat("test")
assert(nodes["chat-form"].style.display == "none")
assert(tonumber(nodes["chat-list"].style.height:match("^(%d+)px$")) == before)

-- Clamp panel and column widths when the viewport changes.
ctx.dimensions.x = 650
ctx.dimensions.y = 400
ui:layout()
assert(ui.geometry.width <= 650)
assert(ui.geometry.height <= 400)
assert(ui.geometry.left + ui.geometry.width <= 650)
assert(ui.geometry.top + ui.geometry.height <= 400)
assert(ui.geometry.chat >= 160)
assert(ui.geometry.online >= 40)
assert(ui.geometry.sightings >= 105)

nodes["layout-done"]:dispatch("click")
assert(not ui.layout_editing)
assert(nodes["skynet-header"].style.display == "flex")
assert(nodes["skynet-header"].style["border-bottom-width"] == "0px")
assert(nodes["skynet-panel"].style["border-width"] == "0px")
assert(nodes["split-left"].style["border-width"] == "0px")
assert(nodes["split-right"].style["border-width"] == "0px")
assert(nodes["split-left-guide"].style["background-color"] == nil)
assert(nodes["split-right-guide"].style["background-color"] == nil)
assert(nodes["skynet-panel"].classes["layout-edit"] == false)
assert(nodes["layout-done"].style.display == "none")
assert(nodes["resize-grip"].style.display == "none")
assert(focus[#focus] == false)
assert(#saves == 5)

-- The online column used to stop at 95px. Let the user drag down to
-- 40px, without changing the minimum chat width or splitter hit target.
ctx.dimensions.x, ctx.dimensions.y = 1024, 806
assert(ui:set_layout_editing(true))
nodes["split-left"]:dispatch("dragstart", {mouse_x = 400, mouse_y = 660})
nodes["split-left"]:dispatch("drag", {mouse_x = 100, mouse_y = 660})
nodes["split-left"]:dispatch("dragend")
assert(ui.geometry.online == 40)
assert(ui.geometry.chat >= 160)
assert(saves[#saves].online == 40)
assert(ui:set_layout_editing(false))
-- A new UI instance should load all saved dimensions and positions.
local last_geometry = saves[#saves]
local restored_ui = UI.new({
    load_geometry = function() return last_geometry end,
})
restored_ui.context = ctx
assert(restored_ui:normalize_geometry())
for _, field in ipairs({"left", "top", "width", "height",
                         "online", "sightings"}) do
    assert(restored_ui.geometry[field] == last_geometry[field],
        "failed to restore " .. field)
end

assert(ui:reset_layout())
assert(ui.geometry.left >= 0)
assert(ui.geometry.top >= 0)
ui:unmount()
assert(doc.closed)

-- Rows must persist across 1-second ticks; the fade timer updates
-- only their style.opacity with fractional milliseconds from VO's game clock.
-- This avoids resetting the animation and preserves the age labels.
local fake_time, fine_ms = 5000, 1000000
local sighting_list = element("sightings-list")
local sighting_row = element("sighting-row-1")
local sighting_age = element("sighting-age-1")
local fade_timer = {schedule_count = 0}
function fade_timer:SetTimeout(ms, callback)
    self.duration = ms
    self.callback = callback
    self.schedule_count = self.schedule_count + 1
end
function fade_timer:Kill() self.callback = nil end
local sighting_ui = UI.new({
    clock = function() return fake_time end,
    sighting_time_ms = function() return fine_ms end,
    sighting_fade_timer = fade_timer,
    sighting_ttl = 60,
})
sighting_ui.document = {
    GetElementById = function(_, id)
        if id == "sightings-list" then return sighting_list end
        if id == "sighting-row-1" then return sighting_row end
        if id == "sighting-age-1" then return sighting_age end
    end,
}
sighting_ui:add_sighting("FadePilot", "Vult", "B-8", fake_time)
local original_rml = sighting_list.inner_rml
assert(original_rml:find('id="sighting-row-1"', 1, true))
assert(original_rml:find('id="sighting-age-1"', 1, true))
assert(original_rml:find('style="opacity: 1.0000;"', 1, true))
assert(fade_timer.schedule_count == 1)
assert(fade_timer.duration == 1000) -- Not 25fps before fading begins.

fake_time, fine_ms = 5030, 1030000
sighting_ui:tick()
assert(sighting_list.inner_rml == original_rml)
assert(sighting_age.inner_rml == "30s")
assert(sighting_row.style.opacity == nil) -- No repaint before 85% TTL.

fake_time, fine_ms = 5051, 1051000
sighting_ui:tick()
assert(sighting_list.inner_rml == original_rml)
assert(sighting_age.inner_rml == "51s")
assert(sighting_row.style.opacity == nil)

fake_time, fine_ms = 5054, 1054000
sighting_ui:tick()
assert(sighting_row.style.opacity == "0.7067")
assert(sighting_age.inner_rml == "54s")
assert(sighting_list.inner_rml == original_rml)
-- Timer pulses continue at 25 frames per second once fading begins.
local pulse = assert(fade_timer.callback)
fine_ms = 1054250
pulse()
assert(fade_timer.duration == 40)
assert(sighting_row.style.opacity == "0.6822")
assert(sighting_list.inner_rml == original_rml)
pulse = assert(fade_timer.callback)
fine_ms = 1054500
pulse()
assert(sighting_row.style.opacity == "0.6578")
assert(sighting_age.inner_rml == "54s") -- Timer leaves age label alone.

fake_time, fine_ms = 5059, 1059000
sighting_ui:tick()
assert(sighting_row.style.opacity == "0.2178")
assert(sighting_age.inner_rml == "59s")
fake_time, fine_ms = 5060, 1060000
sighting_ui:tick()
assert(sighting_ui.sightings.FadePilot == nil)
assert(sighting_list.inner_rml == "")

-- No chat opacity tracking, row measurements, or background gradient
-- should remain; chat text must be fully legible while scrolling.
assert(not ui_source:find("update_chat_fade", 1, true))
assert(not ui_source:find("chat_opacity_values", 1, true))
assert(not ui_source:find("chat-row-", 1, true))
assert(not ui_source:find("CHAT_TEXT_FADE", 1, true))
assert(not ui_source:find("COLUMN_BACKDROP_FADE", 1, true))
assert(not ui_source:find("columns-solid-fill", 1, true))
assert(ui_source:find([['<div class="chat-row">']], 1, true))

-- The flood command must inject sample sightings at multiple TTL phases,
-- without changing the 40-message batch or follow-to-bottom behavior.
local main_file = assert(io.open("main.lua", "r"))
local main_source = main_file:read("*a")
main_file:close()
assert(main_source:find("local phases = {0, 0.70, 0.85, 0.90, 0.95, 0.98}", 1, true))
assert(main_source:find('ui:add_sighting("Fade-" .. i', 1, true))
assert(main_source:find("ui:add_chat_batch(messages)", 1, true))
assert(main_source:find("ui:follow_chat(true)", 1, true))
-- Purpose-built in-game overflow test for both non-chat columns.
assert(main_source:find('args[2] == "scroll"', 1, true))
assert(main_source:find('args[2] == "scrollcheck"', 1, true))
assert(main_source:find('for i = 1, 32 do', 1, true))
assert(main_source:find('for i = 1, 24 do', 1, true))
assert(main_source:find('ui:replace_online(names)', 1, true))
assert(main_source:find('ui:add_sighting("TestSight-"', 1, true))
assert(main_source:find('tonumber(list.scroll_top)', 1, true))
assert(main_source:find('tonumber(list.client_height)', 1, true))
assert(main_source:find('tonumber(list.scroll_height)', 1, true))

-- Exercise actual preference serialization from main.lua without loading
-- the whole in-game entry point. VO exposes gkini.ReadString/WriteString.
local pref_begin = assert(main_source:find("local LAYOUT_SECTION =", 1, true))
local pref_end = assert(main_source:find("local ui = UI.new({", pref_begin, true))
local pref_code = main_source:sub(pref_begin, pref_end - 1)
    .. "\nreturn load_geometry, save_geometry"
local compile = loadstring or load
local load_pref, save_pref = assert(compile(pref_code))()
local old_gkini, old_game = gkini, Game
local persisted = nil
gkini = {
    ReadString = function(section, key, default)
        assert(section == "skynetui" and key == "layout_v1")
        return persisted or default
    end,
    WriteString = function(section, key, value)
        assert(section == "skynetui" and key == "layout_v1")
        persisted = value
        return true
    end,
}
Game = nil
assert(load_pref() == nil)
assert(save_pref(last_geometry))
assert(type(persisted) == "string")
local loaded = assert(load_pref())
for _, field in ipairs({"left", "top", "width", "height",
                         "online", "sightings"}) do
    assert(loaded[field] == last_geometry[field],
        "gkini round-trip failed: " .. field)
end
-- Migrate a layout stored using the previous Game preference API.
persisted = nil
Game = {
    GetPrefString = function(key, default)
        assert(key == "skynetui.layout.v1")
        return table.concat({"220", "585", "650", "216", "40", "190"}, ",")
    end,
}
local legacy = assert(load_pref())
assert(legacy.online == 40 and legacy.sightings == 190)
assert(save_pref(legacy))
assert(persisted == "220,585,650,216,40,190")
gkini, Game = old_gkini, old_game

print("PASS: online/sightings overflow tests, layout persistence, chat follow and sighting fade")
