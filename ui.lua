-- Standalone Skynet-style RmlUi HUD. No networking or VO custom events here.
local UI = {}
-- Vendetta Online does not expose setmetatable to plugins.
-- UI instances receive the methods directly rather than via __index.

local DEFAULTS = {
    -- Reserve enough space for the radar widgets; values remain configurable.
    radar_margin_left = 190,
    radar_margin_right = 190,
    bottom_margin = 5,
    height = 166,
    min_width = 440,
    min_height = 145,
    online_width = 180,
    sightings_width = 160,
    online_name_limit = 20,
    sighting_ttl = 60,
    chat_limit = 200,
    neutral_color = "#a8b9c8",
    document_path = "panel.rml",
}

local function escape(value)
    return (tostring(value or "")
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
        :gsub("'", "&#39;"))
end

local function short_name(name, limit)
    name = tostring(name or "")
    if #name <= limit then return name end
    return name:sub(1, math.max(1, limit - 3)) .. "..."
end

local function label(text, color, class)
    return '<span class="' .. (class or "") .. '" style="color: ' .. color .. ';">'
        .. escape(text) .. '</span>'
end

function UI.new(options)
    options = options or {}
    local self = {}
    for name, method in pairs(UI) do
        if type(method) == "function" and name ~= "new" then
            self[name] = method
        end
    end
    self.settings = {}
    for key, value in pairs(DEFAULTS) do
        self.settings[key] = options[key] == nil and value or options[key]
    end
    self.clock = options.clock or os.time
    self.context = options.context
    self.document = nil
    self.visible = options.visible ~= false
    self.connected = false
    self.chat_input_open = false
    self.chat_draft = ""
    self.chat_listeners_bound = false
    self.chat_diagnostics = false
    self.on_chat_submit = options.on_chat_submit
    self.on_chat_focus = options.on_chat_focus
    self.text_entry_class = options.text_entry_class
    self.chat_entry = nil
    -- Follow fresh messages until the user scrolls away from the bottom.
    -- A delayed scroll is needed because RmlUi lays out inner_rml after it
    -- has been assigned, so scroll_height may still be the OLD value.
    self.chat_follow_bottom = true
    self.chat_scroll_pending = false
    self.chat_scroll_applying = false
    -- RmlUi sends "scroll" events for programmatic scroll and relayout too.
    -- Only genuine mouse input may disable following new chat messages.
    self.chat_scroll_user_input = false
    self.chat_scroll_mouse_down = false
    self.chat_scroll_trace = false
    self.chat_scroll_timer = options.chat_scroll_timer
    self.load_geometry = options.load_geometry
    self.save_geometry = options.save_geometry
    self.on_layout_focus = options.on_layout_focus
    self.layout_editing = false
    self.layout_chrome_applied = nil
    self.layout_controls_bound = false
    self.geometry = nil
    self.drag_state = nil
    self.online = {}
    self.chat = {}
    self.sightings = {}
    self.player_alliances = {}
    self.sector_owners = {}
    self.alliance_colors = {}
    return self
end

function UI:mount(context, document)
    if self.document then return true end
    context = context or self.context
    if not context then return false, "No RmlUi context" end
    -- VO resolves LoadDocument() paths relative to the calling plugin during
    -- startup. A caller can supply a document loaded from its main.lua here.
    document = document or context:LoadDocument(self.settings.document_path)
    if not document then return false, "Could not load RML document: " .. tostring(self.settings.document_path) end
    self.context = context
    self.document = document
    self:layout()
    self:render()
    if not self:bind_chat_input() then
        return false, "chat input initialization failed"
    end
    if not self:bind_layout_controls() then
        return false, "window controls initialization failed"
    end
    self:bind_chat_scroll()
    if self.visible then
        document:Show()
    else
        document:Hide()
    end
    return true
end

-- Geometry is in actual context pixels, not percentages. Explicit heights
-- keep RmlUi's flex children from letting chat overflow the panel bottom.
local HEADER_HEIGHT = 25
local COLUMN_PADDING = 4
local SECTION_PADDING = 6
local INPUT_HEIGHT = 29
local SPLITTER_WIDTH = 8
local HORIZONTAL_PADDING = 8 -- border + inner columns padding
local MIN_CHAT_WIDTH = 160
local MIN_ONLINE_WIDTH = 95
local MIN_SIGHTINGS_WIDTH = 105

