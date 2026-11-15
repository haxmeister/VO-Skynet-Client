-- Reusable RmlUi / native HUD input router for Vendetta Online.
-- This is deliberately independent of any particular RmlUi document or field.
-- Lua in VO's plugin sandbox has no setmetatable; copy methods to instances.
local Router = {}

function Router.new(options)
    options = options or {}
    local self = {}
    for name, method in pairs(Router) do
        if type(method) == "function" and name ~= "new" then
            self[name] = method
        end
    end

    self.get_hud = options.get_hud or function()
        return HUD and HUD.dlg
    end
    self.set_input_mode = options.set_input_mode or function(enabled)
        if not Game or type(Game.SetInputMode) ~= "function" then
            error("Game.SetInputMode unavailable")
        end
        Game.SetInputMode(enabled)
    end
    self.hide_mouse = options.hide_mouse or function()
        if gkinterface and type(gkinterface.HideMouse) == "function" then
            gkinterface.HideMouse()
        end
    end
    -- Never restore flight controls while the PDA/menu owns input.
    -- Default remains normal restoration for independent router users.
    self.should_restore_flight = options.should_restore_flight
    self.new_timer = options.new_timer or function() return Timer() end
    -- 0 disables the watchdog. Each owner can override it when acquiring.
    self.default_timeout_ms = options.timeout_ms == nil
        and 0 or options.timeout_ms
    self.owners = {}
    self.total = 0
    self.dialog = nil
    self.prior_active = nil
    self.mode_disabled = false
    return self
end

local function stop_timer(holder)
    if holder.timer then
        pcall(function() holder.timer:Kill() end)
        holder.timer = nil
    end
end

function Router:is_active(owner)
    if owner ~= nil then return self.owners[owner] ~= nil end
    return self.total > 0
end

function Router:_restore()
    -- Always release IUP before returning keyboard input to normal flight.
    local dlg = self.dialog
    local prior = self.prior_active
    local restore_mode = self.mode_disabled
    self.dialog = nil
    self.prior_active = nil
    self.mode_disabled = false

    if dlg then
        local ok, err = pcall(function() dlg.active = prior or "YES" end)
        if not ok then
            print("Skynet input: FAILED to restore HUD.active: " .. tostring(err))
        end
    end
    if restore_mode then
        local restore_flight = true
        if type(self.should_restore_flight) == "function" then
            local ok, allowed = pcall(self.should_restore_flight)
            -- An uncertain HUD state must not force flight-mode input
            -- over the PDA's own input handling.
            restore_flight = ok and allowed == true
        end
        if restore_flight then
            local ok, err = pcall(self.set_input_mode, true)
            if not ok then
                print("Skynet input: FAILED to restore flight mode: " .. tostring(err))
            else
                pcall(self.hide_mouse)
            end
        end
    end
end

-- acquire(owner, on_cancel, timeout_ms): owner is a stable string/token.
-- Multiple acquisitions by the SAME owner are reference-counted.
-- Multiple distinct owners can hold the shared input mode simultaneously.
-- A watchdog expiry cancels every owner so the HUD cannot remain inactive.
function Router:acquire(owner, on_cancel, timeout_ms)
    if owner == nil then return false, "owner is required" end
    local holder = self.owners[owner]
    if holder then
        holder.count = holder.count + 1
        self.total = self.total + 1
        return true
    end

    if self.total == 0 then
        local ok_hud, dlg = pcall(self.get_hud)
        if not ok_hud or not dlg then
            return false, "HUD.dlg is unavailable"
        end
        local ok_previous, previous = pcall(function() return dlg.active end)
        if not ok_previous then
            return false, "cannot read HUD.dlg.active"
        end
        local saved = previous or "YES"
        local ok_inactive, inactive_error = pcall(function() dlg.active = "NO" end)
        if not ok_inactive then
            return false, "cannot deactivate HUD: " .. tostring(inactive_error)
        end

        local ok_mode, mode_error = pcall(self.set_input_mode, false)
        if not ok_mode then
            -- The setter might have partially succeeded before raising.
            pcall(self.set_input_mode, true)
            pcall(function() dlg.active = saved end)
            return false, "cannot switch input mode: " .. tostring(mode_error)
        end
        self.dialog = dlg
        self.prior_active = saved
        self.mode_disabled = true
        print("Skynet input: HUD remains visible; IUP input disabled")
    end

    holder = { count = 1, on_cancel = on_cancel }
    self.owners[owner] = holder
    self.total = self.total + 1

    local duration = timeout_ms
    if duration == nil then duration = self.default_timeout_ms end
    if type(duration) == "number" and duration > 0 then
        local ok_timer, timer_or_error = pcall(self.new_timer)
        if ok_timer and timer_or_error then
            holder.timer = timer_or_error
            local ok_timeout, timeout_error = pcall(function()
                holder.timer:SetTimeout(duration, function()
                    if self.owners[owner] == holder then
                        print("Skynet input: safety timeout for " .. tostring(owner))
                        self:cancel_all("safety-timeout")
                    end
                end)
            end)
            if not ok_timeout then
                print("Skynet input: watchdog failed: " .. tostring(timeout_error))
                stop_timer(holder)
                -- Fail closed if a requested safety timeout cannot be armed.
                self:release(owner)
                return false, "cannot arm safety timeout"
            end
        else
            print("Skynet input: cannot create watchdog timer")
            self:release(owner)
            return false, "cannot create safety timer"
        end
    end
    return true
end

function Router:release(owner)
    local holder = self.owners[owner]
    if not holder then return true end
    holder.count = holder.count - 1
    self.total = self.total - 1
    if holder.count == 0 then
        stop_timer(holder)
        self.owners[owner] = nil
    end
    if self.total == 0 then self:_restore() end
    return true
end

function Router:cancel_all(reason)
    -- Clear the registry before invoking callbacks. Each owner may close its
    -- own widget, triggering a reentrant release() with no side effects.
    local callbacks = {}
    for owner, holder in pairs(self.owners) do
        stop_timer(holder)
        if type(holder.on_cancel) == "function" then
            callbacks[#callbacks + 1] = holder.on_cancel
        end
        self.owners[owner] = nil
    end
    self.total = 0
    self:_restore()
    for _, callback in ipairs(callbacks) do
        local ok, err = pcall(callback, reason or "input-canceled")
        if not ok then
            print("Skynet input: cancel callback failed: " .. tostring(err))
        end
    end
end

return Router
