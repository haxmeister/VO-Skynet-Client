-- Local demonstration data and developer commands; no network delivery.
local Demo = {}

function Demo.seed(ui)
    -- Simulated roster and chat. This plugin does not send any network messages.
    local now = os.time()
    ui:set_alliance_color("itani", "#65c6ff")
    ui:set_alliance_color("serco", "#ff8282")
    ui:set_alliance_color("uit", "#80e5a6")
    ui:set_player_alliance("Falcon", "itani")
    ui:set_player_alliance("Raven", "serco")
    ui:set_player_alliance("Wraith", "uit")
    ui:set_player_alliance("Specter", "itani")
    ui:set_player_alliance("Drake", "serco")
    ui:set_sector_owner("Odia M-14", "serco")
    ui:set_sector_owner("Sedina B-8", "itani")
    ui:replace_online({ "Wraith", "Falcon", "Raven", "Specter" })
    ui:add_chat("Falcon", "Anyone near Sedina?")
    ui:add_chat("Raven", "Two hostiles spotted.")
    ui:add_chat("Wraith", "Heading there now.")
    ui:add_chat("Falcon", "I'll hold position.")
    ui:add_sighting("Drake", "Vult", "Odia M-14", now - 8)
    ui:add_sighting("Specter", "Prom", "Sedina B-8", now - 17)
    ui:set_connected(true) -- Demonstration indicator, not a real connection.
    ui:set_chat_submit_handler(function(message)
        ui:add_chat("LOCAL TEST", message)
    end)
end

function Demo.run(ui, mode)
    if mode == "flood" then
        local messages = {}
        for i = 1, 40 do
            messages[#messages + 1] = {
                name = "DEMO",
                message = "Scrolling test message " .. i
                    .. ": this intentionally long chat entry should wrap within"
                    .. " the panel and never push the input below the viewport.",
            }
        end
        -- One chat DOM update and one follow scroll, not 40 rebuilds.
        ui:add_chat_batch(messages)
        ui:follow_chat(true) -- Log actual scroll metrics on 3 passes.

        -- Sample the entire lifespan, especially the last 15%:
        -- three fully visible rows followed by three fading rows.
        -- Refreshes continue aging/removing these test sightings.
        local seen_now = os.time()
        local ttl = math.max(1, tonumber(ui.settings.sighting_ttl) or 60)
        local phases = {0, 0.70, 0.85, 0.90, 0.95, 0.98}
        for i, phase in ipairs(phases) do
            local age = math.floor(ttl * phase)
            ui:add_sighting("Fade-" .. i, "Vult", "B-8", seen_now - age)
        end
        print("Skynet UI: added 40 chat messages and 6 aging sightings;"
            .. " following newest chat")
    elseif mode == "scroll" then
        -- Force both non-chat columns to overflow without changing the
        -- player's saved geometry. The demo sightings naturally expire
        -- on the usual 60-second schedule; rerun to refresh them.
        local names = {}
        for i = 1, 32 do
            names[i] = "TestPilot-" .. string.format("%02d", i)
        end
        ui:replace_online(names)
        local seen_now = os.time()
        for i = 1, 24 do
            ui:add_sighting("TestSight-" .. string.format("%02d", i),
                "Vult", "B-8", seen_now)
        end
        print("Skynet UI: scroll test loaded 32 online pilots and"
            .. " 24 fresh sightings (expire after usual TTL)."
            .. " Open /skynetui layout for mouse wheel and scrollbars;"
            .. " use /skynetui demo scrollcheck to see scroll positions.")
    elseif mode == "scrollcheck" then
        -- Query real RmlUi scroll metrics rather than inferring
        -- scrolling from the number of generated demo entries.
        for _, spec in ipairs({
            {"online", "online-list"},
            {"sightings", "sightings-list"},
        }) do
            local list = ui:node(spec[2])
            if list then
                local ok, top, client, extent = pcall(function()
                    return tonumber(list.scroll_top),
                        tonumber(list.client_height),
                        tonumber(list.scroll_height)
                end)
                if ok and top and client and extent then
                    print("Skynet UI: " .. spec[1]
                        .. " scroll_top=" .. tostring(top)
                        .. " viewport=" .. tostring(client)
                        .. " content=" .. tostring(extent)
                        .. " max=" .. tostring(math.max(0,
                            extent - client)))
                else
                    print("Skynet UI: " .. spec[1]
                        .. " scroll metrics unavailable")
                end
            end
        end
    else
        ui:add_chat("Raven", "New demo message.")
        ui:add_sighting("Drake", "Vult", "Odia M-14")
    end
end

return Demo