local function clamp(n, low, high)
    if high < low then return low end
    return math.max(low, math.min(n, high))
end

local function px(n)
    return tostring(math.floor(n + 0.5)) .. "px"
end

function UI:viewport()
    if not self.context then return nil end
    local d = self.context.dimensions
    local w = d and tonumber(d.x)
    local h = d and tonumber(d.y)
    if not w or not h or w <= 0 or h <= 0 then return nil end
    return math.floor(w), math.floor(h)
end

function UI:default_geometry(screen_width, screen_height)
    local left = tonumber(self.settings.radar_margin_left) or 190
    local right = tonumber(self.settings.radar_margin_right) or 190
    local w = screen_width - left - right
    local minw = math.min(screen_width, tonumber(self.settings.min_width) or 440)
    w = clamp(w, minw, screen_width)
    local h = clamp(tonumber(self.settings.height) or 166,
        math.min(screen_height, tonumber(self.settings.min_height) or 145),
        screen_height)
    return {
        left = left,
        top = screen_height - (tonumber(self.settings.bottom_margin) or 5) - h,
        width = w,
        height = h,
        online = tonumber(self.settings.online_width) or 180,
        sightings = tonumber(self.settings.sightings_width) or 160,
    }
end

function UI:normalize_geometry()
    local w, h = self:viewport()
    if not w then return false end
    if not self.geometry then
        if type(self.load_geometry) == "function" then
            local ok, value = pcall(self.load_geometry)
            if ok and type(value) == "table" then
                self.geometry = value
            end
        end
        if not self.geometry then
            self.geometry = self:default_geometry(w, h)
        end
    end
    local g = self.geometry
    local def = self:default_geometry(w, h)
    g.width = clamp(tonumber(g.width) or def.width,
        math.min(w, tonumber(self.settings.min_width) or 440), w)
    g.height = clamp(tonumber(g.height) or def.height,
        math.min(h, tonumber(self.settings.min_height) or 145), h)
    g.left = clamp(tonumber(g.left) or def.left, 0, w - g.width)
    g.top = clamp(tonumber(g.top) or def.top, 0, h - g.height)

    local available = math.max(1,
        g.width - HORIZONTAL_PADDING - (2 * SPLITTER_WIDTH))
    local min_online = math.min(MIN_ONLINE_WIDTH, math.floor(available / 4))
    local min_sightings = math.min(MIN_SIGHTINGS_WIDTH, math.floor(available / 4))
    local min_chat = math.min(MIN_CHAT_WIDTH,
        math.max(1, available - min_online - min_sightings))
    g.online = clamp(tonumber(g.online) or def.online,
        min_online, available - min_sightings - min_chat)
    g.sightings = clamp(tonumber(g.sightings) or def.sightings,
        min_sightings, available - g.online - min_chat)
    g.chat = math.max(1, available - g.online - g.sightings)
    return true
end

