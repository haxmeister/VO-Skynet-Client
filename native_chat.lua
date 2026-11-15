-- Optional Skynet experiment: reparent VO's existing prompt bar.
-- Nothing moves automatically. Use /skynetui native probe|dock|restore.
-- The A-key command still uses VO's normal 'prompt' machinery.
local Native = {}
local state = {
    pending = 0, moved = false,
    control = nil, parent = nil, child_index = nil,
    overlay = nil, layer = nil, original = nil, last_rect = nil,
}

local function log(message)
    print("Skynet native chat: " .. tostring(message))
end

local function protected(fn)
    local ok, result = pcall(fn)
    if not ok then return nil, tostring(result) end
    return result
end

local function get_apis()
    local i = protected(function() return iup end)
    local hud = protected(function() return HUD end)
    if not i or not hud then
        return nil, nil, "IUP or HUD is not available"
    end
    return i, hud
end

local function get_control(hud)
    -- Historical FlamboyanceHUD path to the native chat-input row.
    -- Refuse to move anything unless it is still a direct child of
    -- HUD.chatframe[1][1][1], and its original slot can be recorded.
    local parent, control = protected(function()
        local row = hud.chatframe[1][1][1]
        return {row, row[2]}
    end)
    if not parent or not parent[1] or not parent[2] then
        return nil, nil, "historical HUD.chatframe path not found"
    end
    return parent[2], parent[1]
end

local function inspect(i, label, element)
    if not element then
        log(label .. ": missing")
        return
    end
    local class = protected(function() return i.GetClassName(element) end)
    local actual_parent = protected(function() return i.GetParent(element) end)
    local at = protected(function() return element.POSITION end)
    local size = protected(function() return element.RASTERSIZE end)
    local shown = protected(function() return element.VISIBLE end)
    local mapped = protected(function() return element.WID end)
    log(label .. ": class=" .. tostring(class) .. " position=" .. tostring(at)
        .. " size=" .. tostring(size) .. " visible=" .. tostring(shown)
        .. " wid=" .. tostring(mapped) .. " parent=" .. tostring(actual_parent))
end

local function rect_for(ui)
    local el = ui:node("chat-native-slot")
    if not el then return nil, "RML chat-native-slot missing" end
    local width = protected(function() return tonumber(el.offset_width) end)
    local height = protected(function() return tonumber(el.offset_height) end)
    if not width or not height or width < 100 or height < 12 then
        return nil, "RML slot has no measured size"
    end
    local x, y, cursor, hops = 0, 0, el, 0
    while cursor and hops < 16 do
        x = x + (protected(function() return tonumber(cursor.offset_left) end) or 0)
        y = y + (protected(function() return tonumber(cursor.offset_top) end) or 0)
        cursor = protected(function() return cursor.offset_parent end)
        hops = hops + 1
    end
    if hops >= 16 then return nil, "RML offset-parent chain is too deep" end
    if x < 0 or y < 0 then return nil, "RML slot position is invalid" end
    return {
        x = math.floor(x + 0.5), y = math.floor(y + 0.5),
        width = math.floor(width + 0.5),
        height = math.floor(height + 0.5)
    }
end

local function set_slot(ui, show)
    local el = ui:node("chat-native-slot")
    if el then el.style.display = show and "block" or "none" end
end

function Native.probe(ui)
    local i, hud, why = get_apis()
    if not i then log(why); return false end
    log("IUP functions: GetParent=" .. tostring(type(i.GetParent))
        .. " GetChildPos=" .. tostring(type(i.GetChildPos))
        .. " Reparent=" .. tostring(type(i.Reparent))
        .. " GetClassName=" .. tostring(type(i.GetClassName))
        .. " Map=" .. tostring(type(i.Map))
        .. " Refresh=" .. tostring(type(i.Refresh)))
    local control, parent, error = get_control(hud)
    if not control then log(error); return false end
    inspect(i, "chat input row [1][1][1][2]", control)
    inspect(i, "row parent [1][1][1]", parent)
    inspect(i, "HUD.pluginlayer", protected(function() return hud.pluginlayer end))
    local real_parent = protected(function() return i.GetParent(control) end)
    log("direct parent matches historical path: " .. tostring(real_parent == parent))
    local child_pos = protected(function() return i.GetChildPos(parent, control) end)
    log("current child index: " .. tostring(child_pos))
    local children = protected(function() return i.GetChildCount(control) end)
    log("row child count: " .. tostring(children))
    if type(children) == "number" and type(i.GetChild) == "function" then
        for n = 0, math.min(children - 1, 5) do
            inspect(i, "row child #" .. n, protected(function() return i.GetChild(control, n) end))
        end
    end
    if ui and ui.context then
        local viewport = protected(function() return ui.context.dimensions end)
        log("RmlUi viewport: " .. tostring(viewport and viewport.x)
            .. " x " .. tostring(viewport and viewport.y))
    end
    log("dock mode: " .. (state.moved and "ACTIVE" or "inactive"))
    return true
end

local function saved_attribute(element, attr)
    return protected(function() return element[attr] end)
end

local function apply_overlay(i, rect)
    local overlay = state.overlay
    overlay.POSITION = tostring(rect.x) .. "," .. tostring(rect.y)
    overlay.RASTERSIZE = tostring(rect.width) .. "x" .. tostring(rect.height)
    if state.control then
        state.control.CX = "0"
        state.control.CY = "0"
        state.control.RASTERSIZE = tostring(rect.width) .. "x" .. tostring(rect.height)
    end
    i.Refresh(overlay)
    state.last_rect = rect
