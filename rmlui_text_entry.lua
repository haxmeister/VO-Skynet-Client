-- Reusable RmlUi text-entry controller. Does not depend on Skynet UI.
-- Handles text changes, Enter, Escape, and optional native name completion.
-- RmlUi's generic Element exposes attributes, but not SetSelection().
local Entry = {}

function Entry.new(options)
    options = options or {}
    local self = {}
    for name, method in pairs(Entry) do
        if type(method) == "function" and name ~= "new" then
            self[name] = method
        end
    end
    self.input = options.input
    self.form = options.form
    self.context = options.context
    self.completer = options.completer
    self.on_change = options.on_change
    self.on_submit = options.on_submit
    self.on_cancel = options.on_cancel
    self.diagnostics = options.diagnostics == true
    self.diagnostic_events = 0
    self.draft = ""
    self.is_open = false
    self.bound = false
    self.completion_serial = 0
    self.caret_timer = options.caret_timer or Timer()
    local keys = rmlui and rmlui.key_identifier
    self.keys = {
        tab = (keys and keys.KI_TAB) or 70,
        enter = (keys and keys.KI_RETURN) or 72,
        num_enter = (keys and keys.KI_NUMPADENTER) or 61,
        escape = (keys and keys.KI_ESCAPE) or 81,
        finish = (keys and keys.KI_END) or 88,
    }
    return self
end

local function stop(event)
    if event then pcall(function() event:StopPropagation() end) end
end

function Entry:trace(kind, value)
    if not self.diagnostics or not self.is_open then return end
    self.diagnostic_events = self.diagnostic_events + 1
    if self.diagnostic_events <= 35 then
        print("Skynet RmlUi input: event=" .. tostring(kind)
            .. (value == nil and "" or (" value=" .. tostring(value))))
    end
end

function Entry:set_diagnostics(enabled)
    self.diagnostics = enabled == true
    self.diagnostic_events = 0
end

function Entry:set_draft(value)
    self.draft = value
    if type(self.on_change) == "function" then
        self.on_change(value)
    end
end

function Entry:complete_name()
    if type(self.completer) ~= "function" then return end
    local draft = self.draft
    if draft == "" or not draft:match("%S$") then return end

    -- Try complete message first and then suffixes: supports names with spaces.
    -- Completion is end-of-draft only until RmlUi exposes caret position.
    local starts = {1}
    for i = 1, #draft - 1 do
        if draft:sub(i, i):match("[%s%p]")
            and not draft:sub(i + 1, i + 1):match("[%s%p]") then
            starts[#starts + 1] = i + 1
        end
    end

    local completed, start_at
    for _, first in ipairs(starts) do
        local fragment = draft:sub(first)
        if fragment ~= "" then
            local ok, name = pcall(self.completer, fragment)
            if not ok then
                print("Skynet UI: TabCompleteName failed: " .. tostring(name))
                return
            end
            if type(name) == "string" and name ~= "" then
                completed, start_at = name, first
                break
            end
        end
    end
    if not completed then
        print("Skynet UI: native name cache found no match")
        return
    end

    local updated = draft:sub(1, start_at - 1) .. completed
    if updated == draft then return end
    local ok, err = pcall(function()
        self.input:SetAttribute("value", updated)
    end)
    if not ok then
        print("Skynet UI: RmlUi input value write failed: " .. tostring(err))
        return
    end
    self:set_draft(updated)
    self.completion_serial = self.completion_serial + 1
    local serial = self.completion_serial

    -- Delay synthetic END until the original Tab callback has returned.
    -- The current VO client accepts ProcessKeyDown/Up on its RmlUi context.
    self.caret_timer:SetTimeout(1, function()
        if not self.is_open or self.draft ~= updated
            or self.completion_serial ~= serial then return end
        local ctx = self.context
        local ok, issue = pcall(function()
            self.input:Focus()
            ctx:ProcessKeyDown(self.keys.finish, 0)
            ctx:ProcessKeyUp(self.keys.finish, 0)
        end)
        if not ok then
            print("Skynet UI: caret-to-end failed: " .. tostring(issue))
        end
    end)
end

function Entry:bind()
    if self.bound then return true end
    if not self.input then return false, "missing RmlUi input element" end
    local input = self.input

    local ok, err = pcall(function()
        input:AddEventListener("change", function(event)
            if not self.is_open then return end
            local params = event and event.parameters
            local value = params and params.value
            if type(value) == "string" then
                self:set_draft(value)
                self:trace("change", #value)
            end
        end, false)

        for _, kind in ipairs({"focus", "blur", "click", "textinput"}) do
            local label = kind
            input:AddEventListener(label, function()
                self:trace(label)
            end, false)
        end

        local function on_key(event, phase)
            if not self.is_open then return end
            local params = event and event.parameters
            local key = params and params.key_identifier
            self:trace(phase, key)
            if key == self.keys.tab then
                stop(event)
                if phase == "keydown" then self:complete_name() end
            elseif key == self.keys.escape then
                stop(event)
                if type(self.on_cancel) == "function" then
                    self.on_cancel("escape-" .. phase)
                end
            elseif key == self.keys.enter or key == self.keys.num_enter then
                stop(event)
                if type(self.on_submit) == "function" then
                    self.on_submit(self.draft, "enter-" .. phase)
                end
            end
        end

        input:AddEventListener("keydown", function(event)
            on_key(event, "keydown")
        end, false)
        input:AddEventListener("keyup", function(event)
            on_key(event, "keyup")
        end, false)

        if self.form then
            self.form:AddEventListener("submit", function(event)
                if not self.is_open then return end
                stop(event)
                local params = event and event.parameters
                local message = params and params.message
                if type(message) ~= "string" then message = self.draft end
                if type(self.on_submit) == "function" then
                    self.on_submit(message, "form-submit")
                end
            end, false)
        end
    end)
    if not ok then
        return false, tostring(err)
    end
    self.bound = true
    return true
end

function Entry:open()
    if not self.bound then return false, "text entry not bound" end
    self.is_open = true
    self.diagnostic_events = 0
    self.completion_serial = self.completion_serial + 1
    self:set_draft("")
    local ok, err = pcall(function() self.input:SetAttribute("value", "") end)
    if not ok then
        self.is_open = false
        return false, tostring(err)
    end
    return true
end

function Entry:focus()
    local ok, err = pcall(function() self.input:Focus() end)
    if not ok then return false, tostring(err) end
    return true
end

function Entry:close()
    self.is_open = false
    self.completion_serial = self.completion_serial + 1
    self:set_draft("")
    pcall(function() self.input:SetAttribute("value", "") end)
    pcall(function() self.input:Blur() end)
end

return Entry