function UI:layout()
    local panel = self:node("skynet-panel")
    if not panel or not self:normalize_geometry() then return end
    local g = self.geometry

    panel.style.left = px(g.left)
    panel.style.top = px(g.top)
    panel.style.right = "auto"
    panel.style.bottom = "auto"
    panel.style.width = px(g.width)
    panel.style.height = px(g.height)

    -- Window chrome is shown only during /skynetui layout. The outer
    -- shell stays clear; each content section and the compact SKYNET status
    -- tab share one stronger translucent fill defined in panel.rml.
    -- RmlUi's style proxy uses RCSS property names for hyphenated keys.
    local editing = self.layout_editing
    if self.layout_chrome_applied ~= editing then
        -- The parent class selectively paints RmlUi's generated scrollbar
        -- elements, without disabling their scroll behavior or changing
        -- the width reserved for the bars. Class changes happen only on
        -- mode transitions, not during the normal one-second UI refresh.
        local ok, err = pcall(function()
            panel:SetClass("layout-edit", editing)
        end)
        if not ok then
            -- Older embedded builds may not expose SetClass, but we know
            -- SetAttribute is present in the VO RmlUi Lua binding.
            ok, err = pcall(function()
                panel:SetAttribute("class", editing and "layout-edit" or "")
            end)
        end
        if ok then
            self.layout_chrome_applied = editing
        else
            print("Skynet UI: cannot toggle layout scrollbar style: "
                .. tostring(err))
        end
    end
    local header = self:node("skynet-header")
    -- Keep SKYNET and its actual connection state visible while flying.
    -- The title row has no divider line, even while editing the layout.
    if header then
        header.style.display = "flex"
        header.style["border-bottom-width"] = "0px"
    end
    -- Do not double-tint the tab and columns with an underlying panel
    -- fill. The outer frame remains useful in layout mode.
    panel.style["background-color"] = "transparent"
    panel.style["border-width"] = editing and "1px" or "0px"
    panel.style["border-color"] = editing and "#3f7799" or "transparent"

    -- The borderless title row is present in both modes. Only the outer
    -- window border (visible in layout mode) changes the content height.
    -- The geometry still describes the same outer window rectangle.
    local header_height = HEADER_HEIGHT
    local border_allowance = editing and 2 or 0

    -- Give both the column row and each list its own *definite* height.
    -- The chat form occupies a fixed row only while input is open.
    local columns_height = math.max(1, g.height - header_height - border_allowance)
    local section_height = math.max(1, columns_height - COLUMN_PADDING)
    -- No column headings; reclaim their previous 18px for the lists.
    local common_list_height = math.max(1,
        section_height - SECTION_PADDING)
    local chat_list_height = math.max(1,
        common_list_height - (self.chat_input_open and INPUT_HEIGHT or 0))

    local row = self:node("skynet-columns")
    if row then row.style.height = px(columns_height) end
    local online = self:node("online-panel")
    if online then
        online.style.width = px(g.online)
        online.style.height = px(section_height)
    end
    local chat = self:node("chat-panel")
    if chat then
        chat.style.width = px(g.chat)
        chat.style.height = px(section_height)
    end
    local sightings = self:node("sightings-panel")
    if sightings then
        sightings.style.width = px(g.sightings)
        sightings.style.height = px(section_height)
    end
    for _, id in ipairs({"split-left", "split-right"}) do
        local node = self:node(id)
        if node then
            node.style.height = px(section_height)
            -- The full 8px gutter still receives drag events. Its border
            -- stays off so there can never be two separating lines.
            node.style["border-width"] = "0px"
            node.style["background-color"] = editing
                and "rgba(23, 62, 83, 64)" or "transparent"
        end
        local guide = self:node(id .. "-guide")
        if guide then
            -- With column titles removed, the single-pixel guide fills
            -- the entire drag gutter and never shortens its hit target.
            guide.style["margin-top"] = "0px"
            guide.style.height = px(section_height)
            guide.style["background-color"] =
                editing and "#75a9c8" or "#4c7188"
        end
    end

    for _, id in ipairs({"online-list", "sightings-list"}) do
        local node = self:node(id)
        if node then node.style.height = px(common_list_height) end
    end
    local list = self:node("chat-list")
    if list then list.style.height = px(chat_list_height) end

    local done = self:node("layout-done")
    if done then
        done.style.display = self.layout_editing and "block" or "none"
    end
    local grip = self:node("resize-grip")
    if grip then
        grip.style.display = self.layout_editing and "block" or "none"
    end
    if self.layout_last_viewport_width ~= self:viewport() then
        -- Only log changes when the viewport width changes; not every drag.
        print("Skynet UI: panel geometry " .. math.floor(g.width)
            .. "x" .. math.floor(g.height) .. " at "
            .. math.floor(g.left) .. "," .. math.floor(g.top))
        self.layout_last_viewport_width = self:viewport()
    end
end

function UI:save_current_geometry()
    if type(self.save_geometry) ~= "function" or not self.geometry then
        return
    end
    local g = self.geometry
    local ok, err = pcall(self.save_geometry, {
        left = math.floor(g.left + 0.5),
        top = math.floor(g.top + 0.5),
        width = math.floor(g.width + 0.5),
        height = math.floor(g.height + 0.5),
        online = math.floor(g.online + 0.5),
        sightings = math.floor(g.sightings + 0.5),
    })
    if not ok then
        print("Skynet UI: unable to save layout: " .. tostring(err))
    end
