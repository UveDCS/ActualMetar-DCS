-- mission_apply.lua — writes the already-computed values (weather_calc +
-- mission_datetime) directly into the Mission Editor's in-memory `mission`
-- table (require('me_mission').mission). Unlike metar-dcs-app (which edits
-- the .miz as a zip/text file because there's no live editor process),
-- here we mutate the real Lua table: the editor serves it as-is when you
-- hit Save.

local M = {}

-- apply_weather(mission, w) — w is the table returned by weather_calc.normalize
function M.apply_weather(mission, w)
    local weather = mission.weather
    if type(weather) ~= "table" then
        return false, "mission.weather doesn't exist or isn't a table"
    end

    weather.qnh = w.qnh
    weather.temperature = w.temperature
    weather.groundTurbulence = w.ground_turbulence

    if type(weather.wind) == "table" then
        local function set_alt(key, altdata)
            local a = weather.wind[key]
            if type(a) == "table" then
                a.speed = altdata.speed
                a.dir = altdata.dir
            end
        end
        set_alt("atGround", w.wind.ground)
        set_alt("at2000", w.wind.at2000)
        set_alt("at8000", w.wind.at8000)
    end

    local notes = {}
    if type(weather.clouds) == "table" then
        local clouds = weather.clouds
        clouds.density = w.clouds.density
        clouds.base = w.clouds.base
        clouds.thickness = w.clouds.thickness
        clouds.iprecptns = w.clouds.iprecptns
        -- Always written, whether the key already existed or not: adding a
        -- key to a Lua table is safe, and DCS only reads the keys it knows
        -- about - a brand-new blank mission may not have ["preset"] yet
        -- (the native Weather dialog was never touched), and that used to
        -- force a needless fallback to the dynamic model.
        clouds.preset = w.clouds.preset or ""
    end

    if type(weather.visibility) == "table" then
        weather.visibility.distance = w.visibility_m
    end

    weather.enable_fog = w.fog.enable
    if type(weather.fog) == "table" then
        weather.fog.thickness = w.fog.thickness
        weather.fog.visibility = w.fog.visibility
    end

    if type(weather.season) == "table" then
        weather.season.temperature = w.temperature
    end

    if w.name_label and weather.name ~= nil then
        weather.name = w.name_label
    end

    return true, notes
end

-- apply_datetime(mission, dt) — dt is the table returned by mission_datetime.compute
function M.apply_datetime(mission, dt)
    if type(mission.date) ~= "table" then
        return false, "mission.date doesn't exist or isn't a table"
    end
    mission.date.Year = dt.date.Year
    mission.date.Month = dt.date.Month
    mission.date.Day = dt.date.Day
    mission.start_time = dt.start_time
    return true
end

return M
