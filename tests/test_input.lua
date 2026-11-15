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

-- Opening navigation/PDA while Skynet owns the input must not put
-- Game.SetInputMode(true) back into flight mode over the menu.
local menu_switched, menu_cancel = {}, nil
local ship_visible = true
local menu_router = Input.new({
    get_hud = function() return hud end,
    set_input_mode = function(enabled)
        menu_switched[#menu_switched + 1] = enabled
    end,
    should_restore_flight = function() return ship_visible end,
    new_timer = Timer,
})
assert(menu_router:acquire("layout", function(reason)
    menu_cancel = reason
end))
assert(hud.active == "NO" and menu_switched[1] == false)
ship_visible = false
menu_router:cancel_all("ship-hud-not-visible")
assert(hud.active == "YES" and menu_router.total == 0)
assert(menu_cancel == "ship-hud-not-visible")
assert(#menu_switched == 1) -- No flight-mode true while PDA is open.
ship_visible = true
assert(menu_router:acquire("chat"))
assert(menu_router:release("chat"))
assert(menu_switched[#menu_switched] == true) -- Normal flight restores.
assert(#menu_switched == 3)

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
-- Removed experimental tracing must leave just the four functional listeners.
local listener_count = 0
for _ in pairs(input.listeners) do listener_count = listener_count + 1 end
assert(listener_count == 3) -- change, keydown, keyup; submit is on the form.
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

-- Queued completion must not move focus after close/reopen, even if a new
-- draft has exactly the same text as the previous completion.
input:dispatch("change", {value = "lost"})
input:dispatch("keydown", {key_identifier = 70})
local stale_caret = entry.caret_timer.callback
entry:close()
entry:open()
input:dispatch("change", {value = "Lost Crow"})
local key_count = #keys_received
stale_caret()
assert(#keys_received == key_count)
input:dispatch("keydown", {key_identifier = 61})
assert(messages[#messages][1] == "Lost Crow")
assert(messages[#messages][2] == "enter-keydown")
form:dispatch("submit", {message = "form value"})
assert(messages[#messages][1] == "form value")
assert(messages[#messages][2] == "form-submit")
entry:close()

-- A requested watchdog must fail closed on construction or scheduling error.
for _, factory in ipairs({
    function() error("constructor failed") end,
    function() return {SetTimeout = function() error("schedule failed") end} end,
}) do
    local failed_router = Input.new({
        get_hud = function() return hud end,
        set_input_mode = function() end,
        new_timer = factory,
    })
    assert(not failed_router:acquire("chat", nil, 12000))
    assert(hud.active == "YES" and not failed_router:is_active())
end

print("PASS: HUD input ownership, timeout recovery, name Tab completion, caret End, Enter/Escape")