end

function UI:set_layout_focus_handler(handler)
    if handler ~= nil and type(handler) ~= "function" then return false end
    self.on_layout_focus = handler
    return true
end

function UI:set_layout_editing(enabled)
    enabled = enabled == true
    if self.layout_editing == enabled then return true end
    if enabled then
        if not self.visible or not self.document or not self.layout_controls_bound then
            return false
        end
        if type(self.on_layout_focus) == "function" then
            local ok, accepted = pcall(self.on_layout_focus, true)
            if not ok or accepted == false then
                print("Skynet UI: layout mouse focus unavailable")
                return false
            end
        end
        self.layout_editing = true
        print("Skynet UI: layout edit mode; drag title, dividers or lower-right corner")
    else
        self.layout_editing = false
        self.drag_state = nil
        self:save_current_geometry()
        if type(self.on_layout_focus) == "function" then
            local ok, err = pcall(self.on_layout_focus, false)
            if not ok then
                print("Skynet UI: layout focus restore error: " .. tostring(err))
            end
        end
        print("Skynet UI: layout editing complete")
    end
    self:layout()
    return true
end

function UI:reset_layout()
    local w, h = self:viewport()
    if not w then return false end
    self.drag_state = nil
    self.geometry = self:default_geometry(w, h)
    self:layout()
    self:save_current_geometry()
    print("Skynet UI: default layout restored")
    return true
end

function UI:bind_layout_controls()
    if self.layout_controls_bound then return true end
    local handles = {
        ["skynet-header"] = "move",
        ["resize-grip"] = "resize",
        ["split-left"] = "split-left",
        ["split-right"] = "split-right",
    }
    local registered = 0
    for element_id, action in pairs(handles) do
        local node = self:node(element_id)
        if not node then
            print("Skynet UI: missing layout drag handle " .. element_id)
            return false
        end
        local kind = action
        local ok, err = pcall(function()
            node:AddEventListener("dragstart", function(event)
                if not self.layout_editing then return end
                local p = event and event.parameters
                local x = p and tonumber(p.mouse_x)
                local y = p and tonumber(p.mouse_y)
                if not x or not y or not self.geometry then
                    print("Skynet UI: dragstart missing mouse coordinates (" .. kind .. ")")
                    return
                end
                local g = self.geometry
                self.drag_state = {
                    kind = kind, x = x, y = y,
                    left = g.left, top = g.top,
                    width = g.width, height = g.height,
                    online = g.online, sightings = g.sightings,
                }
            end, false)

            node:AddEventListener("drag", function(event)
                if not self.layout_editing or not self.drag_state
                    or self.drag_state.kind ~= kind then return end
                local p = event and event.parameters
                local x = p and tonumber(p.mouse_x)
                local y = p and tonumber(p.mouse_y)
                if not x or not y then return end
                local drag = self.drag_state
                local g = self.geometry
                local dx, dy = x - drag.x, y - drag.y
                local sw, sh = self:viewport()
                if not sw then return end

                if kind == "move" then
                    g.left = clamp(drag.left + dx, 0, sw - g.width)
                    g.top = clamp(drag.top + dy, 0, sh - g.height)
                elseif kind == "resize" then
                    g.width = clamp(drag.width + dx,
                        math.min(sw, self.settings.min_width), sw - g.left)
                    g.height = clamp(drag.height + dy,
                        math.min(sh, self.settings.min_height), sh - g.top)
                elseif kind == "split-left" then
                    g.online = drag.online + dx
                elseif kind == "split-right" then
                    g.sightings = drag.sightings - dx
                end
                self:layout()
            end, false)

            node:AddEventListener("dragend", function()
                if not self.drag_state or self.drag_state.kind ~= kind then
                    return
                end
                self.drag_state = nil
                self:save_current_geometry()
            end, false)
        end)
        if not ok then
            print("Skynet UI: cannot bind " .. kind .. " drag: " .. tostring(err))
            return false
        end
        registered = registered + 1
    end

    local done = self:node("layout-done")
    if not done then return false end
    local ok, err = pcall(function()
        done:AddEventListener("click", function(event)
            if not self.layout_editing then return end
            if event then pcall(function() event:StopPropagation() end) end
            self:set_layout_editing(false)
        end, false)
    end)
    if not ok then
        print("Skynet UI: cannot bind DONE control: " .. tostring(err))
        return false
    end
    self.layout_controls_bound = registered == 4
    return self.layout_controls_bound
