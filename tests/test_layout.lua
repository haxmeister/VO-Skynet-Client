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
    "skynet-panel", "skynet-header", "skynet-columns", "skynet-title",
    "layout-done", "resize-grip",
    "online-panel", "online-list", "online-count",
    "chat-panel", "chat-list", "chat-form", "chat-input",
    "sightings-panel", "sightings-list", "connection-status",
    "split-left", "split-right",
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
assert(ui:mount(ctx, doc))
-- Initial mount may schedule a follow-to-bottom. Flush it before checking.
assert(scroll_timer.duration == 40 and type(scroll_timer.callback) == "function")
scroll_timer.callback()
assert(ui.chat_scroll_pending == false)
assert(ui.chat_follow_bottom == true)

-- A burst of new messages should scroll to the new measured scroll range,
-- not the old scroll_height before RmlUi's asynchronous relayout.
local list = nodes["chat-list"]
list.client_height = 80
list.scroll_height = 120
ui:add_chat("TEST", "first")
local scheduled = scroll_timer.schedule_count
for i = 2, 40 do
    ui:add_chat("TEST", "flood " .. i)
end
assert(scroll_timer.schedule_count == scheduled) -- one timer, not 40
list.scroll_height = 520 -- simulate RmlUi recalculating content after render
scroll_timer.callback()
assert(list.scroll_top == 440)
assert(ui.chat_scroll_pending == false)

-- User intentionally scrolls upward: do not snap back on new messages.
list.scroll_top = 100
list:dispatch("scroll")
assert(ui.chat_follow_bottom == false)
list.scroll_height = 560
ui:add_chat("TEST", "should stay at manually selected position")
assert(list.scroll_top == 100)
assert(ui.chat_scroll_pending == false)

-- User returns to bottom: follow mode automatically re-engages.
list.scroll_top = 480
list:dispatch("scroll")
assert(ui.chat_follow_bottom == true)
ui:add_chat("TEST", "follow again")
list.scroll_height = 680
scroll_timer.callback()
assert(list.scroll_top == 600)

assert(ui.geometry.left == 190)
assert(ui.geometry.width == 644)
assert(ui.geometry.top == 635)
assert(ui.geometry.height == 166)
assert(ui.geometry.online == 180)
assert(ui.geometry.sightings == 160)
assert(ui.geometry.chat == 280)
assert(nodes["chat-list"].style.height == "111px")
assert(nodes["chat-input"].style.height == nil) -- static RML style

assert(ui:set_layout_editing(true))
assert(ui.layout_editing)
assert(nodes["layout-done"].style.display == "block")
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
assert(ui.geometry.online >= 95)
assert(ui.geometry.sightings >= 105)

nodes["layout-done"]:dispatch("click")
assert(not ui.layout_editing)
assert(nodes["layout-done"].style.display == "none")
assert(focus[#focus] == false)
assert(#saves == 5)

assert(ui:reset_layout())
assert(ui.geometry.left >= 0)
assert(ui.geometry.top >= 0)
ui:unmount()
assert(doc.closed)

print("PASS: panel drag, corner resize, column splitters, chat input height, viewport clamp, DONE")
