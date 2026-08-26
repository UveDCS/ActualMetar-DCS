-- window.lua — "ACTUAL METAR" panel. A single floating Window, same
-- single-instance pattern as dcs_sms_me.about / prefab_manager. Only uses
-- widgets confirmed in dcs-sms's own code: Window, Static, EditBox, Button
-- (see about.lua / mass_edit_forms/*.lua in that project).

local dcs_maps = require("actual_metar.dcs_maps")
local mission_datetime = require("actual_metar.mission_datetime")
local mission_apply = require("actual_metar.mission_apply")
local metar_fetch = require("actual_metar.metar_fetch")
local ticker = require("actual_metar.ticker")
local custom_maps = require("actual_metar.custom_maps")

local M = {}
local W = nil
local widgets = {}
local state = {
    date_mode = "actual",
    time_mode = "map",
    weather = nil,
    job = nil,
    map_zone = { std_offset_h = 0, rule = "none" },
}

-- Assigned when the window is built (wire_radio_group for the Time group).
-- Lets us force the time mode from code (e.g. jump from "Map" to "Local"
-- if a custom ICAO with no known real timezone is chosen).
local select_time_mode = nil

local function log_err(msg)
    pcall(function() _G.log.write("actual_metar", _G.log.ERROR or 1, tostring(msg)) end)
end

local function make_label(text, skin_fn)
    local Static = require("Static")
    local Skin = require("Skin")
    local lbl = Static.new()
    pcall(function()
        local s = (skin_fn and skin_fn()) or (Skin.staticSkin_ME and Skin.staticSkin_ME())
        if s then lbl:setSkin(s) end
    end)
    if lbl.setText then lbl:setText(text) end
    return lbl
end

local function set_text(widget, text)
    if widget and widget.setText then pcall(widget.setText, widget, text) end
end

local function set_bounds(widget, x, y, w, h)
    if widget and widget.setBounds then pcall(widget.setBounds, widget, x, y, w, h) end
end

local function get_text(widget)
    if widget and widget.getText then
        local ok, t = pcall(widget.getText, widget)
        if ok then return t end
    end
    return ""
end

local function make_button(text, on_click)
    local Button = require("Button")
    local Skin = require("Skin")
    local btn = Button.new()
    pcall(function() if Skin.buttonSkin_ME then btn:setSkin(Skin.buttonSkin_ME()) end end)
    set_text(btn, text)
    if btn.addChangeCallback then
        btn:addChangeCallback(function()
            local ok, err = pcall(on_click)
            if not ok then
                log_err("button '" .. tostring(text) .. "' failed: " .. tostring(err))
                set_text(widgets.apply_status_lbl, "Internal error (see dcs.log, actual_metar): " .. tostring(err))
            end
        end)
    end
    return btn
end

-- CheckBox: native class confirmed in dcs-sms's real source (mass_edit.lua,
-- trigger_finder.lua): CheckBox.new(), cb:setState(bool), cb:getState(),
-- cb:addChangeCallback(function(box) ... end).
local function make_checkbox(initial_state, on_change)
    local ok_c, CheckBox = pcall(require, "CheckBox")
    if not (ok_c and CheckBox and CheckBox.new) then return nil end
    local ok, cb = pcall(CheckBox.new)
    if not ok or not cb then return nil end
    pcall(function()
        local Skin = require("Skin")
        if Skin.checkBoxSkin_MENew and cb.setSkin then cb:setSkin(Skin.checkBoxSkin_MENew()) end
    end)
    pcall(cb.setState, cb, initial_state == true)
    if cb.addChangeCallback and on_change then
        cb:addChangeCallback(function(box)
            local ok2, err = pcall(function()
                local checked = box and box.getState and box:getState() == true
                on_change(checked)
            end)
            if not ok2 then
                log_err("checkbox failed: " .. tostring(err))
            end
        end)
    end
    return cb
end

-- Group of CheckBoxes with radio-button behavior (only one checked at a
-- time). "boxes" is {mode_key -> checkbox_widget}. Checking one unchecks
-- the rest and calls on_select(mode_key). Returns select_key(key) so the
-- selection can be forced from code (not just from a user click) -
-- sync_map_combo uses it to jump from "Map" to "Local" when needed.
local function wire_radio_group(boxes, on_select)
    local function select_key(key)
        for other_key, other_cb in pairs(boxes) do
            if other_cb then pcall(other_cb.setState, other_cb, other_key == key) end
        end
        on_select(key)
    end

    for key, cb in pairs(boxes) do
        if cb and cb.addChangeCallback then
            cb:addChangeCallback(function(box)
                local ok, err = pcall(function()
                    local checked = box and box.getState and box:getState() == true
                    if not checked then
                        -- the only active one can't be unchecked: re-check it
                        pcall(cb.setState, cb, true)
                        return
                    end
                    select_key(key)
                end)
                if not ok then log_err("radio group failed: " .. tostring(err)) end
            end)
        end
    end

    return select_key
end

-- List of maps (DCS_MAPS + EXTRA + the user's custom ICAOs), index-aligned
-- with the items inserted into the combo, so we can resolve "current
-- selection -> entry". is_builtin tells built-in entries (can't be
-- removed) apart from hand-added ones.
local MAP_ENTRIES = {}

local function rebuild_map_entries()
    MAP_ENTRIES = {}
    for _, m in ipairs(dcs_maps.MAPS) do
        MAP_ENTRIES[#MAP_ENTRIES + 1] = { name = m.name, icao = m.icao, std_offset_h = m.std_offset_h, rule = m.rule, is_builtin = true }
    end
    for _, m in ipairs(dcs_maps.EXTRA) do
        MAP_ENTRIES[#MAP_ENTRIES + 1] = { name = m.name, icao = m.icao, std_offset_h = m.std_offset_h, rule = m.rule, is_builtin = true }
    end
    for _, m in ipairs(custom_maps.load()) do
        MAP_ENTRIES[#MAP_ENTRIES + 1] = { name = m.name, icao = m.icao, std_offset_h = m.std_offset_h, rule = m.rule, is_builtin = false }
    end
end

local function entry_label(entry)
    return string.format("%s (%s)", entry.name, entry.icao)
end

local last_combo_index = nil

-- ComboList/ListBoxItem: the same native classes dcs-sms uses for its
-- country picker (mass_edit_forms/set_country.lua). No evidence in that
-- code of a live change callback, so the ICAO is synced by polling (see
-- poll_job), not by event.
local function populate_combo_items(combo)
    if not combo then return end
    local ok_i, ListBoxItem = pcall(require, "ListBoxItem")
    if not (ok_i and ListBoxItem and ListBoxItem.new) then return end
    if combo.removeAllItems then pcall(combo.removeAllItems, combo) end
    for _, m in ipairs(MAP_ENTRIES) do
        local ok2, item = pcall(ListBoxItem.new, entry_label(m))
        if ok2 and item and combo.insertItem then
            pcall(combo.insertItem, combo, item)
        end
    end
    last_combo_index = nil
end

local function make_map_combo()
    local ok_c, ComboList = pcall(require, "ComboList")
    if not (ok_c and ComboList and ComboList.new) then return nil end
    local ok, combo = pcall(ComboList.new)
    if not ok or not combo then return nil end
    pcall(function()
        local Skin = require("Skin")
        if Skin.listBoxSkin_ME and combo.setSkin then combo:setSkin(Skin.listBoxSkin_ME()) end
    end)
    rebuild_map_entries()
    populate_combo_items(combo)
    return combo
end

-- If the combo's selection changed since last time, updates the ICAO and
-- the map's timezone. Called from poll_job (once per tick).
local function sync_map_combo()
    local combo = widgets.map_combo
    if not combo or not combo.getSelectedItem then return end
    local ok, item = pcall(combo.getSelectedItem, combo)
    if not ok or not item then return end
    local idx = nil
    for i, entry in ipairs(MAP_ENTRIES) do
        if item.getText then
            local ok3, text = pcall(item.getText, item)
            if ok3 and text == entry_label(entry) then idx = i; break end
        end
    end
    if idx and idx ~= last_combo_index then
        last_combo_index = idx
        local entry = MAP_ENTRIES[idx]
        set_text(widgets.icao_box, entry.icao)
        state.map_zone = { std_offset_h = entry.std_offset_h, rule = entry.rule }
        set_text(widgets.theatre_lbl, "Map chosen by hand: " .. entry.name)

        -- A custom ICAO has no known real timezone, so the "Map" time mode
        -- doesn't make sense for it - it gets disabled, and if it was
        -- selected we jump to "Local".
        local allow_map_hora = entry.is_builtin
        if widgets.time_map_cb and widgets.time_map_cb.setEnabled then
            pcall(widgets.time_map_cb.setEnabled, widgets.time_map_cb, allow_map_hora)
        end
        if widgets.time_map_lbl and widgets.time_map_lbl.setEnabled then
            pcall(widgets.time_map_lbl.setEnabled, widgets.time_map_lbl, allow_map_hora)
        end
        if not allow_map_hora and state.time_mode == "map" and select_time_mode then
            select_time_mode("local")
        end
    end
end

local function on_add_icao_click()
    local icao = get_text(widgets.icao_box)
    local custom_name = get_text(widgets.name_box)
    local ok, result = custom_maps.add(icao, custom_name)
    if not ok then
        set_text(widgets.status_lbl, "Couldn't add: " .. tostring(result))
        return
    end
    rebuild_map_entries()
    populate_combo_items(widgets.map_combo)
    set_text(widgets.name_box, "")
    set_text(widgets.status_lbl, "Added " .. icao:upper() .. " to the map list.")
end

local function on_remove_icao_click()
    local combo = widgets.map_combo
    if not combo or not combo.getSelectedItem then return end
    local ok, item = pcall(combo.getSelectedItem, combo)
    if not ok or not item or not item.getText then
        set_text(widgets.status_lbl, "Select a map in the dropdown first.")
        return
    end
    local ok2, text = pcall(item.getText, item)
    if not ok2 then return end
    local entry = nil
    for _, e in ipairs(MAP_ENTRIES) do
        if entry_label(e) == text then entry = e; break end
    end
    if not entry then
        set_text(widgets.status_lbl, "Select a map in the dropdown first.")
        return
    end
    if entry.is_builtin then
        set_text(widgets.status_lbl, "Built-in maps can't be removed, only the ones you added.")
        return
    end
    local ok3, result = custom_maps.remove(entry.icao)
    if not ok3 then
        set_text(widgets.status_lbl, "Couldn't remove: " .. tostring(result))
        return
    end
    rebuild_map_entries()
    populate_combo_items(widgets.map_combo)
    set_text(widgets.status_lbl, "Removed " .. entry.icao .. " from the map list.")
end

local function make_editbox(default_text)
    local EditBox = require("EditBox")
    local Skin = require("Skin")
    local e = EditBox.new()
    pcall(function() if Skin.editBoxSkin_ME then e:setSkin(Skin.editBoxSkin_ME()) end end)
    if default_text then set_text(e, default_text) end
    return e
end

-- ---------------------------------------------------------------------------
-- Map / timezone detection from mission.theatre

local function detect_map()
    local ok, mm = pcall(require, "me_mission")
    local theatre = (ok and mm and mm.mission and mm.mission.theatre) or nil
    local entry = theatre and dcs_maps.guess_from_theatre(theatre)
    if entry then
        state.map_zone = { std_offset_h = entry.std_offset_h, rule = entry.rule }
        set_text(widgets.theatre_lbl, "Detected map: " .. theatre .. " (" .. entry.name .. ")")
        if widgets.icao_box and get_text(widgets.icao_box) == "" then
            set_text(widgets.icao_box, entry.icao)
        end
    else
        state.map_zone = { std_offset_h = 0, rule = "none" }
        set_text(widgets.theatre_lbl, "Map not recognized (theatre=" .. tostring(theatre) ..
            ") - using UTC. Type the ICAO by hand; tell us this theatre " ..
            "value and we'll add its timezone.")
    end
end

-- ---------------------------------------------------------------------------
-- METAR fetch (pumped by actual_metar.ticker once per tick)

local tick_count = 0
local function poll_job()
    tick_count = tick_count + 1
    if widgets.tick_lbl then
        set_text(widgets.tick_lbl, "ticks: " .. tick_count)
    end
    if tick_count == 1 then
        pcall(function() _G.log.write("actual_metar", _G.log.INFO or 3, "first tick received - UpdateManager works") end)
    end
    pcall(sync_map_combo)
    if not state.job then return end
    local st = state.job:step()
    if st == "running" then
        set_text(widgets.status_lbl, "Fetching... (" .. state.job:debug() .. ")")
    elseif st == "done" then
        state.weather = state.job.weather
        state.job = nil
        set_text(widgets.status_lbl, "METAR obtained.")
        set_text(widgets.raw_lbl, state.weather.raw_metar or "")
        set_text(widgets.summary_lbl, string.format(
            "Ground wind %d deg / %.1f m/s | QNH %d mmHg | Temp %.1f C | Vis %d m",
            state.weather.wind.ground.dir, state.weather.wind.ground.speed,
            state.weather.qnh, state.weather.temperature, state.weather.visibility_m))
        local cl = state.weather.clouds
        set_text(widgets.clouds_lbl, cl.preset ~= "" and
            string.format("Clouds: %s - preset %s, base %d m", cl.cover, cl.preset, cl.base) or
            string.format("Clouds: %s - base %d m, density %d/10 (no preset)", cl.cover, cl.base, cl.density))
    elseif st == "error" then
        set_text(widgets.status_lbl, "Error: " .. tostring(state.job.error))
        state.job = nil
    end
end

M._poll_job = poll_job -- exposed for actual_metar.ticker

local function on_fetch_click()
    if not ticker.is_installed() then
        pcall(ticker.install)
    end
    if not ticker.is_installed() then
        set_text(widgets.status_lbl,
            "Error: the pump (UpdateManager) isn't available in this editor - " ..
            "the fetch can't proceed. Check dcs.log (actual_metar).")
        return
    end
    local icao = get_text(widgets.icao_box)
    set_text(widgets.status_lbl, "Fetching...")
    set_text(widgets.raw_lbl, "")
    set_text(widgets.summary_lbl, "")
    set_text(widgets.clouds_lbl, "")
    state.weather = nil
    state.job = metar_fetch.new()
    state.job:start(icao)
end

-- ---------------------------------------------------------------------------
-- Apply

local function parse_date(s)
    local y, m, d = tostring(s or ""):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return nil end
    return { year = tonumber(y), month = tonumber(m), day = tonumber(d) }
end

local function parse_time(s)
    local h, m = tostring(s or ""):match("^(%d+):(%d+)$")
    if not h then return nil end
    return { hour = tonumber(h), min = tonumber(m), sec = 0 }
end

local function on_apply_click()
    if not state.weather then
        set_text(widgets.apply_status_lbl, "Get a METAR first.")
        return
    end
    local ok, mm = pcall(require, "me_mission")
    if not ok or not mm or type(mm.mission) ~= "table" then
        set_text(widgets.apply_status_lbl, "No mission is open in the editor.")
        return
    end
    local mission = mm.mission

    local wok, wnotes = mission_apply.apply_weather(mission, state.weather)
    if not wok then
        set_text(widgets.apply_status_lbl, "Error applying weather: " .. tostring(wnotes))
        return
    end

    local msg = "Weather applied."
    if type(wnotes) == "table" and #wnotes > 0 then
        msg = msg .. " " .. table.concat(wnotes, " ")
    end

    if widgets.datetime_enable_on then
        local date_value = state.date_mode == "custom" and parse_date(get_text(widgets.date_custom_box)) or nil
        local time_value = state.time_mode == "custom" and parse_time(get_text(widgets.time_custom_box)) or nil
        if state.date_mode == "custom" and not date_value then
            set_text(widgets.apply_status_lbl, msg .. " Invalid custom date (use YYYY-MM-DD).")
            return
        end
        if state.time_mode == "custom" and not time_value then
            set_text(widgets.apply_status_lbl, msg .. " Invalid custom time (use HH:MM).")
            return
        end
        local dt, err = mission_datetime.compute(
            state.date_mode, date_value, state.time_mode, time_value,
            state.map_zone)
        if not dt then
            set_text(widgets.apply_status_lbl, msg .. " Date/time error: " .. tostring(err))
            return
        end
        local dok, derr = mission_apply.apply_datetime(mission, dt)
        if dok then
            msg = msg .. " Date/time: " .. dt.applied_label .. "."
        else
            msg = msg .. " Date/time error: " .. tostring(derr)
        end
    end

    set_text(widgets.apply_status_lbl, msg .. " Now save the mission (Ctrl+S).")
end

-- ---------------------------------------------------------------------------

function M.toggle()
    -- UpdateManager may not be ready when MissionEditor.lua loaded
    -- init.lua at DCS startup; we retry every time the panel is opened,
    -- by which point the editor is surely fully loaded.
    pcall(ticker.install)

    if W and W.setVisible then
        local ok, visible = pcall(function() return W.isVisible and W:isVisible() end)
        local now_visible = (ok and visible) and false or true
        pcall(W.setVisible, W, now_visible)
        if now_visible then
            pcall(detect_map)
            if widgets.tick_lbl and not ticker.is_installed() then
                set_text(widgets.tick_lbl, "no tick!")
            end
        end
        return
    end

    local ok, err = pcall(function()
        local Window = require("Window")
        local Skin = require("Skin")
        local Gui = require("dxgui")

        local w, h = 560, 520
        local screen_w, screen_h = Gui.GetWindowSize()
        local x = math.floor((screen_w - w) / 2)
        local y = math.floor((screen_h - h) / 2)

        W = Window.new(x, y, w, h, "ACTUAL METAR")
        pcall(function()
            local skin = (Skin.windowSkinME and Skin.windowSkinME()) or Skin.windowSkin()
            if skin then W:setSkin(skin) end
        end)
        W:setVisible(true)
        W:setDraggable(true)
        W:setResizable(false)
        W:setZOrder(200)

        local function add(widget)
            if widget then pcall(W.insertWidget, W, widget) end
            return widget
        end
        local PAD = 16

        widgets.theatre_lbl = add(make_label("Detecting map..."))
        widgets.theatre_lbl:setBounds(PAD, 12, w - 2 * PAD - 90, 18)
        widgets.tick_lbl = add(make_label(ticker.is_installed() and "ticks: 0" or "no tick!"))
        widgets.tick_lbl:setBounds(w - PAD - 90, 12, 90, 18)

        add(make_label("Map:")):setBounds(PAD, 34, 50, 22)
        widgets.map_combo = add(make_map_combo())
        set_bounds(widgets.map_combo, PAD + 54, 34, w - 2 * PAD - 54 - 62, 22)
        widgets.map_add_btn = add(make_button("+", on_add_icao_click))
        set_bounds(widgets.map_add_btn, w - PAD - 58, 34, 26, 22)
        widgets.map_remove_btn = add(make_button("-", on_remove_icao_click))
        set_bounds(widgets.map_remove_btn, w - PAD - 28, 34, 26, 22)

        add(make_label("ICAO:")):setBounds(PAD, 62, 50, 22)
        widgets.icao_box = add(make_editbox(""))
        widgets.icao_box:setBounds(PAD + 54, 62, 80, 22)
        widgets.fetch_btn = add(make_button("Get METAR", on_fetch_click))
        widgets.fetch_btn:setBounds(PAD + 144, 62, 140, 22)
        add(make_label("Name:")):setBounds(PAD + 294, 62, 55, 22)
        widgets.name_box = add(make_editbox(""))
        set_bounds(widgets.name_box, PAD + 350, 62, w - PAD - (PAD + 350), 22)

        widgets.status_lbl = add(make_label(""))
        widgets.status_lbl:setBounds(PAD, 90, w - 2 * PAD, 18)
        widgets.raw_lbl = add(make_label(""))
        widgets.raw_lbl:setBounds(PAD, 110, w - 2 * PAD, 18)
        widgets.summary_lbl = add(make_label(""))
        widgets.summary_lbl:setBounds(PAD, 130, w - 2 * PAD, 18)
        widgets.clouds_lbl = add(make_label(""))
        widgets.clouds_lbl:setBounds(PAD, 150, w - 2 * PAD, 18)

        widgets.datetime_enable_on = true
        widgets.datetime_enable_cb = add(make_checkbox(true, function(checked)
            widgets.datetime_enable_on = checked
        end))
        set_bounds(widgets.datetime_enable_cb, PAD, 182, 20, 20)
        add(make_label("Also apply date and time")):setBounds(PAD + 24, 182, 260, 22)

        add(make_label("Date:")):setBounds(PAD, 212, 50, 22)
        widgets.date_actual_cb = add(make_checkbox(true, nil))
        set_bounds(widgets.date_actual_cb, PAD + 54, 212, 20, 20)
        add(make_label("Current")):setBounds(PAD + 76, 212, 70, 22)
        widgets.date_custom_cb = add(make_checkbox(false, nil))
        set_bounds(widgets.date_custom_cb, PAD + 150, 212, 20, 20)
        add(make_label("Custom")):setBounds(PAD + 172, 212, 100, 22)
        widgets.date_custom_box = add(make_editbox("2026-01-01"))
        widgets.date_custom_box:setBounds(PAD + 276, 212, 100, 22)
        wire_radio_group(
            { actual = widgets.date_actual_cb, custom = widgets.date_custom_cb },
            function(key) state.date_mode = key end)

        add(make_label("Time:")):setBounds(PAD, 244, 50, 22)
        widgets.time_local_cb = add(make_checkbox(false, nil))
        set_bounds(widgets.time_local_cb, PAD + 54, 244, 20, 20)
        add(make_label("Local")):setBounds(PAD + 76, 244, 70, 22)
        widgets.time_map_cb = add(make_checkbox(true, nil))
        set_bounds(widgets.time_map_cb, PAD + 150, 244, 20, 20)
        widgets.time_map_lbl = add(make_label("Map"))
        widgets.time_map_lbl:setBounds(PAD + 172, 244, 50, 22)
        widgets.time_custom_cb = add(make_checkbox(false, nil))
        set_bounds(widgets.time_custom_cb, PAD + 226, 244, 20, 20)
        add(make_label("Custom")):setBounds(PAD + 248, 244, 100, 22)
        widgets.time_custom_box = add(make_editbox("20:00"))
        widgets.time_custom_box:setBounds(PAD + 352, 244, 70, 22)
        select_time_mode = wire_radio_group(
            { ["local"] = widgets.time_local_cb, map = widgets.time_map_cb, custom = widgets.time_custom_cb },
            function(key) state.time_mode = key end)

        widgets.apply_btn = add(make_button("Apply to open mission", on_apply_click))
        widgets.apply_btn:setBounds(PAD, 276, 260, 26)
        widgets.apply_status_lbl = add(make_label(""))
        widgets.apply_status_lbl:setBounds(PAD, 308, w - 2 * PAD, 80)

        detect_map()
    end)

    if not ok then
        log_err("window.toggle failed: " .. tostring(err))
        W = nil
    end
end

function M.hide()
    if W and W.setVisible then pcall(W.setVisible, W, false) end
end

return M