end

function UI:unmount()
    self:cancel_chat()
    self:set_layout_editing(false)
    if self.document then
        self.document:Close()
        self.document = nil
    end
    self.chat_listeners_bound = false
    self.chat_entry = nil
    self.chat_scroll_pending = false
    self.chat_scroll_user_input = false
    self.chat_scroll_mouse_down = false
    self.chat_scroll_trace = false
    if self.chat_scroll_timer then
        pcall(function() self.chat_scroll_timer:Kill() end)
    end
    self.chat_follow_bottom = true
    self.chat_scroll_bound = false
    self.layout_chrome_applied = nil
    self.layout_controls_bound = false
end

function UI:show()
    if self.visible then return end
    self.visible = true
    if self.document then self.document:Show() end
    if self.chat_follow_bottom then self:schedule_chat_follow() end
end

function UI:hide()
    self:cancel_chat()
    if self.layout_editing then self:set_layout_editing(false) end
    if not self.visible then return end
    self.visible = false
    if self.document then self.document:Hide() end
end

-- The UI only collects a message; an integrator decides how to deliver it.
function UI:set_chat_submit_handler(handler)
    if handler ~= nil and type(handler) ~= "function" then return false end
    self.on_chat_submit = handler
    return true
end

-- Kept separate from rendering; the VO integrator controls engine input mode.
function UI:set_chat_focus_handler(handler)
    if handler ~= nil and type(handler) ~= "function" then return false end
    self.on_chat_focus = handler
    return true
end

function UI:notify_chat_focus(open)
    if type(self.on_chat_focus) ~= "function" then return true end
    local ok, result = pcall(self.on_chat_focus, open)
    if not ok then
        print("Skynet UI: chat focus handler failed: " .. tostring(result))
        return false
    end
    return result ~= false
end

function UI:set_chat_diagnostics(enabled)
    self.chat_diagnostics = not not enabled
    if self.chat_entry then
        self.chat_entry:set_diagnostics(self.chat_diagnostics)
    end
end

-- Chat delegates low-level RmlUi events to the reusable text-entry module.
-- Other components can use the same class with their own callbacks.
function UI:bind_chat_input()
    if self.chat_listeners_bound then return true end
    local form = self:node("chat-form")
    local input = self:node("chat-input")
    local klass = self.text_entry_class
    if not form or not input then
        print("Skynet UI: RmlUi chat form or input is missing")
        return false
    end
    if not klass or type(klass.new) ~= "function" then
        print("Skynet UI: rmlui_text_entry.lua was not provided to UI.new")
        return false
    end

    local entry = klass.new({
        form = form,
        input = input,
        context = self.context,
        completer = TabCompleteName,
        diagnostics = self.chat_diagnostics,
        on_change = function(value)
            self.chat_draft = value
        end,
        on_submit = function(message, source)
            self:submit_chat(source, message)
        end,
        on_cancel = function(reason)
            self:cancel_chat(reason)
        end,
    })
    local ok, reason = entry:bind()
    if not ok then
        print("Skynet UI: cannot bind chat input: " .. tostring(reason))
        return false
    end
    self.chat_entry = entry
    self.chat_listeners_bound = true
    return true
end

function UI:begin_chat()
    if not self.visible or not self.chat_listeners_bound
        or not self.chat_entry then return false end
    local form = self:node("chat-form")
    if not form then return false end
    if self.chat_input_open then return true end

    self.chat_input_open = true
    self.chat_draft = ""
    form.style.display = "block"
    self:layout() -- shrink the history viewport before taking input focus
    self:schedule_chat_follow()

    local opened, open_err = self.chat_entry:open()
    if not opened then
        print("Skynet UI: cannot prepare text input: " .. tostring(open_err))
        self:cancel_chat("failed-open")
        return false
    end
    if not self:notify_chat_focus(true) then
        self:cancel_chat("failed-handoff")
        return false
    end
    local focused, focus_err = self.chat_entry:focus()
    if not focused then
        print("Skynet UI: cannot focus RmlUi chat input: " .. tostring(focus_err))
        self:cancel_chat("failed-focus")
        return false
    end
    return true
