-- Shared timer plumbing must preserve VO's deferred-layout behavior.
local UI = dofile("ui.lua")
local function timer()
    local t = {schedules = 0, killed = false}
    function t:SetTimeout(ms, callback)
        if self.fail then error("timer unavailable") end
        self.schedules = self.schedules + 1
        self.duration, self.callback = ms, callback
    end
    function t:Kill() self.killed = true; self.callback = nil end
    return t
end
local list = {scroll_top = 30, client_height = 80, scroll_height = 200}
local doc = {GetElementById = function() return list end,
    Hide = function() end, Close = function() end}
local function fresh(options)
    local ui = UI.new(options)
    ui.document = doc
    ui.sightings = {Pilot = {name = "Pilot", seen_at = 1000}}
    return ui
end

-- The constructor is still invoked as a callable, not type-checked.
local made = 0
Timer = setmetatable({}, {__call = function()
    made = made + 1
    return timer()
end})
local ui = fresh({clock = function() return 1000 end})
ui:schedule_chat_follow()
ui:schedule_chat_follow()
assert(made == 1 and ui.chat_scroll_timer.schedules == 1)
for _, delay in ipairs({40, 120, 240}) do
    assert(ui.chat_scroll_timer.duration == delay)
    ui.chat_scroll_timer.callback()
    assert(list.scroll_top == 120)
end
assert(not ui.chat_scroll_pending)
ui:follow_sightings_top()
ui:follow_sightings_top()
assert(made == 2 and ui.sighting_top_timer.schedules == 1)
assert(ui.sighting_top_timer.duration == 40 and list.scroll_top == 0)
ui:schedule_sighting_fade()
ui:schedule_sighting_fade()
assert(made == 3 and ui.sighting_fade_timer.schedules == 1)
assert(ui.sighting_fade_timer.duration == 1000)
local fade, top = ui.sighting_fade_timer.callback, ui.sighting_top_timer.callback
ui:hide()
assert(ui.sighting_fade_timer.killed and ui.sighting_top_timer.killed)
assert(not ui.sighting_fade_active and not ui.sighting_top_pending)
list.scroll_top = 25
fade(); top()
assert(list.scroll_top == 25 and not ui.sighting_fade_active)
ui:unmount()
assert(ui.chat_scroll_timer.killed and ui.document == nil)

-- Constructor failures use chat's immediate fallback, and keep sighting
-- schedulers idle so a later attempt can recover.
Timer = function() error("no timer") end
ui = fresh({clock = function() return 1000 end})
ui:schedule_chat_follow()
assert(list.scroll_top == 120 and not ui.chat_scroll_pending)
ui:follow_sightings_top()
assert(list.scroll_top == 0 and not ui.sighting_top_pending)
ui:schedule_sighting_fade()
assert(not ui.sighting_fade_active)

-- Injected timers are reused; failures during both initial and later
-- scheduling clear the pending flags without losing the cached timer.
local chat, sighting_top, sighting_fade = timer(), timer(), timer()
chat.fail, sighting_top.fail, sighting_fade.fail = true, true, true
ui = fresh({clock = function() return 1000 end, chat_scroll_timer = chat,
    sighting_top_timer = sighting_top, sighting_fade_timer = sighting_fade})
ui:schedule_chat_follow()
ui:follow_sightings_top()
ui:schedule_sighting_fade()
assert(not ui.chat_scroll_pending and not ui.sighting_top_pending)
assert(not ui.sighting_fade_active)
chat.fail, sighting_top.fail, sighting_fade.fail = false, false, false
ui:schedule_chat_follow()
ui:follow_sightings_top()
ui:schedule_sighting_fade()
assert(ui.chat_scroll_pending and ui.sighting_top_pending and ui.sighting_fade_active)
chat.fail, sighting_fade.fail = true, true
chat.callback()
sighting_fade.callback()
assert(not ui.chat_scroll_pending and not ui.sighting_fade_active)
assert(ui.chat_scroll_timer == chat and ui.sighting_fade_timer == sighting_fade)
ui:unmount()
assert(chat.killed and sighting_top.killed and sighting_fade.killed)
print("PASS: callable/cached timers, exact retries, failure recovery and cleanup")
