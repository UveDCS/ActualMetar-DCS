-- cloud_presets.lua — puerto directo de metar-dcs-app/metar.py (CLOUD_PRESETS
-- + select_cloud_preset). Tabla de presets de nubes de DCS: nombre -> rango
-- de base en metros MSL, agrupados por tipo de cobertura. Fuente:
-- evogelsa/DCS-real-weather (weather/weather.go), validada contra DCS real.

local M = {}

local CLEAR_COVER = { SKC = true, CLR = true, NSC = true, NCD = true, CAVOK = true }

local PRESETS = {
    FEW = {
        { "Preset1", 840, 4200 },
        { "Preset2", 1260, 2520 },
    },
    SCT = {
        { "Preset3", 840, 2520 },
        { "Preset4", 1260, 2520 },
        { "Preset5", 1260, 4620 },
        { "Preset6", 1260, 4200 },
        { "Preset7", 1680, 5040 },
        { "Preset8", 3780, 5460 },
        { "Preset9", 1680, 3780 },
        { "Preset10", 1260, 4200 },
        { "Preset11", 2520, 5460 },
        { "Preset12", 1680, 3360 },
    },
    ["SCT+RA"] = {
        { "RainyPreset4", 1260, 4200 },
        { "NEWRAINPRESET4", 840, 5174 },
    },
    BKN = {
        { "Preset13", 1680, 3360 },
        { "Preset14", 1680, 3360 },
        { "Preset15", 840, 5040 },
        { "Preset16", 1260, 4200 },
        { "Preset17", 0, 2520 },
        { "Preset18", 0, 3780 },
        { "Preset19", 0, 2940 },
        { "Preset20", 0, 3780 },
    },
    ["BKN+RA"] = {
        { "RainyPreset5", 1260, 2520 },
    },
    OVC = {
        { "Preset21", 1260, 4200 },
        { "Preset22", 420, 4200 },
        { "Preset23", 840, 3360 },
        { "Preset24", 420, 2520 },
        { "Preset25", 420, 3360 },
        { "Preset26", 420, 2940 },
        { "Preset27", 420, 2520 },
    },
    ["OVC+RA"] = {
        { "RainyPreset1", 420, 2940 },
        { "RainyPreset2", 840, 2520 },
        { "RainyPreset3", 840, 2520 },
        { "RainyPreset6", 1260, 2940 },
    },
}

local function best_within_range(cands, base_m)
    local best, best_dist = nil, nil
    for _, p in ipairs(cands) do
        if base_m >= p[2] and base_m <= p[3] then
            local mid = (p[2] + p[3]) / 2
            local dist = math.abs(mid - base_m)
            if best == nil or dist < best_dist then
                best, best_dist = p, dist
            end
        end
    end
    return best
end

local function nearest(cands, base_m)
    if #cands == 0 then return nil, nil end
    local best, best_dist = nil, nil
    for _, p in ipairs(cands) do
        local dist
        if base_m >= p[2] and base_m <= p[3] then
            dist = 0
        else
            dist = math.min(math.abs(base_m - p[2]), math.abs(base_m - p[3]))
        end
        if best == nil or dist < best_dist then
            best, best_dist = p, dist
        end
    end
    local clamped = base_m
    if clamped < best[2] then clamped = best[2] end
    if clamped > best[3] then clamped = best[3] end
    return best[1], clamped
end

-- select(cover, base_m, precip) -> preset_name_or_nil, base_to_use
-- Si precip es true, se prioriza SIEMPRE un preset con lluvia (aunque su
-- rango de base encaje peor) antes que uno sin lluvia mas fiel a la base
-- real - ver metar-dcs-app/metar.py para la justificacion.
function M.select(cover, base_m, precip)
    if not cover or CLEAR_COVER[cover] then
        return nil, base_m
    end

    if precip and (cover == "OVC" or cover == "BKN" or cover == "SCT") then
        local rain_candidates = PRESETS[cover .. "+RA"] or {}
        local chosen = best_within_range(rain_candidates, base_m)
        if chosen then return chosen[1], base_m end
        local name, base = nearest(rain_candidates, base_m)
        if name then return name, base end
        -- este tipo de cobertura no tiene ningun preset con lluvia (p.ej. FEW)
    end

    local candidates = PRESETS[cover] or {}
    local chosen = best_within_range(candidates, base_m)
    if chosen then return chosen[1], base_m end
    local name, base = nearest(candidates, base_m)
    if name then return name, base end
    return nil, base_m
end

M.PRESETS = PRESETS
M.CLEAR_COVER = CLEAR_COVER

return M
