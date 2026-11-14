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
    self.chat_listeners_bound = false
    self.on_chat_submit = options.on_chat_submit
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
    self:bind_chat_input()
    if self.visible then
        document:Show()
    else
        document:Hide()
    end
    return true
end

-- Absolute positioning needs a definite panel width in VO's RmlUi.
-- Compute it from the context width so chat can use all radar-safe space.
function UI:layout()
    local panel = self:node("skynet-panel")
    if not panel or not self.context then return end
    local dimensions = self.context.dimensions
    local screen_width = dimensions and tonumber(dimensions.x)
    if not screen_width or screen_width <= 0 then
        -- Do not invent a screen resolution when no dimensions are available.
        return
    end
    local left = tonumber(self.settings.radar_margin_left) or 190
    local right = tonumber(self.settings.radar_margin_right) or 190
    local panel_width = math.max(1, screen_width - left - right)
    if self.layout_width == screen_width and self.layout_left == left
        and self.layout_right == right then
        return
    end
    panel.style.left = tostring(left) .. "px"
    panel.style.right = "auto"
    panel.style.width = tostring(panel_width) .. "px"
    panel.style.bottom = tostring(self.settings.bottom_margin) .. "px"
    panel.style.height = tostring(self.settings.height) .. "px"
    self.layout_width = screen_width
    self.layout_left = left
    self.layout_right = right
    print("Skynet UI layout: viewport " .. screen_width .. "px; panel "
        .. panel_width .. "px; margins " .. left .. "/" .. right)
end

function UI:unmount()
    self:cancel_chat()
    if self.document then
        self.document:Close()
        self.document = nil
    end
    self.chat_listeners_bound = false
end

function UI:show()
    if self.visible then return end
    self.visible = true
    if self.document then self.document:Show() end
end

function UI:hide()
    self:cancel_chat()
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

-- The RML form handles Enter; keydown handles Escape and is also an Enter
-- fallback. Close before invoking a callback to prevent duplicate sends.
function UI:bind_chat_input()
    if self.chat_listeners_bound then return true end
    local form, input = self:node("chat-form"), self:node("chat-input")
    if not form or not input then return false end

    local key_ids = rmlui and rmlui.key_identifier
    local esc = (key_ids and key_ids.KI_ESCAPE) or 81
    local enter = (key_ids and key_ids.KI_RETURN) or 72
    local num_enter = (key_ids and key_ids.KI_NUMPADENTER) or 61

    local ok_form, form_err = pcall(function()
        form:AddEventListener("submit", function(event)
            self:submit_chat()
            if event then event:StopPropagation() end
        end, false)
    end)
    local ok_key, key_err = pcall(function()
        input:AddEventListener("keydown", function(event)
            if not self.chat_input_open then return end
            local key = event.parameters and event.parameters.key_identifier
            if key == esc then
                event:StopPropagation()
                self:cancel_chat()
            elseif key == enter or key == num_enter then
                event:StopPropagation()
                self:submit_chat()
            end
        end, false)
    end)
    self.chat_listeners_bound = ok_form and ok_key
    if not self.chat_listeners_bound then
        print("Skynet UI: chat input listeners unavailable: "
            .. tostring(form_err or key_err))
    end
    return self.chat_listeners_bound
end

function UI:begin_chat()
    if not self.visible or not self.chat_listeners_bound then return false end
    local form, input = self:node("chat-form"), self:node("chat-input")
    if not form or not input then return false end
    if self.chat_input_open then return true end
    self.chat_input_open = true
    form.style.display = "block"
    input.value = ""
    input:Focus()
    return true
end

function UI:cancel_chat()
    if not self.chat_input_open then return end
    self.chat_input_open = false
    local form, input = self:node("chat-form"), self:node("chat-input")
    if input then
        input.value = ""
        input:Blur()
    end
    if form then form.style.display = "none" end
end

function UI:submit_chat()
    if not self.chat_input_open then return false end
    local input = self:node("chat-input")
    local message = input and tostring(input.value or "") or ""
    message = message:match("^%s*(.-)%s*$")
    self:cancel_chat()
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

function UI:add_chat(name, message)
    if type(name) ~= "string" or type(message) ~= "string" then return end
    self.chat[#self.chat + 1] = { name = name, message = message }
    while #self.chat > self.settings.chat_limit do
        table.remove(self.chat, 1)
    end
    self:render_chat()
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

function UI:render_chat()
    local node = self:node("chat-list")
    if not node then return end
    local autoscroll = node.scroll_top + node.client_height >= node.scroll_height - 8
    local output = {}
    for _, entry in ipairs(self.chat) do
        output[#output + 1] = '<div class="chat-row">'
            .. label(entry.name .. ":", self:color_of(self.player_alliances[entry.name]), "pilot")
            .. ' ' .. escape(entry.message) .. '</div>'
    end
    node.inner_rml = table.concat(output)
    if autoscroll then node.scroll_top = node.scroll_height end
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
