-- Standalone Skynet-style RmlUi HUD. No networking or VO custom events here.
local UI = {}
UI.__index = UI

local DEFAULTS = {
    radar_margin_left = 225,
    radar_margin_right = 225,
    bottom_margin = 5,
    height = 166,
    online_name_limit = 20,
    sighting_ttl = 60,
    chat_limit = 200,
    neutral_color = "#a8b9c8",
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
    local self = setmetatable({}, UI)
    self.settings = {}
    for key, value in pairs(DEFAULTS) do
        self.settings[key] = options[key] == nil and value or options[key]
    end
    self.clock = options.clock or os.time
    self.context = options.context
    self.document = nil
    self.visible = true
    self.connected = false
    self.online = {}
    self.chat = {}
    self.sightings = {}
    self.player_alliances = {}
    self.sector_owners = {}
    self.alliance_colors = {}
    return self
end

function UI:mount(context)
    if self.document then return true end
    context = context or self.context
    if not context then return false, "No RmlUi context" end
    local document = context:LoadDocument("panel.rml")
    if not document then return false, "Could not load panel.rml" end
    self.context = context
    self.document = document
    local panel = document:GetElementById("skynet-panel")
    if panel then
        panel.style.left = tostring(self.settings.radar_margin_left) .. "px"
        panel.style.right = tostring(self.settings.radar_margin_right) .. "px"
        panel.style.bottom = tostring(self.settings.bottom_margin) .. "px"
        panel.style.height = tostring(self.settings.height) .. "px"
    end
    self:render()
    document:Show()
    return true
end

function UI:unmount()
    if self.document then
        self.document:Close()
        self.document = nil
    end
end

function UI:show()
    self.visible = true
    if self.document then self.document:Show() end
end

function UI:hide()
    self.visible = false
    if self.document then self.document:Hide() end
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
