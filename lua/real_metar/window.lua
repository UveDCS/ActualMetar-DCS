-- window.lua — panel "REAL METAR". Un solo Window flotante, patron
-- single-instance igual que dcs_sms_me.about / prefab_manager. Solo usa
-- widgets confirmados en el codigo de dcs-sms: Window, Static, EditBox,
-- Button (ver about.lua / mass_edit_forms/*.lua de ese proyecto).

local dcs_maps = require("real_metar.dcs_maps")
local mission_datetime = require("real_metar.mission_datetime")
local mission_apply = require("real_metar.mission_apply")
local metar_fetch = require("real_metar.metar_fetch")
local ticker = require("real_metar.ticker")
local custom_maps = require("real_metar.custom_maps")

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

-- Asignado al montar la ventana (wire_radio_group del grupo Hora). Permite
-- forzar el modo de hora desde codigo (p.ej. saltar de "Mapa" a "Local" si
-- se elige un ICAO personalizado sin zona horaria real conocida).
local select_time_mode = nil

local function log_err(msg)
    pcall(function() _G.log.write("real_metar", _G.log.ERROR or 1, tostring(msg)) end)
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
                log_err("boton '" .. tostring(text) .. "' fallo: " .. tostring(err))
                set_text(widgets.apply_status_lbl, "Error interno (ver dcs.log, real_metar): " .. tostring(err))
            end
        end)
    end
    return btn
end

-- CheckBox: clase nativa confirmada en el codigo real de dcs-sms
-- (mass_edit.lua, trigger_finder.lua): CheckBox.new(), cb:setState(bool),
-- cb:getState(), cb:addChangeCallback(function(box) ... end).
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
                log_err("checkbox fallo: " .. tostring(err))
            end
        end)
    end
    return cb
end

-- Grupo de CheckBoxes con comportamiento de radio (uno solo marcado a la
-- vez). "boxes" es {mode_key -> checkbox_widget}. Marcar uno desmarca el
-- resto y llama a on_select(mode_key). Devuelve select_key(key) para poder
-- forzar la seleccion desde codigo (no solo desde el click del usuario) -
-- lo usa sync_map_combo para saltar de "Mapa" a "Local" si hace falta.
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
                        -- no se permite desmarcar el unico activo: re-marcar
                        pcall(cb.setState, cb, true)
                        return
                    end
                    select_key(key)
                end)
                if not ok then log_err("radio group fallo: " .. tostring(err)) end
            end)
        end
    end

    return select_key
end

-- Lista de mapas (DCS_MAPS + EXTRA + los ICAOs personalizados del usuario)
-- alineada por indice con los items insertados en el combo, para poder
-- resolver "seleccion actual -> entrada". is_builtin distingue los
-- predefinidos (no se pueden borrar) de los añadidos a mano.
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

-- ComboList/ListBoxItem: mismas clases nativas que usa dcs-sms para su
-- selector de pais (mass_edit_forms/set_country.lua). No hay evidencia en
-- ese codigo de un callback de cambio en vivo, asi que la sincronizacion
-- con el ICAO se hace por sondeo (ver poll_job), no por evento.
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

-- Si la seleccion del combo cambio desde la ultima vez, actualiza el ICAO
-- y la zona horaria del mapa. Llamado desde poll_job (una vez por tick).
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
        set_text(widgets.theatre_lbl, "Mapa elegido a mano: " .. entry.name)

        -- Un ICAO personalizado no tiene zona horaria real conocida, asi
        -- que el modo de hora "Mapa" no tiene sentido para el - se
        -- deshabilita, y si estaba seleccionado se salta a "Local".
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
        set_text(widgets.status_lbl, "No se pudo añadir: " .. tostring(result))
        return
    end
    rebuild_map_entries()
    populate_combo_items(widgets.map_combo)
    set_text(widgets.name_box, "")
    set_text(widgets.status_lbl, "Añadido " .. icao:upper() .. " a la lista de mapas.")
end

local function on_remove_icao_click()
    local combo = widgets.map_combo
    if not combo or not combo.getSelectedItem then return end
    local ok, item = pcall(combo.getSelectedItem, combo)
    if not ok or not item or not item.getText then
        set_text(widgets.status_lbl, "Selecciona primero un mapa en el desplegable.")
        return
    end
    local ok2, text = pcall(item.getText, item)
    if not ok2 then return end
    local entry = nil
    for _, e in ipairs(MAP_ENTRIES) do
        if entry_label(e) == text then entry = e; break end
    end
    if not entry then
        set_text(widgets.status_lbl, "Selecciona primero un mapa en el desplegable.")
        return
    end
    if entry.is_builtin then
        set_text(widgets.status_lbl, "No se pueden eliminar los mapas predefinidos, solo los que hayas añadido tú.")
        return
    end
    local ok3, result = custom_maps.remove(entry.icao)
    if not ok3 then
        set_text(widgets.status_lbl, "No se pudo eliminar: " .. tostring(result))
        return
    end
    rebuild_map_entries()
    populate_combo_items(widgets.map_combo)
    set_text(widgets.status_lbl, "Eliminado " .. entry.icao .. " de la lista de mapas.")
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
-- Deteccion del mapa / zona horaria a partir de mission.theatre

local function detect_map()
    local ok, mm = pcall(require, "me_mission")
    local theatre = (ok and mm and mm.mission and mm.mission.theatre) or nil
    local entry = theatre and dcs_maps.guess_from_theatre(theatre)
    if entry then
        state.map_zone = { std_offset_h = entry.std_offset_h, rule = entry.rule }
        set_text(widgets.theatre_lbl, "Mapa detectado: " .. theatre .. " (" .. entry.name .. ")")
        if widgets.icao_box and get_text(widgets.icao_box) == "" then
            set_text(widgets.icao_box, entry.icao)
        end
    else
        state.map_zone = { std_offset_h = 0, rule = "none" }
        set_text(widgets.theatre_lbl, "Mapa no reconocido (theatre=" .. tostring(theatre) ..
            ") - usando UTC. Escribe el ICAO a mano; para el huso horario dime este " ..
            "valor de theatre y lo añado.")
    end
end

-- ---------------------------------------------------------------------------
-- Fetch METAR (bombeado por real_metar.ticker una vez por tick)

local tick_count = 0
local function poll_job()
    tick_count = tick_count + 1
    if widgets.tick_lbl then
        set_text(widgets.tick_lbl, "ticks: " .. tick_count)
    end
    if tick_count == 1 then
        pcall(function() _G.log.write("real_metar", _G.log.INFO or 3, "primer tick recibido - UpdateManager funciona") end)
    end
    pcall(sync_map_combo)
    if not state.job then return end
    local st = state.job:step()
    if st == "running" then
        set_text(widgets.status_lbl, "Consultando... (" .. state.job:debug() .. ")")
    elseif st == "done" then
        state.weather = state.job.weather
        state.job = nil
        set_text(widgets.status_lbl, "METAR obtenido.")
        set_text(widgets.raw_lbl, state.weather.raw_metar or "")
        set_text(widgets.summary_lbl, string.format(
            "Viento suelo %d deg / %.1f m/s | QNH %d mmHg | Temp %.1f C | Vis %d m",
            state.weather.wind.ground.dir, state.weather.wind.ground.speed,
            state.weather.qnh, state.weather.temperature, state.weather.visibility_m))
        local cl = state.weather.clouds
        set_text(widgets.clouds_lbl, cl.preset ~= "" and
            string.format("Nubes: %s - preset %s, base %d m", cl.cover, cl.preset, cl.base) or
            string.format("Nubes: %s - base %d m, densidad %d/10 (sin preset)", cl.cover, cl.base, cl.density))
    elseif st == "error" then
        set_text(widgets.status_lbl, "Error: " .. tostring(state.job.error))
        state.job = nil
    end
end

M._poll_job = poll_job -- expuesto para real_metar.ticker

local function on_fetch_click()
    if not ticker.is_installed() then
        pcall(ticker.install)
    end
    if not ticker.is_installed() then
        set_text(widgets.status_lbl,
            "Error: el bombeo (UpdateManager) no esta disponible en este editor - " ..
            "el fetch no puede avanzar. Mira dcs.log (real_metar).")
        return
    end
    local icao = get_text(widgets.icao_box)
    set_text(widgets.status_lbl, "Consultando...")
    set_text(widgets.raw_lbl, "")
    set_text(widgets.summary_lbl, "")
    set_text(widgets.clouds_lbl, "")
    state.weather = nil
    state.job = metar_fetch.new()
    state.job:start(icao)
end

-- ---------------------------------------------------------------------------
-- Fecha / Hora mode toggles


-- ---------------------------------------------------------------------------
-- Aplicar

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
        set_text(widgets.apply_status_lbl, "Primero obtén un METAR.")
        return
    end
    local ok, mm = pcall(require, "me_mission")
    if not ok or not mm or type(mm.mission) ~= "table" then
        set_text(widgets.apply_status_lbl, "No hay una mision abierta en el editor.")
        return
    end
    local mission = mm.mission

    local wok, wnotes = mission_apply.apply_weather(mission, state.weather)
    if not wok then
        set_text(widgets.apply_status_lbl, "Error aplicando clima: " .. tostring(wnotes))
        return
    end

    local msg = "Clima aplicado."
    if type(wnotes) == "table" and #wnotes > 0 then
        msg = msg .. " " .. table.concat(wnotes, " ")
    end

    if widgets.datetime_enable_on then
        local date_value = state.date_mode == "custom" and parse_date(get_text(widgets.date_custom_box)) or nil
        local time_value = state.time_mode == "custom" and parse_time(get_text(widgets.time_custom_box)) or nil
        if state.date_mode == "custom" and not date_value then
            set_text(widgets.apply_status_lbl, msg .. " Fecha personalizada invalida (usa AAAA-MM-DD).")
            return
        end
        if state.time_mode == "custom" and not time_value then
            set_text(widgets.apply_status_lbl, msg .. " Hora personalizada invalida (usa HH:MM).")
            return
        end
        local dt, err = mission_datetime.compute(
            state.date_mode, date_value, state.time_mode, time_value,
            state.map_zone)
        if not dt then
            set_text(widgets.apply_status_lbl, msg .. " Error en fecha/hora: " .. tostring(err))
            return
        end
        local dok, derr = mission_apply.apply_datetime(mission, dt)
        if dok then
            msg = msg .. " Fecha/hora: " .. dt.applied_label .. "."
        else
            msg = msg .. " Error fecha/hora: " .. tostring(derr)
        end
    end

    set_text(widgets.apply_status_lbl, msg .. " Ahora guarda la mision (Ctrl+S).")
end

-- ---------------------------------------------------------------------------

function M.toggle()
    -- UpdateManager puede no estar listo cuando MissionEditor.lua cargo
    -- init.lua al arrancar DCS; reintentamos cada vez que se abre el panel,
    -- momento en el que el editor seguro que ya esta completamente cargado.
    pcall(ticker.install)

    if W and W.setVisible then
        local ok, visible = pcall(function() return W.isVisible and W:isVisible() end)
        local now_visible = (ok and visible) and false or true
        pcall(W.setVisible, W, now_visible)
        if now_visible then
            pcall(detect_map)
            if widgets.tick_lbl and not ticker.is_installed() then
                set_text(widgets.tick_lbl, "sin tick!")
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

        W = Window.new(x, y, w, h, "REAL METAR")
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

        widgets.theatre_lbl = add(make_label("Detectando mapa..."))
        widgets.theatre_lbl:setBounds(PAD, 12, w - 2 * PAD - 90, 18)
        widgets.tick_lbl = add(make_label(ticker.is_installed() and "ticks: 0" or "sin tick!"))
        widgets.tick_lbl:setBounds(w - PAD - 90, 12, 90, 18)

        add(make_label("Mapa:")):setBounds(PAD, 34, 50, 22)
        widgets.map_combo = add(make_map_combo())
        set_bounds(widgets.map_combo, PAD + 54, 34, w - 2 * PAD - 54 - 62, 22)
        widgets.map_add_btn = add(make_button("+", on_add_icao_click))
        set_bounds(widgets.map_add_btn, w - PAD - 58, 34, 26, 22)
        widgets.map_remove_btn = add(make_button("-", on_remove_icao_click))
        set_bounds(widgets.map_remove_btn, w - PAD - 28, 34, 26, 22)

        add(make_label("ICAO:")):setBounds(PAD, 62, 50, 22)
        widgets.icao_box = add(make_editbox(""))
        widgets.icao_box:setBounds(PAD + 54, 62, 80, 22)
        widgets.fetch_btn = add(make_button("Obtener METAR", on_fetch_click))
        widgets.fetch_btn:setBounds(PAD + 144, 62, 140, 22)
        add(make_label("Nombre:")):setBounds(PAD + 294, 62, 55, 22)
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
        add(make_label("También aplicar fecha y hora")):setBounds(PAD + 24, 182, 260, 22)

        add(make_label("Fecha:")):setBounds(PAD, 212, 50, 22)
        widgets.date_actual_cb = add(make_checkbox(true, nil))
        set_bounds(widgets.date_actual_cb, PAD + 54, 212, 20, 20)
        add(make_label("Actual")):setBounds(PAD + 76, 212, 70, 22)
        widgets.date_custom_cb = add(make_checkbox(false, nil))
        set_bounds(widgets.date_custom_cb, PAD + 150, 212, 20, 20)
        add(make_label("Personalizada")):setBounds(PAD + 172, 212, 100, 22)
        widgets.date_custom_box = add(make_editbox("2026-01-01"))
        widgets.date_custom_box:setBounds(PAD + 276, 212, 100, 22)
        wire_radio_group(
            { actual = widgets.date_actual_cb, custom = widgets.date_custom_cb },
            function(key) state.date_mode = key end)

        add(make_label("Hora:")):setBounds(PAD, 244, 50, 22)
        widgets.time_local_cb = add(make_checkbox(false, nil))
        set_bounds(widgets.time_local_cb, PAD + 54, 244, 20, 20)
        add(make_label("Local")):setBounds(PAD + 76, 244, 70, 22)
        widgets.time_map_cb = add(make_checkbox(true, nil))
        set_bounds(widgets.time_map_cb, PAD + 150, 244, 20, 20)
        widgets.time_map_lbl = add(make_label("Mapa"))
        widgets.time_map_lbl:setBounds(PAD + 172, 244, 50, 22)
        widgets.time_custom_cb = add(make_checkbox(false, nil))
        set_bounds(widgets.time_custom_cb, PAD + 226, 244, 20, 20)
        add(make_label("Personalizada")):setBounds(PAD + 248, 244, 100, 22)
        widgets.time_custom_box = add(make_editbox("20:00"))
        widgets.time_custom_box:setBounds(PAD + 352, 244, 70, 22)
        select_time_mode = wire_radio_group(
            { ["local"] = widgets.time_local_cb, map = widgets.time_map_cb, custom = widgets.time_custom_cb },
            function(key) state.time_mode = key end)

        widgets.apply_btn = add(make_button("Aplicar a la mision abierta", on_apply_click))
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
