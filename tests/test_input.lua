-- Standalone Lua tests for the reusable input helpers.
-- Run from the repository root: lua tests/test_input.lua
local timers = {}
function Timer()
    local timer = {}
    function timer:SetTimeout(ms, callback)
        self.duration = ms
        self.callback = callback
    end
    function timer:Kill()
        self.callback = nil
    end
    timers[#timers + 1] = timer
    return timer
end

rmlui = {
    key_identifier = {
        KI_TAB = 70, KI_RETURN = 72, KI_NUMPADENTER = 61,
        KI_ESCAPE = 81, KI_END = 88,
    },
}

local Input = dofile("rmlui_input.lua")
local hud = { active = "YES" }
local switched, canceled, mouse_hidden = {}, {}, 0
local router = Input.new({
    timeout_ms = 0,
    get_hud = function() return hud end,
    set_input_mode = function(enabled)
        switched[#switched + 1] = enabled
    end,
    hide_mouse = function() mouse_hidden = mouse_hidden + 1 end,
    new_timer = Timer,
})

assert(router:acquire("chat", function(reason)
    canceled[#canceled + 1] = "chat:" .. reason
end, 0))
assert(hud.active == "NO")
assert(switched[1] == false)
assert(router:acquire("chat", nil, 0))
assert(router:acquire("settings", function(reason)
    canceled[#canceled + 1] = "settings:" .. reason
end, 0))
assert(router.total == 3)
router:release("chat")
assert(hud.active == "NO" and router.total == 2)
router:release("settings")
assert(hud.active == "NO" and router.total == 1)
router:release("chat")
assert(hud.active == "YES" and router.total == 0)
assert(switched[2] == true and mouse_hidden == 1)

-- Inactivity timeout must restore input BEFORE running widget cancel hooks.
local callback_saw_hud
assert(router:acquire("chat", function(reason)
    callback_saw_hud = hud.active
    canceled[#canceled + 1] = reason
    router:release("chat") -- safe reentrant close
end, 12000))
assert(router.owners.chat.timer.duration == 12000)
local watchdog = router.owners.chat.timer.callback
assert(type(watchdog) == "function")
watchdog()
assert(callback_saw_hud == "YES")
assert(hud.active == "YES" and router.total == 0)
assert(canceled[#canceled] == "safety-timeout")
watchdog() -- stale timer must be harmless
assert(router.total == 0)

-- Input mode errors should roll back IUP ACTIVE without registering an owner.
local failing = Input.new({
    get_hud = function() return hud end,
    set_input_mode = function(enabled)
        if enabled == false then error("simulated failure") end
    end,
    new_timer = Timer,
})
local ok = failing:acquire("bad")
assert(not ok and hud.active == "YES" and failing.total == 0)

-- Minimal fake RmlUi element: dispatch real-style event parameters to listeners.
local function element()
    local node = { listeners = {}, attrs = {}, focused = false }
    function node:AddEventListener(kind, callback)
        self.listeners[kind] = callback
    end
    function node:SetAttribute(key, value)
        self.attrs[key] = value
    end
    function node:GetAttribute(key)
        return self.attrs[key]
    end
    function node:Focus() self.focused = true end
    function node:Blur() self.focused = false end
    function node:dispatch(kind, params)
        local event = { parameters = params or {}, stopped = false }
        function event:StopPropagation() self.stopped = true end
        local handler = self.listeners[kind]
        if handler then handler(event) end
        return event
    end
    return node
end

local Text = dofile("rmlui_text_entry.lua")
local input = element()
local form = element()
local keys_received, messages, canceled_entry, last_change = {}, {}, nil, ""
local context = {}
function context:ProcessKeyDown(key, mods)
    keys_received[#keys_received + 1] = {"down", key}
end
function context:ProcessKeyUp(key, mods)
    keys_received[#keys_received + 1] = {"up", key}
end

local entry = Text.new({
    input = input,
    form = form,
    context = context,
    completer = function(fragment)
        if fragment == "lost" then return "Lost Crow" end
        if fragment == "Dra" then return "Draugath" end
        return nil
    end,
    on_change = function(value) last_change = value end,
    on_submit = function(message, source)
        messages[#messages + 1] = {message, source}
    end,
    on_cancel = function(reason) canceled_entry = reason end,
    caret_timer = Timer(),
})
assert(entry:bind())
assert(entry:open())
assert(entry:focus())
input:dispatch("change", {value = "lost"})
assert(entry.draft == "lost" and last_change == "lost")
local tab = input:dispatch("keydown", {key_identifier = 70})
assert(tab.stopped)
assert(input:GetAttribute("value") == "Lost Crow")
assert(entry.draft == "Lost Crow")
assert(input:dispatch("keyup", {key_identifier = 70}).stopped)
entry.caret_timer.callback()
assert(keys_received[1][2] == 88 and keys_received[2][2] == 88)
input:dispatch("keydown", {key_identifier = 72})
assert(messages[1][1] == "Lost Crow")
assert(messages[1][2] == "enter-keydown")

-- Completion within a message, with a multi-word player name suffix.
input:dispatch("change", {value = "hello Dra"})
input:dispatch("keydown", {key_identifier = 70})
assert(entry.draft == "hello Draugath")
entry:close()
assert(not entry.is_open and input:GetAttribute("value") == "")
assert(not input.focused)
assert(entry:open())
input:dispatch("keydown", {key_identifier = 81})
assert(canceled_entry == "escape-keydown")

print("PASS: HUD input ownership, timeout recovery, name Tab completion, caret End, Enter/Escape")