end

function Native.restore(ui)
    state.pending = state.pending + 1
    if not state.moved then
        set_slot(ui, false)
        return true
    end
    local i = get_apis()
    if not i then
        log("Cannot restore: IUP is unavailable. ReloadInterface may recover the HUD.")
        return false
    end
    local ref = protected(function()
        return i.GetChild(state.parent, state.child_index)
    end)
    local ok, result = pcall(i.Reparent, state.control, state.parent, ref)
    if not ok or result ~= 0 then
        log("Restore failed (Reparent=" .. tostring(result)
            .. "): " .. tostring(ok and "IUP error" or result))
        log("DO NOT close/destroy the dock container. ReloadInterface to rebuild the HUD.")
        return false
    end
    local original = state.original
    for key, value in pairs(original) do
        pcall(function() i.SetAttribute(state.control, key, value) end)
    end
    state.moved = false
    state.control = nil
    if state.overlay then state.overlay.VISIBLE = "NO" end
    pcall(i.Refresh, state.parent)
    set_slot(ui, false)
    log("native input restored to original HUD parent")
    return true
end

function Native.realign(ui)
    if not state.moved then return end
    local rect = rect_for(ui)
    if not rect then return end
    local old = state.last_rect
    if old and rect.x == old.x and rect.y == old.y
        and rect.width == old.width and rect.height == old.height then
        return
    end
    local i = get_apis()
    if i then
        local ok, err = pcall(apply_overlay, i, rect)
        if not ok then log("alignment update failed: " .. tostring(err)) end
    end
end

function Native.dock(ui)
    if state.moved then log("already docked"); return true end
    if not ui.visible then log("show Skynet in flight first"); return false end
    local i, hud, why = get_apis()
    if not i then log(why); return false end
    if type(i.GetParent) ~= "function" or type(i.GetChildPos) ~= "function"
        or type(i.GetChild) ~= "function" or type(i.Reparent) ~= "function"
        or type(i.Map) ~= "function" or type(i.Refresh) ~= "function"
        or type(i.Append) ~= "function" or type(i.cbox) ~= "function" then
        log("required IUP layout functions are unavailable; no changes made")
        return false
    end
    local control, parent, why_control = get_control(hud)
    if not control then log(why_control); return false end
    local actual = protected(function() return i.GetParent(control) end)
    local pos = protected(function() return i.GetChildPos(parent, control) end)
    if actual ~= parent or type(pos) ~= "number" or pos < 0 then
        log("input hierarchy differs from the historical path; run probe first")
        return false
    end
    local layer = protected(function() return hud.pluginlayer end)
    if not layer then log("HUD.pluginlayer unavailable"); return false end

    state.pending = state.pending + 1
    local generation = state.pending
    set_slot(ui, true)
    local timer = Timer()
    -- RmlUi needs a layout pass after exposing the 22px input slot.
    timer:SetTimeout(100, function()
        if generation ~= state.pending or state.moved then return end
        if not ui.visible then set_slot(ui, false); return end
        local rect, geometry_error = rect_for(ui)
        if not rect then
            log(geometry_error)
            set_slot(ui, false)
            return
        end
        local overlay = state.overlay
        if not overlay then
            local ok_create, result = pcall(function()
                local box = i.cbox {}
                box.FLOATING = "YES"
                box.RASTERSIZE = tostring(rect.width) .. "x" .. tostring(rect.height)
                box.POSITION = tostring(rect.x) .. "," .. tostring(rect.y)
                box.VISIBLE = "NO"
                i.Append(layer, box)
                i.Map(box)
                return box
            end)
            if not ok_create then
                log("overlay creation failed: " .. tostring(result))
                set_slot(ui, false)
                return
            end
            overlay = result
            state.overlay = overlay
        end
        state.control = control
        state.parent = parent
        state.child_index = pos
        state.layer = layer
        state.original = {
            FLOATING = saved_attribute(control, "FLOATING"),
            POSITION = saved_attribute(control, "POSITION"),
            RASTERSIZE = saved_attribute(control, "RASTERSIZE"),
            CX = saved_attribute(control, "CX"),
            CY = saved_attribute(control, "CY"),
            EXPAND = saved_attribute(control, "EXPAND"),
        }
        local ok_move, result = pcall(i.Reparent, control, overlay, nil)
        if not ok_move or result ~= 0 then
            log("IUP refused to move input (code=" .. tostring(result) .. ")")
            -- Do not touch the native control unless the reparent succeeded.
            state.control = nil
            set_slot(ui, false)
            return
        end
        state.moved = true
        overlay.VISIBLE = "YES"
        local ok_place, place_err = pcall(apply_overlay, i, rect)
        if not ok_place then
            log("position failed; restoring: " .. tostring(place_err))
            Native.restore(ui)
            return
        end
        log("DOCKED at " .. rect.x .. "," .. rect.y
            .. " (" .. rect.width .. "x" .. rect.height .. "): press A to test")
        log("Use /skynetui native restore before changing other HUD plugins.")
    end)
    log("measuring Skynet input slot; preparing opt-in native dock")
    return true
end

return Native
