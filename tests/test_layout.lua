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
    "skynet-tab-angle", "tab-angle-1", "tab-angle-2", "tab-angle-3",
    "tab-angle-4", "skynet-columns", "skynet-title",
    "layout-done", "resize-grip",
    "online-panel", "online-list",
    "chat-panel", "chat-list", "chat-form", "chat-input", "chat-top-fade",
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
-- A single tinted column-row background must fill the splitter gutters.
-- Do not also paint the .section children: that would double-stack alpha.
-- The SKYNET tab body and its stepped right tip must match that color.
local rml_file = assert(io.open("panel.rml", "r"))
local rml_source = rml_file:read("*a")
rml_file:close()
local tab_css = assert(rml_source:match("#skynet%-identity%s*{([^}]+)}"))
local row_css = assert(rml_source:match("#skynet%-columns%s*{([^}]+)}"))
local section_css = assert(rml_source:match("%.section%s*{([^}]+)}"))
local angle_css = assert(rml_source:match("%.tab%-angle%-step%s*{([^}]+)}"))
-- RmlUi rgba() alpha is 0..255; 170 is about 67% opacity.
local shared_fill = "background-color: rgba(7, 20, 36, 170);"
assert(tab_css:find(shared_fill, 1, true))
assert(row_css:find(shared_fill, 1, true))
assert(angle_css:find(shared_fill, 1, true))
assert(section_css:find("background-color: transparent;", 1, true))
assert(row_css:find("padding: 0px 3px 4px;", 1, true))
-- Confirm four explicitly rendered stair steps form a 16px chamfer.
for i = 1, 4 do
    local rule = assert(rml_source:match(
        "#tab%-angle%-" .. i .. "%s*{([^}]+)}"))
    assert(rule:find("width: " .. (i * 4) .. "px;", 1, true))
    assert(rml_source:find('id="tab-angle-' .. i
        .. '" class="tab-angle-step"', 1, true))
end
assert(angle_css:find("height: 6px;", 1, true))
assert(rml_source:find('id="skynet-tab"', 1, true))
-- A vertex-colored overlay works without a shader-based text mask.
-- It must not intercept the chat's wheel or drag events.
local fade_css = assert(rml_source:match("#chat%-top%-fade%s*{([^}]+)}"))
assert(fade_css:find("position: absolute;", 1, true))
assert(fade_css:find("pointer-events: none;", 1, true))
assert(fade_css:find("decorator: vertical-gradient(", 1, true))
assert(fade_css:find("rgba(7, 20, 36, 240)", 1, true))
assert(fade_css:find("rgba(7, 20, 36, 0)", 1, true))
assert(rml_source:find('id="chat-top-fade"', 1, true))
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
assert(nodes["chat-top-fade"].style.display == "none")
assert(nodes["chat-top-fade"].style.width == "259px")
assert(nodes["split-left"].style["border-width"] == "0px")
assert(nodes["split-right"].style["border-width"] == "0px")
assert(nodes["split-left-guide"].style["background-color"] == "#4c7188")
assert(nodes["split-right-guide"].style["background-color"] == "#4c7188")
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
assert(nodes["chat-top-fade"].style.display == "block")
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
assert(nodes["chat-top-fade"].style.display == "none")
flush_follow()
assert(nodes["chat-top-fade"].style.display == "block")
assert(list.scroll_top == 440)
assert(ui.chat_scroll_pending == false)

-- Returning to the very top makes the oldest message completely readable.
list.scroll_top = 0
list:dispatch("mousescroll")
list:dispatch("scroll")
assert(nodes["chat-top-fade"].style.display == "none")
assert(ui.chat_follow_bottom == false)

-- User intentionally scrolls upward: do not snap back on new messages.
list.scroll_top = 100
list:dispatch("mousescroll") -- real mouse-wheel intent precedes scroll
list:dispatch("scroll")
assert(ui.chat_follow_bottom == false)
assert(nodes["chat-top-fade"].style.display == "block")
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
assert(nodes["chat-list"].style.height == "131px")
assert(nodes["online-list"].style.height == "131px")
assert(nodes["sightings-list"].style.height == "131px")
assert(nodes["chat-input"].style.height == nil) -- static RML style

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
assert(nodes["split-left-guide"].style["background-color"] == "#75a9c8")
assert(nodes["split-right-guide"].style["background-color"] == "#75a9c8")
assert(nodes["split-left-guide"].style["margin-top"] == "0px")
assert(nodes["split-right-guide"].style["margin-top"] == "0px")
assert(nodes["split-left-guide"].style.height == "135px")
assert(nodes["split-right-guide"].style.height == "135px")
assert(nodes["split-left"].style.height == "135px")
assert(nodes["split-right"].style.height == "135px")
assert(nodes["skynet-panel"].classes["layout-edit"] == true)
assert(nodes["chat-list"].style.height == "129px")
assert(nodes["online-list"].style.height == "129px")
assert(nodes["sightings-list"].style.height == "129px")
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
assert(nodes["chat-top-fade"].style.width
    == tostring(ui.geometry.chat - 21) .. "px")

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
assert(ui.geometry.online >= 95)
assert(ui.geometry.sightings >= 105)

nodes["layout-done"]:dispatch("click")
assert(not ui.layout_editing)
assert(nodes["skynet-header"].style.display == "flex")
assert(nodes["skynet-header"].style["border-bottom-width"] == "0px")
assert(nodes["skynet-panel"].style["border-width"] == "0px")
assert(nodes["split-left"].style["border-width"] == "0px")
assert(nodes["split-right"].style["border-width"] == "0px")
assert(nodes["split-left-guide"].style["background-color"] == "#4c7188")
assert(nodes["split-right-guide"].style["background-color"] == "#4c7188")
assert(nodes["skynet-panel"].classes["layout-edit"] == false)
assert(nodes["layout-done"].style.display == "none")
assert(nodes["resize-grip"].style.display == "none")
assert(focus[#focus] == false)
assert(#saves == 5)

assert(ui:reset_layout())
assert(ui.geometry.left >= 0)
assert(ui.geometry.top >= 0)
ui:unmount()
assert(doc.closed)

print("PASS: 67%-opaque panel, shader-free chat top fade, scroll visibility, gutter fill, resize")