end

function UI:cancel_chat(reason)
    if not self.chat_input_open then return end
    self.chat_input_open = false
    self.chat_draft = ""
    print("Skynet UI: closing RmlUi chat: " .. tostring(reason or "cancel"))
    if self.chat_entry then self.chat_entry:close() end
    local form = self:node("chat-form")
    if form then form.style.display = "none" end
    self:layout() -- restore the history viewport height after closing input
    self:schedule_chat_follow()
    -- Always restore native HUD interaction, even when focus failed to open.
    self:notify_chat_focus(false)
end

-- Accept text from either an RmlUi input or VO's native chat prompt.
function UI:deliver_chat(message)
    if type(message) ~= "string" then return false end
    message = message:match("^%s*(.-)%s*$")
    if message == "" then return false end
    if type(self.on_chat_submit) == "function" then
        local ok, err = pcall(self.on_chat_submit, message)
        if not ok then
            print("Skynet UI: chat submit handler failed: " .. tostring(err))
            return false
        end
    end
    return true
end

function UI:submit_chat(source, submitted)
    if not self.chat_input_open then return false end
    local message = type(submitted) == "string" and submitted or self.chat_draft
    print("Skynet UI: RmlUi submit via " .. tostring(source or "unknown")
        .. "; text length=" .. #message)
    -- Deliver before restoring the IUP HUD, so its show event can't interrupt
    -- the local RmlUi render. Cancel still runs if delivery fails.
    local delivered = self:deliver_chat(message)
    self:cancel_chat("submitted-" .. tostring(source or "unknown"))
    print("Skynet UI: RmlUi message delivered=" .. tostring(delivered))
    return delivered
end

function UI:set_connected(connected)
    self.connected = not not connected
    self:render_status()
end

function UI:set_alliance_color(alliance, hex)
    -- Colors are only accepted as #RRGGBB to keep generated RML safe.
    if type(hex) ~= "string" or not hex:match("^#%x%x%x%x%x%x$") then return false end
    self.alliance_colors[alliance] = hex
    self:render()
    return true
end

function UI:set_player_alliance(name, alliance)
    self.player_alliances[name] = alliance
    self:render()
end

function UI:set_sector_owner(sector, alliance)
    self.sector_owners[sector] = alliance -- nil means unowned or unknown.
    self:render_sightings()
end

function UI:color_of(alliance)
    return self.alliance_colors[alliance] or self.settings.neutral_color
end

function UI:replace_online(names)
    self.online = {}
    for _, name in ipairs(names or {}) do
        if type(name) == "string" then
            self.online[name] = true
        end
    end
    self:render_online()
end

-- Add a batch with one RmlUi rebuild. Rebuilding the whole chat DOM for
-- every message in a 40-message flood can trigger scroll/layout events
-- between inserts and falsely make a followed feed appear manually scrolled.
function UI:add_chat_batch(entries)
    if type(entries) ~= "table" then return end
    local dirty = false
    for _, entry in ipairs(entries) do
        local name, message = entry.name, entry.message
        if type(name) == "string" and type(message) == "string" then
            self.chat[#self.chat + 1] = { name = name, message = message }
            dirty = true
        end
    end
    if not dirty then return end
    while #self.chat > self.settings.chat_limit do
        table.remove(self.chat, 1)
    end
    self:render_chat()
end

function UI:add_chat(name, message)
    if type(name) ~= "string" or type(message) ~= "string" then return end
    self:add_chat_batch({{name = name, message = message}})
end

-- This is useful for explicitly requested jump-to-live actions, including
-- /skynetui demo flood. Ordinary incoming messages respect manual scroll-up.
function UI:follow_chat(trace)
    self.chat_follow_bottom = true
    -- Enable a small amount of measurements for the flood test only.
    -- No chat text or player names are logged.
    if trace then self.chat_scroll_trace = true end
    self:schedule_chat_follow()
end

function UI:add_sighting(name, ship_type, sector, seen_at)
    if type(name) ~= "string" or name == "" then return end
    local when = tonumber(seen_at) or self.clock()
    local old = self.sightings[name]
    if old and when < old.seen_at then return end
    self.sightings[name] = {
        name = name, ship_type = tostring(ship_type or "?"),
        sector = tostring(sector or "?"), seen_at = when,
    }
    self:render_sightings()
end

function UI:tick()
    self:layout() -- Adjust if the game's viewport resolution changes.
    local now = self.clock()
    local dirty = false
    for name, sighting in pairs(self.sightings) do
        if now - sighting.seen_at >= self.settings.sighting_ttl then
            self.sightings[name] = nil
            dirty = true
        end
    end
    -- The age labels change even when no sightings expire.
    if dirty or self.document then self:render_sightings() end
end

function UI:node(id)
    return self.document and self.document:GetElementById(id)
end

function UI:render_status()
    local node = self:node("connection-status")
    if node then
        node.inner_rml = self.connected
            and '<span class="status-on">CONNECTED</span>'
            or '<span class="status-off">DISCONNECTED</span>'
    end
end

function UI:render_online()
    local items = {}
    for name in pairs(self.online) do items[#items + 1] = name end
    table.sort(items, function(a,b)
        local al, bl = a:lower(), b:lower()
        return al == bl and a < b or al < bl
    end)
    local node = self:node("online-list")
    if node then
        local output = {}
        for _, name in ipairs(items) do
            output[#output + 1] = '<div class="online-row">'
                .. label(short_name(name, self.settings.online_name_limit),
                    self:color_of(self.player_alliances[name]), "pilot") .. '</div>'
        end
        node.inner_rml = table.concat(output)
    end
    local count = self:node("online-count")
    if count then count.inner_rml = tostring(#items) end
end

-- RmlUi may report the previous scroll range immediately after inner_rml.
-- Use the measured scrollable bottom, and repeat after later layout frames.
-- Unlike ScrollIntoView(false), this never moves backwards to the location
-- of an out-of-date element in the current VO RmlUi binding.
function UI:scroll_chat_to_bottom(pass)
    local node = self:node("chat-list")
    if not node or not self.chat_follow_bottom then return end

    local function measures()
        local ok, top, client, height = pcall(function()
            return tonumber(node.scroll_top), tonumber(node.client_height),
                tonumber(node.scroll_height)
        end)
        if not ok then return "unavailable" end
        return tostring(top) .. "/" .. tostring(client) .. "/" .. tostring(height)
    end

    local before = self.chat_scroll_trace and measures() or nil
    local target
    self.chat_scroll_applying = true
    local ok, err = pcall(function()
        local height = tonumber(node.scroll_height) or 0
        local client = tonumber(node.client_height) or 0
        target = math.max(0, height - client)
        node.scroll_top = target
    end)
    self.chat_scroll_applying = false

    if self.chat_scroll_trace then
        print("Skynet UI: chat follow pass=" .. tostring(pass)
            .. " target=" .. tostring(target)
            .. " write=" .. tostring(ok)
            .. " before=" .. tostring(before)
            .. " after=" .. measures()
            .. (not ok and (" error=" .. tostring(err)) or ""))
    end
end

function UI:schedule_chat_follow()
    if not self.chat_follow_bottom or self.chat_scroll_pending then return end
    if not self.chat_scroll_timer then
        -- In VO, Timer() may be a callable table, not a Lua function.
        -- type(Timer) == "function" incorrectly rejected the working
        -- constructor and forced every flood follow into pass 0.
        local made, timer_or_err = pcall(function() return Timer() end)
        if not made or not timer_or_err then
            print("Skynet UI: cannot create chat follow timer: "
                .. tostring(timer_or_err))
            self:scroll_chat_to_bottom(0)
            self.chat_scroll_trace = false
            return
        end
        self.chat_scroll_timer = timer_or_err
    end
    self.chat_scroll_pending = true

    local function pass(number)
        if not self.document or not self.visible or not self.chat_follow_bottom then
            self.chat_scroll_pending = false
            self.chat_scroll_trace = false
            return
        end

        self:scroll_chat_to_bottom(number)
        if number >= 3 then
            self.chat_scroll_pending = false
            self.chat_scroll_trace = false
            return
        end

        -- Spread retries across actual render frames instead of assuming
        -- a single 40ms callback always sees finished RmlUi layout.
        local delay = number == 1 and 120 or 240
        local ok, err = pcall(function()
            self.chat_scroll_timer:SetTimeout(delay, function()
                pass(number + 1)
            end)
        end)
        if not ok then
            self.chat_scroll_pending = false
            self.chat_scroll_trace = false
            print("Skynet UI: failed to reschedule chat follow: "
                .. tostring(err))
        end
    end

    local ok, err = pcall(function()
        self.chat_scroll_timer:SetTimeout(40, function()
            pass(1)
        end)
    end)
    if not ok then
        self.chat_scroll_pending = false
        print("Skynet UI: cannot schedule chat follow: " .. tostring(err))
        self:scroll_chat_to_bottom(0)
        self.chat_scroll_trace = false
    end
end

-- A user who scrolls up should be able to read earlier chat undisturbed.
-- Scrolling to the bottom again re-enables follow mode.
function UI:bind_chat_scroll()
    if self.chat_scroll_bound then return true end
    local node = self:node("chat-list")
    if not node then return false end
    local ok, err = pcall(function()
        -- RmlUi emits scroll for *both* real user scrolling and a DOM
        -- replacement changing the scroll range. Wheel / mouse interaction
        -- identifies the intentional kind of scroll.
        node:AddEventListener("mousescroll", function()
            self.chat_scroll_user_input = true
        end, false)
        node:AddEventListener("mousedown", function()
            self.chat_scroll_mouse_down = true
        end, false)
        node:AddEventListener("mouseup", function()
            self.chat_scroll_mouse_down = false
        end, false)
        node:AddEventListener("scroll", function()
            if self.chat_scroll_applying then return end
            if not self.chat_scroll_user_input
                and not self.chat_scroll_mouse_down then
                return -- layout scroll, not user input
            end
            self.chat_scroll_user_input = false
            local top = tonumber(node.scroll_top) or 0
            local visible = tonumber(node.client_height) or 0
            local extent = tonumber(node.scroll_height) or 0
            self.chat_follow_bottom = top + visible >= extent - 8
        end, false)
    end)
    if not ok then
        print("Skynet UI: cannot bind chat scroll listener: " .. tostring(err))
        return false
    end
    self.chat_scroll_bound = true
    return true
end

function UI:render_chat()
    local node = self:node("chat-list")
    if not node then return end
    local output = {}
    for _, entry in ipairs(self.chat) do
        output[#output + 1] = '<div class="chat-row">'
            .. label(entry.name .. ":", self:color_of(self.player_alliances[entry.name]), "pilot")
            .. ' ' .. escape(entry.message) .. '</div>'
    end
    if self.chat_follow_bottom then
        -- Arm the pending follow BEFORE replacing the DOM, since a relayout
        -- can generate a "scroll" event synchronously during inner_rml.
        self:schedule_chat_follow()
    end
    node.inner_rml = table.concat(output)
end

function UI:render_sightings()
    local items, now = {}, self.clock()
    for _, sighting in pairs(self.sightings) do
        if now - sighting.seen_at < self.settings.sighting_ttl then
            items[#items + 1] = sighting
        end
    end
    table.sort(items, function(a,b)
        if a.seen_at ~= b.seen_at then return a.seen_at > b.seen_at end
        return a.name < b.name
    end)
    local output = {}
    for _, s in ipairs(items) do
        local age = math.max(0, math.floor(now - s.seen_at))
        output[#output + 1] = '<div class="sighting-row">'
            .. label(s.name, self:color_of(self.player_alliances[s.name]), "sighting-pilot")
            .. '<span class="sighting-ship">' .. escape(s.ship_type) .. '</span>'
            .. label(s.sector, self:color_of(self.sector_owners[s.sector]), "sighting-sector")
            .. '<span class="sighting-age">' .. age .. 's</span></div>'
    end
    local node = self:node("sightings-list")
    if node then node.inner_rml = table.concat(output) end
end

function UI:render()
    self:render_status()
    self:render_online()
    self:render_chat()
    self:render_sightings()
end

return UI
