-- weather_calc.lua — direct port of metar-dcs-app/metar.py
-- (normalize_for_dcs). Converts the aviationweather.gov JSON (already
-- decoded into a Lua table) into the values ready to write into
-- mission.weather. See metar-dcs-app/metar.py for the full justification
-- of each conversion (reversed wind direction, ISA lapse rate, rain preset
-- priority, etc.) — here just the code, minimal comments.

local cloud_presets = require("actual_metar.cloud_presets")

local M = {}

local KT_TO_MPS = 0.514444
local SM_TO_M = 1609.34
local HPA_TO_MMHG = 0.750062
local ISA_LAPSE_C_PER_M = 0.0065

local CLOUD_DENSITY = {
    SKC = 0, CLR = 0, NSC = 0, NCD = 0, CAVOK = 0,
    FEW = 2, SCT = 4, BKN = 7, OVC = 9,
}
local CLOUD_THICKNESS = { FEW = 300, SCT = 600, BKN = 1200, OVC = 2000 }
local COVER_RANK = { OVC = 4, BKN = 3, SCT = 2, FEW = 1 }

local function round(x, ndigits)
    local mult = 10 ^ (ndigits or 0)
    if x >= 0 then
        return math.floor(x * mult + 0.5) / mult
    else
        return math.ceil(x * mult - 0.5) / mult
    end
end

local function parse_visibility_sm(visib)
    if visib == nil then return 10.0 end
    local s = tostring(visib)
    s = s:gsub("%s+$", ""):gsub("^%s+", "")
    if s:sub(-1) == "+" then s = s:sub(1, -2) end
    local num, den = s:match("^(%-?%d+%.?%d*)/(%-?%d+%.?%d*)$")
    if num and den then
        local n, d = tonumber(num), tonumber(den)
        if n and d and d ~= 0 then return n / d end
        return 10.0
    end
    local v = tonumber(s)
    if v then return v end
    return 10.0
end

-- Picks the reference cloud layer: if there's precipitation, the one with
-- the highest coverage; otherwise the first one with a ceiling (BKN/OVC);
-- if there's no ceiling, the first reported layer.
local function reference_layer(clouds, precip)
    if not clouds or #clouds == 0 then return nil end
    if precip then
        local best, best_rank = nil, -1
        for _, c in ipairs(clouds) do
            local rank = COVER_RANK[c.cover] or 0
            if rank > best_rank then best, best_rank = c, rank end
        end
        return best
    end
    for _, c in ipairs(clouds) do
        if c.cover == "BKN" or c.cover == "OVC" then return c end
    end
    return clouds[1]
end

local function contains_word(s, word)
    if not s then return false end
    return s:find("%f[%a]" .. word .. "%f[%A]") ~= nil
end

local MONTH_NAMES = {
    "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
    "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
}

-- report_time comes as "2026-08-23T19:00:00.000Z" (ISO 8601, always UTC).
local function build_name_label(icao, report_time)
    if not report_time then return nil end
    local y, mo, d, hh, mi = report_time:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
    if not y then return nil end
    mo = tonumber(mo)
    local mon = MONTH_NAMES[mo] or "???"
    return string.format("Real weather - METAR %s %s%s%s %s%sZ", icao or "?", d, mon, y, hh, mi)
end

-- normalize(raw) -> table ready for mission_apply.lua
function M.normalize(raw)
    local wdir = raw.wdir
    local wspd_kt = raw.wspd or 0
    local wgst_kt = raw.wgst

    if type(wdir) == "string" then wdir = nil end -- "VRB" or similar
    local dcs_dir_ground = nil
    if wdir ~= nil then
        dcs_dir_ground = (tonumber(wdir) + 180.0) % 360.0
    end

    local speed_ground_mps = tonumber(wspd_kt) * KT_TO_MPS
    local speed_2000_mps = speed_ground_mps * 1.4
    local speed_8000_mps = speed_ground_mps * 2.0

    local turbulence_mps = 0.0
    if wgst_kt and tonumber(wgst_kt) then
        turbulence_mps = math.max(0.0, (tonumber(wgst_kt) - tonumber(wspd_kt)) * KT_TO_MPS)
    end

    local elev_m = raw.elev or 0
    local temp_c = raw.temp
    local temp_sea_level = nil
    if temp_c ~= nil then
        temp_sea_level = round(tonumber(temp_c) + tonumber(elev_m) * ISA_LAPSE_C_PER_M, 1)
    end

    local altim_hpa = raw.altim
    local qnh_mmhg = nil
    if altim_hpa ~= nil then
        qnh_mmhg = round(tonumber(altim_hpa) * HPA_TO_MMHG, 0)
    end

    local visib_sm = parse_visibility_sm(raw.visib)
    local visib_m = math.min(80000, round(visib_sm * SM_TO_M, 0))

    local wx = (raw.wxString or "") .. " " .. (raw.rawOb or "")
    local iprecptns = 0
    if contains_word(wx, "SN") or wx:find("SNRA") or wx:find("%-SN") or wx:find("%+SN") then
        iprecptns = 2
    elseif contains_word(wx, "RA") or wx:find("%-RA") or wx:find("%+RA") or wx:find("DZ") or wx:find("SHRA") then
        iprecptns = 1
    end
    local precip = iprecptns > 0

    local clouds = raw.clouds or {}
    local layer = reference_layer(clouds, precip)
    local cover = layer and layer.cover or "SKC"
    local base_ft = layer and layer.base or nil
    local base_agl_m = base_ft and (tonumber(base_ft) * 0.3048) or 0.0
    local base_msl_m = layer and round(tonumber(elev_m) + base_agl_m, 0) or 300
    local density = CLOUD_DENSITY[cover] or 0
    local thickness_m = CLOUD_THICKNESS[cover] or 200

    local preset_name, preset_base_m = cloud_presets.select(cover, base_msl_m, precip)
    local base_m = round(preset_base_m, 0)

    local enable_fog = (visib_m < 1000) or (wx:find("FG") ~= nil)
    local fog_visibility = enable_fog and math.min(6000, visib_m) or 0
    local fog_thickness = enable_fog and 200 or 0

    return {
        icao = raw.icaoId,
        raw_metar = raw.rawOb,
        obs_time = raw.reportTime,
        name_label = build_name_label(raw.icaoId, raw.reportTime),
        wind = {
            ground = { dir = dcs_dir_ground or 0, speed = round(speed_ground_mps, 1) },
            at2000 = { dir = dcs_dir_ground or 0, speed = round(speed_2000_mps, 1) },
            at8000 = { dir = dcs_dir_ground or 0, speed = round(speed_8000_mps, 1) },
        },
        ground_turbulence = round(turbulence_mps, 0),
        temperature = temp_sea_level or 20.0,
        qnh = qnh_mmhg or 760,
        visibility_m = visib_m,
        clouds = {
            preset = preset_name or "",
            density = preset_name and 0 or density,
            base = base_m,
            thickness = preset_name and 200 or thickness_m,
            iprecptns = preset_name and 0 or iprecptns,
            cover = cover,
        },
        fog = {
            enable = enable_fog,
            visibility = fog_visibility,
            thickness = fog_thickness,
        },
        metar_wind_from_deg = wdir,
        metar_wind_speed_kt = wspd_kt,
        metar_visib_sm = visib_sm,
        metar_temp_c = temp_c,
        metar_altim_hpa = altim_hpa,
    }
end

return M
